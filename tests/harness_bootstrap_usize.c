#include <stdint.h>
#include <stddef.h>

extern size_t add_size(size_t left, size_t right);
extern size_t choose_size(size_t left, size_t right);
extern size_t answer_size(void);

int main(void) {
    return add_size(SIZE_MAX, 1) == 0
        && add_size(20, 22) == 42
        && choose_size(7, 9) == 9
        && choose_size(9, 7) == 9
        && answer_size() == 42 ? 0 : 1;
}
