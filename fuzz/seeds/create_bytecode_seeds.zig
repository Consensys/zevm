// create_bytecode_seeds.zig — One-shot tool to write hand-crafted binary seed files.
//
// Run once: zig run fuzz/seeds/create_bytecode_seeds.zig
//
// Creates the bytecode seed corpus in fuzz/seeds/bytecode/ and
// minimal transaction seeds in fuzz/seeds/transaction/.

const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    std.fs.cwd().makeDir("fuzz/seeds/bytecode") catch |e| if (e != error.PathAlreadyExists) return e;
    std.fs.cwd().makeDir("fuzz/seeds/transaction") catch |e| if (e != error.PathAlreadyExists) return e;
    std.fs.cwd().makeDir("fuzz/seeds/precompile") catch |e| if (e != error.PathAlreadyExists) return e;

    // --- Bytecode seeds (format: spec_id[1] + gas_limit[8] + bytecode[N]) ---
    // spec_id=17 (Prague), gas=1_000_000

    const spec: u8 = 17; // Prague
    const gas: u64 = 1_000_000;

    try writeBytecodeFile("fuzz/seeds/bytecode/push_stop.bin", spec, gas, &.{
        0x60, 0x42, // PUSH1 0x42
        0x00,       // STOP
    });

    try writeBytecodeFile("fuzz/seeds/bytecode/add_return.bin", spec, gas, &.{
        0x60, 0x01,  // PUSH1 1
        0x60, 0x02,  // PUSH1 2
        0x01,        // ADD
        0x5f,        // PUSH0
        0x52,        // MSTORE
        0x60, 0x20,  // PUSH1 32
        0x5f,        // PUSH0
        0xf3,        // RETURN
    });

    try writeBytecodeFile("fuzz/seeds/bytecode/jump_dest.bin", spec, gas, &.{
        0x60, 0x04,  // PUSH1 4 (jump target)
        0x56,        // JUMP
        0xfe,        // INVALID (never reached)
        0x5b,        // JUMPDEST (offset 4)
        0x00,        // STOP
    });

    try writeBytecodeFile("fuzz/seeds/bytecode/sstore_sload.bin", spec, gas, &.{
        0x60, 0x42,  // PUSH1 0x42 (value)
        0x5f,        // PUSH0 (key=0)
        0x55,        // SSTORE
        0x5f,        // PUSH0 (key=0)
        0x54,        // SLOAD
        0x50,        // POP
        0x00,        // STOP
    });

    try writeBytecodeFile("fuzz/seeds/bytecode/revert.bin", spec, gas, &.{
        0x60, 0x00,  // PUSH1 0
        0x60, 0x00,  // PUSH1 0
        0xfd,        // REVERT
    });

    try writeBytecodeFile("fuzz/seeds/bytecode/callvalue.bin", spec, gas, &.{
        0x34,        // CALLVALUE
        0x5f,        // PUSH0
        0x52,        // MSTORE
        0x60, 0x20,  // PUSH1 32
        0x5f,        // PUSH0
        0xf3,        // RETURN
    });

    try writeBytecodeFile("fuzz/seeds/bytecode/keccak256.bin", spec, gas, &.{
        0x5f,        // PUSH0
        0x5f,        // PUSH0
        0x20,        // KECCAK256 (hash of empty bytes)
        0x5f,        // PUSH0
        0x52,        // MSTORE
        0x60, 0x20,  // PUSH1 32
        0x5f,        // PUSH0
        0xf3,        // RETURN
    });

    try writeBytecodeFile("fuzz/seeds/bytecode/create.bin", spec, gas, &.{
        // Push empty init code onto memory (nothing to push)
        0x5f,        // PUSH0 (size=0)
        0x5f,        // PUSH0 (offset=0)
        0x5f,        // PUSH0 (value=0)
        0xf0,        // CREATE
        0x50,        // POP (created address)
        0x00,        // STOP
    });

    try writeBytecodeFile("fuzz/seeds/bytecode/log1.bin", spec, gas, &.{
        0x60, 0x00,  // PUSH1 0 (size)
        0x60, 0x00,  // PUSH1 0 (offset)
        0x60, 0xde,  // PUSH1 0xde (topic)
        0xa1,        // LOG1
        0x00,        // STOP
    });

    try writeBytecodeFile("fuzz/seeds/bytecode/tstore_tload.bin", spec, gas, &.{
        0x60, 0x42,  // PUSH1 0x42 (value)
        0x5f,        // PUSH0 (key)
        0x5d,        // TSTORE
        0x5f,        // PUSH0 (key)
        0x5c,        // TLOAD
        0x50,        // POP
        0x00,        // STOP
    });

    // --- Transaction seeds ---
    // Simple ETH transfer seed
    try writeTxFile("fuzz/seeds/transaction/simple_transfer.bin", spec, gas, false);
    // Create contract seed (empty init code)
    try writeTxFile("fuzz/seeds/transaction/create_empty.bin", spec, gas, true);

    // --- Precompile seeds (format: pc_index[1] + spec_variant[1] + gas_limit[8] + input[N]) ---
    // ecrecover: 32 bytes hash + 32 bytes v + 32 bytes r + 32 bytes s
    try writePrecompileFile("fuzz/seeds/precompile/ecrecover.bin", 0, 5, gas, &(.{0} ** 128));
    // sha256: empty input
    try writePrecompileFile("fuzz/seeds/precompile/sha256_empty.bin", 1, 5, gas, &.{});
    // sha256: 32 bytes
    try writePrecompileFile("fuzz/seeds/precompile/sha256_32.bin", 1, 5, gas, &(.{0} ** 32));
    // identity: 32 bytes
    try writePrecompileFile("fuzz/seeds/precompile/identity.bin", 3, 5, gas, &(.{0} ** 32));
    // modexp: base=0, exp=0, mod=1
    try writePrecompileFile("fuzz/seeds/precompile/modexp.bin", 4, 3, gas, &(.{
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, // base_len = 1
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, // exp_len = 1
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, // mod_len = 1
        0, // base = 0
        0, // exp = 0
        1, // mod = 1
    }));
    // blake2f: 213 bytes (valid structure with 0 rounds)
    try writePrecompileFile("fuzz/seeds/precompile/blake2f.bin", 8, 3, gas, &(.{0} ** 213));

    std.debug.print("Seed files created successfully.\n", .{});
}

fn writeBytecodeFile(path: []const u8, spec: u8, gas: u64, bytecode: []const u8) !void {
    const f = try std.fs.cwd().createFile(path, .{});
    defer f.close();
    var gas_le: [8]u8 = undefined;
    std.mem.writeInt(u64, &gas_le, gas, .little);
    try f.writeAll(&.{spec});
    try f.writeAll(&gas_le);
    try f.writeAll(bytecode);
}

fn writeTxFile(path: []const u8, spec: u8, gas: u64, is_create: bool) !void {
    const f = try std.fs.cwd().createFile(path, .{});
    defer f.close();
    const flags: u8 = if (is_create) 0x01 else 0x00;
    var gas_le: [8]u8 = undefined;
    std.mem.writeInt(u64, &gas_le, gas, .little);
    const zero16 = [_]u8{ 0, 0 };
    // spec_id, flags, gas_limit(8), caller(20), target(20), value(32), calldata_len(2), bytecode_len(2) = 86 bytes
    try f.writeAll(&.{spec});
    try f.writeAll(&.{flags});
    try f.writeAll(&gas_le);
    try f.writeAll(&(.{0x10} ** 20)); // caller
    try f.writeAll(&(.{0x20} ** 20)); // target
    try f.writeAll(&(.{0x00} ** 32)); // value = 0
    try f.writeAll(&zero16);           // calldata_len = 0
    try f.writeAll(&zero16);           // bytecode_len = 0
}

fn writePrecompileFile(path: []const u8, pc_idx: u8, spec_variant: u8, gas: u64, input: []const u8) !void {
    const f = try std.fs.cwd().createFile(path, .{});
    defer f.close();
    var gas_le: [8]u8 = undefined;
    std.mem.writeInt(u64, &gas_le, gas, .little);
    try f.writeAll(&.{pc_idx});
    try f.writeAll(&.{spec_variant});
    try f.writeAll(&gas_le);
    try f.writeAll(input);
}
