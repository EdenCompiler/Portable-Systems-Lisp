#include "../bootstrap/native_api.h"
#include <assert.h>
#include <string.h>
int main(void) {
    struct native_signature records[23];
    struct native_parameter parameters[33];
    struct native_signature_context signatures = {0};
    struct native_compile_context context = {0};
    memset(records, 0xa5, sizeof records);
    memset(parameters, 0xa5, sizeof parameters);
    signatures.signatures = records; signatures.signature_capacity = 21;
    signatures.parameters = parameters; signatures.parameter_capacity = 31;
    context.signatures = &signatures;
    assert(!native_register_runtime_signatures(&context));
    assert(!signatures.signature_count && !signatures.parameter_count);
    context.profile = 1;
    signatures.parameter_capacity = 30;
    assert(!native_register_runtime_signatures(&context));
    assert(!signatures.signature_count && !signatures.parameter_count);
    assert(records[0].name == UINTPTR_MAX / 255 * 165);
    signatures.parameter_capacity = 31;
    signatures.signature_count = 22;
    assert(!native_register_runtime_signatures(&context));
    assert(signatures.signature_count == 22 && !signatures.parameter_count);
    signatures.signature_count = 0;
    signatures.parameter_count = 32;
    assert(!native_register_runtime_signatures(&context));
    assert(!signatures.signature_count && signatures.parameter_count == 32);
    signatures.parameter_count = 0;
    assert(native_register_runtime_signatures(&context));
    assert(signatures.signature_count == 21 && signatures.parameter_count == 31);
    assert(records[0].arity == 2 && records[0].result_code == 15);
    assert(!memcmp(records[0].runtime_name, "psl_rt_cons_precise", 18));
    assert(records[4].result_code == 9 && records[4].allocation_free == 1);
    assert(records[5].arity == 0 && records[5].result_code == 12);
    assert(records[8].arity == 2 && records[8].result_code == 0);
    for (unsigned i = 0; i < 21; ++i) {
        assert(native_runtime_signature_p(&context, &records[i]));
        unsigned saved = records[i].result_code;
        records[i].result_code = 11;
        assert(!native_runtime_signature_p(&context, &records[i]));
        records[i].result_code = saved;
    }
    assert(records[10].arity == 2 && records[10].result_code == 15 && !records[10].allocation_free);
    assert(records[11].result_code == 3 && records[11].result_size == 1);
    assert(parameters[records[10].first_parameter + 1].scalar_code == 3);
    assert(parameters[records[10].first_parameter + 1].size == 1);
    assert(records[12].result_code == 12 && records[12].arity == 3);
    assert(records[13].arity == 2 && records[13].result_code == 15 && !records[13].allocation_free);
    assert(records[13].runtime_name_length == 37);
    assert(!memcmp(records[13].runtime_name, "psl_rt_make_string_from_bytes_precise", 37));
    assert(parameters[records[13].first_parameter].scalar_code == 1);
    assert(parameters[records[13].first_parameter+1].scalar_code == 2);
    for(unsigned i=14;i<19;++i) {
        assert(records[i].result_code==15 && records[i].result_size==8);
        assert(records[i].arity==(i==18?2:1));
        assert(records[i].allocation_free==(i==15 || i==17));
        assert(parameters[records[i].first_parameter].scalar_code==15);
    }
    assert(records[19].arity==2 && records[19].result_code==15 && !records[19].allocation_free);
    assert(records[20].arity==1 && records[20].result_code==15 && records[20].allocation_free);
    assert(parameters[records[20].first_parameter].scalar_code==2);
    context.profile = 0;
    assert(!native_runtime_signature_p(&context, &records[0]));
    return 0;
}
