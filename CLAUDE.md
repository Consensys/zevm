# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ZEVM is a high-performance Ethereum Virtual Machine (EVM) implementation written in Zig. It is a port of the Rust [revm](https://github.com/bluealloy/revm) implementation, providing:

1. **Complete EVM Implementation**: Full support for Ethereum protocol up to Prague hardfork
2. **Production-Ready Precompiles**: All 18 standard Ethereum precompiled contracts implemented
3. **Cross-Platform Support**: Works on macOS, Linux, and Windows with static linking
4. **Type-Safe Design**: Leverages Zig's compile-time guarantees for safety and performance

The project maintains **100% feature parity** with the Rust revm reference implementation, verified through comprehensive testing and comparison.

## Build and Development Commands

### Essential Commands

```bash
# Build using Makefile (recommended - auto-detects OS and installs deps)
make
make build          # Build only
make install-deps   # Install dependencies only
make test           # Run all tests
make clean          # Clean build artifacts

# Manual Zig build commands
zig build                    # Build all targets
zig build test              # Run tests
zig build -Dblst=false      # Build without blst library
zig build -Dmcl=false       # Build without mcl library

# Build specific examples
zig build precompile_example
zig build zevm-test
zig build zevm-bench
```

### Platform-Specific Notes

- **macOS**: Uses Homebrew for dependencies (`/opt/homebrew/include`)
- **Linux**: Uses apt-get/dnf for dependencies (`/usr/local/include`)
- **Windows**: Uses vcpkg (see CROSS_PLATFORM.md)

The Makefile automatically detects the OS and installs dependencies accordingly.

## Architecture

The project follows a modular architecture mirroring revm's structure:

### Core Modules

- **`src/primitives/`**: Core types (U256, Address, Hash), constants, and hardfork definitions
- **`src/bytecode/`**: Opcode definitions, bytecode analysis, and EIP-7702 support
- **`src/state/`**: Account info, storage, and state transitions
- **`src/database/`**: Pluggable database interface with in-memory implementation
- **`src/context/`**: Block, transaction, and configuration management
- **`src/interpreter/`**: Stack-based EVM interpreter with gas tracking
- **`src/precompile/`**: All 18 Ethereum precompiled contracts
- **`src/handler/`**: Transaction execution orchestration
- **`src/inspector/`**: Debugging and profiling tools

### Key Design Patterns

1. **Modular Structure**: Each module is self-contained with a `main.zig` entry point
2. **Static Linking**: All crypto libraries (`blst`, `mcl`) are statically linked for self-contained binaries
3. **Spec-Based Execution**: Hardfork support via `SpecId` enum, with precompiles adapting gas costs per spec
4. **Error Handling**: Uses Zig's error union types (`PrecompileError`, `InstructionResult`, etc.)
5. **Memory Safety**: Leverages Zig's memory management (no GC, explicit allocators)

### Important Interfaces

1. **PrecompileId**: Union enum identifying precompiles, supports Custom variants
2. **PrecompileSpecId**: Enum for hardfork specs (Homestead, Byzantium, Istanbul, Berlin, Cancun, Prague, Osaka)
3. **Database Interface**: Pluggable state storage (see `src/database/main.zig`)
4. **Inspector Interface**: Hooks for transaction tracing and debugging
5. **Context**: Manages execution state, environment, and configuration

## Precompiles

All 18 standard Ethereum precompiles are implemented:

### Core Precompiles
- **Identity** (0x04): Data copy
- **SHA256** (0x02): SHA-256 hash function
- **RIPEMD160** (0x03): RIPEMD-160 hash function
- **ECRECOVER** (0x01): Elliptic curve signature recovery (libsecp256k1)

### Advanced Precompiles
- **ModExp** (0x05): Modular exponentiation (Byzantium/Berlin/Osaka variants)
- **BN254** (0x06-0x08): BN254 curve operations (mcl library)
- **Blake2F** (0x09): Blake2 compression function
- **KZG Point Evaluation** (0x0A): KZG commitment verification (blst library)
- **BLS12-381** (0x0B-0x11): All 7 BLS12-381 precompiles (blst library)
- **P256Verify** (0x100): secp256r1 signature verification (OpenSSL)

### Precompile Features

- **PrecompileId.name()**: Returns EIP-7910 standardized names
- **PrecompileId.precompile()**: Gets spec-appropriate precompile implementation
- **PrecompileId.Custom**: Support for custom precompile identifiers
- **Gas Cost Adaptation**: Precompiles automatically adjust gas costs based on hardfork

## Dependencies

### Required External Libraries

1. **libsecp256k1**: ECRECOVER precompile (typically via package manager)
2. **OpenSSL**: P256Verify precompile (typically via package manager)
3. **blst**: BLS12-381 and KZG operations (built from source or installed)
4. **mcl**: BN254 operations (built from source or installed)

### Dependency Management

- **Makefile**: Automatically installs dependencies via OS-specific package managers
- **build.zig**: Handles linking and include paths for all libraries
- **Static Linking**: All binaries statically link `blst` and `mcl` for portability
- **Fallback**: Libraries can be disabled with `-Dblst=false` or `-Dmcl=false`

See `CROSS_PLATFORM.md` and `DEPENDENCIES.md` for detailed installation instructions.

## Reference Implementation

This project is a port of **revm** (Rust EVM). When implementing new features:

1. **Check revm first**: Look at `revm/crates/` for reference implementation
2. **Maintain parity**: Ensure behavior matches revm exactly
3. **Test vectors**: Use Ethereum test suite and revm's test cases
4. **Documentation**: See `PRECOMPILE_FEATURE_PARITY.md` for comparison

### Key Differences from Rust

- **Memory Management**: Zig uses explicit allocators, no RAII
- **Error Handling**: Zig error unions vs Rust Result types
- **Generics**: Zig uses `comptime` for compile-time polymorphism
- **Pattern Matching**: Zig uses `switch` expressions instead of `match`

## Testing Strategy

1. **Unit Tests**: Each module has comprehensive unit tests (`src/precompile/tests.zig`)
2. **Integration Tests**: Full EVM execution tests (`src/test.zig`)
3. **Precompile Tests**: 73+ unit tests covering all precompiles
4. **Gas Cost Verification**: Tests verify gas costs match revm exactly
5. **Cross-Platform**: CI runs tests on both Ubuntu and macOS

### Running Tests

```bash
make test                    # Run all tests via Makefile
zig build test              # Run tests via Zig build system
zig test src/test.zig       # Run specific test file
```

## Important Files

### Build System
- **`build.zig`**: Main Zig build configuration, handles library linking
- **`Makefile`**: Cross-platform build automation and dependency management
- **`src/version.zig`**: Version information and release metadata

### Documentation
- **`README.md`**: Main project documentation
- **`CHANGELOG.md`**: Version history and changes
- **`RELEASE_NOTES.md`**: Detailed release notes
- **`CROSS_PLATFORM.md`**: Platform-specific build instructions
- **`DEPENDENCIES.md`**: Dependency installation guide
- **`PRECOMPILE_FEATURE_PARITY.md`**: Comparison with revm implementation

### Reference Implementation
- **`revm/`**: Rust reference implementation (submodule or copy)
- Used for understanding behavior and maintaining parity

## Code Conventions

### Naming
- **Modules**: `snake_case` for file names (`main.zig`, `secp256k1.zig`)
- **Types**: `PascalCase` for structs, enums, unions (`PrecompileId`, `PrecompileResult`)
- **Functions**: `camelCase` for public functions (`precompile`, `execute`)
- **Constants**: `UPPER_SNAKE_CASE` for module-level constants (`P256VERIFY`, `BYZANTIUM`)

### Error Handling
- Use Zig error unions: `PrecompileResult = union(enum) { success: PrecompileOutput, err: PrecompileError }`
- Return errors explicitly: `return PrecompileResult{ .err = PrecompileError.OutOfGas }`
- Use `try` for error propagation

### Memory Management
- Use explicit allocators: `std.heap.c_allocator` for global, or pass allocators to functions
- Prefer stack allocation when possible
- Use `std.ArrayList` for dynamic arrays

### Precompile Implementation Pattern

```zig
// Define precompile constant
pub const PRECOMPILE = main.Precompile.new(
    main.PrecompileId.Sha256,
    main.u64ToAddress(2),
    sha256Run,
);

// Implementation function
pub fn sha256Run(input: []const u8, gas_limit: u64) main.PrecompileResult {
    const gas_cost = main.calcLinearCost(input.len, 60, 12);
    if (gas_cost > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }
    // ... implementation
    return main.PrecompileResult{ .success = main.PrecompileOutput.new(gas_cost, result) };
}
```

## Current Development Context

### Recent Changes (v0.3.1)
- Fixed ModExp Osaka gas calculation to match EIP-7883
- Fixed EIP-7823 input size limits (1024 bytes)
- Added PrecompileId.Custom variant and convenience methods
- Verified Fusaka upgrade parity with revm

### Ongoing Maintenance
- Maintain feature parity with revm
- Keep up with Ethereum hardfork changes
- Ensure cross-platform compatibility
- Optimize performance where possible

## Common Tasks

### Adding a New Precompile
1. Create implementation file in `src/precompile/`
2. Add PrecompileId variant in `src/precompile/main.zig`
3. Register in appropriate spec in `Precompiles.forSpec()`
4. Add tests in `src/precompile/tests.zig`
5. Update `PRECOMPILE_FEATURE_PARITY.md`

### Updating Gas Costs
1. Check revm implementation for reference
2. Update gas calculation function
3. Add tests for new gas costs
4. Verify against Ethereum test suite

### Fixing Cross-Platform Issues
1. Check `build.zig` for platform-specific logic
2. Update `Makefile` if needed
3. Test on target platform
4. Update `CROSS_PLATFORM.md` if instructions change

## Getting Help

- **Reference Implementation**: Check `revm/crates/` for Rust implementation
- **Ethereum Specs**: See EIPs and Ethereum execution specs
- **Zig Documentation**: https://ziglang.org/documentation/
- **Build Issues**: See `CROSS_PLATFORM.md` and `DEPENDENCIES.md`

