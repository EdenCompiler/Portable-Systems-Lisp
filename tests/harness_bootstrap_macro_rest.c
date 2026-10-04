#include <assert.h>
#include <stdint.h>
#include <stdio.h>
extern uint64_t macro_rest_value(uint64_t), macro_rest_order(uint64_t), macro_rest_quote(uint64_t);
extern uint64_t macro_rest_empty(void), macro_rest_repeated(uint64_t), macro_rest_names(uint64_t);
static uint64_t observed[2];
static unsigned count;
uint64_t macro_rest_tick(uint64_t value) { assert(count<2); observed[count++]=value; return value; }
int main(void) {
    const uint64_t values[]={0,42,UINT64_MAX};
    for (unsigned i=0;i<sizeof values/sizeof values[0];++i) {
        uint64_t value=values[i];
        assert(macro_rest_value(value)==value+42);
        count=0;
        assert(macro_rest_order(value)==42 && count==2);
        assert(observed[0]==value && observed[1]==value+1);
        assert(macro_rest_quote(value)==value+9);
        assert(macro_rest_repeated(value)==value*2+7);
        assert(macro_rest_names(value)==value+9);
    }
    assert(macro_rest_empty()==84);
    puts("macro rest/body arguments, empty lists, splicing and order passed");
    return 0;
}
