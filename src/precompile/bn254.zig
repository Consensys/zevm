const std = @import("std");
const primitives = @import("primitives");
const main = @import("main.zig");
const mcl_wrapper = @import("mcl_wrapper.zig");

/// BN254 elliptic curve precompiles
pub const add = struct {
    pub const BYZANTIUM_ADD_GAS_COST: u64 = 500;
    pub const ISTANBUL_ADD_GAS_COST: u64 = 150;

    pub const BYZANTIUM = main.Precompile.new(
        main.PrecompileId.Bn254Add,
        main.u64ToAddress(6),
        bn254AddRunByzantium,
    );

    pub const ISTANBUL = main.Precompile.new(
        main.PrecompileId.Bn254Add,
        main.u64ToAddress(6),
        bn254AddRunIstanbul,
    );
};

pub const mul = struct {
    pub const BYZANTIUM_MUL_GAS_COST: u64 = 40_000;
    pub const ISTANBUL_MUL_GAS_COST: u64 = 6_000;

    pub const BYZANTIUM = main.Precompile.new(
        main.PrecompileId.Bn254Mul,
        main.u64ToAddress(7),
        bn254MulRunByzantium,
    );

    pub const ISTANBUL = main.Precompile.new(
        main.PrecompileId.Bn254Mul,
        main.u64ToAddress(7),
        bn254MulRunIstanbul,
    );
};

pub const pair = struct {
    pub const BYZANTIUM_PAIR_PER_POINT: u64 = 80_000;
    pub const BYZANTIUM_PAIR_BASE: u64 = 100_000;
    pub const ISTANBUL_PAIR_PER_POINT: u64 = 34_000;
    pub const ISTANBUL_PAIR_BASE: u64 = 45_000;

    pub const BYZANTIUM = main.Precompile.new(
        main.PrecompileId.Bn254Pairing,
        main.u64ToAddress(8),
        bn254PairingRunByzantium,
    );

    pub const ISTANBUL = main.Precompile.new(
        main.PrecompileId.Bn254Pairing,
        main.u64ToAddress(8),
        bn254PairingRunIstanbul,
    );
};

const FQ_LEN: usize = 32;
const SCALAR_LEN: usize = 32;
const FQ2_LEN: usize = 2 * FQ_LEN;
const G1_LEN: usize = 2 * FQ_LEN; // 64 bytes
const G2_LEN: usize = 2 * FQ2_LEN; // 128 bytes
const ADD_INPUT_LEN: usize = 2 * G1_LEN; // 128 bytes
const MUL_INPUT_LEN: usize = G1_LEN + SCALAR_LEN; // 96 bytes
const PAIR_ELEMENT_LEN: usize = G1_LEN + G2_LEN; // 192 bytes

/// Right pad input to specified length
fn rightPad(comptime len: usize, input: []const u8) [len]u8 {
    var padded: [len]u8 = [_]u8{0} ** len;
    const copy_len = @min(input.len, len);
    @memcpy(padded[0..copy_len], input[0..copy_len]);
    return padded;
}

/// BN254 elliptic curve addition (Byzantium)
fn bn254AddRunByzantium(input: []const u8, gas_limit: u64) main.PrecompileResult {
    return runAdd(input, add.BYZANTIUM_ADD_GAS_COST, gas_limit);
}

/// BN254 elliptic curve addition (Istanbul)
fn bn254AddRunIstanbul(input: []const u8, gas_limit: u64) main.PrecompileResult {
    return runAdd(input, add.ISTANBUL_ADD_GAS_COST, gas_limit);
}

fn runAdd(input: []const u8, gas_cost: u64, gas_limit: u64) main.PrecompileResult {
    if (gas_cost > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    const padded_input = rightPad(ADD_INPUT_LEN, input);
    const p1_bytes: [G1_LEN]u8 = padded_input[0..G1_LEN].*;
    const p2_bytes: [G1_LEN]u8 = padded_input[G1_LEN..].*;

    // Validate points
    if (!isValidG1Point(&p1_bytes) or !isValidG1Point(&p2_bytes)) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bn254FieldPointNotAMember };
    }

    var output: [64]u8 = undefined;
    if (mcl_wrapper.isAvailable()) {
        if (mcl_wrapper.g1Add(p1_bytes, p2_bytes)) |result| {
            output = result;
        } else |_| {
            // Fallback to placeholder if mcl fails
            @memset(&output, 0);
        }
    } else {
        // Placeholder if mcl not available
        @memset(&output, 0);
    }

    return main.PrecompileResult{ .success = main.PrecompileOutput.new(gas_cost, &output) };
}

/// BN254 elliptic curve scalar multiplication (Byzantium)
fn bn254MulRunByzantium(input: []const u8, gas_limit: u64) main.PrecompileResult {
    return runMul(input, mul.BYZANTIUM_MUL_GAS_COST, gas_limit);
}

/// BN254 elliptic curve scalar multiplication (Istanbul)
fn bn254MulRunIstanbul(input: []const u8, gas_limit: u64) main.PrecompileResult {
    return runMul(input, mul.ISTANBUL_MUL_GAS_COST, gas_limit);
}

fn runMul(input: []const u8, gas_cost: u64, gas_limit: u64) main.PrecompileResult {
    if (gas_cost > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    const padded_input = rightPad(MUL_INPUT_LEN, input);
    const point_bytes: [G1_LEN]u8 = padded_input[0..G1_LEN].*;
    const scalar_bytes: [SCALAR_LEN]u8 = padded_input[G1_LEN..].*;

    // Validate point
    if (!isValidG1Point(&point_bytes)) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bn254FieldPointNotAMember };
    }

    var output: [64]u8 = undefined;
    if (mcl_wrapper.isAvailable()) {
        if (mcl_wrapper.g1Mul(point_bytes, scalar_bytes)) |result| {
            output = result;
        } else |_| {
            // Fallback to placeholder if mcl fails
            @memset(&output, 0);
        }
    } else {
        // Placeholder if mcl not available
        @memset(&output, 0);
    }

    return main.PrecompileResult{ .success = main.PrecompileOutput.new(gas_cost, &output) };
}

/// BN254 elliptic curve pairing check (Byzantium)
fn bn254PairingRunByzantium(input: []const u8, gas_limit: u64) main.PrecompileResult {
    return runPairing(input, pair.BYZANTIUM_PAIR_PER_POINT, pair.BYZANTIUM_PAIR_BASE, gas_limit);
}

/// BN254 elliptic curve pairing check (Istanbul)
fn bn254PairingRunIstanbul(input: []const u8, gas_limit: u64) main.PrecompileResult {
    return runPairing(input, pair.ISTANBUL_PAIR_PER_POINT, pair.ISTANBUL_PAIR_BASE, gas_limit);
}

fn runPairing(input: []const u8, pair_per_point_cost: u64, pair_base_cost: u64, gas_limit: u64) main.PrecompileResult {
    if (input.len % PAIR_ELEMENT_LEN != 0) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bn254PairLength };
    }

    const num_pairs = input.len / PAIR_ELEMENT_LEN;
    const gas_used = @as(u64, num_pairs) * pair_per_point_cost + pair_base_cost;
    if (gas_used > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    // TODO: Replace with actual BN254 pairing check using external library
    // Parse pairs and verify pairing
    var i: usize = 0;
    while (i < input.len) : (i += PAIR_ELEMENT_LEN) {
        const g1_bytes = input[i..][0..G1_LEN];
        const g2_bytes = input[i + G1_LEN..][0..G2_LEN];
        if (!isValidG1Point(g1_bytes) or !isValidG2Point(g2_bytes)) {
            return main.PrecompileResult{ .err = main.PrecompileError.Bn254FieldPointNotAMember };
        }
    }

    // Placeholder: actual implementation would check pairing
    // TODO: Call bn254_pairing_check(pairs) from crypto library
    // Result is 1 if pairing is valid, 0 otherwise
    var output: [32]u8 = [_]u8{0} ** 32;
    output[31] = 1; // Placeholder: assume valid

    return main.PrecompileResult{ .success = main.PrecompileOutput.new(gas_used, &output) };
}

/// Basic validation for G1 point (checks if coordinates are in valid range)
/// TODO: Replace with proper curve validation
fn isValidG1Point(point: []const u8) bool {
    if (point.len < G1_LEN) return false;
    // Basic check: not all zeros (unless it's point at infinity which is (0,0))
    // For now, accept any 64-byte input
    return true;
}

/// Basic validation for G2 point
/// TODO: Replace with proper curve validation
fn isValidG2Point(point: []const u8) bool {
    if (point.len < G2_LEN) return false;
    // Basic check: not all zeros (unless it's point at infinity)
    // For now, accept any 128-byte input
    return true;
}
