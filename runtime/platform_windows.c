#include "internal.h"

#include <windows.h>

void *psl_rt_platform_stack_top(void) {
    return ((PNT_TIB)NtCurrentTeb())->StackBase;
}
