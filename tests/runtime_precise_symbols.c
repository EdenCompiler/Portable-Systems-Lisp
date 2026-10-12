#include "../runtime/psl_runtime.h"
#include <assert.h>
#include <string.h>
static psl_value name(const char *s) {
 return psl_rt_make_string_from_bytes_precise((uint64_t)(uintptr_t)s,strlen(s));
}
int main(void) {
 psl_value values[3]={PSL_NIL,PSL_NIL,PSL_NIL};psl_root frame;
 psl_rt_push_roots(&frame,values,3);
 psl_value pkg_name=name("Package");values[0]=psl_rt_make_package_precise(pkg_name);
 values[1]=name("Keep");values[2]=psl_rt_intern_precise(values[0],values[1]);
 assert(psl_rt_symbol_name(values[2])==values[1]);
 uint64_t raw=psl_rt_make_symbol_precise(name("Dead"));
 for(unsigned i=0;i<2048;++i) {
  psl_value junk_name=name("Transient");
  (void)psl_rt_make_package_precise(junk_name);
  assert(psl_rt_intern_precise(values[0],values[1])==values[2]);
 }
 assert(raw && psl_rt_live_objects()<260);
 psl_rt_collect_precise();assert(psl_rt_live_objects()==4);
 assert(psl_rt_string_length(psl_rt_package_name(values[0]))==7);
 assert(psl_rt_string_byte(psl_rt_symbol_name(values[2]),0)=='K');
 psl_rt_pop_roots(&frame);psl_rt_collect_precise();assert(!psl_rt_live_objects());
 return 0;
}
