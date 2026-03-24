// input_decoder.zig — Decode binary fuzz inputs into ZEVM types.
//
// Binary format for transaction harness (minimum 84 bytes):
//   [0]       spec_id (u8, clamped to 0..MAX_SPEC)
//   [1]       flags: bit0=is_create
//   [2..9]    gas_limit (u64 LE, capped at MAX_GAS)
//   [10..29]  caller address (20 bytes)
//   [30..49]  target address (20 bytes, ignored if is_create)
//   [50..81]  value (U256 as 32 bytes LE)
//   [82..83]  calldata_len (u16 LE)
//   [84..N]   calldata bytes
//   [N..N+1]  bytecode_len (u16 LE)
//   [N+2..]   bytecode bytes
//
// Binary format for bytecode harness (minimum 9 bytes):
//   [0]       spec_id (u8)
//   [1..8]    gas_limit (u64 LE)
//   [9..]     raw bytecode
//
// Binary format for precompile harness (minimum 2 bytes):
//   [0]       precompile_index (u8, 0-17 mapped to PrecompileId variants)
//   [1]       spec_variant (u8)
//   [2..9]    gas_limit (u64 LE)
//   [10..]    raw input data

const std = @import("std");
const primitives = @import("primitives");

/// Maximum EVM spec ID value (amsterdam = 22)
pub const MAX_SPEC_ID: u8 = 22;

/// Gas limit cap — prevents AFL++ timeout from infinite loops
pub const MAX_GAS: u64 = 10_000_000;

/// Maximum calldata length per fuzz input
pub const MAX_CALLDATA: u16 = 4096;

/// Maximum bytecode length (EIP-170 max code size)
pub const MAX_BYTECODE: u16 = 24576;

/// Memory limit cap for fuzzing (1 MB) — prevents OOM from MSTORE expansion
pub const FUZZ_MEMORY_LIMIT: u64 = 1 << 20;

/// Decoded transaction fuzz input
pub const TxFuzzInput = struct {
    spec_id: primitives.SpecId,
    is_create: bool,
    gas_limit: u64,
    caller: primitives.Address,
    target: primitives.Address,
    value: primitives.U256,
    calldata: []const u8,
    bytecode: []const u8,
};

/// Decoded bytecode fuzz input
pub const BytecodeFuzzInput = struct {
    spec_id: primitives.SpecId,
    gas_limit: u64,
    bytecode: []const u8,
};

/// Decoded precompile fuzz input
pub const PrecompileFuzzInput = struct {
    precompile_index: u8,
    spec_variant: u8,
    gas_limit: u64,
    input_data: []const u8,
};

/// Decode a binary fuzz buffer into a TxFuzzInput.
/// Returns null if the buffer is too short.
pub fn decodeTxInput(data: []const u8) ?TxFuzzInput {
    // Minimum: 1 + 1 + 8 + 20 + 20 + 32 + 2 = 84 bytes
    if (data.len < 84) return null;

    const raw_spec = data[0];
    const spec_id: primitives.SpecId = @enumFromInt(@min(raw_spec, MAX_SPEC_ID));

    const flags = data[1];
    const is_create = (flags & 0x01) != 0;

    const gas_limit_raw = std.mem.readInt(u64, data[2..10], .little);
    const gas_limit = @min(gas_limit_raw, MAX_GAS);

    var caller: primitives.Address = undefined;
    @memcpy(&caller, data[10..30]);

    var target: primitives.Address = undefined;
    @memcpy(&target, data[30..50]);

    // Value: 32 bytes LE → U256
    const value = std.mem.readInt(primitives.U256, data[50..82], .little);

    const calldata_len_raw = std.mem.readInt(u16, data[82..84], .little);
    const calldata_len: usize = @min(calldata_len_raw, MAX_CALLDATA);

    var offset: usize = 84;
    if (offset + calldata_len > data.len) return null;
    const calldata = data[offset .. offset + calldata_len];
    offset += calldata_len;

    if (offset + 2 > data.len) return null;
    const bytecode_len_raw = std.mem.readInt(u16, data[offset..][0..2], .little);
    const bytecode_len: usize = @min(bytecode_len_raw, MAX_BYTECODE);
    offset += 2;

    if (offset + bytecode_len > data.len) return null;
    const bytecode = data[offset .. offset + bytecode_len];

    return TxFuzzInput{
        .spec_id = spec_id,
        .is_create = is_create,
        .gas_limit = gas_limit,
        .caller = caller,
        .target = target,
        .value = value,
        .calldata = calldata,
        .bytecode = bytecode,
    };
}

/// Decode a binary fuzz buffer into a BytecodeFuzzInput.
/// Returns null if the buffer is too short.
pub fn decodeBytecodeFuzzInput(data: []const u8) ?BytecodeFuzzInput {
    // Minimum: 1 + 8 = 9 bytes
    if (data.len < 9) return null;

    const raw_spec = data[0];
    const spec_id: primitives.SpecId = @enumFromInt(@min(raw_spec, MAX_SPEC_ID));

    const gas_limit_raw = std.mem.readInt(u64, data[1..9], .little);
    const gas_limit = @min(gas_limit_raw, MAX_GAS);

    const bytecode = data[9..];

    return BytecodeFuzzInput{
        .spec_id = spec_id,
        .gas_limit = gas_limit,
        .bytecode = bytecode,
    };
}

/// Decode a binary fuzz buffer into a PrecompileFuzzInput.
/// Returns null if the buffer is too short.
pub fn decodePrecompileFuzzInput(data: []const u8) ?PrecompileFuzzInput {
    // Minimum: 1 + 1 + 8 = 10 bytes
    if (data.len < 10) return null;

    const precompile_index = data[0];
    const spec_variant = data[1];
    const gas_limit_raw = std.mem.readInt(u64, data[2..10], .little);
    const gas_limit = @min(gas_limit_raw, MAX_GAS);
    const input_data = data[10..];

    return PrecompileFuzzInput{
        .precompile_index = precompile_index,
        .spec_variant = spec_variant,
        .gas_limit = gas_limit,
        .input_data = input_data,
    };
}
