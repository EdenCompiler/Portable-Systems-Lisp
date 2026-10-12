#include "../runtime/psl_runtime.h"
#include <assert.h>
int main(void) {
 psl_value live=psl_rt_make_string_precise(3,65);psl_root root;
 psl_rt_push_roots(&root,&live,1);
 assert(psl_rt_string_length(live)==3);
 assert(psl_rt_string_byte(live,0)==65 && psl_rt_string_byte(live,2)==65);
 psl_rt_string_set_byte(live,1,0);assert(psl_rt_string_byte(live,1)==0);
 /* Machine aliases are deliberately outside the explicit root vector. */
 uint64_t raw=psl_rt_make_string_precise(8,99);
 for(unsigned i=0;i<1024;++i) (void)psl_rt_make_string_precise(i%17,255);
 assert(raw && psl_rt_live_objects()<130);
 psl_rt_collect_precise();assert(psl_rt_live_objects()==1);
 assert(psl_rt_string_length(live)==3 && psl_rt_string_byte(live,2)==65);
 psl_rt_pop_roots(&root);psl_rt_collect_precise();assert(psl_rt_live_objects()==0);
 live=psl_rt_make_string_precise(0,0);assert(psl_rt_string_length(live)==0);
 psl_rt_collect_precise();assert(psl_rt_live_objects()==0);return 0;
}
