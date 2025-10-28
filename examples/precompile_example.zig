const std = @import("std");
const primitives = @import("primitives");
const bytecode = @import("bytecode");
const state = @import("state");
const database = @import("database");
const context = @import("context");
const interpreter = @import("interpreter");
const precompile = @import("precompile");
const handler = @import("handler");
const inspector = @import("inspector");

/// Example: Using precompiled contracts
pub fn main() !void {
    std.log.info("=== Precompile Example ===\n", .{});

    // Test Identity precompile (address 0x04)
    std.log.info("--- Testing Identity Precompile ---", .{});
    const identity_input = "Hello, ZEVM!";
    std.log.info("Input: {s}", .{identity_input});

    const identity_precompile = precompile.Precompile.new(
        precompile.PrecompileId.Identity,
        precompile.u64ToAddress(4),
        precompile.identity.identityRun,
    );

    const identity_result = identity_precompile.execute(identity_input, 10000);
    switch (identity_result) {
        .success => |output| {
            std.log.info("Success!", .{});
            std.log.info("  Gas used: {}", .{output.gas_used});
            std.log.info("  Output: {s}", .{output.bytes});
            std.log.info("  Reverted: {}", .{output.reverted});
        },
        .err => |err| {
            std.log.err("Error: {}", .{err});
        },
    }

    // Test SHA256 precompile (address 0x02)
    std.log.info("\n--- Testing SHA256 Precompile ---", .{});
    const sha256_input = "test data";
    std.log.info("Input: {s}", .{sha256_input});

    const sha256_precompile = precompile.Precompile.new(
        precompile.PrecompileId.Sha256,
        precompile.u64ToAddress(2),
        precompile.hash.sha256Run,
    );

    const sha256_result = sha256_precompile.execute(sha256_input, 10000);
    switch (sha256_result) {
        .success => |output| {
            std.log.info("Success!", .{});
            std.log.info("  Gas used: {}", .{output.gas_used});
            std.log.info("  Output hash (first 8 bytes): {x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
                output.bytes[0],
                output.bytes[1],
                output.bytes[2],
                output.bytes[3],
                output.bytes[4],
                output.bytes[5],
                output.bytes[6],
                output.bytes[7],
            });
            std.log.info("  Reverted: {}", .{output.reverted});
        },
        .err => |err| {
            std.log.err("Error: {}", .{err});
        },
    }

    // Test RIPEMD160 precompile (address 0x03)
    std.log.info("\n--- Testing RIPEMD160 Precompile ---", .{});
    const ripemd_input = "test data";
    std.log.info("Input: {s}", .{ripemd_input});

    const ripemd_precompile = precompile.Precompile.new(
        precompile.PrecompileId.Ripemd160,
        precompile.u64ToAddress(3),
        precompile.hash.ripemd160Run,
    );

    const ripemd_result = ripemd_precompile.execute(ripemd_input, 10000);
    switch (ripemd_result) {
        .success => |output| {
            std.log.info("Success!", .{});
            std.log.info("  Gas used: {}", .{output.gas_used});
            std.log.info("  Output hash (first 8 bytes): {x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
                output.bytes[0],
                output.bytes[1],
                output.bytes[2],
                output.bytes[3],
                output.bytes[4],
                output.bytes[5],
                output.bytes[6],
                output.bytes[7],
            });
            std.log.info("  Reverted: {}", .{output.reverted});
        },
        .err => |err| {
            std.log.err("Error: {}", .{err});
        },
    }

    // Create a precompiles collection
    std.log.info("\n--- Testing Precompiles Collection ---", .{});
    var precompiles = precompile.Precompiles.new();

    try precompiles.add(identity_precompile);
    try precompiles.add(sha256_precompile);
    try precompiles.add(ripemd_precompile);

    std.log.info("Added {} precompiles to collection", .{3});

    // Retrieve a precompile by address
    const identity_addr = precompile.u64ToAddress(4);
    const retrieved = precompiles.get(identity_addr);
    if (retrieved) |pc| {
        std.log.info("Retrieved precompile: {}", .{pc.id});
    } else {
        std.log.info("Precompile not found", .{});
    }

    std.log.info("\n=== Example Complete ===", .{});
}
