#include "internal.h"

#include <stdlib.h>
#include <string.h>

psl_value psl_rt_make_string(size_t length, uint8_t fill) {
    if (length == SIZE_MAX) {
        abort();
    }
    psl_object *string = psl_rt_allocate(PSL_OBJECT_STRING, length + 1);
    string->length = length;
    memset(string->bytes, fill, length);
    string->bytes[length] = 0;
    return (psl_value)(uintptr_t)string;
}

size_t psl_rt_string_length(psl_value value) {
    return psl_rt_expect_object(value, PSL_OBJECT_STRING)->length;
}

uint8_t psl_rt_string_byte(psl_value value, size_t index) {
    psl_object *string = psl_rt_expect_object(value, PSL_OBJECT_STRING);
    if (index >= string->length) {
        abort();
    }
    return string->bytes[index];
}

void psl_rt_string_set_byte(psl_value value, size_t index, uint8_t byte) {
    psl_object *string = psl_rt_expect_object(value, PSL_OBJECT_STRING);
    if (index >= string->length) {
        abort();
    }
    string->bytes[index] = byte;
}

int psl_rt_strings_equal(psl_value left, psl_value right) {
    psl_object *a = psl_rt_expect_object(left, PSL_OBJECT_STRING);
    psl_object *b = psl_rt_expect_object(right, PSL_OBJECT_STRING);
    return a->length == b->length &&
           memcmp(a->bytes, b->bytes, a->length) == 0;
}
