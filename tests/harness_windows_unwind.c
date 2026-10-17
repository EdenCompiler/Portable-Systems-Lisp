#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>

extern uint64_t add42(uint64_t value);

typedef struct {
    size_t prologue;
    size_t allocation_start;
    size_t allocation_end;
    size_t frame_pointer_end;
    uint32_t frame;
} unwind_layout;

static int decode_unwind_layout(const unsigned char *code,
                                const unsigned char *info,
                                int large,
                                unwind_layout *layout) {
    size_t allocation_count = 0;
    size_t frame_pointer_count = 0;
    if ((info[0] & 7) != 1 || (info[0] >> 3) != 0 || code[0] != 0x55)
        return 2;
    layout->prologue = info[1];
    if (layout->prologue < 11)
        return 2;
    for (size_t offset = 1; offset + 7 <= layout->prologue; ++offset) {
        if (memcmp(code + offset, "\x48\x81\xec", 3) == 0) {
            layout->allocation_start = offset;
            ++allocation_count;
        }
    }
    for (size_t offset = 1; offset + 3 <= layout->prologue; ++offset) {
        if (memcmp(code + offset, "\x48\x89\xe5", 3) == 0) {
            layout->frame_pointer_end = offset + 3;
            ++frame_pointer_count;
        }
    }
    if (allocation_count != 1 || frame_pointer_count != 1 ||
        layout->allocation_start + 7 > layout->prologue ||
        ((info[3] & 15) != 0 && (info[3] & 15) != 5))
        return 2;
    layout->allocation_end = layout->allocation_start + 7;
    memcpy(&layout->frame, code + layout->allocation_start + 3,
           sizeof layout->frame);
    if ((layout->frame % 16) != 0 ||
        (large && (layout->frame < 4096 || layout->prologue <= 11)))
        return 3;
    return 0;
}

static int check_unwind(void *function, int large) {
    DWORD64 image_base = 0;
    DWORD64 address = (DWORD64)(uintptr_t)function;
    PRUNTIME_FUNCTION entry = RtlLookupFunctionEntry(address, &image_base, 0);
    if (entry == 0 || address != image_base + entry->BeginAddress)
        return 1;
    const unsigned char *code = function;
    const unsigned char *info =
        (const unsigned char *)(uintptr_t)(image_base + entry->UnwindData);
    unwind_layout layout = {0};
    int decoded = decode_unwind_layout(code, info, large, &layout);
    if (decoded)
        return decoded;
    unsigned char *stack = calloc(1, layout.frame + 128);
    if (!stack)
        return 4;
    DWORD64 initial_sp = ((DWORD64)(uintptr_t)(stack + layout.frame + 64) & ~UINT64_C(15)) + 8;
    const DWORD64 prior_rbp = UINT64_C(0x123456780000);
    const DWORD64 return_pc = UINT64_C(0x234567890000);
    DWORD64 frame_pointer = initial_sp - 8;
    if (layout.frame_pointer_end >= layout.allocation_end)
        frame_pointer -= layout.frame;
    *(DWORD64 *)(uintptr_t)initial_sp = return_pc;
    *(DWORD64 *)(uintptr_t)(initial_sp - 8) = prior_rbp;
    /* Before PUSH, before/after allocation and frame setup, then in the body. */
    size_t cuts[] = {0, 1, layout.allocation_start,
                     layout.allocation_start + 3, layout.allocation_end,
                     layout.frame_pointer_end,
                     layout.prologue, layout.prologue + 1};
    for (size_t i = 0; i < sizeof cuts / sizeof cuts[0]; ++i) {
        CONTEXT context;
        memset(&context, 0, sizeof context);
        context.Rip = address + cuts[i];
        context.Rsp = initial_sp - (cuts[i] ? 8 : 0) -
                      (cuts[i] >= layout.allocation_end ? layout.frame : 0);
        context.Rbp = cuts[i] >= layout.frame_pointer_end ? frame_pointer : prior_rbp;
        PVOID handler = 0;
        DWORD64 establisher = 0;
        RtlVirtualUnwind(UNW_FLAG_NHANDLER, image_base, context.Rip, entry,
                        &context, &handler, &establisher, 0);
        if (context.Rip != return_pc || context.Rsp != initial_sp + 8 ||
            context.Rbp != prior_rbp) {
            free(stack);
            return 5;
        }
    }
    free(stack);
    return 0;
}

#ifdef PSL_WINDOWS_FRAME_GATE
extern uint64_t large_frame(uint64_t value);
static uint64_t calls;
static int body_unwind_failed;

uint64_t frame_tick(uint64_t value, uint64_t index) {
    if (index != calls++)
        abort();
    if (index == 0) {
        CONTEXT context;
        RtlCaptureContext(&context);
        DWORD64 base = 0, establisher = 0;
        PVOID handler = 0;
        PRUNTIME_FUNCTION entry = RtlLookupFunctionEntry(context.Rip, &base, 0);
        if (!entry) abort();
        RtlVirtualUnwind(UNW_FLAG_NHANDLER, base, context.Rip, entry,
                        &context, &handler, &establisher, 0);
        entry = RtlLookupFunctionEntry(context.Rip, &base, 0);
        if (!entry || base + entry->BeginAddress != (DWORD64)(uintptr_t)&large_frame)
            abort();
        RtlVirtualUnwind(UNW_FLAG_NHANDLER, base, context.Rip, entry,
                        &context, &handler, &establisher, 0);
        /* The actual PSL frame returns to this C module's main function. */
        entry = RtlLookupFunctionEntry(context.Rip, &base, 0);
        if (!entry) body_unwind_failed = 1;
    }
    return value + index;
}
#endif

int main(void) {
    int result = check_unwind((void *)(uintptr_t)&add42, 0);
    if (result) return result;
    if (add42(8) != 50) return 6;
#ifdef PSL_WINDOWS_FRAME_GATE
    result = check_unwind((void *)(uintptr_t)&large_frame, 1);
    if (result) return 10 + result;
    if (large_frame(7) != 82600 || calls != 400 || body_unwind_failed)
        return 20;
#endif
    return 0;
}
