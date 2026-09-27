#include "../bootstrap/native_api.h"
#include <string.h>
#include <stdio.h>

struct fixture {
    struct psl_ast_node syntax[256];
    struct native_hir_node hir_nodes[256];
    struct native_ssa_value ssa_values[256];
    struct native_ssa_block ssa_blocks[256];
    struct native_ir_type types[256];
    struct native_lir_instruction lir_instructions[1024];
    struct native_lir_block lir_blocks[768];
    struct native_call_fixup calls[256], jumps[768];
    uintptr_t bindings[256], labels[768];
    uint8_t bytes[32768];
    struct psl_scanner scanner;
    struct psl_token token;
    struct psl_parser parser;
    struct psl_parsed_integer integer;
    struct native_type_shape shape;
    struct native_layout_context layouts;
    struct native_signature signatures[1];
    struct native_parameter parameters[2];
    struct native_signature_context signature_context;
    struct native_function functions[1];
    struct native_hir_arena hir;
    struct native_ssa_arena ssa;
    struct native_lir_arena lir;
    struct native_fixup_arena call_fixups, jump_fixups;
    struct byte_buffer code;
    struct native_compile_context context;
};

static int compile_source_options(struct fixture *f, const uint8_t *source, uint32_t level) {
    memset(f, 0, sizeof *f);
    f->scanner = (struct psl_scanner){source, strlen((const char *)source), 0, 0};
    f->parser = (struct psl_parser){&f->scanner, &f->token, 0, f->syntax, 0, 256, 0};
    f->layouts = (struct native_layout_context){
        &f->parser, source, NULL, 0, 0, NULL, 0, 0, &f->shape, 0
    };
    f->signature_context = (struct native_signature_context){
        &f->layouts, f->signatures, 0, 1, f->parameters, 0, 2, 0
    };
    f->hir = (struct native_hir_arena){f->hir_nodes, 0, 256, 0};
    f->ssa = (struct native_ssa_arena){f->ssa_values, f->types, 0, 256, f->ssa_blocks, 0, 256, 0, 0};
    f->lir = (struct native_lir_arena){f->lir_instructions, 0, 1024, f->types, 0, 256, f->lir_blocks, 0, 768, 0};
    f->call_fixups = (struct native_fixup_arena){f->calls, 0, 256, 0};
    f->jump_fixups = (struct native_fixup_arena){f->jumps, 0, 768, 0};
    f->code = (struct byte_buffer){f->bytes, 0, sizeof f->bytes};
    f->context = (struct native_compile_context){
        &f->parser, source, &f->integer, &f->hir, &f->code,
        &f->call_fixups, f->functions, &f->signature_context, 1, 0, NULL,
        0, 0, 0, 0, &f->ssa, f->bindings, &f->lir, f->labels, &f->jump_fixups, 0, 0, 0
    };
    f->context.optimization = level;
    uintptr_t root = parser_next(&f->parser);
    return root && native_parse_signature(&f->signature_context, root) &&
           predeclare_scalar_form(&f->context, f->signatures, f->functions) &&
           compile_scalar_form(&f->context, f->signatures, f->functions);
}

static int compile_source(struct fixture *f, const uint8_t *source) {
    return compile_source_options(f, source, 0);
}

static int check_live_mutation(struct fixture *f, uintptr_t index) {
    f->ssa_values[index].live = 0;
    int rejected = !ssa_verify_liveness(&f->context);
    f->ssa_values[index].live = 1;
    return rejected;
}

static int check_dead_values(struct fixture *f) {
    static const uint8_t source[] =
        "(defun choice (input counter)"
        " (declare (type u64 input) (type (ptr u64) counter) (returns u64))"
        " (wrap* input 17)"
        " (let ((unused (if (< input 2) (choice input counter) (choice 0 counter))))"
        "   (store counter input) (deref counter) (wrap+ input 3)))";
    if (!compile_source_options(f, source, 1)) return 1;
    if (!ssa_verify_liveness(&f->context)) return 2;
    uintptr_t dead = 0, phi = 0, effects = 0, links = 0;
    for (uintptr_t i = 0; i < f->ssa.value_count; ++i) {
        struct native_ssa_value *value = &f->ssa_values[i];
        if (!value->live) {
            ++dead;
            if (value->kind == 28) ++phi;
            for (uintptr_t j = 0; j < f->lir.count; ++j)
                if (f->lir_instructions[j].destination == i + 1) return 3;
        }
        if (value->kind == 7 || value->kind == 24 || value->kind == 25) {
            if (!value->live || !check_live_mutation(f, i)) return 4;
            ++effects;
        }
        if (value->kind == 17) {
            if (!value->live || !check_live_mutation(f, i)) return 5;
            ++links;
        }
    }
    if (!dead || phi != 1 || effects != 4 || links != 4) return 6;
    f->ssa_values[0].live = 2;
    if (ssa_verify_liveness(&f->context)) return 7;
    f->ssa_values[0].live = 1;
    if (!ssa_optimize_function(&f->context)) return 8;
    f->context.optimization = 0;
    if (!ssa_optimize_function(&f->context)) return 9;
    for (uintptr_t i = 0; i < f->ssa.value_count; ++i)
        if (f->ssa_values[i].live != 1) return 10;
    return 0;
}

static int check_cfg_copy(struct fixture *f) {
    static const uint8_t source[] =
        "(defun choice (input) (declare (type u64 input) (returns u64))"
        " (let ((picked (if t input 0)))"
        "  (if (= picked 1) (wrap+ picked 42) (wrap* input 2))))";
    if (!compile_source_options(f, source, 0)) return 1;
    uintptr_t blocks = f->ssa.block_count, values = f->ssa.value_count;
    if (!compile_source_options(f, source, 1)) return 2;
    if (f->ssa.block_count >= blocks || f->ssa.value_count >= values) return 3;
    uintptr_t copy = 0;
    for (uintptr_t i = 0; i < f->ssa.value_count; ++i)
        if (f->ssa_values[i].kind == 31) copy = i + 1;
    if (!copy || !ssa_verify_liveness(&f->context)) return 4;
    struct native_ssa_value saved = f->ssa_values[copy - 1];
    f->ssa_values[copy - 1].left = copy;
    if (ssa_verify_function(&f->context)) return 5;
    f->ssa_values[copy - 1] = saved;
    f->ssa_values[copy - 1].right = saved.left;
    if (ssa_verify_function(&f->context)) return 6;
    f->ssa_values[copy - 1] = saved;
    f->ssa_values[copy - 1].predecessor_left = 1;
    if (ssa_verify_function(&f->context)) return 7;
    f->ssa_values[copy - 1] = saved;
    f->ssa_values[copy - 1].scalar_code = 3;
    f->types[copy - 1].scalar_code = 3;
    if (ssa_verify_function(&f->context)) return 9;
    f->ssa_values[copy - 1] = saved;
    f->types[copy - 1].scalar_code = saved.scalar_code;
    f->ssa_blocks[0].target_left = blocks;
    if (ssa_verify_function(&f->context)) return 8;
    return 0;
}

static int check_cfg_cycles(struct fixture *f) {
    static const uint8_t finite[] =
        "(defun choice (input) (declare (type u64 input) (returns u64))"
        " (while nil (choice input)) input)";
    static const uint8_t infinite[] =
        "(defun choice (input) (declare (type u64 input) (returns void))"
        " (while t (choice input)) (choice 0))";
    if (!compile_source_options(f, finite, 1)) return 1;
    for (uintptr_t i = 0; i < f->lir.count; ++i)
        if (f->lir_instructions[i].kind == 7 || f->lir_instructions[i].kind == 102) return 2;
    if (!compile_source_options(f, infinite, 1)) return 3;
    for (uintptr_t i = 0; i < f->lir.count; ++i)
        if (f->lir_instructions[i].kind == 103 || f->lir_instructions[i].kind == 102) return 4;
    return ssa_verify_liveness(&f->context) && lir_verify_function(&f->context) ? 0 : 5;
}

static int compile_fixture(struct fixture *f) {
    static const uint8_t source[] =
        "(defun choice (input)"
        " (declare (type u64 input) (returns u64) (c-export :c))"
        " (let ((x (if (< input 2) (wrap+ input 10) (wrap* input 3))))"
        "   (wrap+ x 1)))";
    return compile_source(f, source);
}

static int check_void_mutations(struct fixture *f) {
    static const uint8_t source[] =
        "(defun choice (input) (declare (type u64 input) (returns void))"
        " (if (< input 2) (choice 0) (choice 1)))";
    if (!compile_source(f, source)) return 1;
    uintptr_t join = 0, call = 0, returned = 0;
    for (uintptr_t i = 0; i < f->ssa.value_count; ++i)
        if (f->ssa_values[i].kind == 29) join = i;
    for (uintptr_t i = 0; i < f->lir.count; ++i) {
        if (f->lir_instructions[i].kind == 7) call = i + 1;
        if (f->lir_instructions[i].kind == 103) returned = i + 1;
        if (f->lir_instructions[i].kind == 104) return 2;
    }
    if (!join || !call || !returned) return 3;
    /* A void join has no incoming machine values to copy. */
    f->ssa_values[join].left = 1;
    if (ssa_verify_function(&f->context)) return 4;
    f->ssa_values[join].left = 0;
    /* A marker cannot masquerade as a value literal or PHI. */
    f->ssa_values[join].kind = 1;
    f->types[join].kind = 1;
    if (ssa_verify_function(&f->context)) return 5;
    f->ssa_values[join].kind = 28;
    f->types[join].kind = 28;
    if (ssa_verify_function(&f->context)) return 6;
    f->ssa_values[join].kind = 29;
    f->types[join].kind = 29;
    f->lir_instructions[returned - 1].left = f->lir_instructions[call - 1].destination;
    if (lir_verify_function(&f->context)) return 7;
    f->lir_instructions[returned - 1].left = 0;
    f->lir_instructions[call - 1].scalar_code = 1;
    if (lir_verify_function(&f->context)) return 8;
    f->lir_instructions[call - 1].scalar_code = 12;
    return ssa_verify_function(&f->context) && lir_verify_function(&f->context) ? 0 : 9;
}

static int check_ssa_mutations(struct fixture *f) {
    uintptr_t phi = 0;
    for (uintptr_t i = 0; i < f->ssa.value_count; ++i)
        if (f->ssa_values[i].kind == 28) phi = i + 1;
    if (!phi) return 1;
    struct native_ssa_value saved = f->ssa_values[phi - 1];
    f->ssa_values[phi - 1].predecessor_left = saved.predecessor_right;
    if (ssa_verify_function(&f->context)) return 2;
    f->ssa_values[phi - 1] = saved;
    f->ssa_values[phi - 1].left = saved.right;
    if (ssa_verify_function(&f->context)) return 3;
    f->ssa_values[phi - 1] = saved;
    f->ssa_values[phi - 1].left = f->ssa.value_count + 1;
    if (ssa_verify_function(&f->context)) return 4;
    f->context.optimization = 1;
    if (ssa_optimize_function(&f->context)) return 9;
    if (f->ssa_values[phi - 1].left != f->ssa.value_count + 1) return 10;
    f->context.optimization = 0;
    f->ssa_values[phi - 1] = saved;
    f->ssa_values[phi - 1].scalar_code = 3;
    f->types[phi - 1].scalar_code = 3;
    if (ssa_verify_function(&f->context)) return 5;
    f->ssa_values[phi - 1] = saved;
    f->types[phi - 1].scalar_code = saved.scalar_code;
    uintptr_t target = f->ssa_blocks[0].target_left;
    f->ssa_blocks[0].target_left = f->ssa.block_count + 1;
    if (ssa_verify_function(&f->context)) return 6;
    f->ssa_blocks[0].target_left = target;
    uintptr_t next = f->ssa_values[0].next;
    f->ssa_values[0].next = 1;
    if (ssa_verify_function(&f->context)) return 7;
    f->ssa_values[0].next = next;
    return ssa_verify_function(&f->context) ? 0 : 8;
}

static int check_lir_mutations(struct fixture *f) {
    uintptr_t copy = 0, binary = 0;
    for (uintptr_t i = 0; i < f->lir.count; ++i) {
        if (f->lir_instructions[i].kind == 104) copy = i + 1;
        if (f->lir_instructions[i].kind == 4) binary = i + 1;
    }
    if (!copy || !binary) return 1;
    struct native_lir_instruction saved = f->lir_instructions[binary - 1];
    f->lir_instructions[binary - 1].left = saved.destination;
    if (lir_verify_function(&f->context)) return 2;
    f->lir_instructions[binary - 1] = saved;
    f->lir_instructions[0].target = f->lir.label_count + 1;
    if (lir_verify_function(&f->context)) return 3;
    f->lir_instructions[0].target = 1;
    struct native_lir_instruction removed = f->lir_instructions[copy - 1];
    memmove(&f->lir_instructions[copy - 1], &f->lir_instructions[copy],
            (f->lir.count - copy) * sizeof removed);
    --f->lir.count;
    if (lir_verify_function(&f->context)) return 4;
    memmove(&f->lir_instructions[copy], &f->lir_instructions[copy - 1],
            (f->lir.count - copy + 1) * sizeof removed);
    f->lir_instructions[copy - 1] = removed;
    ++f->lir.count;
    f->types[0].pointee = UINTPTR_MAX;
    if (lir_verify_function(&f->context)) return 5;
    f->types[0].pointee = 0;
    return lir_verify_function(&f->context) ? 0 : 6;
}

int main(void) {
    struct fixture fixture = {0};
    if (!compile_fixture(&fixture)) return 1;
    if (!ssa_verify_function(&fixture.context) || !lir_verify_function(&fixture.context)) return 2;
    if (check_ssa_mutations(&fixture)) return 3;
    if (check_lir_mutations(&fixture)) return 4;
    if (check_void_mutations(&fixture)) return 5;
    int dead_status = check_dead_values(&fixture);
    if (dead_status) {
        fprintf(stderr, "dead-value verification failed: %d\n", dead_status);
        return 6;
    }
    int cfg_status = check_cfg_copy(&fixture);
    if (cfg_status) {
        fprintf(stderr, "CFG copy verification failed: %d\n", cfg_status);
        return 7;
    }
    cfg_status = check_cfg_cycles(&fixture);
    if (cfg_status) {
        fprintf(stderr, "CFG cycle verification failed: %d\n", cfg_status);
        return 8;
    }
    return 0;
}
