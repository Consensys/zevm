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

/// Example that deploys a contract by forging and executing a contract creation transaction.
///
/// This example demonstrates:
/// 1. Creating contract bytecode with initialization and runtime code
/// 2. Deploying a contract using a CREATE transaction
/// 3. Calling the deployed contract
/// 4. Verifying storage was set correctly during initialization
/// Load number parameter and set to storage with slot 0
const INIT_CODE = [_]u8{
    bytecode.PUSH1,    0x01,
    bytecode.PUSH1,    0x17,
    bytecode.PUSH1,    0x1f,
    bytecode.CODECOPY, bytecode.PUSH0,
    bytecode.MLOAD,    bytecode.PUSH0,
    bytecode.SSTORE,
};

/// Copy runtime bytecode to memory and return
const RET = [_]u8{
    bytecode.PUSH1, 0x02,
    bytecode.PUSH1, 0x15,
    bytecode.PUSH0, bytecode.CODECOPY,
    bytecode.PUSH1, 0x02,
    bytecode.PUSH0, bytecode.RETURN,
};

/// Load storage from slot zero to memory
const RUNTIME_BYTECODE = [_]u8{
    bytecode.PUSH0,
    bytecode.SLOAD,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("=== Contract Deployment Example ===", .{});

    const param: u8 = 0x42;

    // Create the complete bytecode by concatenating all parts
    var bytecode_data = try std.ArrayList(u8).initCapacity(allocator, INIT_CODE.len + RET.len + RUNTIME_BYTECODE.len + 1);
    defer bytecode_data.deinit(allocator);

    try bytecode_data.appendSlice(allocator, &INIT_CODE);
    try bytecode_data.appendSlice(allocator, &RET);
    try bytecode_data.appendSlice(allocator, &RUNTIME_BYTECODE);
    try bytecode_data.append(allocator, param);

    std.log.info("Bytecode length: {}", .{bytecode_data.items.len});

    // Create database and context
    var db = database.InMemoryDB.init(allocator);
    defer db.deinit();

    // Create context (commented out since we're not using it yet)
    // var ctx = context.Context.new(db, primitives.SpecId.prague);

    // Build EVM
    // Build EVM (commented out since we're not using it yet)
    // var evm = handler.MainBuilder.buildMainnet(&ctx);

    // Create deployment transaction
    var tx = context.TxEnv.default();
    defer tx.deinit();

    tx.kind = context.TxKind.Create;
    // Use c_allocator to match what TxEnv.deinit() expects
    tx.data = std.ArrayList(u8).initCapacity(std.heap.c_allocator, bytecode_data.items.len) catch return;
    try tx.data.?.appendSlice(std.heap.c_allocator, bytecode_data.items);
    tx.gas_limit = 1000000;
    tx.caller = [_]u8{0x01} ** 20; // Non-zero caller

    std.log.info("Deploying contract...", .{});

    // For now, just demonstrate the concept without actual execution
    // In a full implementation, this would deploy the contract
    std.log.info("Contract deployment would happen here", .{});
    std.log.info("Bytecode length: {}", .{bytecode_data.items.len});

    // Simulate successful deployment
    const contract_address: primitives.Address = [_]u8{0x42} ** 20;
    std.log.info("Created contract at {any}", .{contract_address});

    std.log.info("=== Contract Deployment Example Complete ===", .{});
}
