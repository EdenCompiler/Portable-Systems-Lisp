#include <stddef.h>
#include <stdint.h>

struct inner { unsigned char tag; unsigned long count; };
struct outer { unsigned char head; struct inner inner; unsigned short tail; };
struct mixed { unsigned char tag; float measure; void *context; double ratio; };

extern size_t outer_size(void);
extern size_t outer_alignment(void);
extern size_t inner_offset(void);
extern size_t count_offset(void);
extern size_t mixed_size(void);
extern size_t mixed_alignment(void);
extern size_t mixed_context_offset(void);
extern unsigned long read_inner_count(struct inner *);

int main(void)
{
    struct inner value = { 3, 0x12345678UL };

    if (outer_size() != sizeof(struct outer))
        return 1;
    if (outer_alignment() != _Alignof(struct outer))
        return 2;
    if (inner_offset() != offsetof(struct outer, inner))
        return 3;
    if (count_offset() != offsetof(struct inner, count))
        return 4;
    if (read_inner_count(&value) != value.count)
        return 5;
    if (mixed_size() != sizeof(struct mixed))
        return 6;
    if (mixed_alignment() != _Alignof(struct mixed))
        return 7;
    if (mixed_context_offset() != offsetof(struct mixed, context))
        return 8;
    return 0;
}
