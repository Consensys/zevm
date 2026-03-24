/*
 * afl_shim.c — AFL++ persistent-mode wrapper for ZEVM fuzz harnesses.
 *
 * Compiled with afl-clang-lto to provide AFL++ coverage instrumentation
 * over both this shim and (via LTO) the Zig static library.
 *
 * Usage (via fuzz/Makefile):
 *   make harness            # builds zevm-fuzz binary
 *   ./zevm-fuzz             # transaction harness (default)
 *   ./zevm-fuzz bytecode    # bytecode-only harness
 *   ./zevm-fuzz precompile  # precompile harness
 */

#include <string.h>
#include <stdio.h>
#include <unistd.h>

/* Zig harness functions exported from libzevm-fuzz.a */
extern int zevm_fuzz_transaction(const unsigned char *data, unsigned long len);
extern int zevm_fuzz_bytecode(const unsigned char *data, unsigned long len);
extern int zevm_fuzz_precompile(const unsigned char *data, unsigned long len);

/* AFL++ deferred initialization + persistent mode macros.
 * __AFL_FUZZ_INIT() declares the shared memory buffer variables.
 * __AFL_INIT() blocks until AFL++ has set up the forkserver.
 * __AFL_LOOP(N) returns true for the next N iterations, then exits. */
__AFL_FUZZ_INIT();

int main(int argc, char **argv) {
    /* Select harness from first argument; default is transaction */
    int (*fuzz_fn)(const unsigned char *, unsigned long) = zevm_fuzz_transaction;

    if (argc > 1) {
        if (strcmp(argv[1], "bytecode") == 0) {
            fuzz_fn = zevm_fuzz_bytecode;
        } else if (strcmp(argv[1], "precompile") == 0) {
            fuzz_fn = zevm_fuzz_precompile;
        }
    }

    /* Deferred forkserver init — AFL++ takes over here */
    __AFL_INIT();

    /* Shared memory test case buffer — populated by AFL++ before each loop */
    unsigned char *buf = __AFL_FUZZ_TESTCASE_BUF;

    /* Persistent mode: run up to 10000 iterations per fork */
    while (__AFL_LOOP(10000)) {
        int len = __AFL_FUZZ_TESTCASE_LEN;
        if (len < 2) continue;
        fuzz_fn(buf, (unsigned long)len);
    }

    return 0;
}
