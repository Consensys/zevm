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

/// Simple benchmark for ZEVM performance testing
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("=== ZEVM Performance Benchmark ===", .{});

    // Benchmark 1: U256 operations
    try benchmarkU256Operations();

    // Benchmark 2: Stack operations
    try benchmarkStackOperations();

    // Benchmark 3: Memory operations
    try benchmarkMemoryOperations();

    // Benchmark 4: Gas tracking
    try benchmarkGasTracking();

    // Benchmark 5: Precompile operations
    try benchmarkPrecompiles();

    // Benchmark 6: Database operations
    try benchmarkDatabaseOperations(allocator);

    // Benchmark 7: Context operations
    try benchmarkContextOperations(allocator);

    std.log.info("=== Benchmark Complete ===", .{});
}

fn benchmarkU256Operations() !void {
    std.log.info("Benchmarking U256 operations...", .{});

    const iterations = 1_000_000;
    const start_time = std.time.nanoTimestamp();

    var sum: primitives.U256 = 0;
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        sum += i;
        sum *= 2;
        sum /= 3;
    }

    const end_time = std.time.nanoTimestamp();
    const duration = end_time - start_time;
    const ops_per_sec = (iterations * 3 * 1_000_000_000) / @as(u64, @intCast(duration));

    std.log.info("U256 operations: {} ops/sec", .{ops_per_sec});
    std.log.info("Final sum: {}", .{sum}); // Prevent optimization
}

fn benchmarkStackOperations() !void {
    std.log.info("Benchmarking Stack operations...", .{});

    const iterations = 100_000;
    var stack = interpreter.Stack.new();

    const start_time = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        try stack.push(@as(primitives.U256, i));
        if (stack.len() > 100) {
            _ = stack.pop();
        }
    }

    const end_time = std.time.nanoTimestamp();
    const duration = end_time - start_time;
    const ops_per_sec = (iterations * 1_000_000_000) / @as(u64, @intCast(duration));

    std.log.info("Stack operations: {} ops/sec", .{ops_per_sec});
}

fn benchmarkMemoryOperations() !void {
    std.log.info("Benchmarking Memory operations...", .{});

    const iterations = 10_000;
    var memory = interpreter.Memory.new();
    defer memory.deinit();

    const start_time = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const offset = i * 32;
        const value = [_]u8{@as(u8, @intCast(i & 0xFF))} ** 32;
        try memory.set(offset, &value);
        _ = memory.slice(offset, offset + 32);
    }

    const end_time = std.time.nanoTimestamp();
    const duration = end_time - start_time;
    const ops_per_sec = (iterations * 2 * 1_000_000_000) / @as(u64, @intCast(duration));

    std.log.info("Memory operations: {} ops/sec", .{ops_per_sec});
}

fn benchmarkGasTracking() !void {
    std.log.info("Benchmarking Gas tracking...", .{});

    const iterations = 1_000_000;
    var gas = interpreter.Gas.new(1_000_000);

    const start_time = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        _ = gas.spend(1);
        _ = gas.getRemaining();
        _ = gas.getLimit();
    }

    const end_time = std.time.nanoTimestamp();
    const duration = end_time - start_time;
    const ops_per_sec = (iterations * 3 * 1_000_000_000) / @as(u64, @intCast(duration));

    std.log.info("Gas tracking: {} ops/sec", .{ops_per_sec});
}

fn benchmarkPrecompiles() !void {
    std.log.info("Benchmarking Precompiles...", .{});

    const iterations = 10_000;
    const input = "Hello, ZEVM Benchmark!";

    const start_time = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const result = precompile.identity.identityRun(input, 10000);
        _ = result; // Prevent optimization
    }

    const end_time = std.time.nanoTimestamp();
    const duration = end_time - start_time;
    const ops_per_sec = (iterations * 1_000_000_000) / @as(u64, @intCast(duration));

    std.log.info("Precompile operations: {} ops/sec", .{ops_per_sec});
}

fn benchmarkDatabaseOperations(allocator: std.mem.Allocator) !void {
    std.log.info("Benchmarking Database operations...", .{});

    const iterations = 10_000;
    var db = database.InMemoryDB.init(allocator);
    defer db.deinit();

    const start_time = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const addr: primitives.Address = [_]u8{@as(u8, @intCast(i & 0xFF))} ** 20;
        const account = state.AccountInfo.new(
            @as(primitives.U256, i),
            i,
            primitives.KECCAK_EMPTY,
            bytecode.Bytecode.new(),
        );

        try db.insertAccount(addr, account);
        _ = try db.basic(addr);
    }

    const end_time = std.time.nanoTimestamp();
    const duration = end_time - start_time;
    const ops_per_sec = (iterations * 2 * 1_000_000_000) / @as(u64, @intCast(duration));

    std.log.info("Database operations: {} ops/sec", .{ops_per_sec});
}

fn benchmarkContextOperations(allocator: std.mem.Allocator) !void {
    std.log.info("Benchmarking Context operations...", .{});

    const iterations = 1_000;
    var db = database.InMemoryDB.init(allocator);
    defer db.deinit();

    const start_time = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        var ctx = context.Context.new(db, primitives.SpecId.prague);
        var tx = context.TxEnv.default();
        defer tx.deinit();

        tx.caller = [_]u8{@as(u8, @intCast(i & 0xFF))} ** 20;
        tx.gas_limit = 100000;
        ctx.tx = tx;

        _ = ctx.cfg.spec;
        _ = ctx.block.gas_limit;
    }

    const end_time = std.time.nanoTimestamp();
    const duration = end_time - start_time;
    const ops_per_sec = (iterations * 1_000_000_000) / @as(u64, @intCast(duration));

    std.log.info("Context operations: {} ops/sec", .{ops_per_sec});
}
