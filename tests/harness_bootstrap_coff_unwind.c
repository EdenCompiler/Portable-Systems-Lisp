#include <stdint.h>
#include <string.h>
#include <windows.h>

extern uint64_t answer(void);

int main(void) {
    DWORD64 image_base = 0;
    DWORD64 address = (DWORD64)(uintptr_t)&answer;
    PRUNTIME_FUNCTION function = RtlLookupFunctionEntry(address, &image_base, NULL);
    if (!function || image_base + function->BeginAddress != address) return 1;
    const uint8_t *info = (const uint8_t *)(uintptr_t)(image_base + function->UnwindData);
    if (info[0] != 1 || info[1] != 11 || info[2] != 3 || info[3] != 5) return 2;
    if (info[5] != 3 || (info[7] & 15) != 2 || info[9] != 0x50) return 3;
    uintptr_t frame = ((uintptr_t)(info[7] >> 4) + 1) * 8;
    _Alignas(16) uint8_t stack[2048] = {0};
    uintptr_t entry = ((uintptr_t)(stack + 1024) & ~(uintptr_t)15) + 8;
    uintptr_t old_bp = (uintptr_t)0x1020304050607080ULL;
    uintptr_t return_address = (uintptr_t)0x123456789abcdef0ULL;
    memcpy((void *)entry, &return_address, 8);
    memcpy((void *)(entry - 8), &old_bp, 8);
    CONTEXT context = {0};
    context.Rip = address + 11 + 28;
    context.Rsp = entry - 8 - frame;
    context.Rbp = context.Rsp;
    PVOID handler = NULL;
    DWORD64 establisher = 0;
    RtlVirtualUnwind(UNW_FLAG_NHANDLER, image_base, context.Rip, function,
                     &context, &handler, &establisher, NULL);
    if (context.Rip != return_address || context.Rsp != entry + 8 ||
        context.Rbp != old_bp) return 4;
    return answer() == 42 ? 0 : 5;
}
