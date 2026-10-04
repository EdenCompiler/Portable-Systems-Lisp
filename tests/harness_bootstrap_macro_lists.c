#include <stdint.h>
#include <assert.h>
#include <stdio.h>
extern uint64_t lists_answer(uint64_t),lists_nil(void),lists_default(uint64_t),lists_effects(void);
static uint64_t calls;
uint64_t lists_tick(void) { return ++calls; }
int main(void) {
 const uint64_t values[]={0,4,UINT64_MAX};
 for(unsigned i=0;i<sizeof values/sizeof values[0];++i) {
  assert(lists_answer(values[i])==values[i]*2+13);
  assert(lists_default(values[i])==values[i]+3);
 }
 assert(lists_nil()==42);
 assert(lists_effects()==3 && calls==2);
 puts("build-host LIST constructs nested syntax, NIL and spliced defaults");
}
