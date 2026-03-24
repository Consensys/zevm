# ZEVM Fuzzing with AFL++

Coverage-based fuzzing infrastructure for ZEVM using AFL++. Three fuzzing harnesses exercise different parts of the EVM:

| Harness | Target | Speed |
|---------|--------|-------|
| `transaction` | Full validate→preExec→exec→postExec pipeline | ~5k exec/s |
| `bytecode` | Bytecode interpreter with minimal context | ~10k exec/s |
| `precompile` | Individual precompile C library bindings | ~50k exec/s |

Findings can be converted to spec test JSON format for regression testing.

## Prerequisites

- **AFL++**: `brew install aflplusplus` (macOS) or [build from source](https://github.com/AFLplusplus/AFLplusplus)
- **Zig 0.15+**: already required for building ZEVM
- **Crypto libraries**: `secp256k1`, `openssl`, `blst`, `mcl` — run `make install-deps` from the project root

## Quick Start

```bash
# From project root — install AFL++ and build harness
cd fuzz
make deps        # installs AFL++ via Homebrew (macOS)
make harness     # builds zevm-fuzz binary

# Generate seeds from existing spec test fixtures (optional but recommended)
make seeds

# Start fuzzing (Ctrl-C to stop)
make fuzz-bytecode    # fastest; good for opcode coverage
make fuzz-tx          # broadest; exercises full transaction validation
make fuzz-precompile  # targets C library (blst, mcl, secp256k1, openssl) bindings
```

## Architecture

```
AFL++ (afl-fuzz)
    |
    | stdin/shmem test cases
    v
zevm-fuzz binary
    ├── afl_shim.c         (compiled with afl-clang-lto — provides coverage instrumentation)
    └── libzevm-fuzz.a     (Zig static library — ReleaseSafe, bounds checks active)
            ├── fuzz_transaction.zig   → exports zevm_fuzz_transaction()
            ├── fuzz_bytecode.zig      → exports zevm_fuzz_bytecode()
            ├── fuzz_precompile.zig    → exports zevm_fuzz_precompile()
            └── input_decoder.zig      → binary format → ZEVM types
```

AFL++ provides full LLVM coverage instrumentation via LTO (Link-Time Optimization), so coverage feedback comes from both the C shim and all Zig code.

## Input Formats

### Transaction harness (min 84 bytes)

```
[0]       spec_id         u8   0=frontier .. 22=amsterdam
[1]       flags           u8   bit0=is_create
[2..9]    gas_limit       u64  little-endian, capped at 10M
[10..29]  caller          [20]u8
[30..49]  target          [20]u8  (ignored if is_create)
[50..81]  value           [32]u8  U256 little-endian
[82..83]  calldata_len    u16  little-endian, capped at 4096
[84..N]   calldata
[N..N+1]  bytecode_len    u16  little-endian, capped at 24576
[N+2..]   bytecode for target contract
```

### Bytecode harness (min 9 bytes)

```
[0]     spec_id    u8
[1..8]  gas_limit  u64 little-endian
[9..]   raw bytecode bytes
```

### Precompile harness (min 10 bytes)

```
[0]     precompile_index  u8   0=ecrecover .. 17=p256verify
[1]     spec_variant      u8   0=Homestead .. 6=Osaka
[2..9]  gas_limit         u64  little-endian
[10..]  raw precompile input data
```

## Corpus and Dictionaries

- **`seeds/bytecode/`** — hand-crafted minimal EVM programs covering key opcode families
- **`seeds/transaction/`** — populated from spec test fixtures via `make seeds`
- **`seeds/precompile/`** — minimal valid inputs for each precompile
- **`dictionaries/evm_opcodes.dict`** — all EVM opcodes for bytecode mutation guidance
- **`dictionaries/evm_values.dict`** — common EVM constants (max U256, common gas values)

## Converting Findings to Spec Tests

When AFL++ finds a crash, convert it to a reproducible spec test fixture:

```bash
# Convert a single crash file
make tools   # build fuzz2spec binary first
./zig-out/bin/fuzz2spec fuzz/findings/bytecode/crashes/id:000000 bytecode > spec-tests/fuzz/crash_001.json

# Convert all crash files at once
make convert
```

The generated JSON is in the Ethereum execution-spec-tests format and can be loaded by the spec test runner:

```bash
zig build spec-test-runner
./zig-out/bin/spec-test-runner spec-tests/fuzz/
```

The `post.state` is initially empty (documents the crash input without asserting post-state). After fixing the underlying bug, add expected post-state or leave it empty as a "must not crash" regression test.

## Multi-Core Fuzzing

AFL++ scales linearly with CPU cores using the `-M`/`-S` parallel mode:

```bash
# Automatically uses all available cores
make fuzz-tx-parallel

# Or specify core count
make fuzz-tx-parallel CORES=8
```

## Interpreting Results

```
+----------------------------------------------------+
|          american fuzzy lop ++4.xx (main)          |
+----+-----+------+-------+-------+--------+--------+
| # | run | stab | alive | finds | cycles |   map  |
| 1 |  1k |  99% |  100% |    3  |     2  |  12.3k |
+----+-----+------+-------+-------+--------+--------+
```

- **map**: edge coverage — higher is better (ZEVM should reach ~15k+ edges in the transaction harness)
- **finds**: new inputs added to corpus — watch this grow rapidly at first, then slow down
- **cycles**: after the first cycle completes, AFL++ has explored most quick paths
- **crashes/**: any file here is a bug — convert it and file an issue

## Known Limitations

1. **Gas-limited loops**: The harness caps gas at 10M and memory at 1MB to prevent timeouts/OOM. This means some valid-but-expensive programs won't fully execute.

2. **Precompile gas**: The precompile harness passes the capped gas directly. Some precompiles (BLS MSM) may run under-gas but this still exercises their input parsing.

3. **State isolation**: Each fuzz iteration creates a fresh `InMemoryDB`. There is no cross-iteration state persistence. This is correct for finding per-input bugs but won't catch state accumulation bugs.

4. **macOS SIP**: If AFL++ complains about core dumps or CPU frequency, set `AFL_SKIP_CPUFREQ=1` (already set in Makefile targets).
