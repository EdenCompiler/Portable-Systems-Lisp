#include "internal.h"

void *psl_rt_stack_top(void) {
    static void *top;
    if (top == NULL) {
        top = psl_rt_platform_stack_top();
    }
    return top;
}
