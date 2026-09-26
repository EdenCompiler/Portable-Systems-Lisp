#include "../bootstrap/native_api.h"
#include <string.h>

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
    struct native_parameter parameters[1];
    struct native_signature_context signature_context;
    struct native_function functions[1];
    struct native_hir_arena hir;
    struct native_ssa_arena ssa;
    struct native_lir_arena lir;
    struct native_fixup_arena call_fixups, jump_fixups;
    struct byte_buffer code;
    struct native_compile_context context;
};

static int compile_fixture(struct fixture *f) {
    static const uint8_t source[] =
        "(defun choice (input)"
        " (declare (type u64 input) (returns u64) (c-export :c))"
        " (let ((x (if (< input 2) (wrap+ input 10) (wrap* input 3))))"
        "   (wrap+ x 1)))";
    f->scanner = (struct psl_scanner){source, sizeof source - 1, 0, 0};
    f->parser = (struct psl_parser){&f->scanner, &f->token, 0, f->syntax, 0, 256, 0};
    f->layouts = (struct native_layout_context){
        &f->parser, source, NULL, 0, 0, NULL, 0, 0, &f->shape, 0
    };
    f->signature_context = (struct native_signature_context){
        &f->layouts, f->signatures, 0, 1, f->parameters, 0, 1, 0
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
        0, 0, 0, 0, &f->ssa, f->bindings, &f->lir, f->labels, &f->jump_fixups
    };
    uintptr_t root = parser_next(&f->parser);
    return root && native_parse_signature(&f->signature_context, root) &&
           predeclare_scalar_form(&f->context, f->signatures, f->functions) &&
           compile_scalar_form(&f->context, f->signatures, f->functions);
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
    return 0;
}
