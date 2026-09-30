#include <assert.h>
#include <string.h>

extern int answer(void);

int check_c_strings(const unsigned char *first, const unsigned char *second) {
    assert(first != second);
    assert(strcmp((const char *)first, "portable") == 0);
    assert(strcmp((const char *)second, "systems lisp") == 0);
    return 42;
}

int main(void) {
    assert(answer() == 42);
    return 0;
}
