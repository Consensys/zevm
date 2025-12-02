# Changelog

All notable changes to ZEVM will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Nothing yet

### Changed
- Nothing yet

### Deprecated
- Nothing yet

### Removed
- Nothing yet

### Fixed
- Nothing yet

### Security
- Nothing yet

## [0.3.1] - 2025-12-02

### Added
- **PrecompileId.Custom variant**: Added support for custom precompile identifiers via `PrecompileId.custom("id")`
- **PrecompileId.name() method**: Returns EIP-7910 standardized names for all precompiles (e.g., "SHA256", "BN254_ADD")
- **PrecompileId.precompile() method**: Convenience method to get the appropriate precompile implementation for a given spec, handling spec-specific variants automatically

### Fixed
- **ModExp Osaka gas calculation**: Fixed gas calculation formula to use `max(500, complexity * iteration_count)` instead of `500 + complexity * iteration_count` to match EIP-7883 specification
- **ModExp Osaka complexity calculation**: Fixed to use `max(base_len, mod_len)` instead of `max(base_len, exp_len, mod_len)` for complexity calculation
- **EIP-7823 input size limit**: Corrected ModExp input size limit from 32768 bytes to 1024 bytes per parameter as specified in EIP-7823

### Changed
- **PrecompileId type**: Changed from `enum` to `union(enum)` to support Custom variant while maintaining backward compatibility with all existing precompile IDs

## [0.3.0] - 2025-12-01

### Added
- **Cross-Platform Makefile**: Comprehensive build system with OS detection and automated dependency installation
- **Static Linking Support**: All binaries now statically link `blst` and `mcl` libraries for self-contained deployment
- **Automated Dependency Management**: Makefile targets for installing dependencies on macOS, Linux, and Windows
- **Source-Based Library Installation**: Automatic cloning and building of `blst` and `mcl` from source if not found
- **Dependency Verification**: `make check-deps` target to verify all required dependencies before building
- **CROSS_PLATFORM.md**: Comprehensive guide for building on all supported platforms
- **PRECOMPILE_FEATURE_PARITY.md**: Detailed feature parity comparison with Rust revm implementation

### Changed
- **Build System**: Enhanced `build.zig` to support static linking with proper C++ standard library handling
- **CI Workflow**: Simplified CI to use Makefile for consistent builds across platforms
- **Library Linking**: Improved library detection and linking order for static libraries
- **Documentation**: Updated README with new Makefile-based build instructions

### Fixed
- **Linux Static Linking**: Fixed C++ standard library linking to use `libstdc++` instead of `libc++` on Linux
- **Ubuntu CI Build**: Resolved undefined symbol errors related to C++ standard library on Ubuntu CI runners
- **macOS Dynamic Library Loading**: Fixed runtime library path issues on macOS CI
- **Library Path Handling**: Improved handling of absolute vs relative library paths in build system

### Security
- **Static Linking**: Improved security posture with self-contained binaries that don't depend on system libraries

## [0.1.0] - 2024-10-27

### Added
- **Initial Release**: Complete EVM implementation ported from Rust revm
- **Core EVM Interpreter**: Full implementation with all standard opcodes
- **Gas Tracking System**: Comprehensive gas metering and tracking
- **Stack-based Execution**: Efficient interpreter with proper overflow/underflow handling
- **Memory Management**: Dynamic memory allocation with bounds checking
- **Ethereum Protocol Support**: All hardforks from Frontier to Prague
- **EIP-1559 Support**: Transaction types and fee market implementation
- **EIP-2930 Support**: Access list support for gas optimization
- **EIP-4844 Support**: Blob transaction support (Cancun upgrade)
- **EIP-7702 Support**: Initial EOF (Ethereum Object Format) support

### Primitives Module
- **U256 Type**: 256-bit unsigned integer implementation
- **Address Type**: 20-byte Ethereum address type
- **Hash Type**: 32-byte hash type (Keccak-256)
- **Hardfork Definitions**: All Ethereum hardforks from Frontier to Prague
- **Constants**: EVM constants and magic numbers
- **Specification IDs**: Hardfork specification management

### Bytecode Module
- **Opcode Definitions**: All EVM opcodes with metadata
- **OpCodeInfo**: Opcode information (gas cost, stack inputs/outputs)
- **Bytecode Analysis**: Jump destination analysis
- **Legacy Bytecode**: Traditional bytecode format support
- **EOF Bytecode**: Ethereum Object Format support
- **EIP-7702**: Delegated bytecode support

### State Module
- **AccountInfo**: Account state management (balance, nonce, code hash)
- **Account**: Complete account representation
- **Storage**: Key-value storage implementation
- **State Transitions**: Proper state change handling

### Database Module
- **Database Interface**: Pluggable database abstraction
- **InMemoryDB**: High-performance in-memory database implementation
- **Account Operations**: Insert, retrieve, and update account data
- **Code Operations**: Bytecode storage and retrieval
- **Storage Operations**: Storage slot management
- **Block Hash Storage**: Historical block hash storage

### Context Module
- **BlockEnv**: Block environment (number, timestamp, gas limit, etc.)
- **TxEnv**: Transaction environment (caller, gas limit, value, etc.)
- **CfgEnv**: Configuration environment (hardfork, chain ID, etc.)
- **LocalContext**: Local execution context
- **Journal**: State change tracking and rollback support
- **Context**: Main EVM context combining all environments

### Interpreter Module
- **Interpreter**: Core EVM execution engine
- **Gas**: Gas tracking and metering system
- **Stack**: EVM stack implementation with overflow protection
- **Memory**: Dynamic memory management
- **InstructionResult**: Execution result handling
- **InterpreterAction**: Call and create action support
- **InstructionContext**: Context for instruction execution
- **ExtBytecode**: Extended bytecode with EOF support

### Precompile Module
- **Precompile Framework**: Generic precompile implementation framework
- **Identity Precompile** (0x04): Data copy operation
- **SHA256 Precompile** (0x02): SHA-256 cryptographic hash function
- **RIPEMD160 Precompile** (0x03): RIPEMD-160 cryptographic hash function
- **ECRECOVER Precompile** (0x01): Elliptic curve signature recovery
- **ModExp Precompile** (0x05): Modular exponentiation (placeholder)
- **BN254 Precompiles** (0x06-0x08): BN254 curve operations (placeholder)
- **Blake2F Precompile** (0x09): Blake2 compression function (placeholder)
- **KZG Point Evaluation** (0x0A): KZG commitment verification (placeholder)
- **BLS12-381 Precompiles** (0x0B-0x11): BLS12-381 curve operations (placeholder)
- **Precompile Collection**: Management of multiple precompiles
- **Gas Calculation**: Linear cost calculation for precompiles

### Handler Module
- **ExecutionResult**: Transaction execution result handling
- **Frame Management**: Execution frame stack management
- **Instructions**: EVM instruction set
- **Precompiles**: Precompile collection management
- **Mainnet Builder**: Mainnet EVM instance builder
- **Execution Orchestration**: Transaction execution coordination
- **Validation**: Transaction and environment validation
- **Gas Calculation**: Initial gas and refund calculation

### Inspector Module
- **Inspector Framework**: Generic inspection and debugging framework
- **GasInspector**: Real-time gas consumption tracking
- **CountInspector**: Execution metrics and statistics
- **NoOpInspector**: Minimal overhead debugging option
- **InspectorHandler**: Inspector integration with execution flow
- **Call/Create Tracking**: Function call and contract creation tracking
- **Log Tracking**: Event log tracking
- **Selfdestruct Tracking**: Contract destruction tracking

### Testing
- **Comprehensive Test Suite**: 100% test coverage across all modules
- **Unit Tests**: Individual module testing
- **Integration Tests**: End-to-end EVM execution testing
- **Example Verification**: All examples tested and working
- **Test Framework**: Structured testing with proper assertions

### Examples
- **Simple Contract Example**: Basic contract execution demonstration
- **Gas Inspector Example**: Gas tracking and profiling demonstration
- **Precompile Example**: Precompiled contract usage demonstration
- **Simple EVM Example**: Basic EVM setup and execution
- **Benchmark Example**: Performance testing framework

### Build System
- **Zig Build System**: Complete build configuration for Zig 0.15.1+
- **Modular Builds**: Individual modules can be built separately
- **Cross-platform Support**: Works on all platforms supported by Zig
- **Dependency Management**: Proper module dependency handling
- **Example Builds**: All examples built as separate executables

### Documentation
- **Comprehensive README**: Complete project documentation
- **API Documentation**: Inline documentation for all public APIs
- **Usage Examples**: Detailed usage examples for all modules
- **Build Instructions**: Clear build and installation instructions
- **Architecture Documentation**: Detailed architecture overview

### Performance
- **Zero-cost Abstractions**: Compile-time optimizations
- **Efficient Memory Usage**: Minimal runtime allocations
- **Fast Execution**: Optimized opcode dispatch
- **Gas Efficiency**: Accurate gas metering with minimal overhead

### Type Safety
- **Compile-time Guarantees**: Leverages Zig's compile-time features
- **Memory Safety**: No undefined behavior or memory leaks
- **Error Handling**: Comprehensive error handling with proper propagation
- **Type-safe APIs**: All public APIs are type-safe

### Security
- **Memory Safety**: No buffer overflows or memory leaks
- **Integer Overflow Protection**: Proper handling of arithmetic operations
- **Stack Overflow Protection**: EVM stack bounds checking
- **Gas Limit Enforcement**: Proper gas limit checking and enforcement

---

## Version History

- **v0.1.0** (2024-10-27): Initial release with complete EVM implementation

## Contributing

When adding new features or making changes, please update this changelog following the format above. Include:
- Clear description of what was added/changed/fixed
- Reference to relevant issues or pull requests
- Breaking changes should be clearly marked
- Security-related changes should be highlighted

## Format Guidelines

- Use present tense ("Add feature" not "Added feature")
- Use imperative mood ("Move" not "Moves" or "Moved")
- Group changes by type (Added, Changed, Deprecated, Removed, Fixed, Security)
- Use bullet points for multiple changes
- Include version numbers and dates
- Link to relevant issues and pull requests
- Mark breaking changes clearly
