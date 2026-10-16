.DEFAULT_GOAL := all
.DELETE_ON_ERROR:

PSLCC ?= ./pslcc
PSLFLAGS ?= -O1
BUILD_DIR ?= build
SOURCE ?=
OUTPUT ?= $(BUILD_DIR)/program.o
TARGET ?= x86_64-linux-gnu
PROFILE ?= hosted
CFLAGS ?= -O2 -Wall -Wextra -Werror

BOOTSTRAP_SOURCES := $(shell find bootstrap -name '*.lisp')
STAGE0_SOURCES := $(shell find src -name '*.lisp') pslcc
NATIVE_COMPILER := $(BUILD_DIR)/pslcc-native
NATIVE_CORE := $(BUILD_DIR)/native-core.o
NATIVE_HOST := $(BUILD_DIR)/native-host.o
NATIVE_SOURCE := $(BUILD_DIR)/native-source.o
NATIVE_INPUT := $(BUILD_DIR)/native-input.o
NATIVE_PATH := $(BUILD_DIR)/native-path.o
NATIVE_DRIVER := $(BUILD_DIR)/native-driver.o
NATIVE_OUTPUT := $(BUILD_DIR)/native-output.o
NATIVE_DIAGNOSTICS := $(BUILD_DIR)/native-diagnostics.o
NATIVE_OBJECTS := $(NATIVE_CORE) $(NATIVE_HOST) $(NATIVE_SOURCE) $(NATIVE_INPUT) $(NATIVE_PATH) $(NATIVE_DRIVER) $(NATIVE_OUTPUT) $(NATIVE_DIAGNOSTICS)
HOST_SOURCES := bootstrap/driver.c bootstrap/host/platform_stdio.c bootstrap/host/platform_toolchain.c
HOST_HEADERS := $(shell find bootstrap -name '*.h')

.PHONY: test-native-cl-user test-native-cli-ir test-native-cli-link test-managed-vectors test-native-vectors test-native-source-identities test-lexical-validation all compiler native stage0 compile example test test-native test-static-data test-self-core test-bootstrap-corpus test-native-environment test-native-cli test-native-ir test-native-function-addresses test-native-closures \
        test-windows test-native-win64-frame test-native-managed test-native-roots test-native-byte-strings test-native-string-literals test-native-runtime-symbols test-native-multiple-values test-native-word-aggregates test-native-integer-aggregates test-native-float-aggregates test-native-windows test-aarch64 test-native-aarch64 test-native-riscv64 test-riscv64 clean help

all: compiler
compiler native: $(NATIVE_COMPILER)

# Stage 0 runs directly under SBCL; it has no separate build artifact.
stage0:
	$(PSLCC) --help

# Compile one PSL source file into a relocatable object. Example:
# make compile SOURCE=examples/basic/standalone.lisp OUTPUT=build/standalone.o
compile: | $(BUILD_DIR)
	@test -n "$(SOURCE)" || { \
		echo 'SOURCE is required (for example: make compile SOURCE=program.lisp)'; \
		exit 2; \
	}
	$(PSLCC) $(PSLFLAGS) --target="$(TARGET)" --profile="$(PROFILE)" \
		-c "$(SOURCE)" -o "$(OUTPUT)"

$(BUILD_DIR):
	mkdir -p "$@"

$(NATIVE_CORE): $(BOOTSTRAP_SOURCES) $(STAGE0_SOURCES) | $(BUILD_DIR)
	$(PSLCC) $(PSLFLAGS) -c bootstrap/native-core.lisp -o "$@"

$(NATIVE_HOST): $(BOOTSTRAP_SOURCES) $(STAGE0_SOURCES) | $(BUILD_DIR)
	$(PSLCC) $(PSLFLAGS) -c bootstrap/host/driver.lisp -o "$@"

$(NATIVE_SOURCE): $(BOOTSTRAP_SOURCES) $(STAGE0_SOURCES) | $(BUILD_DIR)
	$(PSLCC) $(PSLFLAGS) -c bootstrap/host/source_unit.lisp -o "$@"

$(NATIVE_INPUT): $(BOOTSTRAP_SOURCES) $(STAGE0_SOURCES) | $(BUILD_DIR)
	$(PSLCC) $(PSLFLAGS) -c bootstrap/host/source_io.lisp -o "$@"

$(NATIVE_PATH): $(BOOTSTRAP_SOURCES) $(STAGE0_SOURCES) | $(BUILD_DIR)
	$(PSLCC) $(PSLFLAGS) -c bootstrap/host/source_path_posix.lisp -o "$@"

$(NATIVE_DRIVER): $(BOOTSTRAP_SOURCES) $(STAGE0_SOURCES) | $(BUILD_DIR)
	$(PSLCC) $(PSLFLAGS) -c bootstrap/host/compiler.lisp -o "$@"

$(NATIVE_OUTPUT): $(BOOTSTRAP_SOURCES) $(STAGE0_SOURCES) | $(BUILD_DIR)
	$(PSLCC) $(PSLFLAGS) -c bootstrap/host/output.lisp -o "$@"

$(NATIVE_DIAGNOSTICS): $(BOOTSTRAP_SOURCES) $(STAGE0_SOURCES) | $(BUILD_DIR)
	$(PSLCC) $(PSLFLAGS) -c bootstrap/host/diagnostics.lisp -o "$@"

# Build the native compiler host for the current Linux typed subset.
$(NATIVE_COMPILER): $(NATIVE_OBJECTS) $(HOST_SOURCES) $(HOST_HEADERS)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(HOST_SOURCES) $(NATIVE_OBJECTS) $(LDFLAGS) $(LDLIBS) -o "$@"

$(BUILD_DIR)/arithmetic: examples/native/arithmetic.lisp $(STAGE0_SOURCES) | $(BUILD_DIR)
	$(PSLCC) $(PSLFLAGS) "$<" -o "$@"

example: $(BUILD_DIR)/arithmetic
	"$(BUILD_DIR)/arithmetic"

test:
	sh tests/smoke.sh

test-native: test-static-data
	sh tests/bootstrap_native_compiler.sh

test-native-managed: native
	sh tests/bootstrap_managed_values.sh "$(NATIVE_COMPILER)" "$(TARGET)"

test-native-roots: native
	sh tests/bootstrap_managed_roots.sh "$(NATIVE_COMPILER)" "$(TARGET)"

test-native-byte-strings: native
	sh tests/bootstrap_byte_strings.sh "$(NATIVE_COMPILER)" "$(TARGET)"

test-native-string-literals: native
	sh tests/bootstrap_string_literals.sh "$(NATIVE_COMPILER)" "$(TARGET)"

test-native-runtime-symbols: native
	sh tests/bootstrap_runtime_symbols.sh "$(NATIVE_COMPILER)" "$(TARGET)"

test-native-multiple-values: native
	sh tests/bootstrap_multiple_values.sh "$(NATIVE_COMPILER)" "$(TARGET)"

test-native-word-aggregates: native
	sh tests/bootstrap_word_aggregates.sh "$(NATIVE_COMPILER)" "$(TARGET)"

test-native-integer-aggregates: native
	sh tests/bootstrap_integer_aggregates.sh "$(NATIVE_COMPILER)" "$(TARGET)"

test-native-float-aggregates: native
	sh tests/bootstrap_float_aggregates.sh "$(NATIVE_COMPILER)" "$(TARGET)"

test-native-function-addresses: native
	sh tests/bootstrap_function_addresses.sh "$(NATIVE_COMPILER)" "$(TARGET)"

test-native-closures: native
	sh tests/bootstrap_native_closures.sh "$(NATIVE_COMPILER)" "$(TARGET)"

test-native-ir: native
	sh tests/bootstrap_ir_dump.sh "$(NATIVE_COMPILER)" "$(TARGET)"

test-native-cli: native
	sh tests/bootstrap_native_cli.sh "$(NATIVE_COMPILER)" "$(TARGET)"
	sh tests/bootstrap_cli_diagnostics.sh "$(NATIVE_COMPILER)" "$(TARGET)"

test-native-cli-ir: native
	sh tests/bootstrap_native_cli_ir_dump.sh "$(NATIVE_COMPILER)" "$(TARGET)"

test-native-cli-link: native
	sh tests/bootstrap_native_cli_link.sh "$(NATIVE_COMPILER)" "$(TARGET)"

test-native-cl-user: native
	sh tests/bootstrap_cl_user.sh "$(NATIVE_COMPILER)" "$(TARGET)"

test-native-source-identities: native
	sh tests/bootstrap_source_identities.sh "$(NATIVE_COMPILER)" "$(TARGET)"

test-lexical-validation: native
	sh tests/bootstrap_lexical_validation.sh "$(NATIVE_COMPILER)" "$(TARGET)"

test-managed-vectors:
	sh tests/bootstrap_managed_vectors.sh "$(TARGET)"

test-native-vectors: native
	sh tests/bootstrap_native_vectors.sh "$(NATIVE_COMPILER)" "$(TARGET)"

test-static-data:
	sh tests/bootstrap_static_data.sh x86_64-linux-gnu

test-native-environment: native
	sh tests/bootstrap_environment.sh "$(NATIVE_COMPILER)"
	sh tests/bootstrap_reader_identity.sh "$(NATIVE_COMPILER)"
	sh tests/bootstrap_package_operations.sh "$(NATIVE_COMPILER)"
	sh tests/bootstrap_package_forms.sh "$(NATIVE_COMPILER)"
	sh tests/bootstrap_package_form_edges.sh "$(NATIVE_COMPILER)"
	sh tests/bootstrap_macros.sh "$(NATIVE_COMPILER)"

test-self-core:
	sh tests/bootstrap_self_core.sh

test-bootstrap-corpus: native
	python3 tests/bootstrap_corpus.py --native "$(NATIVE_COMPILER)"

test-windows:
	sh tests/windows.sh

test-native-win64-frame:
	sh tests/bootstrap_win64_frame.sh

test-native-windows: native
	sh tests/bootstrap_static_data.sh x86_64-windows-gnu
	sh tests/bootstrap_native_windows.sh

test-aarch64:
	sh tests/aarch64.sh

test-native-aarch64: native
	sh tests/bootstrap_static_data.sh aarch64-linux-gnu
	sh tests/bootstrap_native_aarch64.sh

test-native-riscv64: native
	sh tests/bootstrap_static_data.sh riscv64-linux-gnu
	sh tests/bootstrap_native_riscv64.sh

test-riscv64:
	sh tests/riscv64.sh

# Remove only artifacts owned by this Makefile.
clean:
	rm -f "$(NATIVE_COMPILER)" $(NATIVE_OBJECTS) "$(BUILD_DIR)/arithmetic"

help:
	@echo 'make                   Build the native compiler subset (SBCL + C compiler)'
	@echo 'make compiler          Build build/pslcc-native'
	@echo 'make stage0            Check the SBCL compiler launcher'
	@echo 'make compile SOURCE=FILE [OUTPUT=FILE] Compile one PSL file to an object'
	@echo 'make example           Compile and run the pure Lisp arithmetic example'
	@echo 'make test              Run the Linux smoke suite'
	@echo 'make test-native       Check native compilation and C interoperability'
	@echo 'make test-native-managed Check hosted native values and profile safety'
	@echo 'make test-native-roots Check native precise roots and collecting calls'
	@echo 'make test-native-byte-strings Check native managed byte strings and ABI'
	@echo 'make test-native-string-literals Check native string literals and byte spans'
	@echo 'make test-native-runtime-symbols Check managed symbols and runtime packages'
	@echo 'make test-native-multiple-values Check two values, lexical bindings and roots'
	@echo 'make test-native-word-aggregates Check natural integer/pointer records in one word'
	@echo 'make test-native-integer-aggregates Check natural records through 16 bytes and ABI frames'
	@echo 'make test-native-float-aggregates Check floating and mixed natural C records'
	@echo 'make test-native-ir         Check verified IR text and unit capture'
	@echo 'make test-native-function-addresses Check defined function addresses and long text'
	@echo 'make test-native-closures   Check lexical closures and precise captured roots'
	@echo 'make test-native-source-identities Check escaped lexical names and captures'
	@echo 'make test-lexical-validation Check native and Stage 0 LET validation'
	@echo 'make test-managed-vectors Check hosted managed VALUE-vector runtime'
	@echo 'make test-native-vectors Check native hosted VALUE-vector lowering'
	@echo 'make test-static-data  Check native ELF static data output on x86-64 Linux'
	@echo 'make test-native-cli-link Check native executable, static, shared and runtime linking'
	@echo 'make test-native-cli Check native object command-line syntax and parser ABI'
	@echo 'make test-native-cli-ir Check verified IR CLI stages, growth and object identity'
	@echo 'make test-native-environment Check build-host package and symbol reader APIs'
	@echo 'make test-self-core    Compare successive native core generations'
	@echo 'make test-bootstrap-corpus Audit every example against Stage 0 at O0/O1 (Python 3 required)'
	@echo 'make test-windows      Run Windows checks (MinGW-w64 and Wine required)'
	@echo 'make test-native-win64-frame Check native Win64 frame, LIR, and unwind encoding'
	@echo 'make test-native-windows Check native Windows COFF output and generations with Wine'
	@echo 'make test-aarch64      Run AArch64 checks (cross compiler and QEMU required)'
	@echo 'make test-native-aarch64 Check native AArch64 output and generations with QEMU'
	@echo 'make test-native-riscv64 Check native RISC-V output and generations with QEMU'
	@echo 'make test-riscv64      Run RISC-V checks (cross toolchains and QEMU required)'
	@echo 'make clean             Remove generated Makefile artifacts'
	@echo 'Variables: PSLCC, PSLFLAGS, BUILD_DIR, SOURCE, OUTPUT, TARGET, PROFILE'
	@echo '           CC, CPPFLAGS, CFLAGS, LDFLAGS, LDLIBS'
