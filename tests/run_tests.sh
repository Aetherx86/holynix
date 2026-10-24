#!/usr/bin/env bash
set -e

echo "========================================================"
echo " HolyC Unix Kernel & Terminal Operating System Test Suite"
echo " Terry A. Davis Memorial Edition"
echo "========================================================"

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$WORKSPACE_DIR"

echo -e "\n\033[96m[1/7] Cleaning and Building HolyC Toolchain & Kernel...\033[0m"
make clean
make all

echo -e "\n\033[96m[2/7] Running In-Kernel POSIX Subsystem Tests (--test)...\033[0m"
./bin/holy_unix --test

echo -e "\n\033[96m[3/7] Running Linux OS / Kernel Compliance TDD Test Suite...\033[0m"
${CC:-clang} -Wall -O2 tests/test_linux_kernel.c -o tests/test_linux_kernel
./tests/test_linux_kernel

echo -e "\n\033[96m[4/7] Testing Shell Commands & System Info...\033[0m"
./bin/holy_unix -c "uname -a; whoami; pwd; uptime"

echo -e "\n\033[96m[5/7] Testing VFS, Pipes, and Redirection...\033[0m"
./bin/holy_unix -c "echo HolyC Unix Operating System > /tmp/demo.txt; cat /tmp/demo.txt | grep HolyC; wc /tmp/demo.txt"

echo -e "\n\033[96m[6/7] Testing In-Kernel HolyC Script Execution...\033[0m"
./bin/holy_unix -c "holyc /home/terry/hello.HC"

echo -e "\n\033[96m[7/7] Testing TempleOS Divine Oracle (/dev/god & god)...\033[0m"
./bin/holy_unix -c "god 5"

echo -e "\n\033[92m========================================================"
echo " ALL HOLYC UNIX KERNEL VERIFICATIONS PASSED SUCCESSFULLY!"
echo "========================================================\033[0m"
