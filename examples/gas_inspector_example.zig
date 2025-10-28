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

/// Example: Using the GasInspector to track gas consumption
pub fn main() !void {
    std.log.info("=== Gas Inspector Example ===\n", .{});

    // Create a gas inspector
    var gas_inspector = inspector.GasInspector.new();
    std.log.info("Gas inspector created", .{});

    // Create a gas tracker
    var gas = interpreter.Gas.new(100000);
    std.log.info("Initial gas limit: {}", .{gas.getLimit()});

    // Initialize the inspector with the gas tracker
    gas_inspector.initializeInterp(&gas);
    std.log.info("Gas remaining: {}", .{gas_inspector.gasRemaining()});
    std.log.info("Last gas cost: {}", .{gas_inspector.lastGasCost()});

    // Simulate some operations
    std.log.info("\n--- Simulating operations ---", .{});

    // Operation 1: PUSH1 (3 gas)
    _ = gas.spend(3);
    gas_inspector.step(&gas);
    std.log.info("After PUSH1:", .{});
    std.log.info("  Gas remaining: {}", .{gas_inspector.gasRemaining()});

    _ = gas.spend(3);
    gas_inspector.stepEnd(&gas);
    std.log.info("  Last gas cost: {}", .{gas_inspector.lastGasCost()});

    // Operation 2: ADD (3 gas)
    _ = gas.spend(3);
    gas_inspector.step(&gas);
    std.log.info("After ADD:", .{});
    std.log.info("  Gas remaining: {}", .{gas_inspector.gasRemaining()});

    _ = gas.spend(3);
    gas_inspector.stepEnd(&gas);
    std.log.info("  Last gas cost: {}", .{gas_inspector.lastGasCost()});

    // Operation 3: MSTORE (6 gas)
    _ = gas.spend(6);
    gas_inspector.step(&gas);
    std.log.info("After MSTORE:", .{});
    std.log.info("  Gas remaining: {}", .{gas_inspector.gasRemaining()});

    _ = gas.spend(6);
    gas_inspector.stepEnd(&gas);
    std.log.info("  Last gas cost: {}", .{gas_inspector.lastGasCost()});

    // Final summary
    std.log.info("\n--- Final Summary ---", .{});
    std.log.info("Total gas used: {}", .{gas.getSpent()});
    std.log.info("Gas remaining: {}", .{gas.getRemaining()});
    std.log.info("Gas efficiency: {d:.2}%", .{@as(f64, @floatFromInt(gas.getRemaining())) / @as(f64, @floatFromInt(gas.getLimit())) * 100.0});

    std.log.info("\n=== Example Complete ===", .{});
}
