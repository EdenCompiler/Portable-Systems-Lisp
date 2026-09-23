#define _GNU_SOURCE
#include "internal.h"

#include <pthread.h>
#include <stdlib.h>

void *psl_rt_platform_stack_top(void) {
    pthread_attr_t attributes;
    void *stack_base;
    size_t stack_size;
    if (pthread_getattr_np(pthread_self(), &attributes) != 0) {
        abort();
    }
    if (pthread_attr_getstack(&attributes, &stack_base, &stack_size) != 0) {
        abort();
    }
    pthread_attr_destroy(&attributes);
    return (unsigned char *)stack_base + stack_size;
}
