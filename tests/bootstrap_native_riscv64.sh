#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec sh "$project_root/tests/bootstrap_native_elf.sh" riscv64-linux-gnu
