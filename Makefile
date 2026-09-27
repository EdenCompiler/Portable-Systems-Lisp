.DEFAULT_GOAL := all
.DELETE_ON_ERROR:

PSLCC ?= ./pslcc
PSLFLAGS ?= -O1
BUILD_DIR ?= build
CFLAGS ?= -O2 -Wall -Wextra -Werror

BOOTSTRAP_SOURCES := $(shell find bootstrap -name '*.lisp')
STAGE0_SOURCES := $(shell find src -name '*.lisp') pslcc
NATIVE_COMPILER := $(BUILD_DIR)/pslcc-native
NATIVE_CORE := $(BUILD_DIR)/native-core.o
NATIVE_HOST := $(BUILD_DIR)/native-host.o
NATIVE_SOURCE := $(BUILD_DIR)/native-source.o

.PHONY: all native stage0 example test test-native test-self-core \
        test-windows test-aarch64 test-riscv64 clean help

all: native
native: $(NATIVE_COMPILER)

# Stage 0 runs directly under SBCL; it has no separate build artifact.
stage0:
	$(PSLCC) --help

$(BUILD_DIR):
	mkdir -p "$@"

$(NATIVE_CORE): $(BOOTSTRAP_SOURCES) $(STAGE0_SOURCES) | $(BUILD_DIR)
	$(PSLCC) $(PSLFLAGS) -c bootstrap/native-core.lisp -o "$@"

$(NATIVE_HOST): $(BOOTSTRAP_SOURCES) $(STAGE0_SOURCES) | $(BUILD_DIR)
	$(PSLCC) $(PSLFLAGS) -c bootstrap/host/driver.lisp -o "$@"

$(NATIVE_SOURCE): $(BOOTSTRAP_SOURCES) $(STAGE0_SOURCES) | $(BUILD_DIR)
	$(PSLCC) $(PSLFLAGS) -c bootstrap/host/source_unit.lisp -o "$@"

# The native compiler currently emits x86-64 Linux objects for its typed subset.
$(NATIVE_COMPILER): $(NATIVE_CORE) $(NATIVE_HOST) $(NATIVE_SOURCE) bootstrap/driver.c bootstrap/native_api.h \
                    bootstrap/host/source.c bootstrap/host/source.h
	$(CC) $(CPPFLAGS) $(CFLAGS) bootstrap/driver.c bootstrap/host/source.c \
	  "$(NATIVE_CORE)" "$(NATIVE_HOST)" "$(NATIVE_SOURCE)" $(LDFLAGS) $(LDLIBS) -o "$@"

$(BUILD_DIR)/arithmetic: examples/native/arithmetic.lisp $(STAGE0_SOURCES) | $(BUILD_DIR)
	$(PSLCC) $(PSLFLAGS) "$<" -o "$@"

example: $(BUILD_DIR)/arithmetic
	"$(BUILD_DIR)/arithmetic"

test:
	sh tests/smoke.sh

test-native:
	sh tests/bootstrap_native_compiler.sh

test-self-core:
	sh tests/bootstrap_self_core.sh

test-windows:
	sh tests/windows.sh

test-aarch64:
	sh tests/aarch64.sh

test-riscv64:
	sh tests/riscv64.sh

# Remove only artifacts owned by this Makefile.
clean:
	rm -f "$(NATIVE_COMPILER)" "$(NATIVE_CORE)" "$(NATIVE_HOST)" "$(NATIVE_SOURCE)" "$(BUILD_DIR)/arithmetic"

help:
	@echo 'make                   Build the native compiler subset (SBCL + C compiler)'
	@echo 'make stage0            Check the SBCL compiler launcher'
	@echo 'make example           Compile and run the pure Lisp arithmetic example'
	@echo 'make test              Run the Linux smoke suite'
	@echo 'make test-native       Check native compilation and C interoperability'
	@echo 'make test-self-core    Compare successive native core generations'
	@echo 'make test-windows      Run Windows checks (MinGW-w64 and Wine required)'
	@echo 'make test-aarch64      Run AArch64 checks (cross compiler and QEMU required)'
	@echo 'make test-riscv64      Run RISC-V checks (cross toolchains and QEMU required)'
	@echo 'make clean             Remove generated Makefile artifacts'
	@echo 'Variables: PSLCC, PSLFLAGS, BUILD_DIR, CC, CPPFLAGS, CFLAGS, LDFLAGS, LDLIBS'
