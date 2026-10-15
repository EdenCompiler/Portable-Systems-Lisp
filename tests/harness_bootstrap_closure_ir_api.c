#include "../bootstrap/native_api.h"
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

/* The structural HIR receiver is independently callable by API clients. Keep
   a tiny leaf fixture here so malformed kind-36 references cannot slip past
   the verifier before the typed HIR pass runs. */
static int accepts(struct native_hir_node *node,
                   const struct native_function *functions,
                   uintptr_t function_count) {
    struct native_hir_arena arena = {node, 1, 1, 0};
    return hir_verify_root(&arena, 1, functions, function_count, 0);
}

static void set_address(struct native_hir_node *address, uintptr_t target,
                        uintptr_t source) {
    memset(address, 0, sizeof *address);
    address->kind = 36;
    address->type_code = 1;
    address->scalar_code = 2;
    address->target = target;
    address->source = source;
}

static uintptr_t imported_target(const struct native_driver *driver) {
    for (uintptr_t i = 0; i < driver->context.prior_count; ++i)
        if (driver->storage.functions[i].imported) return i + 1;
    assert(!"expected at least one runtime import");
    return 0;
}

static void compiled_receiver_checks(unsigned level) {
    static const char source[] =
        "(defun outer (x) (declare (type value x) (returns value)) "
        "(funcall (lambda (argument) argument) x)) "
        "(defun other (x) (declare (type value x) (returns value)) "
        "(funcall (lambda (argument) argument) x)) "
        "(defun address_sink () (declare (returns u64)) 0)";
    struct native_driver *driver = calloc(1, sizeof *driver);
    assert(driver);
    driver->length = sizeof source - 1;
    driver->source = malloc(driver->length + 1);
    assert(driver->source);
    memcpy(driver->source, source, driver->length + 1);
    assert(native_prepare_driver(driver));
    driver->context.target = NATIVE_TARGET_X86_64_LINUX;
    driver->context.profile = 1;
    driver->context.optimization = level;
    struct native_unit_result result = {0};
    assert(native_compile_unit(&driver->context, &driver->object, &result));
    assert(driver->context.closure_plan_count == 2);

    uintptr_t origin = driver->storage.closure_plans[0].origin;
    uintptr_t other_origin = driver->storage.closure_plans[1].origin;
    uintptr_t target = driver->storage.closure_plans[0].function_index + 1;
    uintptr_t other_target = driver->storage.closure_plans[1].function_index + 1;
    uintptr_t imported = imported_target(driver);
    uintptr_t count = driver->context.prior_count;
    struct native_signature sink = {0};
    sink.generated = 1;
    sink.result_code = 2;
    driver->context.current_signature = &sink;
    driver->context.current_arity = 0;

    struct native_hir_node hir_address;
    set_address(&hir_address, target, origin);
    driver->hir.nodes[0] = hir_address;
    driver->hir.count = 1;
    assert(hir_verify_scalar_tree(&driver->context, 1, 0));
    assert(hir_verify_root(&driver->hir, 1, driver->storage.functions,
                           count, 0));
    hir_address.target = imported;
    driver->hir.nodes[0] = hir_address;
    assert(!hir_verify_scalar_tree(&driver->context, 1, 0));
    assert(!hir_verify_root(&driver->hir, 1, driver->storage.functions,
                            count, 0));
    hir_address.target = count + 1;
    driver->hir.nodes[0] = hir_address;
    assert(!hir_verify_scalar_tree(&driver->context, 1, 0));
    assert(!hir_verify_root(&driver->hir, 1, driver->storage.functions,
                            count, 0));
    hir_address.target = 1; /* an ordinary, defined source function */
    driver->hir.nodes[0] = hir_address;
    assert(!hir_verify_scalar_tree(&driver->context, 1, 0));
    hir_address.target = other_target; /* another generated callback */
    driver->hir.nodes[0] = hir_address;
    assert(!hir_verify_scalar_tree(&driver->context, 1, 0));
    hir_address.target = target;
    hir_address.source = other_origin; /* valid lambda, wrong callback owner */
    driver->hir.nodes[0] = hir_address;
    assert(!hir_verify_scalar_tree(&driver->context, 1, 0));
    hir_address.source = 1; /* a DEFUN AST node is not the lambda origin */
    driver->hir.nodes[0] = hir_address;
    assert(!hir_verify_scalar_tree(&driver->context, 1, 0));

    assert(compile_scalar_form(&driver->context,
                               driver->signature_context.signatures,
                               driver->storage.functions));
    assert(ssa_verify_function(&driver->context));
    assert(lir_verify_function(&driver->context));
    uintptr_t hir_ref = 0, ssa_ref = 0, lir_ref = 0;
    for (uintptr_t i = 0; i < driver->hir.count; ++i)
        if (driver->hir.nodes[i].kind == 36) hir_ref = i + 1;
    for (uintptr_t i = 0; i < driver->ssa.value_count; ++i)
        if (driver->ssa.values[i].kind == 36) ssa_ref = i + 1;
    for (uintptr_t i = 0; i < driver->lir.count; ++i)
        if (driver->lir.instructions[i].kind == 36) lir_ref = i + 1;
    assert(hir_ref && ssa_ref && lir_ref);
    struct native_hir_node *typed_hir = &driver->hir.nodes[hir_ref - 1];
    struct native_ssa_value *typed_ssa = &driver->ssa.values[ssa_ref - 1];
    struct native_lir_instruction *typed_lir = &driver->lir.instructions[lir_ref - 1];
    struct native_hir_node saved_hir = *typed_hir;
    struct native_ssa_value saved_ssa = *typed_ssa;
    struct native_lir_instruction saved_lir = *typed_lir;
    struct native_ir_type saved_ssa_type = driver->ssa.types[ssa_ref - 1];
    struct native_ir_type saved_lir_type = driver->lir.types[lir_ref - 1];

    typed_hir->target = 1; typed_ssa->target = 1; typed_lir->target = 1;
    assert(!hir_verify_scalar_tree(&driver->context, hir_ref, 0));
    assert(!ssa_verify_function(&driver->context));
    assert(!lir_verify_function(&driver->context));
    *typed_hir = saved_hir; *typed_ssa = saved_ssa; *typed_lir = saved_lir;

    typed_hir->target = imported; typed_ssa->target = imported; typed_lir->target = imported;
    assert(!hir_verify_scalar_tree(&driver->context, hir_ref, 0));
    assert(!ssa_verify_function(&driver->context));
    assert(!lir_verify_function(&driver->context));
    *typed_hir = saved_hir; *typed_ssa = saved_ssa; *typed_lir = saved_lir;
    typed_hir->target = count + 1; typed_ssa->target = count + 1; typed_lir->target = count + 1;
    assert(!hir_verify_scalar_tree(&driver->context, hir_ref, 0));
    assert(!ssa_verify_function(&driver->context));
    assert(!lir_verify_function(&driver->context));
    *typed_hir = saved_hir; *typed_ssa = saved_ssa; *typed_lir = saved_lir;

    typed_hir->target = other_target; typed_ssa->target = other_target;
    typed_lir->target = other_target;
    assert(!hir_verify_scalar_tree(&driver->context, hir_ref, 0));
    assert(!ssa_verify_function(&driver->context));
    assert(!lir_verify_function(&driver->context));
    *typed_hir = saved_hir; *typed_ssa = saved_ssa; *typed_lir = saved_lir;
    typed_hir->source = 1; typed_ssa->source = 1; typed_lir->source = 1;
    assert(!hir_verify_scalar_tree(&driver->context, hir_ref, 0));
    assert(!ssa_verify_function(&driver->context));
    assert(!lir_verify_function(&driver->context));
    *typed_hir = saved_hir; *typed_ssa = saved_ssa; *typed_lir = saved_lir;
    typed_hir->source = UINTPTR_MAX; typed_ssa->source = UINTPTR_MAX;
    typed_lir->source = UINTPTR_MAX;
    assert(!hir_verify_scalar_tree(&driver->context, hir_ref, 0));
    assert(!ssa_verify_function(&driver->context));
    assert(!lir_verify_function(&driver->context));
    *typed_hir = saved_hir; *typed_ssa = saved_ssa; *typed_lir = saved_lir;
    typed_hir->source = other_origin; typed_ssa->source = other_origin;
    typed_lir->source = other_origin;
    assert(!hir_verify_scalar_tree(&driver->context, hir_ref, 0));
    assert(!ssa_verify_function(&driver->context));
    assert(!lir_verify_function(&driver->context));
    *typed_hir = saved_hir; *typed_ssa = saved_ssa; *typed_lir = saved_lir;
    typed_hir->pointee = 1;
    typed_ssa->pointee = 1; driver->ssa.types[ssa_ref - 1].pointee = 1;
    typed_lir->pointee = 1; driver->lir.types[lir_ref - 1].pointee = 1;
    assert(!hir_verify_scalar_tree(&driver->context, hir_ref, 0));
    assert(!ssa_verify_function(&driver->context));
    assert(!lir_verify_function(&driver->context));
    *typed_hir = saved_hir; *typed_ssa = saved_ssa; *typed_lir = saved_lir;
    driver->ssa.types[ssa_ref - 1] = saved_ssa_type;
    driver->lir.types[lir_ref - 1] = saved_lir_type;
    assert(ssa_verify_function(&driver->context));
    assert(lir_verify_function(&driver->context));
    typed_hir->value = 1; typed_ssa->value = 1; typed_lir->value = 1;
    assert(!hir_verify_scalar_tree(&driver->context, hir_ref, 0));
    assert(!ssa_verify_function(&driver->context));
    assert(!lir_verify_function(&driver->context));
    *typed_hir = saved_hir; *typed_ssa = saved_ssa; *typed_lir = saved_lir;
    typed_hir->left = 1; typed_ssa->left = 1; typed_lir->left = 1;
    assert(!hir_verify_root(&driver->hir, hir_ref, driver->storage.functions,
                            count, 0));
    assert(!ssa_verify_function(&driver->context));
    assert(!lir_verify_function(&driver->context));
    *typed_hir = saved_hir; *typed_ssa = saved_ssa; *typed_lir = saved_lir;
    typed_hir->scalar_code = 1;
    typed_ssa->scalar_code = 1; driver->ssa.types[ssa_ref - 1].scalar_code = 1;
    typed_lir->scalar_code = 1; driver->lir.types[lir_ref - 1].scalar_code = 1;
    assert(!hir_verify_scalar_tree(&driver->context, hir_ref, 0));
    assert(!ssa_verify_function(&driver->context));
    assert(!lir_verify_function(&driver->context));

    *typed_hir = saved_hir; *typed_ssa = saved_ssa; *typed_lir = saved_lir;
    driver->ssa.types[ssa_ref - 1] = saved_ssa_type;
    driver->lir.types[lir_ref - 1] = saved_lir_type;
    assert(hir_verify_scalar_tree(&driver->context, hir_ref, 0));
    assert(ssa_verify_function(&driver->context));
    assert(lir_verify_function(&driver->context));

    struct native_signature *callback =
        &driver->signature_context.signatures[target - 1];
    uintptr_t arity = callback->arity;
    callback->arity = 1;
    assert(!hir_verify_scalar_tree(&driver->context, hir_ref, 0));
    assert(!ssa_verify_function(&driver->context));
    assert(!lir_verify_function(&driver->context));
    callback->arity = arity;
    uint32_t result_code = callback->result_code;
    callback->result_code = 2;
    assert(!hir_verify_scalar_tree(&driver->context, hir_ref, 0));
    assert(!ssa_verify_function(&driver->context));
    assert(!lir_verify_function(&driver->context));
    callback->result_code = result_code;
    struct native_parameter *environment =
        &driver->signature_context.parameters[callback->first_parameter];
    uint32_t parameter_code = environment->scalar_code;
    environment->scalar_code = 2;
    assert(!hir_verify_scalar_tree(&driver->context, hir_ref, 0));
    assert(!ssa_verify_function(&driver->context));
    assert(!lir_verify_function(&driver->context));
    environment->scalar_code = parameter_code;
    assert(hir_verify_scalar_tree(&driver->context, hir_ref, 0));
    assert(ssa_verify_function(&driver->context));
    assert(lir_verify_function(&driver->context));

    native_release_driver(driver);
    free(driver);
}

int main(void) {
    struct native_function functions[3];
    memset(functions, 0, sizeof functions);
    functions[2].imported = 1;
    struct native_hir_node address;
    memset(&address, 0, sizeof address);
    address.kind = 36;
    address.type_code = 1;
    address.scalar_code = 2;
    address.source = 1;

    address.target = 1;
    assert(accepts(&address, functions, 2));
    address.target = 2;
    assert(accepts(&address, functions, 2));
    address.target = 3;
    assert(!accepts(&address, functions, 3)); /* imported target */
    assert(!accepts(&address, functions, 2)); /* out of range */
    address.target = 0;
    assert(!accepts(&address, functions, 2));

    address.target = 1;
    address.left = 1;
    assert(!accepts(&address, functions, 2));
    address.left = 0;
    address.right = 1;
    assert(!accepts(&address, functions, 2));
    address.right = 0;
    address.value = 1;
    assert(!accepts(&address, functions, 2));
    address.value = 0;

    /* A defined function after an import is not a legal defined-prefix target. */
    functions[1].imported = 1;
    functions[2].imported = 0;
    address.target = 3;
    assert(!accepts(&address, functions, 3));
    compiled_receiver_checks(0);
    compiled_receiver_checks(1);
    puts("native closure function-address HIR shape checks passed");
    return 0;
}
