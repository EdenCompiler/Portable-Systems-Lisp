#include <assert.h>
#include <stdint.h>
#include <stdio.h>

extern uint64_t macro_primitive_values(void);
extern uint64_t macro_primitive_equal_one(void);
extern uint64_t macro_primitive_second_short(void);
extern uint64_t macro_primitive_second_empty(void);
extern uint64_t macro_primitive_eq_empty_list_nil(void);
extern uint64_t macro_primitive_eq_nil_empty_list(void);
extern uint64_t macro_primitive_eq_quoted_empty_list(void);
extern uint64_t macro_primitive_eq_distinct_symbols(void);
extern uint64_t macro_primitive_eq_qualified_escaped_symbol(void);
extern uint64_t macro_primitive_second_three(void);
extern uint64_t macro_primitive_second_list(void);
extern uint64_t macro_primitive_length_zero(void);
extern uint64_t macro_primitive_length_two(void);
extern uint64_t macro_primitive_length_ten(void);
extern uint64_t macro_primitive_length_template(void);

int main(void) {
    assert(macro_primitive_values() == 37);
    assert(macro_primitive_equal_one() == 43);
    assert(macro_primitive_second_short() == 41);
    assert(macro_primitive_second_empty() == 42);
    assert(macro_primitive_eq_empty_list_nil() == 46);
    assert(macro_primitive_eq_nil_empty_list() == 47);
    assert(macro_primitive_eq_quoted_empty_list() == 48);
    assert(macro_primitive_eq_distinct_symbols() == 49);
    assert(macro_primitive_eq_qualified_escaped_symbol() == 50);
    assert(macro_primitive_second_three() == 44);
    assert(macro_primitive_second_list() == 43);
    assert(macro_primitive_length_zero() == 0);
    assert(macro_primitive_length_two() == 2);
    assert(macro_primitive_length_ten() == 10);
    assert(macro_primitive_length_template() == 45);
    puts("compile-time macro primitives preserve Common Lisp values");
    return 0;
}
