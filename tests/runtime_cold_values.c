#include "../runtime/psl_runtime.h"
#include <assert.h>
#include <stdlib.h>
static unsigned registrations;
void __real_psl_rt_register_permanent_roots(psl_value *,size_t);
void __wrap_psl_rt_register_permanent_roots(psl_value *values,size_t count) {
 ++registrations;__real_psl_rt_register_permanent_roots(values,count);
}
#ifdef VERIFY_MALLOC
static unsigned allocations;
void *__real_malloc(size_t);
void *__wrap_malloc(size_t n) {++allocations;return __real_malloc(n);}
#endif
int main(void) {
 assert(psl_rt_value_count()==0 && psl_rt_nth_value(0)==PSL_NIL);
 assert(psl_rt_nth_value(1)==PSL_NIL && psl_rt_nth_value(SIZE_MAX)==PSL_NIL);
 assert(!registrations);
#ifdef VERIFY_MALLOC
 assert(!allocations);
#endif
 assert(psl_rt_values2(PSL_TRUE,PSL_NIL)==PSL_TRUE);assert(registrations==1);
#ifdef VERIFY_MALLOC
 assert(allocations==1);
#endif
 assert(psl_rt_nth_value(0)==PSL_TRUE && psl_rt_nth_value(1)==PSL_NIL);
 assert(psl_rt_nth_value(2)==PSL_NIL && registrations==1);
#ifdef VERIFY_MALLOC
 assert(allocations==1);
#endif
 return 0;
}
