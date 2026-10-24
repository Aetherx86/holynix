# HolyC Unix Kernel & Terminal Operating System Makefile
# Terry A. Davis Memorial Edition

CC ?= clang
CFLAGS ?= -Wall -Wextra -O2
HOLYC = ./tools/holyc

all: bin/holy_unix

tools/holyc: tools/holyc.c
	@mkdir -p tools
	@echo "==> Compiling HolyC Transpiler / Compiler Tool..."
	$(CC) $(CFLAGS) tools/holyc.c -o tools/holyc

bin/holy_unix: tools/holyc src/holyc/Kernel.HC src/holyc/*.HC src/runtime/holyc_rt.h
	@mkdir -p bin
	@echo "==> Compiling HolyC Unix Kernel from HolyC source (.HC)..."
	$(HOLYC) src/holyc/Kernel.HC -Isrc/holyc -o bin/holy_unix
	@echo "==> Build successful: bin/holy_unix"

tests/test_linux_kernel: tests/test_linux_kernel.c
	$(CC) $(CFLAGS) tests/test_linux_kernel.c -o tests/test_linux_kernel -lm

test: bin/holy_unix tests/test_linux_kernel
	@echo "==> Running Automated In-Kernel Subsystem Test Suite..."
	./bin/holy_unix --test
	@echo "==> Running Linux / POSIX Compliance TDD Test Suite..."
	./tests/test_linux_kernel

run: bin/holy_unix
	@./bin/holy_unix

clean:
	rm -rf bin tools/holyc tests/test_linux_kernel out.o a.out /tmp/holyc_*

.PHONY: all test run clean
