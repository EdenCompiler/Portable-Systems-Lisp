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
HOST_HEADERS := bootstrap/frontend/environment.h bootstrap/native_api.h bootstrap/host/source.h bootstrap/host/compiler.h

.PHONY: all compiler native stage0 compile example test test-native test-static-data test-self-core test-bootstrap-corpus test-native-environment \
        test-windows test-native-win64-frame test-native-windows test-aarch64 test-native-aarch64 test-native-riscv64 test-riscv64 clean help

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
	@echo 'make test-static-data  Check native ELF static data output on x86-64 Linux'
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
