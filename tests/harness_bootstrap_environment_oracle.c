#include "../bootstrap/frontend/environment.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint8_t names[200000];
static struct native_ct_package packages[16];
static struct native_ct_symbol symbols[2400];
static struct native_ct_presence present[3000];
static struct native_ct_use uses[32];
static struct native_ct_alias aliases[8];
static uintptr_t identities[2000];

int main(int argc, char **argv) {
    assert(argc == 2);
    struct native_ct_environment e = {
        .names=names, .name_capacity=sizeof names,
        .packages=packages, .package_capacity=16,
        .symbols=symbols, .symbol_capacity=2400,
        .present=present, .present_capacity=3000,
        .uses=uses, .use_capacity=32,
        .aliases=aliases, .alias_capacity=8
    };
    assert(native_ct_seed_standard(&e));
    FILE *oracle = fopen(argv[1], "r");
    assert(oracle);
    char line[1024];
    unsigned observations = 0;
    while (fgets(line, sizeof line, oracle)) {
        char *home = strchr(line, '\t'); assert(home); *home++ = 0;
        char *name = strchr(home, '\t'); assert(name); *name++ = 0;
        char *token = strchr(name, '\t'); assert(token); *token++ = 0;
        char *newline = strpbrk(token, "\r\n"); assert(newline); *newline = 0;
        unsigned expected = (unsigned)strtoul(line, NULL, 10);
        uintptr_t symbol = native_ct_read_symbol(&e, (const uint8_t *)token, strlen(token));
        if (!expected) {
            assert(!symbol && e.error); e.error = 0;
        } else {
            if (!symbol || e.error) fprintf(stderr,"token %s: native error %u, oracle identity %u\n",token,e.error,expected);
            assert(symbol && !e.error && expected < 2000);
            if (identities[expected]) assert(identities[expected] == symbol);
            else {
                for (unsigned i=1; i<2000; ++i) assert(identities[i] != symbol);
                identities[expected] = symbol;
            }
            uintptr_t package = !strcmp(home, "NONE") ? 0 :
                native_ct_find_package(&e, (const uint8_t *)home, strlen(home));
            assert(package || !strcmp(home, "NONE"));
            const struct native_ct_symbol *definition = &symbols[symbol-1];
            assert(definition->package == package && definition->length == strlen(name));
            assert(!memcmp(names + definition->name, name, definition->length));
        }
        ++observations;
    }
    assert(!ferror(oracle) && fclose(oracle) == 0 && observations == 811);
    puts("native symbol names and identities match 811 independent SBCL reader observations");
    return 0;
}
