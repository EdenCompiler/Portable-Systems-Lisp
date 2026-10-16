#include "internal.h"

#include <stdlib.h>
#include <string.h>

static size_t vector_storage_bytes(size_t capacity) {
    if (capacity > (SIZE_MAX - sizeof(psl_object)) / sizeof(psl_value)) {
        abort();
    }
    return capacity * sizeof(psl_value);
}

static psl_object *make_storage(size_t capacity) {
    psl_object *storage = psl_rt_allocate_precise(
        PSL_OBJECT_VALUE_VECTOR_STORAGE, vector_storage_bytes(capacity));
    storage->length = capacity;
    psl_value *items = (psl_value *)storage->bytes;
    for (size_t index = 0; index < capacity; index++) {
        items[index] = PSL_NIL;
    }
    return storage;
}

static psl_object *expect_vector(psl_value value) {
    return psl_rt_expect_object(value, PSL_OBJECT_VALUE_VECTOR);
}

static psl_object *vector_storage(psl_object *vector) {
    return psl_rt_expect_object(vector->slots[0],
                                PSL_OBJECT_VALUE_VECTOR_STORAGE);
}

psl_value psl_rt_make_value_vector_precise(size_t length, psl_value initial) {
    psl_value roots_values[2] = {PSL_NIL, initial};
    psl_root roots;
    psl_rt_push_roots(&roots, roots_values, 2);

    psl_object *vector = psl_rt_allocate_precise(PSL_OBJECT_VALUE_VECTOR, 0);
    roots_values[0] = (psl_value)(uintptr_t)vector;
    vector->length = length;

    psl_object *storage = make_storage(length);
    psl_value *items = (psl_value *)storage->bytes;
    for (size_t index = 0; index < length; index++) {
        items[index] = roots_values[1];
    }
    vector->slots[0] = (psl_value)(uintptr_t)storage;

    psl_value result = roots_values[0];
    psl_rt_pop_roots(&roots);
    return result;
}

size_t psl_rt_value_vector_length(psl_value value) {
    return expect_vector(value)->length;
}

psl_value psl_rt_value_vector_ref(psl_value value, size_t index) {
    psl_object *vector = expect_vector(value);
    if (index >= vector->length) {
        abort();
    }
    return ((psl_value *)vector_storage(vector)->bytes)[index];
}

psl_value psl_rt_value_vector_set(psl_value value, size_t index,
                                  psl_value item) {
    psl_object *vector = expect_vector(value);
    if (index >= vector->length) {
        abort();
    }
    ((psl_value *)vector_storage(vector)->bytes)[index] = item;
    return item;
}

static size_t grown_capacity(size_t current, size_t required) {
    size_t capacity = current == 0 ? 4 : current;
    while (capacity < required) {
        if (capacity > SIZE_MAX / 2) {
            capacity = required;
            break;
        }
        capacity *= 2;
    }
    (void)vector_storage_bytes(capacity);
    return capacity;
}

static void grow_vector(psl_value *roots_values, size_t required) {
    psl_object *vector = expect_vector(roots_values[0]);
    psl_object *old_storage = vector_storage(vector);
    size_t capacity = grown_capacity(old_storage->length, required);
    psl_object *new_storage = make_storage(capacity);
    memcpy(new_storage->bytes, old_storage->bytes,
           vector->length * sizeof(psl_value));
    vector->slots[0] = (psl_value)(uintptr_t)new_storage;
}

size_t psl_rt_value_vector_push_precise(psl_value value, psl_value item) {
    psl_value roots_values[2] = {value, item};
    psl_root roots;
    psl_rt_push_roots(&roots, roots_values, 2);

    psl_object *vector = expect_vector(roots_values[0]);
    size_t index = vector->length;
    if (index == SIZE_MAX) {
        abort();
    }
    size_t required = index + 1;
    if (required > vector_storage(vector)->length) {
        grow_vector(roots_values, required);
    }

    vector = expect_vector(roots_values[0]);
    ((psl_value *)vector_storage(vector)->bytes)[index] = roots_values[1];
    vector->length = required;
    psl_rt_pop_roots(&roots);
    return index;
}
