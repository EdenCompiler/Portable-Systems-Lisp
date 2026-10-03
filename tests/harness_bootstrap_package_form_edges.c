#include "../bootstrap/native_api.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
int main(void) {
    const char *text = "(defpackage \"EXAMPLE\" (:use))";
    struct psl_scanner scanner = {(const uint8_t *)text, strlen(text), 0, 0};
    struct psl_token token = {0};
    struct psl_ast_node nodes[64] = {{0}};
    struct psl_parser parser = {.scanner=&scanner, .token=&token, .nodes=nodes, .capacity=64};
    struct native_compile_context context = {.parser=&parser, .source=(const uint8_t *)text};
    struct native_package_context state = {0};
    uintptr_t root = parser_next(&parser);
    assert(root && !parser.error);
    uintptr_t count = parser.count;
    assert(native_source_package_kind(&context, root) == 1);
    assert(!native_apply_package_form(&context, root, &state));
    assert(state.error == NATIVE_CT_REFERENCE && !state.environment);
    assert(parser.count == count && !parser.error);
    assert(!native_source_package_kind(&context, 0));
    assert(!native_source_package_kind(&context, UINTPTR_MAX));
    assert(!native_apply_package_form(&context, 0, &state));
    assert(state.error == NATIVE_CT_REFERENCE);
    assert(!native_apply_package_form(&context, UINTPTR_MAX, &state));
    assert(state.error == NATIVE_CT_REFERENCE);
    struct native_reader_environment reader = {0};
    parser.environment = &reader;
    assert(!native_apply_package_form(&context, root, &state));
    assert(state.error == NATIVE_CT_REFERENCE && !state.environment);
    assert(parser.count == count && !parser.error);
    struct native_ct_environment env = {.error=NATIVE_CT_CAPACITY, .current_package=99};
    reader.environment = &env;
    assert(!native_apply_package_form(&context, root, &state));
    assert(state.error == NATIVE_CT_CAPACITY && env.current_package == 99);
    assert(parser.count == count && !parser.error);
    puts("native source package APIs reject missing environments and invalid references");
}
