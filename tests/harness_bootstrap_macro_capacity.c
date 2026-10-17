#include <stdint.h>

extern uint64_t macro_registry_capacity_answer(void);
extern uint64_t macro_binding_capacity_answer(void);

int main(void) {
    return macro_registry_capacity_answer() == 1 &&
           macro_binding_capacity_answer() == 1 ? 0 : 1;
}
