#include <stdint.h>

uint64_t c_counter = 10;

extern uint64_t psl_counter;
extern uint32_t MixedCaseExport;
extern int32_t psl_signed;
extern uint8_t *psl_null;
extern uint16_t unreferenced_export;

extern uint64_t read_psl_counter(void);
extern uint64_t replace_psl_counter(uint64_t value);
extern uint32_t read_mixed_export(void);
extern uint64_t increment_imported_counter(void);

int main(void)
{
    if (psl_counter != 41 || read_psl_counter() != 41)
        return 1;
    if (replace_psl_counter(73) != 73 || psl_counter != 73)
        return 2;
    if (MixedCaseExport != UINT32_C(0x89abcdef) ||
        read_mixed_export() != UINT32_C(0x89abcdef))
        return 3;
    if (psl_signed != -17 || psl_null != 0)
        return 4;
    if (unreferenced_export != UINT16_C(0x1234))
        return 5;
    if (increment_imported_counter() != 11 || c_counter != 11)
        return 6;
    return 0;
}
