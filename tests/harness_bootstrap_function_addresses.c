#include <assert.h>
#include <stdint.h>
#include <string.h>
extern uint64_t address_target(void);
extern uintptr_t address_probe(void);
int main(void) {
 typedef uint64_t (*function)(void);
 _Static_assert(sizeof(function)==sizeof(uintptr_t),"supported function address ABI");
 uintptr_t address=address_probe();function target=NULL;memcpy(&target,&address,sizeof target);
 assert(target==address_target);assert(target()==42 && address_target()==42);
 return 0;
}
