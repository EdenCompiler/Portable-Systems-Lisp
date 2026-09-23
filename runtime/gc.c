#include "internal.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static psl_object *objects;
static psl_root *roots;
static psl_root *permanent_roots;
static size_t object_count;
static size_t collection_limit = 256;

static psl_object *find_object(psl_value value) {
    if (value == 0 || (value & UINT64_C(7)) != 0) {
        return NULL;
    }
    for (psl_object *object = objects; object != NULL; object = object->next) {
        if ((psl_value)(uintptr_t)object == value) {
            return object;
        }
    }
    return NULL;
}

psl_object *psl_rt_expect_object(psl_value value, psl_object_kind kind) {
    psl_object *object = find_object(value);
    if (object == NULL || (kind != 0 && object->kind != kind)) {
        abort();
    }
    return object;
}

psl_object_kind psl_rt_kind(psl_value value) {
    return psl_rt_expect_object(value, 0)->kind;
}

void psl_rt_push_roots(psl_root *root, psl_value *values, size_t count) {
    root->previous = roots;
    root->values = values;
    root->count = count;
    roots = root;
}

void psl_rt_pop_roots(psl_root *root) {
    if (roots != root) {
        abort();
    }
    roots = root->previous;
}

void psl_rt_register_permanent_roots(psl_value *values, size_t count) {
    psl_root *root = malloc(sizeof(*root));
    if (root == NULL) {
        abort();
    }
    root->previous = permanent_roots;
    root->values = values;
    root->count = count;
    permanent_roots = root;
}

static void mark_value(psl_value value, psl_object **work, size_t *used) {
    psl_object *object = find_object(value);
    if (object != NULL && !object->marked) {
        object->marked = 1;
        work[(*used)++] = object;
    }
}

static void mark_registered_roots(psl_object **work, size_t *used) {
    for (psl_root *root = roots; root != NULL; root = root->previous) {
        for (size_t index = 0; index < root->count; index++) {
            mark_value(root->values[index], work, used);
        }
    }
    for (psl_root *root = permanent_roots; root != NULL;
         root = root->previous) {
        for (size_t index = 0; index < root->count; index++) {
            mark_value(root->values[index], work, used);
        }
    }
}

#if defined(__GNUC__) || defined(__clang__)
__attribute__((no_sanitize_address))
#endif
static void mark_stack(psl_object **work, size_t *used) {
    uintptr_t marker = 0;
    uintptr_t start = (uintptr_t)&marker;
    uintptr_t end = (uintptr_t)psl_rt_stack_top();
    start = (start + sizeof(uintptr_t) - 1) & ~(sizeof(uintptr_t) - 1);
    if (start > end) {
        abort();
    }
    for (uintptr_t address = start; address + sizeof(psl_value) <= end;
         address += sizeof(psl_value)) {
        psl_value candidate;
        memcpy(&candidate, (const void *)address, sizeof(candidate));
        mark_value(candidate, work, used);
    }
}

static void mark_children(psl_object *object, psl_object **work, size_t *used) {
    size_t slots = 0;
    switch (object->kind) {
        case PSL_OBJECT_CONS: slots = 2; break;
        case PSL_OBJECT_STRING: slots = 0; break;
        case PSL_OBJECT_SYMBOL: slots = 3; break;
        case PSL_OBJECT_PACKAGE: slots = 2; break;
        case PSL_OBJECT_CLOSURE: slots = 1; break;
    }
    for (size_t index = 0; index < slots; index++) {
        mark_value(object->slots[index], work, used);
    }
}

static void sweep_objects(void) {
    psl_object **link = &objects;
    while (*link != NULL) {
        psl_object *object = *link;
        if (object->marked) {
            object->marked = 0;
            link = &object->next;
        } else {
            *link = object->next;
            free(object);
            object_count--;
        }
    }
}

void psl_rt_collect(void) {
    psl_object **work = malloc((object_count == 0 ? 1 : object_count)
                               * sizeof(*work));
    size_t used = 0;
    if (work == NULL) {
        abort();
    }
    mark_registered_roots(work, &used);
    mark_stack(work, &used);
    for (size_t index = 0; index < used; index++) {
        mark_children(work[index], work, &used);
    }
    free(work);
    sweep_objects();
    collection_limit = object_count < 128 ? 256 : object_count * 2;
}

psl_object *psl_rt_allocate(psl_object_kind kind, size_t extra_bytes) {
    (void)psl_rt_stack_top();
    if (object_count >= collection_limit) {
        psl_rt_collect();
    }
    if (extra_bytes > SIZE_MAX - sizeof(psl_object)) {
        abort();
    }
    psl_object *object = calloc(1, sizeof(psl_object) + extra_bytes);
    if (object == NULL || ((uintptr_t)object & (uintptr_t)7) != 0) {
        abort();
    }
    object->kind = kind;
    object->next = objects;
    objects = object;
    object_count++;
    return object;
}

size_t psl_rt_live_objects(void) {
    return object_count;
}
