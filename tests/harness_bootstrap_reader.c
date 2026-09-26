#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct psl_scanner {
    const uint8_t *data;
    uintptr_t length;
    uintptr_t cursor;
    uint8_t error;
};

struct psl_token {
    uint32_t kind;
    uintptr_t start;
    uintptr_t length;
};

extern uint32_t scan_next(struct psl_scanner *scanner,
                          struct psl_token *token);

struct expected_token {
    uint32_t kind;
    const char *spelling;
};

static int check_fixture(void) {
    static const char source[] =
        " \t; comment\n(defun |two words| (x) `(,x ,@items) #'fn \"a\\\"b\")";
    static const struct expected_token expected[] = {
        {1, "("}, {8, "defun"}, {8, "|two words|"}, {1, "("},
        {8, "x"}, {2, ")"}, {4, "`"}, {1, "("}, {5, ","},
        {8, "x"}, {6, ",@"}, {8, "items"}, {2, ")"},
        {9, "#'"}, {8, "fn"}, {7, "\"a\\\"b\""}, {2, ")"}
    };
    struct psl_scanner scanner = {
        (const uint8_t *)source, sizeof source - 1, 0, 0
    };
    struct psl_token token = {0};

    for (size_t i = 0; i < sizeof expected / sizeof expected[0]; ++i) {
        size_t length = strlen(expected[i].spelling);
        if (scan_next(&scanner, &token) != expected[i].kind) return 1;
        if (token.kind != expected[i].kind || token.length != length) return 2;
        if (memcmp(source + token.start, expected[i].spelling, length) != 0)
            return 3;
    }
    if (scan_next(&scanner, &token) != 0 || token.length != 0) return 4;
    return 0;
}

static int check_unterminated(const char *source) {
    struct psl_scanner scanner = {
        (const uint8_t *)source, strlen(source), 0, 0
    };
    struct psl_token token = {0};
    return scan_next(&scanner, &token) == 255 && token.kind == 255 ? 0 : 1;
}

static int check_file(const char *path) {
    FILE *stream = fopen(path, "rb");
    uint8_t *source;
    long size;
    struct psl_scanner scanner;
    struct psl_token token = {0};

    if (!stream) return 1;
    if (fseek(stream, 0, SEEK_END) != 0 || (size = ftell(stream)) < 0 ||
        fseek(stream, 0, SEEK_SET) != 0) {
        fclose(stream);
        return 2;
    }
    source = malloc((size_t)size + 1);
    if (!source) {
        fclose(stream);
        return 3;
    }
    if (fread(source, 1, (size_t)size, stream) != (size_t)size) {
        free(source);
        fclose(stream);
        return 4;
    }
    fclose(stream);
    scanner = (struct psl_scanner){source, (uintptr_t)size, 0, 0};
    for (;;) {
        uintptr_t before = scanner.cursor;
        uint32_t kind = scan_next(&scanner, &token);
        if (kind == 255 || scanner.cursor < before) {
            free(source);
            return 5;
        }
        if (kind == 0) break;
        if (scanner.cursor == before) {
            free(source);
            return 6;
        }
    }
    free(source);
    return 0;
}

int main(int argc, char **argv) {
    if (check_fixture()) return 1;
    if (check_unterminated("\"unfinished")) return 2;
    if (check_unterminated("|unfinished")) return 3;
    if (check_unterminated("\\")) return 4;
    for (int i = 1; i < argc; ++i) {
        if (check_file(argv[i])) return 5;
    }
    return 0;
}
