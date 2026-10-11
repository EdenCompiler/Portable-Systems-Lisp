#include "../bootstrap/native_api.h"
#include <assert.h>
#include <string.h>
int main(void) {
    struct native_signature records[12];
    struct native_parameter parameters[15];
    struct native_signature_context signatures = {0};
    struct native_compile_context context = {0};
    memset(records, 0xa5, sizeof records);
    memset(parameters, 0xa5, sizeof parameters);
    signatures.signatures = records; signatures.signature_capacity = 10;
    signatures.parameters = parameters; signatures.parameter_capacity = 13;
    context.signatures = &signatures;
    assert(!native_register_runtime_signatures(&context));
    assert(!signatures.signature_count && !signatures.parameter_count);
    context.profile = 1;
    signatures.parameter_capacity = 12;
    assert(!native_register_runtime_signatures(&context));
    assert(!signatures.signature_count && !signatures.parameter_count);
    assert(records[0].name == UINTPTR_MAX / 255 * 165);
    signatures.parameter_capacity = 13;
    signatures.signature_count = 11;
    assert(!native_register_runtime_signatures(&context));
    assert(signatures.signature_count == 11 && !signatures.parameter_count);
    signatures.signature_count = 0;
    signatures.parameter_count = 14;
    assert(!native_register_runtime_signatures(&context));
    assert(!signatures.signature_count && signatures.parameter_count == 14);
    signatures.parameter_count = 0;
    assert(native_register_runtime_signatures(&context));
    assert(signatures.signature_count == 10 && signatures.parameter_count == 13);
    assert(records[0].arity == 2 && records[0].result_code == 15);
    assert(!memcmp(records[0].runtime_name, "psl_rt_cons_precise", 18));
    assert(records[4].result_code == 9 && records[4].allocation_free == 1);
    assert(records[5].arity == 0 && records[5].result_code == 12);
    assert(records[8].arity == 2 && records[8].result_code == 0);
    for (unsigned i = 0; i < 10; ++i) {
        assert(native_runtime_signature_p(&context, &records[i]));
        unsigned saved = records[i].result_code;
        records[i].result_code = 11;
        assert(!native_runtime_signature_p(&context, &records[i]));
        records[i].result_code = saved;
    }
    context.profile = 0;
    assert(!native_runtime_signature_p(&context, &records[0]));
    return 0;
}
