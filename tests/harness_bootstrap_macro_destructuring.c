#include <assert.h>
#include <stdint.h>
#include <stdio.h>

extern uint64_t destructuring_empty(void);
extern uint64_t destructuring_nil(void);
extern uint64_t destructuring_optional_default(void);
extern uint64_t destructuring_optional_provided(void);
extern uint64_t destructuring_optional_outer(void);
extern uint64_t destructuring_optional_lazy(void);
extern uint64_t destructuring_optional_only_nil(void);
extern uint64_t destructuring_optional_only_empty(void);
extern uint64_t destructuring_optional_only_supplied(void);
extern uint64_t destructuring_quoted_prefix(void);
extern uint64_t destructuring_explicit_quote_list(void);
extern uint64_t destructuring_function_prefix(void);
extern uint64_t destructuring_explicit_function_list(void);
extern uint64_t destructuring_empty_sublist(void);
extern uint64_t destructuring_empty_subnil(void);

int main(void) {
    assert(destructuring_empty() == 19);
    assert(destructuring_nil() == 19);
    assert(destructuring_optional_default() == 42);
    assert(destructuring_optional_provided() == 24);
    assert(destructuring_optional_outer() == 26);
    assert(destructuring_optional_lazy() == 22);
    assert(destructuring_optional_only_nil() == 19);
    assert(destructuring_optional_only_empty() == 19);
    assert(destructuring_optional_only_supplied() == 9);
    assert(destructuring_quoted_prefix() == 42);
    assert(destructuring_explicit_quote_list() == 42);
    assert(destructuring_function_prefix() == 31);
    assert(destructuring_explicit_function_list() == 31);
    assert(destructuring_empty_sublist() == 31);
    assert(destructuring_empty_subnil() == 31);
    puts("native macro destructuring supports empty, nested and optional patterns");
    return 0;
}
