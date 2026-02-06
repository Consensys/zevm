const std = @import("std");
const primitives = @import("primitives");
const interpreter = @import("interpreter");
const zbench = @import("zbench");

// ---------------------------------------------------------------------------
// File-scope globals for hooks (hooks are fn() void, no parameters)
// ---------------------------------------------------------------------------
var g_stack: interpreter.Stack = interpreter.Stack.new();
var g_gas: interpreter.Gas = interpreter.Gas.new(0);

const ADD_GAS_COST = 3;
const DIV_GAS_COST = 5;
const SDIV_GAS_COST = 5;
const MUL_GAS_COST = 5;
const MOD_GAS_COST = 5;
const SMOD_GAS_COST = 5;
const SIGNEXTEND_GAS_COST = 5;
const MID_GAS_COST = 8;
const EXP_GAS_1BYTE: u64 = 10 + 50; // 1-byte exponent
const EXP_GAS_32BYTE: u64 = 10 + 50 * 32; // 32-byte exponent
const PREFILL = 900;
const OPS_PER_BATCH = 400;
const NUM_VALUES = 1024;

// Simple PRNG (xorshift64) for reproducible random values
var prng_state: u64 = 42;

fn xorshift64() u64 {
    var x = prng_state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    prng_state = x;
    return x;
}

fn randomU256() primitives.U256 {
    const lo: u128 = @as(u128, xorshift64()) | (@as(u128, xorshift64()) << 64);
    const hi: u128 = @as(u128, xorshift64()) | (@as(u128, xorshift64()) << 64);
    return @as(primitives.U256, hi) << 128 | lo;
}

// Pre-generated random values
var g_values: [NUM_VALUES]primitives.U256 = undefined;
var g_divisor_128: primitives.U256 = undefined; // 128-bit divisor (multi-limb)
var g_divisor_64: primitives.U256 = undefined; // 64-bit divisor (single-limb)
var g_small_exp: [NUM_VALUES]primitives.U256 = undefined; // 1-byte exponents
var g_initialized = false;

fn initValues() void {
    prng_state = 42;
    for (&g_values) |*v| {
        v.* = randomU256();
    }
    // 128-bit divisor: 2 non-zero limbs (exercises multi-limb division)
    const lo: u128 = @as(u128, xorshift64() | 1) | (@as(u128, xorshift64()) << 64);
    g_divisor_128 = @as(primitives.U256, lo);
    // 64-bit divisor: single limb (fast path)
    g_divisor_64 = @as(primitives.U256, xorshift64() | 1);
    // Small exponents (1-byte, 1..255)
    for (&g_small_exp) |*v| {
        v.* = @as(primitives.U256, (xorshift64() & 0xFF) | 1);
    }
    g_initialized = true;
}

fn ensureInit() void {
    if (!g_initialized) initValues();
}

// --- ADD ---

fn resetAdd() void {
    ensureInit();
    g_stack.clear();
    for (0..PREFILL) |i| {
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]);
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * ADD_GAS_COST + 1000);
}

fn benchOpAdd(_: std.mem.Allocator) void {
    for (0..OPS_PER_BATCH) |_| {
        _ = interpreter.opcodes.opAdd(&g_stack, &g_gas);
    }
    std.mem.doNotOptimizeAway(&g_stack);
}

// --- SUB ---

fn resetSub() void {
    ensureInit();
    g_stack.clear();
    for (0..PREFILL) |i| {
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]);
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * ADD_GAS_COST + 1000);
}

fn resetSubBorrow() void {
    ensureInit();
    g_stack.clear();
    // Alternate 0 and 1 to force max borrow (0 - 1 = MAX)
    for (0..PREFILL / 2) |_| {
        g_stack.pushUnsafe(@as(primitives.U256, 1)); // b
        g_stack.pushUnsafe(@as(primitives.U256, 0)); // a
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * ADD_GAS_COST + 1000);
}

fn benchOpSub(_: std.mem.Allocator) void {
    for (0..OPS_PER_BATCH) |_| {
        _ = interpreter.opcodes.opSub(&g_stack, &g_gas);
    }
    std.mem.doNotOptimizeAway(&g_stack);
}

// --- MUL ---

fn resetMul() void {
    ensureInit();
    g_stack.clear();
    for (0..PREFILL) |i| {
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]);
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * MUL_GAS_COST + 1000);
}

fn resetMulSmall() void {
    ensureInit();
    g_stack.clear();
    // 256-bit * 64-bit (small multiplier)
    for (0..PREFILL / 2) |i| {
        g_stack.pushUnsafe(g_divisor_64); // b (small)
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]); // a (large)
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * MUL_GAS_COST + 1000);
}

fn benchOpMul(_: std.mem.Allocator) void {
    for (0..OPS_PER_BATCH) |_| {
        _ = interpreter.opcodes.opMul(&g_stack, &g_gas);
    }
    std.mem.doNotOptimizeAway(&g_stack);
}

// --- DIV ---

fn resetDiv() void {
    ensureInit();
    g_stack.clear();
    // Random 256-bit dividend / 128-bit divisor (multi-limb division)
    for (0..PREFILL / 2) |i| {
        g_stack.pushUnsafe(g_divisor_128); // b (divisor)
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]); // a (dividend)
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * DIV_GAS_COST + 1000);
}

fn resetDivSmall() void {
    ensureInit();
    g_stack.clear();
    // Random 256-bit dividend / 64-bit divisor (single-limb fast path)
    for (0..PREFILL / 2) |i| {
        g_stack.pushUnsafe(g_divisor_64); // b (divisor)
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]); // a (dividend)
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * DIV_GAS_COST + 1000);
}

fn resetDivFull() void {
    ensureInit();
    g_stack.clear();
    // Random 256-bit dividend / random 256-bit divisor (full-width division)
    for (0..PREFILL / 2) |i| {
        // Ensure non-zero divisor by OR'ing with 1
        g_stack.pushUnsafe(g_values[(i + 512) & (NUM_VALUES - 1)] | 1); // b (divisor)
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]); // a (dividend)
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * DIV_GAS_COST + 1000);
}

fn resetDivZero() void {
    ensureInit();
    g_stack.clear();
    // Division by zero — always hits the early-return branch
    for (0..PREFILL / 2) |i| {
        g_stack.pushUnsafe(@as(primitives.U256, 0)); // b (divisor = 0)
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]); // a (dividend)
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * DIV_GAS_COST + 1000);
}

fn benchOpDiv(_: std.mem.Allocator) void {
    for (0..OPS_PER_BATCH) |_| {
        _ = interpreter.opcodes.opDiv(&g_stack, &g_gas);
    }
    std.mem.doNotOptimizeAway(&g_stack);
}

// --- MOD ---

fn resetMod() void {
    ensureInit();
    g_stack.clear();
    for (0..PREFILL / 2) |i| {
        g_stack.pushUnsafe(g_divisor_128); // b (divisor)
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]); // a
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * MOD_GAS_COST + 1000);
}

fn resetModSmall() void {
    ensureInit();
    g_stack.clear();
    for (0..PREFILL / 2) |i| {
        g_stack.pushUnsafe(g_divisor_64); // b (small divisor)
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]); // a
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * MOD_GAS_COST + 1000);
}

fn resetModZero() void {
    ensureInit();
    g_stack.clear();
    for (0..PREFILL / 2) |i| {
        g_stack.pushUnsafe(@as(primitives.U256, 0)); // b = 0
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]); // a
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * MOD_GAS_COST + 1000);
}

fn benchOpMod(_: std.mem.Allocator) void {
    for (0..OPS_PER_BATCH) |_| {
        _ = interpreter.opcodes.opMod(&g_stack, &g_gas);
    }
    std.mem.doNotOptimizeAway(&g_stack);
}

// --- SDIV ---

fn resetSdiv() void {
    ensureInit();
    g_stack.clear();
    // Random 256-bit dividend / 128-bit divisor (signed)
    for (0..PREFILL / 2) |i| {
        g_stack.pushUnsafe(g_divisor_128); // b (divisor)
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]); // a (dividend)
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * SDIV_GAS_COST + 1000);
}

fn resetSdivNegative() void {
    ensureInit();
    g_stack.clear();
    const sign_bit: primitives.U256 = 1 << 255;
    // Negative dividend / positive divisor
    for (0..PREFILL / 2) |i| {
        g_stack.pushUnsafe(g_divisor_128); // b (positive divisor)
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)] | sign_bit); // a (negative)
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * SDIV_GAS_COST + 1000);
}

fn resetSdivBothNeg() void {
    ensureInit();
    g_stack.clear();
    const sign_bit: primitives.U256 = 1 << 255;
    // Negative dividend / negative divisor
    for (0..PREFILL / 2) |i| {
        g_stack.pushUnsafe(g_divisor_128 | sign_bit); // b (negative)
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)] | sign_bit); // a (negative)
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * SDIV_GAS_COST + 1000);
}

fn benchOpSdiv(_: std.mem.Allocator) void {
    for (0..OPS_PER_BATCH) |_| {
        _ = interpreter.opcodes.opSdiv(&g_stack, &g_gas);
    }
    std.mem.doNotOptimizeAway(&g_stack);
}

// --- SMOD ---

fn resetSmod() void {
    ensureInit();
    g_stack.clear();
    for (0..PREFILL / 2) |i| {
        g_stack.pushUnsafe(g_divisor_128); // b (divisor)
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]); // a
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * SMOD_GAS_COST + 1000);
}

fn resetSmodNegative() void {
    ensureInit();
    g_stack.clear();
    const sign_bit: primitives.U256 = 1 << 255;
    // Negative dividend (result takes sign of dividend)
    for (0..PREFILL / 2) |i| {
        g_stack.pushUnsafe(g_divisor_128); // b (positive divisor)
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)] | sign_bit); // a (negative)
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * SMOD_GAS_COST + 1000);
}

fn benchOpSmod(_: std.mem.Allocator) void {
    for (0..OPS_PER_BATCH) |_| {
        _ = interpreter.opcodes.opSmod(&g_stack, &g_gas);
    }
    std.mem.doNotOptimizeAway(&g_stack);
}

// --- SIGNEXTEND ---

fn resetSignextend() void {
    ensureInit();
    g_stack.clear();
    // Test various byte positions (0-15) with random values
    for (0..PREFILL / 2) |i| {
        const byte_pos = i & 15; // 0-15
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]); // value
        g_stack.pushUnsafe(@as(primitives.U256, byte_pos)); // byte_pos
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * SIGNEXTEND_GAS_COST + 1000);
}

fn resetSignextendLow() void {
    ensureInit();
    g_stack.clear();
    // Low byte positions (0-3) — more work
    for (0..PREFILL / 2) |i| {
        const byte_pos = i & 3; // 0-3
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]); // value
        g_stack.pushUnsafe(@as(primitives.U256, byte_pos)); // byte_pos
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * SIGNEXTEND_GAS_COST + 1000);
}

fn resetSignextendHigh() void {
    ensureInit();
    g_stack.clear();
    // High byte positions (28-31) — less work (no extension)
    for (0..PREFILL / 2) |i| {
        const byte_pos = 28 + (i & 3); // 28-31
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]); // value
        g_stack.pushUnsafe(@as(primitives.U256, byte_pos)); // byte_pos
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * SIGNEXTEND_GAS_COST + 1000);
}

fn benchOpSignextend(_: std.mem.Allocator) void {
    for (0..OPS_PER_BATCH) |_| {
        _ = interpreter.opcodes.opSignextend(&g_stack, &g_gas);
    }
    std.mem.doNotOptimizeAway(&g_stack);
}

// --- ADDMOD ---

const TERNARY_PREFILL = 900; // must be divisible by 3

fn resetAddmod() void {
    ensureInit();
    g_stack.clear();
    var i: usize = 0;
    while (i + 2 < TERNARY_PREFILL) : (i += 3) {
        g_stack.pushUnsafe(g_values[(i + 2) & (NUM_VALUES - 1)] | 1); // N (non-zero)
        g_stack.pushUnsafe(g_values[(i + 1) & (NUM_VALUES - 1)]); // b
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]); // a
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * MID_GAS_COST + 1000);
}

fn resetAddmodOverflow() void {
    ensureInit();
    g_stack.clear();
    const MAX = std.math.maxInt(primitives.U256);
    var i: usize = 0;
    while (i + 2 < TERNARY_PREFILL) : (i += 3) {
        g_stack.pushUnsafe(g_values[(i + 2) & (NUM_VALUES - 1)] | 1); // N
        g_stack.pushUnsafe(MAX); // b = MAX
        g_stack.pushUnsafe(MAX); // a = MAX
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * MID_GAS_COST + 1000);
}

fn benchOpAddmod(_: std.mem.Allocator) void {
    for (0..OPS_PER_BATCH) |_| {
        _ = interpreter.opcodes.opAddmod(&g_stack, &g_gas);
    }
    std.mem.doNotOptimizeAway(&g_stack);
}

// --- MULMOD ---

fn resetMulmod() void {
    ensureInit();
    g_stack.clear();
    var i: usize = 0;
    while (i + 2 < TERNARY_PREFILL) : (i += 3) {
        g_stack.pushUnsafe(g_values[(i + 2) & (NUM_VALUES - 1)] | 1); // N (non-zero)
        g_stack.pushUnsafe(g_values[(i + 1) & (NUM_VALUES - 1)]); // b
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]); // a
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * MID_GAS_COST + 1000);
}

fn resetMulmodMax() void {
    ensureInit();
    g_stack.clear();
    const MAX = std.math.maxInt(primitives.U256);
    var i: usize = 0;
    while (i + 2 < TERNARY_PREFILL) : (i += 3) {
        g_stack.pushUnsafe(g_values[(i + 2) & (NUM_VALUES - 1)] | 1); // N
        g_stack.pushUnsafe(MAX); // b = MAX
        g_stack.pushUnsafe(MAX); // a = MAX
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * MID_GAS_COST + 1000);
}

fn benchOpMulmod(_: std.mem.Allocator) void {
    for (0..OPS_PER_BATCH) |_| {
        _ = interpreter.opcodes.opMulmod(&g_stack, &g_gas);
    }
    std.mem.doNotOptimizeAway(&g_stack);
}

// --- EXP ---

fn resetExpSmall() void {
    ensureInit();
    g_stack.clear();
    // Small exponents (1 byte) — fast path
    for (0..PREFILL / 2) |i| {
        g_stack.pushUnsafe(g_small_exp[i & (NUM_VALUES - 1)]); // exponent (1 byte)
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]); // base
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * EXP_GAS_1BYTE + 1000);
}

fn resetExpLarge() void {
    ensureInit();
    g_stack.clear();
    // Large exponents (32 bytes) — worst case
    for (0..PREFILL / 2) |i| {
        g_stack.pushUnsafe(g_values[(i + 512) & (NUM_VALUES - 1)]); // exponent (32 bytes)
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]); // base
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * EXP_GAS_32BYTE + 1000);
}

fn benchOpExp(_: std.mem.Allocator) void {
    for (0..OPS_PER_BATCH) |_| {
        _ = interpreter.opcodes.opExp(&g_stack, &g_gas);
    }
    std.mem.doNotOptimizeAway(&g_stack);
}

// ---------------------------------------------------------------------------
// Gas cost lookup for the results table
// ---------------------------------------------------------------------------
fn gasCostForName(name: []const u8) f64 {
    if (std.mem.startsWith(u8, name, "OP_EXP")) {
        if (std.mem.indexOf(u8, name, "32B")) |_| return @floatFromInt(EXP_GAS_32BYTE);
        return @floatFromInt(EXP_GAS_1BYTE);
    }
    if (std.mem.startsWith(u8, name, "OP_ADDMOD") or std.mem.startsWith(u8, name, "OP_MULMOD"))
        return @floatFromInt(MID_GAS_COST);
    if (std.mem.startsWith(u8, name, "OP_DIV") or
        std.mem.startsWith(u8, name, "OP_SDIV") or
        std.mem.startsWith(u8, name, "OP_MUL") or
        std.mem.startsWith(u8, name, "OP_MOD") or
        std.mem.startsWith(u8, name, "OP_SMOD") or
        std.mem.startsWith(u8, name, "OP_SIGNEXTEND"))
        return @floatFromInt(DIV_GAS_COST);
    return @floatFromInt(ADD_GAS_COST); // ADD, SUB
}

pub fn main() !void {
    var stdout = std.fs.File.stdout().writerStreaming(&.{});
    const writer = &stdout.interface;
    const allocator = std.heap.page_allocator;

    try writer.writeAll("\n=== ZEVM Opcode Benchmark (zBench) ===\n\n");

    var bench = zbench.Benchmark.init(allocator, .{});
    defer bench.deinit();

    try bench.add("OP_ADD", benchOpAdd, .{
        .hooks = .{ .before_each = resetAdd },
    });
    try bench.add("OP_SUB", benchOpSub, .{
        .hooks = .{ .before_each = resetSub },
    });
    try bench.add("OP_SUB (borrow)", benchOpSub, .{
        .hooks = .{ .before_each = resetSubBorrow },
    });
    try bench.add("OP_MUL", benchOpMul, .{
        .hooks = .{ .before_each = resetMul },
    });
    try bench.add("OP_MUL (256x64)", benchOpMul, .{
        .hooks = .{ .before_each = resetMulSmall },
    });
    try bench.add("OP_DIV", benchOpDiv, .{
        .hooks = .{ .before_each = resetDiv },
    });
    try bench.add("OP_DIV (256/256)", benchOpDiv, .{
        .hooks = .{ .before_each = resetDivFull },
    });
    try bench.add("OP_DIV (256/64)", benchOpDiv, .{
        .hooks = .{ .before_each = resetDivSmall },
    });
    try bench.add("OP_DIV (zero)", benchOpDiv, .{
        .hooks = .{ .before_each = resetDivZero },
    });
    try bench.add("OP_MOD", benchOpMod, .{
        .hooks = .{ .before_each = resetMod },
    });
    try bench.add("OP_MOD (256/64)", benchOpMod, .{
        .hooks = .{ .before_each = resetModSmall },
    });
    try bench.add("OP_MOD (zero)", benchOpMod, .{
        .hooks = .{ .before_each = resetModZero },
    });
    try bench.add("OP_SDIV", benchOpSdiv, .{
        .hooks = .{ .before_each = resetSdiv },
    });
    try bench.add("OP_SDIV (neg/pos)", benchOpSdiv, .{
        .hooks = .{ .before_each = resetSdivNegative },
    });
    try bench.add("OP_SDIV (neg/neg)", benchOpSdiv, .{
        .hooks = .{ .before_each = resetSdivBothNeg },
    });
    try bench.add("OP_SMOD", benchOpSmod, .{
        .hooks = .{ .before_each = resetSmod },
    });
    try bench.add("OP_SMOD (neg div)", benchOpSmod, .{
        .hooks = .{ .before_each = resetSmodNegative },
    });
    try bench.add("OP_SIGNEXTEND", benchOpSignextend, .{
        .hooks = .{ .before_each = resetSignextend },
    });
    try bench.add("OP_SIGNEXTEND (0-3)", benchOpSignextend, .{
        .hooks = .{ .before_each = resetSignextendLow },
    });
    try bench.add("OP_SIGNEXTEND (28-31)", benchOpSignextend, .{
        .hooks = .{ .before_each = resetSignextendHigh },
    });
    try bench.add("OP_ADDMOD", benchOpAddmod, .{
        .hooks = .{ .before_each = resetAddmod },
    });
    try bench.add("OP_ADDMOD (MAX)", benchOpAddmod, .{
        .hooks = .{ .before_each = resetAddmodOverflow },
    });
    try bench.add("OP_MULMOD", benchOpMulmod, .{
        .hooks = .{ .before_each = resetMulmod },
    });
    try bench.add("OP_MULMOD (MAX)", benchOpMulmod, .{
        .hooks = .{ .before_each = resetMulmodMax },
    });
    try bench.add("OP_EXP (1B)", benchOpExp, .{
        .hooks = .{ .before_each = resetExpSmall },
    });
    try bench.add("OP_EXP (32B)", benchOpExp, .{
        .hooks = .{ .before_each = resetExpLarge },
    });

    try writer.print("{s:<20}{s:<10}{s:<15}{s:<24}{s:<30}{s:<12}{s:<12}{s}\n", .{
        "benchmark", "runs", "total time", "time/op (avg ± σ)", "(min ... max)", "p75", "p99", "MGas/sec",
    });
    try writer.writeAll("-" ** 135 ++ "\n");

    var it = try bench.iterator();
    while (try it.next()) |step| {
        switch (step) {
            .progress => {},
            .result => |result| {
                defer result.deinit();
                const timings = result.readings.timings_ns;
                if (timings.len == 0) continue;
                const n: f64 = @floatFromInt(timings.len);
                const ops: f64 = @floatFromInt(OPS_PER_BATCH);

                var sum_f: f64 = 0;
                var min_f: f64 = std.math.floatMax(f64);
                var max_f: f64 = 0;
                for (timings) |t| {
                    const per_op: f64 = @as(f64, @floatFromInt(t)) / ops;
                    sum_f += per_op;
                    min_f = @min(min_f, per_op);
                    max_f = @max(max_f, per_op);
                }
                const mean_f = sum_f / n;

                var var_sum_f: f64 = 0;
                for (timings) |t| {
                    const per_op: f64 = @as(f64, @floatFromInt(t)) / ops;
                    const diff = per_op - mean_f;
                    var_sum_f += diff * diff;
                }
                const stddev_f = if (timings.len > 1) @sqrt(var_sum_f / (n - 1)) else 0;

                const per_op_buf = allocator.alloc(f64, timings.len) catch continue;
                defer allocator.free(per_op_buf);
                for (per_op_buf, timings) |*dst, t| dst.* = @as(f64, @floatFromInt(t)) / ops;
                std.mem.sort(f64, per_op_buf, {}, std.sort.asc(f64));
                const p75 = per_op_buf[timings.len * 75 / 100];
                const p99 = per_op_buf[timings.len * 99 / 100];

                const gas_per_op = gasCostForName(result.name);
                const mgas_per_sec = if (mean_f > 0) (gas_per_op * 1_000.0) / mean_f else 0;

                var total_ns: u64 = 0;
                for (timings) |t| total_ns += t;

                // Format each cell into a buffer, then print with fixed column widths
                var buf_runs: [32]u8 = undefined;
                var buf_total: [32]u8 = undefined;
                var buf_avg: [64]u8 = undefined;
                var buf_range: [64]u8 = undefined;
                var buf_p75: [32]u8 = undefined;
                var buf_p99: [32]u8 = undefined;
                var buf_mgas: [32]u8 = undefined;

                const s_runs = std.fmt.bufPrint(&buf_runs, "{d}", .{timings.len}) catch continue;
                const s_total = std.fmt.bufPrint(&buf_total, "{d}ms", .{total_ns / 1_000_000}) catch continue;
                const s_avg = std.fmt.bufPrint(&buf_avg, "{d:.2}ns ± {d:.2}ns", .{ mean_f, stddev_f }) catch continue;
                const s_range = std.fmt.bufPrint(&buf_range, "({d:.2}ns ... {d:.2}ns)", .{ min_f, max_f }) catch continue;
                const s_p75 = std.fmt.bufPrint(&buf_p75, "{d:.2}ns", .{p75}) catch continue;
                const s_p99 = std.fmt.bufPrint(&buf_p99, "{d:.2}ns", .{p99}) catch continue;
                const s_mgas = std.fmt.bufPrint(&buf_mgas, "{d:.0}", .{mgas_per_sec}) catch continue;

                try writer.print("{s:<20}{s:<10}{s:<15}{s:<24}{s:<30}{s:<12}{s:<12}{s}\n", .{
                    result.name, s_runs, s_total, s_avg, s_range, s_p75, s_p99, s_mgas,
                });
            },
        }
    }

    try writer.writeAll("\n");
}
