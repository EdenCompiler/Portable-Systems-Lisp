#include <stdint.h>
#include <stddef.h>

extern uint64_t call_foreign_seven(void);
extern uint64_t call_foreign_eight(void);
extern int64_t call_foreign_narrow(void);
extern int32_t call_foreign_pointer(int32_t *);
extern uint64_t foreign_truth(void);
extern size_t call_strlen(const unsigned char *);

int main(void) {
    int32_t values[] = {10, -20, -30000};
    if (call_foreign_seven() != UINT64_C(7654321)) return 1;
    if (call_foreign_eight() != UINT64_C(7654401654321)) return 2;
    if (call_foreign_narrow() != -7) return 3;
    if (call_foreign_pointer(values) != -30000) return 4;
    if (call_strlen((const unsigned char *)"native ffi") != 10) return 5;
    if (foreign_truth() != 42) return 6;
    return 0;
}
