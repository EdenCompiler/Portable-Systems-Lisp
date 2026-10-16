#include "../bootstrap/native_api.h"
#include <assert.h>
#include <string.h>
int main(void) {
    struct native_signature records[30];
    struct native_parameter parameters[47];
    struct native_signature_context signatures = {0};
    struct native_compile_context context = {0};
    memset(records, 0xa5, sizeof records);
    memset(parameters, 0xa5, sizeof parameters);
    signatures.signatures = records; signatures.signature_capacity = 28;
    signatures.parameters = parameters; signatures.parameter_capacity = 45;
    context.signatures = &signatures;
    assert(!native_register_runtime_signatures(&context));
    assert(!signatures.signature_count && !signatures.parameter_count);
    context.profile = 1;
    signatures.parameter_capacity = 44;
    assert(!native_register_runtime_signatures(&context));
    assert(!signatures.signature_count && !signatures.parameter_count);
    assert(records[0].name == UINTPTR_MAX / 255 * 165);
    signatures.parameter_capacity = 45;
    signatures.signature_count = 29;
    assert(!native_register_runtime_signatures(&context));
    assert(signatures.signature_count == 29 && !signatures.parameter_count);
    signatures.signature_count = 0;
    signatures.parameter_count = 46;
    assert(!native_register_runtime_signatures(&context));
    assert(!signatures.signature_count && signatures.parameter_count == 46);
    signatures.parameter_count = 0;
    assert(native_register_runtime_signatures(&context));
    assert(signatures.signature_count == 28 && signatures.parameter_count == 45);
    assert(records[0].arity == 2 && records[0].result_code == 15);
    assert(!memcmp(records[0].runtime_name, "psl_rt_cons_precise", 18));
    assert(records[4].result_code == 9 && records[4].allocation_free == 1);
    assert(records[5].arity == 0 && records[5].result_code == 12);
    assert(records[8].arity == 2 && records[8].result_code == 0);
    for (unsigned i = 0; i < 28; ++i) {
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
    assert(records[21].arity==2 && records[21].result_code==15 && !records[21].allocation_free);
    assert(records[22].arity==2 && records[22].result_code==15 && !records[22].allocation_free);
    assert(parameters[records[21].first_parameter].scalar_code==2);
    assert(parameters[records[21].first_parameter+1].scalar_code==15);
    assert(parameters[records[22].first_parameter].scalar_code==15);
    assert(parameters[records[22].first_parameter+1].scalar_code==15);
    assert(records[23].arity==2 && records[23].result_code==15 && !records[23].allocation_free);
    assert(parameters[records[23].first_parameter].scalar_code==2);
    assert(parameters[records[23].first_parameter+1].scalar_code==15);
    assert(records[24].arity==1 && records[24].result_code==2 && records[24].allocation_free);
    assert(parameters[records[24].first_parameter].scalar_code==15);
    assert(records[25].arity==2 && records[25].result_code==15 && records[25].allocation_free);
    assert(parameters[records[25].first_parameter].scalar_code==15);
    assert(parameters[records[25].first_parameter+1].scalar_code==2);
    assert(records[26].arity==3 && records[26].result_code==15 && records[26].allocation_free);
    assert(parameters[records[26].first_parameter].scalar_code==15);
    assert(parameters[records[26].first_parameter+1].scalar_code==2);
    assert(parameters[records[26].first_parameter+2].scalar_code==15);
    assert(records[27].arity==2 && records[27].result_code==2 && !records[27].allocation_free);
    assert(parameters[records[27].first_parameter].scalar_code==15);
    assert(parameters[records[27].first_parameter+1].scalar_code==15);
    context.profile = 0;
    assert(!native_runtime_signature_p(&context, &records[0]));
    return 0;
}
