#include <stdint.h>
#include <assert.h>
#include <stdio.h>
extern uint64_t optional_answer(uint64_t), optional_empty(void), optional_rest(uint64_t);
extern uint64_t optional_nil(void), reader_empty_nil(void);
extern uint64_t optional_lazy(uint64_t), optional_one_spec(uint64_t);
int main(void) {
    const uint64_t values[]={0,4,UINT64_MAX};
    for (unsigned i=0;i<sizeof values/sizeof values[0];++i) {
        uint64_t value=values[i];
        assert(optional_answer(value)==value*2+10);
        assert(optional_rest(value)==value+9);
        assert(optional_lazy(value)==value);
        assert(optional_one_spec(value)==value);
    }
    assert(optional_empty()==42 && optional_nil()==84 && reader_empty_nil()==42);
    puts("macro optional defaults, supplied flags, lazy initialization and NIL passed");
    return 0;
}
