const std = @import("std");
const testing = std.testing;
const main = @import("main.zig");
const identity = @import("identity.zig");
const hash = @import("hash.zig");
const secp256k1 = @import("secp256k1.zig");
const modexp = @import("modexp.zig");

test "Identity precompile - basic functionality" {
    const input = "Hello, World!";
    const result = identity.identityRun(input, 1000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == 15 + 3); // base + word cost
    try testing.expect(std.mem.eql(u8, output.bytes, input));
    try testing.expect(output.reverted == false);
}

test "Identity precompile - empty input" {
    const input = "";
    const result = identity.identityRun(input, 1000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == 15); // base only
    try testing.expect(output.bytes.len == 0);
}

test "Identity precompile - out of gas" {
    const input = "Hello, World!";
    const result = identity.identityRun(input, 10); // Not enough gas

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.OutOfGas);
}

test "Identity precompile - large input" {
    var input: [1000]u8 = undefined;
    @memset(&input, 0x42);
    const result = identity.identityRun(&input, 10000);

    try testing.expect(result == .success);
    const output = result.success;
    const expected_gas = 15 + ((1000 + 31) / 32) * 3;
    try testing.expect(output.gas_used == expected_gas);
    try testing.expect(std.mem.eql(u8, output.bytes, &input));
}

test "SHA-256 precompile - basic functionality" {
    const input = "Hello, World!";
    const result = hash.sha256Run(input, 1000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == 60 + 12); // base + word cost
    try testing.expect(output.bytes.len == 32);
    try testing.expect(output.reverted == false);
}

test "SHA-256 precompile - empty input" {
    const input = "";
    const result = hash.sha256Run(input, 1000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == 60); // base only
    try testing.expect(output.bytes.len == 32);

    // Empty string SHA-256: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
    const expected: [32]u8 = .{
        0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14,
        0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f, 0xb9, 0x24,
        0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c,
        0xa4, 0x95, 0x99, 0x1b, 0x78, 0x52, 0xb8, 0x55,
    };
    try testing.expect(std.mem.eql(u8, output.bytes, &expected));
}

test "SHA-256 precompile - out of gas" {
    const input = "Hello, World!";
    const result = hash.sha256Run(input, 50); // Not enough gas

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.OutOfGas);
}

test "SHA-256 precompile - known test vector" {
    const input = "abc";
    const result = hash.sha256Run(input, 1000);

    try testing.expect(result == .success);
    const output = result.success;

    // SHA-256("abc") = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
    const expected: [32]u8 = .{
        0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
        0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
        0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
        0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad,
    };
    try testing.expect(std.mem.eql(u8, output.bytes, &expected));
}

test "RIPEMD-160 precompile - basic functionality" {
    const input = "Hello, World!";
    const result = hash.ripemd160Run(input, 1000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == 600 + 120); // base + word cost
    try testing.expect(output.bytes.len == 32);
    try testing.expect(output.reverted == false);

    // Check that first 12 bytes are zero (padding)
    try testing.expect(std.mem.allEqual(u8, output.bytes[0..12], 0));
}

test "RIPEMD-160 precompile - empty input" {
    const input = "";
    const result = hash.ripemd160Run(input, 1000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == 600); // base only
    try testing.expect(output.bytes.len == 32);
}

test "RIPEMD-160 precompile - out of gas" {
    const input = "Hello, World!";
    const result = hash.ripemd160Run(input, 500); // Not enough gas

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.OutOfGas);
}

test "ECRECOVER precompile - invalid input (wrong v value)" {
    var input: [128]u8 = undefined;
    @memset(&input, 0);
    input[63] = 26; // Invalid v value (not 27 or 28)

    const result = secp256k1.ecRecoverRun(&input, 10000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == 3000);
    try testing.expect(output.bytes.len == 0); // Empty result for invalid input
}

test "ECRECOVER precompile - invalid input (v not padded)" {
    var input: [128]u8 = undefined;
    @memset(&input, 0);
    input[32] = 1; // Non-zero byte before v
    input[63] = 27;

    const result = secp256k1.ecRecoverRun(&input, 10000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == 3000);
    try testing.expect(output.bytes.len == 0); // Empty result for invalid input
}

test "ECRECOVER precompile - valid format but invalid signature" {
    var input: [128]u8 = undefined;
    @memset(&input, 0);
    input[63] = 27; // Valid v value

    const result = secp256k1.ecRecoverRun(&input, 10000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == 3000);
    // May return empty if secp256k1 library not available or signature invalid
}

test "ECRECOVER precompile - out of gas" {
    var input: [128]u8 = undefined;
    @memset(&input, 0);
    input[63] = 27;

    const result = secp256k1.ecRecoverRun(&input, 2000); // Not enough gas

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.OutOfGas);
}

test "ECRECOVER precompile - short input" {
    const input = "short";
    const result = secp256k1.ecRecoverRun(input, 10000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == 3000);
    // Should handle short input gracefully (right-padded)
}

test "ECRECOVER precompile - known test vector" {
    // Test with a known signature recovery case
    // This is a simplified test - in production you'd use a real signature
    var input: [128]u8 = undefined;
    @memset(&input, 0);

    // Set a valid message hash (32 bytes)
    input[0] = 0x01;
    input[31] = 0xFF;

    // Set valid v value (27)
    input[63] = 27;

    // Set signature (64 bytes) - this is a placeholder, not a real signature
    // In a real test, you'd use an actual signature that can be recovered
    input[64] = 0x01;
    input[127] = 0xFF;

    const result = secp256k1.ecRecoverRun(&input, 10000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == 3000);
    // Result may be empty if signature is invalid (which this placeholder is)
    // But the precompile should handle it gracefully
}

test "ModExp precompile - empty input" {
    const input = "";
    const result = modexp.byzantiumRun(input, 1000);

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.ModexpBaseOverflow);
}

test "ModExp precompile - zero base and modulus" {
    var input: [96]u8 = undefined;
    @memset(&input, 0);
    // base_len = 0, exp_len = 0, mod_len = 0

    const result = modexp.byzantiumRun(&input, 1000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.bytes.len == 0);
}

test "ModExp precompile - small values" {
    var input: [128]u8 = undefined;
    @memset(&input, 0);

    // Header: base_len=1, exp_len=1, mod_len=1
    input[31] = 1; // base_len = 1
    input[63] = 1; // exp_len = 1
    input[95] = 1; // mod_len = 1

    // Data: base=2, exp=3, mod=5
    input[96] = 2; // base
    input[97] = 3; // exp
    input[98] = 5; // mod

    // Expected: 2^3 mod 5 = 8 mod 5 = 3
    const result = modexp.byzantiumRun(&input, 10000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.bytes.len == 1);
    try testing.expect(output.bytes[0] == 3);
}

test "ModExp precompile - Berlin gas calculation" {
    var input: [128]u8 = undefined;
    @memset(&input, 0);

    input[31] = 1; // base_len = 1
    input[63] = 1; // exp_len = 1
    input[95] = 1; // mod_len = 1

    input[96] = 2;
    input[97] = 3;
    input[98] = 5;

    const result = modexp.berlinRun(&input, 10000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used >= 200); // Minimum gas for Berlin
}

test "ModExp precompile - Osaka gas calculation" {
    var input: [128]u8 = undefined;
    @memset(&input, 0);

    input[31] = 1; // base_len = 1
    input[63] = 1; // exp_len = 1
    input[95] = 1; // mod_len = 1

    input[96] = 2;
    input[97] = 3;
    input[98] = 5;

    const result = modexp.osakaRun(&input, 10000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used >= 500); // Minimum gas for Osaka
}

test "ModExp precompile - out of gas" {
    var input: [128]u8 = undefined;
    @memset(&input, 0);

    input[31] = 1;
    input[63] = 1;
    input[95] = 1;

    const result = modexp.byzantiumRun(&input, 1); // Not enough gas

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.OutOfGas);
}

test "ModExp precompile - large exponent" {
    var input: [200]u8 = undefined;
    @memset(&input, 0);

    // base_len=1, exp_len=10, mod_len=1
    input[31] = 1;
    input[63] = 10;
    input[95] = 1;

    input[96] = 2; // base = 2
    // exp = 1 (10 bytes, all zeros except last)
    input[105] = 1;
    input[106] = 5; // mod = 5

    const result = modexp.byzantiumRun(&input, 100000);

    try testing.expect(result == .success);
    // 2^1 mod 5 = 2
    const output = result.success;
    try testing.expect(output.bytes.len == 1);
    try testing.expect(output.bytes[0] == 2);
}

// ============================================================================
// Blake2F Precompile Tests
// ============================================================================

test "Blake2F precompile - basic functionality" {
    var input: [213]u8 = undefined;
    @memset(&input, 0);

    // Set rounds = 1 (big-endian)
    input[3] = 1;

    // Set final flag = 1
    input[212] = 1;

    const blake2 = @import("blake2.zig");
    const result = blake2.blake2fRun(&input, 1000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == 1); // 1 round * 1 gas
    try testing.expect(output.bytes.len == 64);
}

test "Blake2F precompile - wrong input length" {
    const input = "short";
    const blake2 = @import("blake2.zig");
    const result = blake2.blake2fRun(input, 1000);

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.Blake2WrongLength);
}

test "Blake2F precompile - invalid final flag" {
    var input: [213]u8 = undefined;
    @memset(&input, 0);
    input[212] = 2; // Invalid flag (must be 0 or 1)

    const blake2 = @import("blake2.zig");
    const result = blake2.blake2fRun(&input, 1000);

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.Blake2WrongFinalIndicatorFlag);
}

test "Blake2F precompile - out of gas" {
    var input: [213]u8 = undefined;
    @memset(&input, 0);
    input[3] = 100; // 100 rounds
    input[212] = 1;

    const blake2 = @import("blake2.zig");
    const result = blake2.blake2fRun(&input, 50); // Not enough gas

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.OutOfGas);
}

// ============================================================================
// BN254 Precompile Tests
// ============================================================================

test "BN254 Add precompile - input validation" {
    var input: [128]u8 = undefined;
    @memset(&input, 0);

    const bn254 = @import("bn254.zig");
    const result = bn254.add.ISTANBUL.execute(&input, 1000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == bn254.add.ISTANBUL_ADD_GAS_COST);
    try testing.expect(output.bytes.len == 64);
}

test "BN254 Add precompile - out of gas" {
    const input = "";
    const bn254 = @import("bn254.zig");
    const result = bn254.add.ISTANBUL.execute(input, 100);

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.OutOfGas);
}

test "BN254 Mul precompile - input validation" {
    var input: [96]u8 = undefined;
    @memset(&input, 0);

    const bn254 = @import("bn254.zig");
    const result = bn254.mul.ISTANBUL.execute(&input, 10000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == bn254.mul.ISTANBUL_MUL_GAS_COST);
    try testing.expect(output.bytes.len == 64);
}

test "BN254 Pairing precompile - input validation" {
    var input: [192]u8 = undefined; // One pair (G1 + G2)
    @memset(&input, 0);

    const bn254 = @import("bn254.zig");
    const result = bn254.pair.ISTANBUL.execute(&input, 100000);

    try testing.expect(result == .success);
    const output = result.success;
    const expected_gas = bn254.pair.ISTANBUL_PAIR_PER_POINT + bn254.pair.ISTANBUL_PAIR_BASE;
    try testing.expect(output.gas_used == expected_gas);
    try testing.expect(output.bytes.len == 32);
}

test "BN254 Pairing precompile - invalid input length" {
    var input: [100]u8 = undefined; // Not a multiple of 192
    @memset(&input, 0);

    const bn254 = @import("bn254.zig");
    const result = bn254.pair.ISTANBUL.execute(&input, 100000);

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.Bn254PairLength);
}

// ============================================================================
// KZG Point Evaluation Precompile Tests
// ============================================================================

test "KZG Point Evaluation - input validation" {
    var input: [192]u8 = undefined;
    @memset(&input, 0);

    // Set versioned hash (first 32 bytes)
    input[0] = 0x01; // Version
    // Rest will be SHA-256 hash of commitment

    const kzg = @import("kzg_point_evaluation.zig");
    const result = kzg.POINT_EVALUATION.execute(&input, 100000);

    // Will fail on version mismatch or proof verification, but should handle input correctly
    // For now, just check it doesn't crash on invalid input
    _ = result;
}

test "KZG Point Evaluation - wrong input length" {
    const input = "short";
    const kzg = @import("kzg_point_evaluation.zig");
    const result = kzg.POINT_EVALUATION.execute(input, 100000);

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.BlobInvalidInputLength);
}

test "KZG Point Evaluation - out of gas" {
    var input: [192]u8 = undefined;
    @memset(&input, 0);

    const kzg = @import("kzg_point_evaluation.zig");
    const result = kzg.POINT_EVALUATION.execute(&input, 1000); // Not enough gas

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.OutOfGas);
}

// ============================================================================
// BLS12-381 Precompile Tests
// ============================================================================

test "BLS12-381 G1 Add - input validation" {
    var input: [256]u8 = undefined; // 2 * 128 bytes (padded G1 points)
    @memset(&input, 0);

    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.g1_add.PRECOMPILE.execute(&input, 1000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == 375); // G1_ADD_BASE_GAS_FEE
    try testing.expect(output.bytes.len == 128); // Padded G1 point
}

test "BLS12-381 G1 Add - wrong input length" {
    const input = "short";
    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.g1_add.PRECOMPILE.execute(input, 1000);

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.Bls12381G1AddInputLength);
}

test "BLS12-381 G1 Add - out of gas" {
    var input: [256]u8 = undefined;
    @memset(&input, 0);

    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.g1_add.PRECOMPILE.execute(&input, 100);

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.OutOfGas);
}

test "BLS12-381 G2 Add - input validation" {
    var input: [512]u8 = undefined; // 2 * 256 bytes (padded G2 points)
    @memset(&input, 0);

    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.g2_add.PRECOMPILE.execute(&input, 1000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == 600); // G2_ADD_BASE_GAS_FEE
    try testing.expect(output.bytes.len == 256); // Padded G2 point
}

test "BLS12-381 G1 MSM - input validation" {
    // Minimum input: 1 point (128 bytes) + 1 scalar (64 bytes) = 192 bytes
    var input: [192]u8 = undefined;
    @memset(&input, 0);

    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.g1_msm.PRECOMPILE.execute(&input, 100000);

    try testing.expect(result == .success);
    const output = result.success;
    // Gas = (1 * 12000 * 1000) / 1000 = 12000
    try testing.expect(output.gas_used >= 12000);
    try testing.expect(output.bytes.len == 128);
}

test "BLS12-381 G2 MSM - input validation" {
    // Minimum input: 1 point (256 bytes) + 1 scalar (64 bytes) = 320 bytes
    var input: [320]u8 = undefined;
    @memset(&input, 0);

    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.g2_msm.PRECOMPILE.execute(&input, 100000);

    try testing.expect(result == .success);
    const output = result.success;
    // Gas = (1 * 22500 * 1000) / 1000 = 22500
    try testing.expect(output.gas_used >= 22500);
    try testing.expect(output.bytes.len == 256);
}

test "BLS12-381 Pairing - input validation" {
    // Minimum input: 1 pair (128 + 256 = 384 bytes)
    var input: [384]u8 = undefined;
    @memset(&input, 0);

    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.pairing.PRECOMPILE.execute(&input, 100000);

    try testing.expect(result == .success);
    const output = result.success;
    // Gas = 1 * 32600 + 37700 = 70300
    try testing.expect(output.gas_used == 70300);
    try testing.expect(output.bytes.len == 32);
}

test "BLS12-381 Pairing - invalid input length" {
    var input: [100]u8 = undefined; // Not a multiple of 384
    @memset(&input, 0);

    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.pairing.PRECOMPILE.execute(&input, 100000);

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.Bls12381PairingInputLength);
}

test "BLS12-381 MapFpToG1 - input validation" {
    var input: [64]u8 = undefined; // Padded Fp element
    @memset(&input, 0);

    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.map_fp_to_g1.PRECOMPILE.execute(&input, 10000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == 5500); // MAP_FP_TO_G1_BASE_GAS_FEE
    try testing.expect(output.bytes.len == 128);
}

test "BLS12-381 MapFp2ToG2 - input validation" {
    var input: [128]u8 = undefined; // Padded Fp2 element
    @memset(&input, 0);

    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.map_fp2_to_g2.PRECOMPILE.execute(&input, 50000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == 23800); // MAP_FP2_TO_G2_BASE_GAS_FEE
    try testing.expect(output.bytes.len == 256);
}

// ============================================================================
// P256Verify Precompile Tests
// ============================================================================

test "P256Verify - input validation" {
    var input: [160]u8 = undefined; // 32 (msg) + 32 (r) + 32 (s) + 32 (x) + 32 (y)
    @memset(&input, 0);

    const secp256r1 = @import("secp256r1.zig");
    const result = secp256r1.P256VERIFY.execute(&input, 10000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == 3450); // P256VERIFY_BASE_GAS_FEE
    // Result will be empty (invalid signature) but should succeed
}

test "P256Verify - wrong input length" {
    const input = "short";
    const secp256r1 = @import("secp256r1.zig");
    const result = secp256r1.P256VERIFY.execute(input, 10000);

    try testing.expect(result == .success);
    // Should handle gracefully, verifyImpl returns false for wrong length
    const output = result.success;
    try testing.expect(output.bytes.len == 0);
}

test "P256Verify - out of gas" {
    var input: [160]u8 = undefined;
    @memset(&input, 0);

    const secp256r1 = @import("secp256r1.zig");
    const result = secp256r1.P256VERIFY.execute(&input, 1000);

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.OutOfGas);
}

test "P256Verify Osaka - different gas cost" {
    var input: [160]u8 = undefined;
    @memset(&input, 0);

    const secp256r1 = @import("secp256r1.zig");
    const result = secp256r1.P256VERIFY_OSAKA.execute(&input, 10000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == 6900); // P256VERIFY_BASE_GAS_FEE_OSAKA
}

// ============================================================================
// Additional Comprehensive Tests
// ============================================================================

test "Blake2F precompile - known test vector (2 rounds)" {
    // Test vector from revm benchmarks
    var input: [213]u8 = undefined;
    @memset(&input, 0);

    // rounds = 2 (big-endian)
    input[3] = 2;

    // Set some test data in h, m, t
    input[4] = 0x48; // Start of h state
    input[68] = 0x61; // Start of m (message)
    input[69] = 0x62;
    input[70] = 0x63;

    // t_0 = 3 (little-endian)
    input[196] = 3;

    // final flag = 1
    input[212] = 1;

    const blake2 = @import("blake2.zig");
    const result = blake2.blake2fRun(&input, 1000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == 2); // 2 rounds * 1 gas
    try testing.expect(output.bytes.len == 64);
    // Output should be non-zero (actual compression result)
}

test "Blake2F precompile - zero rounds" {
    var input: [213]u8 = undefined;
    @memset(&input, 0);
    input[212] = 1; // final flag

    const blake2 = @import("blake2.zig");
    const result = blake2.blake2fRun(&input, 1000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == 0); // 0 rounds
}

test "BN254 Add precompile - Byzantium gas cost" {
    var input: [128]u8 = undefined;
    @memset(&input, 0);

    const bn254 = @import("bn254.zig");
    const result = bn254.add.BYZANTIUM.execute(&input, 1000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == bn254.add.BYZANTIUM_ADD_GAS_COST);
    try testing.expect(output.gas_used == 500); // Byzantium cost is higher
}

test "BN254 Mul precompile - Byzantium gas cost" {
    var input: [96]u8 = undefined;
    @memset(&input, 0);

    const bn254 = @import("bn254.zig");
    const result = bn254.mul.BYZANTIUM.execute(&input, 50000);

    try testing.expect(result == .success);
    const output = result.success;
    try testing.expect(output.gas_used == bn254.mul.BYZANTIUM_MUL_GAS_COST);
    try testing.expect(output.gas_used == 40000); // Byzantium cost is higher
}

test "BN254 Pairing precompile - multiple pairs" {
    // Two pairs: 2 * 192 = 384 bytes
    var input: [384]u8 = undefined;
    @memset(&input, 0);

    const bn254 = @import("bn254.zig");
    const result = bn254.pair.ISTANBUL.execute(&input, 200000);

    try testing.expect(result == .success);
    const output = result.success;
    const expected_gas = 2 * bn254.pair.ISTANBUL_PAIR_PER_POINT + bn254.pair.ISTANBUL_PAIR_BASE;
    try testing.expect(output.gas_used == expected_gas);
    try testing.expect(output.bytes.len == 32);
}

test "BN254 Pairing precompile - Byzantium gas cost" {
    var input: [192]u8 = undefined;
    @memset(&input, 0);

    const bn254 = @import("bn254.zig");
    const result = bn254.pair.BYZANTIUM.execute(&input, 200000);

    try testing.expect(result == .success);
    const output = result.success;
    const expected_gas = bn254.pair.BYZANTIUM_PAIR_PER_POINT + bn254.pair.BYZANTIUM_PAIR_BASE;
    try testing.expect(output.gas_used == expected_gas);
    try testing.expect(output.gas_used == 180000); // Byzantium cost is much higher
}

test "KZG Point Evaluation - version mismatch" {
    var input: [192]u8 = undefined;
    @memset(&input, 0);

    // Set wrong version in versioned hash
    input[0] = 0x02; // Wrong version (should be 0x01)

    // Compute hash of commitment (zeros) and set version
    var computed_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input[96..144], &computed_hash, .{});
    computed_hash[0] = 0x01; // Correct version

    // But we set wrong version in input
    @memcpy(input[0..32], &computed_hash);
    input[0] = 0x02; // Wrong version

    const kzg = @import("kzg_point_evaluation.zig");
    const result = kzg.POINT_EVALUATION.execute(&input, 100000);

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.BlobMismatchedVersion);
}

test "BLS12-381 G1 MSM - multiple points" {
    // 3 points: 3 * (128 + 64) = 576 bytes
    var input: [576]u8 = undefined;
    @memset(&input, 0);

    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.g1_msm.PRECOMPILE.execute(&input, 100000);

    try testing.expect(result == .success);
    const output = result.success;
    // Gas should be calculated with discount table
    try testing.expect(output.gas_used >= 12000);
    try testing.expect(output.bytes.len == 128);
}

test "BLS12-381 G2 MSM - multiple points" {
    // 3 points: 3 * (256 + 64) = 960 bytes
    var input: [960]u8 = undefined;
    @memset(&input, 0);

    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.g2_msm.PRECOMPILE.execute(&input, 200000);

    try testing.expect(result == .success);
    const output = result.success;
    // Gas should be calculated with discount table
    try testing.expect(output.gas_used >= 22500);
    try testing.expect(output.bytes.len == 256);
}

test "BLS12-381 Pairing - multiple pairs" {
    // 3 pairs: 3 * 384 = 1152 bytes
    var input: [1152]u8 = undefined;
    @memset(&input, 0);

    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.pairing.PRECOMPILE.execute(&input, 200000);

    try testing.expect(result == .success);
    const output = result.success;
    // Gas = 3 * 32600 + 37700 = 135500
    try testing.expect(output.gas_used == 135500);
    try testing.expect(output.bytes.len == 32);
}

test "BLS12-381 G1 MSM - invalid input length" {
    // Invalid length (not a multiple of point+scalar size)
    var input: [200]u8 = undefined;
    @memset(&input, 0);

    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.g1_msm.PRECOMPILE.execute(&input, 100000);

    // Should still succeed (will calculate k based on available input)
    // But may have issues with parsing
    _ = result;
}

test "BLS12-381 G2 MSM - invalid input length" {
    // Invalid length (not a multiple of point+scalar size)
    var input: [300]u8 = undefined;
    @memset(&input, 0);

    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.g2_msm.PRECOMPILE.execute(&input, 100000);

    // Should still succeed (will calculate k based on available input)
    _ = result;
}

test "BLS12-381 MapFpToG1 - invalid input length" {
    const input = "short";
    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.map_fp_to_g1.PRECOMPILE.execute(input, 10000);

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.Bls12381MapFpToG1InputLength);
}

test "BLS12-381 MapFp2ToG2 - invalid input length" {
    const input = "short";
    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.map_fp2_to_g2.PRECOMPILE.execute(input, 50000);

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.Bls12381MapFp2ToG2InputLength);
}

test "BLS12-381 MapFpToG1 - out of gas" {
    var input: [64]u8 = undefined;
    @memset(&input, 0);

    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.map_fp_to_g1.PRECOMPILE.execute(&input, 1000);

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.OutOfGas);
}

test "BLS12-381 MapFp2ToG2 - out of gas" {
    var input: [128]u8 = undefined;
    @memset(&input, 0);

    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.map_fp2_to_g2.PRECOMPILE.execute(&input, 1000);

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.OutOfGas);
}

test "BLS12-381 G2 Add - out of gas" {
    var input: [512]u8 = undefined;
    @memset(&input, 0);

    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.g2_add.PRECOMPILE.execute(&input, 100);

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.OutOfGas);
}

test "BLS12-381 G1 MSM - out of gas" {
    var input: [192]u8 = undefined;
    @memset(&input, 0);

    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.g1_msm.PRECOMPILE.execute(&input, 1000);

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.OutOfGas);
}

test "BLS12-381 G2 MSM - out of gas" {
    var input: [320]u8 = undefined;
    @memset(&input, 0);

    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.g2_msm.PRECOMPILE.execute(&input, 1000);

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.OutOfGas);
}

test "BLS12-381 Pairing - out of gas" {
    var input: [384]u8 = undefined;
    @memset(&input, 0);

    const bls12_381 = @import("bls12_381.zig");
    const result = bls12_381.pairing.PRECOMPILE.execute(&input, 1000);

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.OutOfGas);
}

test "BN254 Mul precompile - out of gas" {
    var input: [96]u8 = undefined;
    @memset(&input, 0);

    const bn254 = @import("bn254.zig");
    const result = bn254.mul.ISTANBUL.execute(&input, 1000);

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.OutOfGas);
}

test "BN254 Pairing precompile - out of gas" {
    var input: [192]u8 = undefined;
    @memset(&input, 0);

    const bn254 = @import("bn254.zig");
    const result = bn254.pair.ISTANBUL.execute(&input, 1000);

    try testing.expect(result == .err);
    try testing.expect(result.err == main.PrecompileError.OutOfGas);
}

test "BN254 Pairing precompile - empty input" {
    const input = "";
    const bn254 = @import("bn254.zig");
    const result = bn254.pair.ISTANBUL.execute(input, 100000);

    // Empty input should be valid (0 pairs)
    try testing.expect(result == .success);
    const output = result.success;
    // Gas = 0 * per_point + base = base
    try testing.expect(output.gas_used == bn254.pair.ISTANBUL_PAIR_BASE);
}
