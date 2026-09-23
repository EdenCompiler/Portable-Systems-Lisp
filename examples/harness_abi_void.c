extern void relay_void(void *);
extern int notify_then_42(void *);

static void *last_value;

void consume_c(void *value)
{
    last_value = value;
}

int main(void)
{
    int value = 7;
    relay_void(&value);
    if (last_value != &value)
        return 1;
    last_value = 0;
    if (notify_then_42(&value) != 42 || last_value != &value)
        return 2;
    return 0;
}
