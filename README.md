# ZEVM - Zig Ethereum Virtual Machine

A high-performance Ethereum Virtual Machine implementation in Zig, ported from the Rust [revm](https://github.com/bluealloy/revm) project.

<img width="400" height="400" alt="image" src="https://github.com/user-attachments/assets/e840bec8-26e7-47ee-8b8c-d9723c9183bd" />

## Overview

ZEVM is a complete EVM implementation that provides:
- Full Ethereum protocol support up to the Prague hardfork
- Modular architecture for easy customization
- High-performance execution
- Comprehensive precompile support
- Built-in debugging and inspection tools
- Type-safe implementation leveraging Zig's compile-time guarantees

## Features

### Core Components

- **Primitives**: Core types (U256, Address, Hash), constants, and hardfork definitions
- **Bytecode**: Opcode definitions, bytecode analysis, and EIP-7702 support
- **State Management**: Account info, storage, and state transitions
- **Database**: Pluggable database interface with in-memory implementation
- **Context**: Block, transaction, and configuration management
- **Interpreter**: Stack-based EVM interpreter with gas tracking
- **Precompiles**: Ethereum precompiled contracts (SHA256, RIPEMD160, ECRECOVER, etc.)
- **Handler**: Transaction execution orchestration
- **Inspector**: Debugging and profiling tools

### Supported Hardforks

- Frontier
- Homestead
- Tangerine
- Spurious Dragon
- Byzantium
- Constantinople
- Petersburg
- Istanbul
- Berlin
- London
- Paris (The Merge)
- Shanghai
- Cancun
- Prague (Latest)

### Precompiled Contracts

- **Identity** (0x04): Data copy
- **SHA256** (0x02): SHA-256 hash function
- **RIPEMD160** (0x03): RIPEMD-160 hash function
- **ECRECOVER** (0x01): Elliptic curve signature recovery
- **ModExp** (0x05): Modular exponentiation
- **BN254** (0x06-0x08): BN254 curve operations
- **Blake2F** (0x09): Blake2 compression function
- **KZG Point Evaluation** (0x0A): KZG commitment verification
- **BLS12-381** (0x0B-0x11): BLS12-381 curve operations

## Building

### Prerequisites

- Zig 0.15.1 or later
- C compiler (for system libraries)

### Build Commands

```bash
# Build the library and all executables
zig build

# Run the comprehensive test suite
./zig-out/bin/zevm-test

# Run examples
./zig-out/bin/simple_contract
./zig-out/bin/gas_inspector_example
./zig-out/bin/precompile_example
```

## Examples

### Simple Contract Execution

```zig
const database = @import("database");
const context = @import("context");
const primitives = @import("primitives");
const interpreter = @import("interpreter");
const bytecode = @import("bytecode");
const state = @import("state");

// Create an in-memory database
var db = database.InMemoryDB.init(std.heap.c_allocator);
defer db.deinit();

// Create a context with Prague specification
var ctx = context.Context.new(db, primitives.SpecId.prague);

// Create bytecode
const bytecode_obj = bytecode.Bytecode.new();

// Set up the contract account
const contract_address: primitives.Address = [_]u8{0x01} ** 20;
const account = state.AccountInfo.new(
    @as(primitives.U256, 0), // balance
    0, // nonce
    primitives.KECCAK_EMPTY, // code hash
    bytecode_obj,
);

try db.insertAccount(contract_address, account);

// Set up transaction
var tx = context.TxEnv.default();
defer tx.deinit();
tx.caller = [_]u8{0x02} ** 20;
tx.gas_limit = 100000;
ctx.tx = tx;

// Create interpreter
const inputs = interpreter.InputsImpl.new(
    tx.caller,
    contract_address,
    @as(primitives.U256, 0),
    &[_]u8{},
    tx.gas_limit,
    interpreter.CallScheme.call,
    false,
    0,
);

var interp = interpreter.Interpreter.new(
    interpreter.Memory.new(),
    interpreter.ExtBytecode.new(bytecode_obj),
    inputs,
    false,
    primitives.SpecId.prague,
    tx.gas_limit,
);
```

### Gas Tracking with Inspector

```zig
const inspector = @import("inspector");
const interpreter = @import("interpreter");

// Create a gas inspector
var gas_inspector = inspector.GasInspector.new();

// Create a gas tracker
var gas = interpreter.Gas.new(100000);

// Initialize the inspector
gas_inspector.initializeInterp(&gas);

// Simulate operations
_ = gas.spend(3); // PUSH1
gas_inspector.step(&gas);

_ = gas.spend(3); // ADD
gas_inspector.stepEnd(&gas);

// Check gas usage
std.log.info("Gas remaining: {}", .{gas_inspector.gasRemaining()});
std.log.info("Last gas cost: {}", .{gas_inspector.lastGasCost()});
```

### Using Precompiles

```zig
const precompile = @import("precompile");

// Create an identity precompile
const identity_precompile = precompile.Precompile.new(
    precompile.PrecompileId.Identity,
    precompile.u64ToAddress(4),
    precompile.identity.identityRun,
);

// Execute the precompile
const input = "Hello, ZEVM!";
const result = identity_precompile.execute(input, 10000);

switch (result) {
    .success => |output| {
        std.log.info("Gas used: {}", .{output.gas_used});
        std.log.info("Output: {s}", .{output.bytes});
    },
    .err => |err| {
        std.log.err("Error: {}", .{err});
    },
}
```

## Testing

The project includes a comprehensive test suite covering all modules:

```bash
# Run all tests
./zig-out/bin/zevm-test
```

Other executables:
`./zig-out/bin/precompile_example` - Precompile demonstration
`./zig-out/bin/simple_contract` - Basic contract execution
`./zig-out/bin/gas_inspector_example` - Gas tracking example
`./zig-out/bin/zevm-test` - Comprehensive test suite

Test coverage includes:
- Primitives (U256, Address, Hash operations)
- Bytecode (opcode parsing and analysis)
- State management (account and storage)
- Database operations
- Context management
- Interpreter execution
- Precompile functionality
- Handler orchestration
- Inspector tools
- Integration tests

## Performance

ZEVM is designed for high performance:
- Zero-cost abstractions using Zig's compile-time features
- Minimal allocations with stack-based execution
- Efficient memory management
- Optimized opcode dispatch
- Fast precompile implementations

## Contributing

Contributions are welcome! Areas for improvement:
- Complete precompile implementations (BN254, BLS12-381, etc.)
- Additional database backends
- Performance optimizations
- More comprehensive test coverage
- Documentation improvements

## License

This project is a port of [revm](https://github.com/bluealloy/revm) to Zig. Please refer to the original project for licensing information.

## Acknowledgments

- [revm](https://github.com/bluealloy/revm) - The original Rust implementation
- The Ethereum Foundation for the EVM specification
- The Zig community for the excellent language and tooling

## Status

ZEVM is currently in active development. The core EVM functionality is complete and tested, but some advanced features (complex precompiles, full EOF support) are still being implemented.

### Completed
✅ Core EVM interpreter
✅ All standard opcodes
✅ Gas tracking and metering
✅ State management
✅ Database interface
✅ Basic precompiles (Identity, SHA256, RIPEMD160, ECRECOVER)
✅ Inspector tools
✅ Comprehensive test suite
✅ Example applications

### In Progress
🚧 Advanced precompiles (BN254, BLS12-381, KZG)
🚧 Full EOF (EIP-7702) support
🚧 Additional database backends
🚧 Performance benchmarking

## Resources

- [Ethereum Yellow Paper](https://ethereum.github.io/yellowpaper/paper.pdf)
- [EVM Opcodes](https://www.evm.codes/)
- [Ethereum Improvement Proposals](https://eips.ethereum.org/)
- [revm Documentation](https://github.com/bluealloy/revm)
- [Zig Documentation](https://ziglang.org/documentation/master/)
