#include <stdint.h>
#include <windows.h>

extern uint64_t add42(uint64_t value);

int main(void) {
    DWORD64 image_base = 0;
    DWORD64 address = (DWORD64)(uintptr_t)&add42;
    PRUNTIME_FUNCTION entry = RtlLookupFunctionEntry(address, &image_base, 0);
    if (entry == 0)
        return 1;
    if (address < image_base + entry->BeginAddress ||
        address >= image_base + entry->EndAddress)
        return 2;

    const unsigned char *info =
        (const unsigned char *)(uintptr_t)(image_base + entry->UnwindData);
    if ((info[0] & 7) != 1 || info[1] != 11 || (info[3] & 15) != 5)
        return 3;
    return add42(8) == 50 ? 0 : 4;
}
