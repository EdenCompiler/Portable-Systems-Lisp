#include "../bootstrap/native_api.h"
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/mman.h>
#endif

extern uintptr_t win64_frame_bytes(uintptr_t values, uintptr_t outgoing);
extern uintptr_t win64_function_prologue(struct byte_buffer *code, uintptr_t frame,
                                         uintptr_t outgoing);
extern int win64_load_parameter(struct byte_buffer *code, uintptr_t outgoing,
                                uintptr_t frame, uintptr_t index);
extern int win64_store_local(struct byte_buffer *code, uintptr_t outgoing,
                             uintptr_t reference, uintptr_t values);
extern int win64_load_local(struct byte_buffer *code, uintptr_t outgoing,
                            uintptr_t reference, uintptr_t values);
extern int win64_register_argument(struct byte_buffer *code, uintptr_t index);
extern int win64_stack_argument(struct byte_buffer *code, uintptr_t index,
                                uintptr_t outgoing);
extern int win64_return(struct byte_buffer *code, uintptr_t frame);
extern int win64_write_unwind(struct byte_buffer *output, uintptr_t frame,
                              uintptr_t prologue);
extern int emit_integer(struct byte_buffer *output, uint64_t value, uintptr_t size);
extern int patch_i32(struct byte_buffer *output, uintptr_t position, int32_t value);

typedef uint64_t (
#ifdef _WIN32
    *win64_function
#else
    __attribute__((ms_abi)) *win64_function
#endif
)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);

static uint8_t code_bytes[1024];
static struct byte_buffer code = {code_bytes, 0, sizeof code_bytes};
static uintptr_t small_frame, large_frame, second_start, small_prologue, large_prologue;

static int build_callee(void) {
    small_frame = win64_frame_bytes(1, 32);
    small_prologue = win64_function_prologue(&code, small_frame, 32);
    return small_frame == 80 && small_prologue == 11 &&
           win64_load_parameter(&code, 32, small_frame, 5) &&
           win64_store_local(&code, 32, 1, 1) &&
           win64_load_parameter(&code, 32, small_frame, 1) &&
           emit_integer(&code, 0xc18948, 3) && /* mov rcx, rax */
           win64_load_local(&code, 32, 1, 1) &&
           emit_integer(&code, 0xc80148, 3) && /* add rax, rcx */
           win64_return(&code, small_frame);
}

static int build_caller(void) {
    second_start = code.length;
    large_frame = win64_frame_bytes(1020, 48);
    large_prologue = win64_function_prologue(&code, large_frame, 48);
    if (large_frame != 8256 || large_prologue != 67 ||
        !win64_load_parameter(&code, 48, large_frame, 1) ||
        !win64_register_argument(&code, 1) ||
        !win64_load_parameter(&code, 48, large_frame, 5) ||
        !win64_stack_argument(&code, 5, 48)) return 0;
    uintptr_t call = code.length;
    return emit_integer(&code, 0xe8, 1) && emit_integer(&code, 0, 4) &&
           patch_i32(&code, call + 1, (int32_t)(0 - (call + 5))) &&
           win64_return(&code, large_frame);
}

static int check_unwind_bytes(void) {
    uint8_t data[32] = {0};
    struct byte_buffer unwind = {data, 0, sizeof data};
    if (!win64_write_unwind(&unwind, small_frame, small_prologue)) return 0;
    if (unwind.length != 12 || data[0] != 1 || data[1] != 11 ||
        data[2] != 3 || data[3] != 5 || data[4] != 11 || data[5] != 3 ||
        data[6] != 8 || data[7] != 0x92 || data[8] != 1 || data[9] != 0x50) return 0;
    unwind.length = 0;
    if (!win64_write_unwind(&unwind, large_frame, large_prologue)) return 0;
    if (unwind.length != 12 || data[0] != 1 || data[1] != 67 ||
        data[2] != 4 || data[3] != 5 || data[4] != 67 || data[5] != 3 ||
        data[6] != 64 || data[7] != 1 || data[8] != (large_frame / 8 & 255) ||
        data[9] != (large_frame / 8 >> 8) || data[10] != 1 || data[11] != 0x50) return 0;
    unwind.length = 0;
    if (win64_write_unwind(&unwind, 80, 67) || unwind.length) return 0;
    unwind.length = 0;
    if (!win64_write_unwind(&unwind, 524288, 67) || unwind.length != 16 ||
        data[2] != 5 || data[6] != 64 || data[7] != 0x11 ||
        data[8] != 0 || data[9] != 0 || data[10] != 8 || data[11] != 0 ||
        data[12] != 1 || data[13] != 0x50) return 0;
    return 1;
}

#ifdef _WIN32
static uint8_t *allocate_executable(size_t size) {
    return VirtualAlloc(NULL, size, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE);
}
static void release_executable(uint8_t *base, size_t size) {
    (void)size;
    VirtualFree(base, 0, MEM_RELEASE);
}
#else
static uint8_t *allocate_executable(size_t size) {
    void *memory = mmap(NULL, size, PROT_READ | PROT_WRITE | PROT_EXEC,
                        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    return memory == MAP_FAILED ? NULL : memory;
}
static void release_executable(uint8_t *base, size_t size) {
    munmap(base, size);
}
#endif

#ifdef _WIN32
static int check_unwind_at(uint8_t *base, RUNTIME_FUNCTION *functions, unsigned function_index,
                           uintptr_t frame, uintptr_t offset, int allocated, int frame_set) {
    CONTEXT context = {0};
    _Alignas(16) uint8_t stack[32768] = {0};
    uintptr_t entry = ((uintptr_t)(stack + 28000) & ~(uintptr_t)15) + 8;
    uintptr_t saved = entry - 8;
    const uintptr_t return_address = (uintptr_t)0x123456789abcdef0ULL;
    const uintptr_t old_bp = (uintptr_t)0x1020304050607080ULL;
    memcpy((void *)entry, &return_address, 8);
    memcpy((void *)saved, &old_bp, 8);
    context.Rip = (DWORD64)(base + functions[function_index].BeginAddress + offset);
    context.Rsp = (DWORD64)(saved - (allocated ? frame : 0));
    context.Rbp = (DWORD64)(frame_set ? context.Rsp : old_bp);
    DWORD64 image_base = 0;
    PRUNTIME_FUNCTION found = RtlLookupFunctionEntry(context.Rip, &image_base, NULL);
    if (!found || found->BeginAddress != functions[function_index].BeginAddress) return 0;
    PVOID handler_data = NULL;
    DWORD64 establisher_frame = 0;
    RtlVirtualUnwind(UNW_FLAG_NHANDLER, image_base, context.Rip, found, &context,
                     &handler_data, &establisher_frame, NULL);
    return context.Rip == return_address && context.Rsp == entry + 8 &&
           context.Rbp == old_bp;
}

static int check_windows_unwind(uint8_t *base, RUNTIME_FUNCTION *functions) {
    int ok = RtlAddFunctionTable(functions, 2, (DWORD64)base);
    if (!ok) return 0;
    ok = check_unwind_at(base, functions, 0, small_frame, 1, 0, 0) &&
         check_unwind_at(base, functions, 0, small_frame, 8, 1, 0) &&
         check_unwind_at(base, functions, 0, small_frame, small_prologue, 1, 1) &&
         check_unwind_at(base, functions, 0, small_frame, small_prologue + 28, 1, 1) &&
         check_unwind_at(base, functions, 1, large_frame, 1, 0, 0) &&
         check_unwind_at(base, functions, 1, large_frame, 14, 0, 0) &&
         check_unwind_at(base, functions, 1, large_frame, 64, 1, 0) &&
         check_unwind_at(base, functions, 1, large_frame, large_prologue, 1, 1) &&
         check_unwind_at(base, functions, 1, large_frame, large_prologue + 28, 1, 1);
    RtlDeleteFunctionTable(functions);
    return ok;
}
#endif

int main(void) {
    if (!build_callee() || !build_caller() || !check_unwind_bytes()) {
        fprintf(stderr, "Win64 frame encoding failed\n");
        return 1;
    }
    uint8_t *memory = allocate_executable(4096);
    if (!memory) return 2;
    memcpy(memory, code.data, code.length);
#ifdef _WIN32
    RUNTIME_FUNCTION functions[2] = {{0, (DWORD)second_start, 0},
                                     {(DWORD)second_start, (DWORD)code.length, 0}};
    struct byte_buffer image = {memory, (code.length + 3) & ~(uintptr_t)3, 4096};
    functions[0].UnwindData = (DWORD)image.length;
    if (!win64_write_unwind(&image, small_frame, small_prologue)) return 3;
    functions[1].UnwindData = (DWORD)image.length;
    if (!win64_write_unwind(&image, large_frame, large_prologue)) return 4;
    if (!check_windows_unwind(memory, functions)) {
        fprintf(stderr, "Windows virtual unwind failed\n");
        return 5;
    }
#endif
    win64_function call = (win64_function)(memory + second_start);
    if (call(17, 1, 2, 3, 25) != 42 || call(100, 0, 0, 0, 200) != 300) {
        fprintf(stderr, "Win64 call or stack probe failed\n");
        return 6;
    }
    release_executable(memory, 4096);
    return 0;
}
