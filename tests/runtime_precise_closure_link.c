#include "../runtime/psl_runtime.h"
#include <assert.h>
static psl_value identity(psl_value environment,psl_value argument) {
 (void)environment;return argument;
}
int main(void) {
 psl_value closure=PSL_NIL;psl_root frame;psl_rt_push_roots(&frame,&closure,1);
 closure=psl_rt_make_closure_precise(identity,PSL_NIL);
 psl_rt_collect_precise();assert(psl_rt_live_objects()==1);
 closure=PSL_NIL;psl_rt_collect_precise();assert(psl_rt_live_objects()==0);
 psl_rt_pop_roots(&frame);return 0;
}
