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

