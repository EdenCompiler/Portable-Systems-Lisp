#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>

extern uint64_t add42(uint64_t value);

static int check_unwind(void *function, int large) {
    DWORD64 image_base = 0;
    DWORD64 address = (DWORD64)(uintptr_t)function;
    PRUNTIME_FUNCTION entry = RtlLookupFunctionEntry(address, &image_base, 0);
    if (entry == 0 || address != image_base + entry->BeginAddress)
        return 1;
    const unsigned char *code = function;
    const unsigned char *info =
        (const unsigned char *)(uintptr_t)(image_base + entry->UnwindData);
    size_t prologue = info[1];
    if ((info[0] & 7) != 1 || (info[3] & 15) != 0 ||
        prologue < 11 || code[0] != 0x55 ||
        memcmp(code + prologue - 7, "\x48\x81\xec", 3) != 0)
        return 2;
    uint32_t frame;
    memcpy(&frame, code + prologue - 4, sizeof frame);
    if ((frame % 16) != 0 || (large && (frame < 4096 || prologue <= 11)))
        return 3;
    unsigned char *stack = calloc(1, frame + 128);
    if (!stack)
        return 4;
    DWORD64 initial_sp = ((DWORD64)(uintptr_t)(stack + frame + 64) & ~UINT64_C(15)) + 8;
    const DWORD64 prior_rbp = UINT64_C(0x123456780000);
    const DWORD64 return_pc = UINT64_C(0x234567890000);
    *(DWORD64 *)(uintptr_t)initial_sp = return_pc;
    *(DWORD64 *)(uintptr_t)(initial_sp - 8) = prior_rbp;
    /* Before PUSH, after PUSH/MOV, during probes, after allocation, in body. */
    size_t cuts[] = {0, 1, 4, prologue - 7, prologue, prologue + 1};
    for (size_t i = 0; i < sizeof cuts / sizeof cuts[0]; ++i) {
        CONTEXT context;
        memset(&context, 0, sizeof context);
        context.Rip = address + cuts[i];
        context.Rsp = initial_sp - (cuts[i] ? 8 : 0) - (cuts[i] >= prologue ? frame : 0);
        context.Rbp = cuts[i] >= 4 ? initial_sp - 8 : prior_rbp;
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
