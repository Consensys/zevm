const std = @import("std");
const primitives = @import("primitives");
const interpreter = @import("interpreter");
const bytecode = @import("bytecode");
const zbench = @import("zbench");

const InstructionTable = interpreter.instruction_table.InstructionTable;
const gas_costs = interpreter.gas_costs;

const U256 = primitives.U256;
const MAX = std.math.maxInt(U256);

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const OPS_PER_BATCH = 400;
const PREFILL = 900; // must be divisible by 2 and 3
const NUM_VALUES = 1024;

// ---------------------------------------------------------------------------
// Global state (zbench hooks require fn() void, so globals are necessary)
// ---------------------------------------------------------------------------

var g_stack: interpreter.Stack = interpreter.Stack.new();
var g_gas: interpreter.Gas = interpreter.Gas.new(0);
var g_spec: primitives.SpecId = .osaka; // Default to latest fork
var g_instruction_table: InstructionTable = undefined;

// ---------------------------------------------------------------------------
// Reproducible test data
// ---------------------------------------------------------------------------

var prng_state: u64 = 42;

fn xorshift64() u64 {
    var x = prng_state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    prng_state = x;
    return x;
}

fn randomU256() U256 {
    const lo: u128 = @as(u128, xorshift64()) | (@as(u128, xorshift64()) << 64);
    const hi: u128 = @as(u128, xorshift64()) | (@as(u128, xorshift64()) << 64);
    return @as(U256, hi) << 128 | lo;
}

var g_values: [NUM_VALUES]U256 = undefined; // random 256-bit values
var g_divisor_128: U256 = undefined; // 128-bit divisor (2 non-zero limbs)
var g_divisor_64: U256 = undefined; // 64-bit divisor (single limb)
var g_small_exp: [NUM_VALUES]U256 = undefined; // 1-byte exponents (1..255)
var g_initialized = false;

fn initValues() void {
    prng_state = 42;
    for (&g_values) |*v| v.* = randomU256();
    const lo: u128 = @as(u128, xorshift64() | 1) | (@as(u128, xorshift64()) << 64);
    g_divisor_128 = @as(U256, lo);
    g_divisor_64 = @as(U256, xorshift64() | 1);
    for (&g_small_exp) |*v| v.* = @as(U256, (xorshift64() & 0xFF) | 1);
    g_initialized = true;
}

fn ensureInit() void {
    if (!g_initialized) initValues();
}

// ---------------------------------------------------------------------------
// Stack fill helpers
//
// Stack layout reminder: opcodes pop TOS first (a), then second (b), then
// third (N). So we push in reverse order: deepest operand first.
// ---------------------------------------------------------------------------

/// Common pre-benchmark setup: init test data, clear stack, set gas budget.
fn setup(gas_cost: u64) void {
    ensureInit();
    g_stack.clear();
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * gas_cost + 1000);
}

/// Push `count` random 256-bit values from the pool.
/// For unary-consuming ops (ADD, SUB, MUL) that pop 2 and push 1.
fn fillRandom(count: usize) void {
    for (0..count) |i| {
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]);
    }
}

/// Push `count` [a, b] pairs: a = random from pool, b = fixed value.
/// Stack per pair: b (deeper), a (top).
fn fillPairs(count: usize, b: U256) void {
    for (0..count) |i| {
        g_stack.pushUnsafe(b);
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]);
    }
}

/// Push `count` [a, b] pairs: both random from pool, b guaranteed non-zero.
/// Stack per pair: b|1 (deeper), a (top).
fn fillRandomPairs(count: usize) void {
    for (0..count) |i| {
        g_stack.pushUnsafe(g_values[(i + 512) & (NUM_VALUES - 1)] | 1);
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]);
    }
}

/// Push `count` [a, b] pairs with both values constant.
/// Stack per pair: b (deeper), a (top).
fn fillConstantPairs(count: usize, a: U256, b: U256) void {
    for (0..count) |_| {
        g_stack.pushUnsafe(b);
        g_stack.pushUnsafe(a);
    }
}

/// Push [a, b, N] triples: all random from pool, N guaranteed non-zero.
/// Stack per triple: N|1 (deepest), b (middle), a (top).
fn fillRandomTriples(count: usize) void {
    var i: usize = 0;
    while (i + 2 < count) : (i += 3) {
        g_stack.pushUnsafe(g_values[(i + 2) & (NUM_VALUES - 1)] | 1);
        g_stack.pushUnsafe(g_values[(i + 1) & (NUM_VALUES - 1)]);
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]);
    }
}

/// Push [a, b, N] triples: a and b fixed, N random non-zero.
/// Stack per triple: N|1 (deepest), b (middle), a (top).
fn fillFixedTriples(count: usize, a: U256, b: U256) void {
    var i: usize = 0;
    while (i + 2 < count) : (i += 3) {
        g_stack.pushUnsafe(g_values[(i + 2) & (NUM_VALUES - 1)] | 1);
        g_stack.pushUnsafe(b);
        g_stack.pushUnsafe(a);
    }
}

/// Push [base, exponent] pairs: base = random, exponent = 1-byte (1..255).
/// Stack per pair: exponent (deeper), base (top).
fn fillExpSmall(count: usize) void {
    for (0..count) |i| {
        g_stack.pushUnsafe(g_small_exp[i & (NUM_VALUES - 1)]);
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]);
    }
}

/// Push [base, exponent] pairs: base = random, exponent = random 32-byte.
/// Stack per pair: exponent (deeper), base (top).
fn fillExpLarge(count: usize) void {
    for (0..count) |i| {
        g_stack.pushUnsafe(g_values[(i + 512) & (NUM_VALUES - 1)]);
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]);
    }
}

/// Push [a, b] pairs where a has sign bit set (negative in two's complement).
fn fillNegativePairs(count: usize, b: U256) void {
    const sign_bit: U256 = 1 << 255;
    for (0..count) |i| {
        g_stack.pushUnsafe(b);
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)] | sign_bit);
    }
}

/// Push [a, b] pairs where both have sign bit set.
fn fillBothNegPairs(count: usize, b: U256) void {
    const sign_bit: U256 = 1 << 255;
    for (0..count) |i| {
        g_stack.pushUnsafe(b | sign_bit);
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)] | sign_bit);
    }
}

/// Push [byte_pos, value] pairs for SIGNEXTEND.
/// Stack per pair: value (deeper), byte_pos (top).
fn fillSignextendPairs(count: usize, mask: usize) void {
    for (0..count) |i| {
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]);
        g_stack.pushUnsafe(@as(U256, i & mask));
    }
}

/// Push [shift, value] pairs for SHL/SHR/SAR.
/// Stack per pair: value (deeper), shift (top).
fn fillShiftPairs(count: usize, mask: usize) void {
    for (0..count) |i| {
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]);
        g_stack.pushUnsafe(@as(U256, (i * 7) & mask));
    }
}

/// Push [shift, value] pairs where value has sign bit set (for SAR negative).
fn fillShiftNegPairs(count: usize, mask: usize) void {
    const sign_bit: U256 = 1 << 255;
    for (0..count) |i| {
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)] | sign_bit);
        g_stack.pushUnsafe(@as(U256, (i * 7) & mask));
    }
}

/// Push [shift, value] pairs alternating pos/neg for SAR.
fn fillShiftMixedPairs(count: usize, mask: usize) void {
    const sign_bit: U256 = 1 << 255;
    for (0..count) |i| {
        const val = g_values[i & (NUM_VALUES - 1)];
        g_stack.pushUnsafe(if (i & 1 == 0) val else val | sign_bit);
        g_stack.pushUnsafe(@as(U256, (i * 7) & mask));
    }
}

/// Push [position, value] pairs for BYTE extraction.
fn fillBytePairs(count: usize) void {
    for (0..count) |i| {
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]);
        g_stack.pushUnsafe(@as(U256, i & 31));
    }
}

// ---------------------------------------------------------------------------
// Benchmark runner (generates the inner loop for any opcode via comptime)
// ---------------------------------------------------------------------------

fn OpRunner(comptime opFn: anytype) type {
    return struct {
        pub fn run(_: std.mem.Allocator) void {
            for (0..OPS_PER_BATCH) |_| {
                _ = opFn(&g_stack, &g_gas);
            }
            std.mem.doNotOptimizeAway(&g_stack);
        }
    };
}

// ---------------------------------------------------------------------------
// Helper: get gas cost from instruction table
// ---------------------------------------------------------------------------

fn gasFor(comptime opcode: u8) u64 {
    return g_instruction_table[opcode].base_gas;
}

// ---------------------------------------------------------------------------
// Reset functions (one per benchmark variant)
// Each calls setup(gas_cost) then a fill helper describing the input pattern.
// ---------------------------------------------------------------------------

// --- Arithmetic ---

// ADD: random 256-bit operands
fn resetAdd() void {
    setup(gasFor(bytecode.ADD));
    fillRandom(PREFILL);
}

// SUB: random operands / forced borrow (0 - 1 = MAX)
fn resetSub() void {
    setup(gasFor(bytecode.SUB));
    fillRandom(PREFILL);
}
fn resetSubBorrow() void {
    setup(gasFor(bytecode.SUB));
    fillConstantPairs(PREFILL / 2, 0, 1);
}

// MUL: random 256x256 / asymmetric 256x64
fn resetMul() void {
    setup(gasFor(bytecode.MUL));
    fillRandom(PREFILL);
}
fn resetMulSmall() void {
    setup(gasFor(bytecode.MUL));
    fillPairs(PREFILL / 2, g_divisor_64);
}

// DIV: 256/128-bit, 256/256-bit, 256/64-bit, divide-by-zero
fn resetDiv() void {
    setup(gasFor(bytecode.DIV));
    fillPairs(PREFILL / 2, g_divisor_128);
}
fn resetDivFull() void {
    setup(gasFor(bytecode.DIV));
    fillRandomPairs(PREFILL / 2);
}
fn resetDivSmall() void {
    setup(gasFor(bytecode.DIV));
    fillPairs(PREFILL / 2, g_divisor_64);
}
fn resetDivZero() void {
    setup(gasFor(bytecode.DIV));
    fillPairs(PREFILL / 2, 0);
}

// SDIV: signed division variants
fn resetSdiv() void {
    setup(gasFor(bytecode.SDIV));
    fillPairs(PREFILL / 2, g_divisor_128);
}
fn resetSdivNegative() void {
    setup(gasFor(bytecode.SDIV));
    fillNegativePairs(PREFILL / 2, g_divisor_128);
}
fn resetSdivBothNeg() void {
    setup(gasFor(bytecode.SDIV));
    fillBothNegPairs(PREFILL / 2, g_divisor_128);
}

// MOD: 256%128-bit, 256%64-bit, mod-by-zero
fn resetMod() void {
    setup(gasFor(bytecode.MOD));
    fillPairs(PREFILL / 2, g_divisor_128);
}
fn resetModSmall() void {
    setup(gasFor(bytecode.MOD));
    fillPairs(PREFILL / 2, g_divisor_64);
}
fn resetModZero() void {
    setup(gasFor(bytecode.MOD));
    fillPairs(PREFILL / 2, 0);
}

// SMOD: signed modulo variants
fn resetSmod() void {
    setup(gasFor(bytecode.SMOD));
    fillPairs(PREFILL / 2, g_divisor_128);
}
fn resetSmodNegative() void {
    setup(gasFor(bytecode.SMOD));
    fillNegativePairs(PREFILL / 2, g_divisor_128);
}

// SIGNEXTEND: various byte positions
fn resetSignextend() void {
    setup(gasFor(bytecode.SIGNEXTEND));
    fillSignextendPairs(PREFILL / 2, 15);
}
fn resetSignextendLow() void {
    setup(gasFor(bytecode.SIGNEXTEND));
    fillSignextendPairs(PREFILL / 2, 3);
}
fn resetSignextendHigh() void {
    ensureInit();
    g_stack.clear();
    const gas_cost = gasFor(bytecode.SIGNEXTEND);
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * gas_cost + 1000);
    for (0..PREFILL / 2) |i| {
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]);
        g_stack.pushUnsafe(@as(U256, 28 + (i & 3)));
    }
}

// ADDMOD: random triples / overflow (MAX + MAX)
fn resetAddmod() void {
    setup(gasFor(bytecode.ADDMOD));
    fillRandomTriples(PREFILL);
}
fn resetAddmodOverflow() void {
    setup(gasFor(bytecode.ADDMOD));
    fillFixedTriples(PREFILL, MAX, MAX);
}

// MULMOD: random triples / worst-case (MAX * MAX)
fn resetMulmod() void {
    setup(gasFor(bytecode.MULMOD));
    fillRandomTriples(PREFILL);
}
fn resetMulmodMax() void {
    setup(gasFor(bytecode.MULMOD));
    fillFixedTriples(PREFILL, MAX, MAX);
}

// EXP: 1-byte exponent (fast) / 32-byte exponent (worst case)
fn resetExpSmall() void {
    const gas_cost = gasFor(bytecode.EXP) + gas_costs.G_EXPBYTE;
    setup(gas_cost);
    fillExpSmall(PREFILL / 2);
}
fn resetExpLarge() void {
    const gas_cost = gasFor(bytecode.EXP) + gas_costs.G_EXPBYTE * 32;
    setup(gas_cost);
    fillExpLarge(PREFILL / 2);
}

// --- Bitwise ---

fn resetAnd() void {
    setup(gasFor(bytecode.AND));
    fillRandom(PREFILL);
}
fn resetOr() void {
    setup(gasFor(bytecode.OR));
    fillRandom(PREFILL);
}
fn resetXor() void {
    setup(gasFor(bytecode.XOR));
    fillRandom(PREFILL);
}
fn resetNot() void {
    setup(gasFor(bytecode.NOT));
    fillRandom(PREFILL);
}
fn resetByte() void {
    setup(gasFor(bytecode.BYTE));
    fillBytePairs(PREFILL / 2);
}

// Shifts: full range (0-255) and small (0-63)
fn resetShl() void {
    setup(gasFor(bytecode.SHL));
    fillShiftPairs(PREFILL / 2, 255);
}
fn resetShlSmall() void {
    setup(gasFor(bytecode.SHL));
    fillShiftPairs(PREFILL / 2, 63);
}
fn resetShr() void {
    setup(gasFor(bytecode.SHR));
    fillShiftPairs(PREFILL / 2, 255);
}
fn resetShrSmall() void {
    setup(gasFor(bytecode.SHR));
    fillShiftPairs(PREFILL / 2, 63);
}
fn resetSar() void {
    setup(gasFor(bytecode.SAR));
    fillShiftMixedPairs(PREFILL / 2, 255);
}
fn resetSarNegative() void {
    setup(gasFor(bytecode.SAR));
    fillShiftNegPairs(PREFILL / 2, 255);
}

// ---------------------------------------------------------------------------
// Gas cost lookup (for MGas/sec column) — uses instruction table
// ---------------------------------------------------------------------------

fn gasCostForName(name: []const u8) f64 {
    if (std.mem.startsWith(u8, name, "OP_ADDMOD")) return @floatFromInt(g_instruction_table[bytecode.ADDMOD].base_gas);
    if (std.mem.startsWith(u8, name, "OP_ADD")) return @floatFromInt(g_instruction_table[bytecode.ADD].base_gas);
    if (std.mem.startsWith(u8, name, "OP_SUB")) return @floatFromInt(g_instruction_table[bytecode.SUB].base_gas);
    if (std.mem.startsWith(u8, name, "OP_MULMOD")) return @floatFromInt(g_instruction_table[bytecode.MULMOD].base_gas);
    if (std.mem.startsWith(u8, name, "OP_MUL")) return @floatFromInt(g_instruction_table[bytecode.MUL].base_gas);
    if (std.mem.startsWith(u8, name, "OP_SDIV")) return @floatFromInt(g_instruction_table[bytecode.SDIV].base_gas);
    if (std.mem.startsWith(u8, name, "OP_DIV")) return @floatFromInt(g_instruction_table[bytecode.DIV].base_gas);
    if (std.mem.startsWith(u8, name, "OP_SMOD")) return @floatFromInt(g_instruction_table[bytecode.SMOD].base_gas);
    if (std.mem.startsWith(u8, name, "OP_MOD")) return @floatFromInt(g_instruction_table[bytecode.MOD].base_gas);
    if (std.mem.startsWith(u8, name, "OP_SIGNEXTEND")) return @floatFromInt(g_instruction_table[bytecode.SIGNEXTEND].base_gas);
    if (std.mem.startsWith(u8, name, "OP_EXP")) {
        const base_gas: f64 = @floatFromInt(g_instruction_table[bytecode.EXP].base_gas);
        const exp_byte_gas: f64 = @floatFromInt(gas_costs.G_EXPBYTE);
        if (std.mem.indexOf(u8, name, "32B")) |_| return base_gas + exp_byte_gas * 32.0;
        return base_gas + exp_byte_gas; // 1-byte exponent
    }
    if (std.mem.startsWith(u8, name, "OP_AND")) return @floatFromInt(g_instruction_table[bytecode.AND].base_gas);
    if (std.mem.startsWith(u8, name, "OP_OR")) return @floatFromInt(g_instruction_table[bytecode.OR].base_gas);
    if (std.mem.startsWith(u8, name, "OP_XOR")) return @floatFromInt(g_instruction_table[bytecode.XOR].base_gas);
    if (std.mem.startsWith(u8, name, "OP_NOT")) return @floatFromInt(g_instruction_table[bytecode.NOT].base_gas);
    if (std.mem.startsWith(u8, name, "OP_BYTE")) return @floatFromInt(g_instruction_table[bytecode.BYTE].base_gas);
    if (std.mem.startsWith(u8, name, "OP_SHL")) return @floatFromInt(g_instruction_table[bytecode.SHL].base_gas);
    if (std.mem.startsWith(u8, name, "OP_SHR")) return @floatFromInt(g_instruction_table[bytecode.SHR].base_gas);
    if (std.mem.startsWith(u8, name, "OP_SAR")) return @floatFromInt(g_instruction_table[bytecode.SAR].base_gas);
    return 3.0; // Default fallback
}

// ---------------------------------------------------------------------------
// Category detection for section separators
// ---------------------------------------------------------------------------

fn getOpcodeCategory(name: []const u8) []const u8 {
    if (std.mem.startsWith(u8, name, "OP_ADD") or
        std.mem.startsWith(u8, name, "OP_SUB") or
        std.mem.startsWith(u8, name, "OP_MUL") or
        std.mem.startsWith(u8, name, "OP_DIV") or
        std.mem.startsWith(u8, name, "OP_SDIV") or
        std.mem.startsWith(u8, name, "OP_MOD") or
        std.mem.startsWith(u8, name, "OP_SMOD") or
        std.mem.startsWith(u8, name, "OP_SIGNEXTEND") or
        std.mem.startsWith(u8, name, "OP_EXP"))
        return "ARITHMETIC";
    if (std.mem.startsWith(u8, name, "OP_AND") or
        std.mem.startsWith(u8, name, "OP_OR") or
        std.mem.startsWith(u8, name, "OP_XOR") or
        std.mem.startsWith(u8, name, "OP_NOT") or
        std.mem.startsWith(u8, name, "OP_BYTE") or
        std.mem.startsWith(u8, name, "OP_SHL") or
        std.mem.startsWith(u8, name, "OP_SHR") or
        std.mem.startsWith(u8, name, "OP_SAR"))
        return "BITWISE";
    return "OTHER";
}

// ---------------------------------------------------------------------------
// Filter and fork parsing
// ---------------------------------------------------------------------------

fn parseSpecId(name: []const u8) ?primitives.SpecId {
    if (std.mem.eql(u8, name, "frontier")) return .frontier;
    if (std.mem.eql(u8, name, "frontier_thawing")) return .frontier_thawing;
    if (std.mem.eql(u8, name, "homestead")) return .homestead;
    if (std.mem.eql(u8, name, "dao_fork")) return .dao_fork;
    if (std.mem.eql(u8, name, "tangerine")) return .tangerine;
    if (std.mem.eql(u8, name, "spurious") or std.mem.eql(u8, name, "spurious_dragon")) return .spurious_dragon;
    if (std.mem.eql(u8, name, "byzantium")) return .byzantium;
    if (std.mem.eql(u8, name, "constantinople")) return .constantinople;
    if (std.mem.eql(u8, name, "petersburg")) return .petersburg;
    if (std.mem.eql(u8, name, "istanbul")) return .istanbul;
    if (std.mem.eql(u8, name, "muir_glacier")) return .muir_glacier;
    if (std.mem.eql(u8, name, "berlin")) return .berlin;
    if (std.mem.eql(u8, name, "london")) return .london;
    if (std.mem.eql(u8, name, "arrow_glacier")) return .arrow_glacier;
    if (std.mem.eql(u8, name, "gray_glacier")) return .gray_glacier;
    if (std.mem.eql(u8, name, "merge")) return .merge;
    if (std.mem.eql(u8, name, "shanghai")) return .shanghai;
    if (std.mem.eql(u8, name, "cancun")) return .cancun;
    if (std.mem.eql(u8, name, "prague")) return .prague;
    if (std.mem.eql(u8, name, "osaka")) return .osaka;
    if (std.mem.eql(u8, name, "amsterdam")) return .amsterdam;
    return null;
}

fn matchesFilter(name: []const u8, filter: []const u8) bool {
    if (filter.len == 0) return true;

    var name_lower_buf: [256]u8 = undefined;
    var filter_lower_buf: [256]u8 = undefined;
    if (name.len > name_lower_buf.len or filter.len > filter_lower_buf.len) return false;

    for (name, 0..) |c, i| name_lower_buf[i] = std.ascii.toLower(c);
    for (filter, 0..) |c, i| filter_lower_buf[i] = std.ascii.toLower(c);

    return std.mem.indexOf(u8, name_lower_buf[0..name.len], filter_lower_buf[0..filter.len]) != null;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

pub fn main() !void {
    var stdout = std.fs.File.stdout().writerStreaming(&.{});
    const writer = &stdout.interface;
    const allocator = std.heap.page_allocator;

    // Parse command-line arguments for fork selection and filter
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip(); // Skip program name

    var filter: []const u8 = "";

    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--fork=")) {
            const fork_name = arg[7..];
            if (parseSpecId(fork_name)) |spec| {
                g_spec = spec;
            } else {
                try writer.print("Error: Unknown fork '{s}'\n", .{fork_name});
                try writer.writeAll("Available forks: frontier, homestead, tangerine, spurious_dragon, byzantium, ");
                try writer.writeAll("constantinople, petersburg, istanbul, berlin, london, shanghai, cancun, prague, osaka, amsterdam\n");
                return error.InvalidFork;
            }
        } else if (std.mem.startsWith(u8, arg, "--filter=")) {
            filter = arg[9..];
        }
    }

    // Initialize instruction table for the selected fork
    g_instruction_table = interpreter.instruction_table.makeInstructionTable(g_spec);

    try writer.print("\n=== ZEVM Opcode Benchmark (zBench) ===\n", .{});
    try writer.print("Fork: {s}\n", .{@tagName(g_spec)});
    if (filter.len > 0) {
        try writer.print("Filter: {s}\n", .{filter});
    }
    try writer.writeAll("\n");

    var bench = zbench.Benchmark.init(allocator, .{});
    defer bench.deinit();

    const opcodes = interpreter.opcodes;

    // --- Arithmetic benchmarks ---
    if (matchesFilter("OP_ADD", filter)) try bench.add("OP_ADD", OpRunner(opcodes.opAdd).run, .{ .hooks = .{ .before_each = resetAdd } });
    if (matchesFilter("OP_SUB", filter)) try bench.add("OP_SUB", OpRunner(opcodes.opSub).run, .{ .hooks = .{ .before_each = resetSub } });
    if (matchesFilter("OP_SUB (borrow)", filter)) try bench.add("OP_SUB (borrow)", OpRunner(opcodes.opSub).run, .{ .hooks = .{ .before_each = resetSubBorrow } });
    if (matchesFilter("OP_MUL", filter)) try bench.add("OP_MUL", OpRunner(opcodes.opMul).run, .{ .hooks = .{ .before_each = resetMul } });
    if (matchesFilter("OP_MUL (256x64)", filter)) try bench.add("OP_MUL (256x64)", OpRunner(opcodes.opMul).run, .{ .hooks = .{ .before_each = resetMulSmall } });
    if (matchesFilter("OP_DIV", filter)) try bench.add("OP_DIV", OpRunner(opcodes.opDiv).run, .{ .hooks = .{ .before_each = resetDiv } });
    if (matchesFilter("OP_DIV (256/256)", filter)) try bench.add("OP_DIV (256/256)", OpRunner(opcodes.opDiv).run, .{ .hooks = .{ .before_each = resetDivFull } });
    if (matchesFilter("OP_DIV (256/64)", filter)) try bench.add("OP_DIV (256/64)", OpRunner(opcodes.opDiv).run, .{ .hooks = .{ .before_each = resetDivSmall } });
    if (matchesFilter("OP_DIV (zero)", filter)) try bench.add("OP_DIV (zero)", OpRunner(opcodes.opDiv).run, .{ .hooks = .{ .before_each = resetDivZero } });
    if (matchesFilter("OP_SDIV", filter)) try bench.add("OP_SDIV", OpRunner(opcodes.opSdiv).run, .{ .hooks = .{ .before_each = resetSdiv } });
    if (matchesFilter("OP_SDIV (neg/pos)", filter)) try bench.add("OP_SDIV (neg/pos)", OpRunner(opcodes.opSdiv).run, .{ .hooks = .{ .before_each = resetSdivNegative } });
    if (matchesFilter("OP_SDIV (neg/neg)", filter)) try bench.add("OP_SDIV (neg/neg)", OpRunner(opcodes.opSdiv).run, .{ .hooks = .{ .before_each = resetSdivBothNeg } });
    if (matchesFilter("OP_MOD", filter)) try bench.add("OP_MOD", OpRunner(opcodes.opMod).run, .{ .hooks = .{ .before_each = resetMod } });
    if (matchesFilter("OP_MOD (256/64)", filter)) try bench.add("OP_MOD (256/64)", OpRunner(opcodes.opMod).run, .{ .hooks = .{ .before_each = resetModSmall } });
    if (matchesFilter("OP_MOD (zero)", filter)) try bench.add("OP_MOD (zero)", OpRunner(opcodes.opMod).run, .{ .hooks = .{ .before_each = resetModZero } });
    if (matchesFilter("OP_SMOD", filter)) try bench.add("OP_SMOD", OpRunner(opcodes.opSmod).run, .{ .hooks = .{ .before_each = resetSmod } });
    if (matchesFilter("OP_SMOD (neg div)", filter)) try bench.add("OP_SMOD (neg div)", OpRunner(opcodes.opSmod).run, .{ .hooks = .{ .before_each = resetSmodNegative } });
    if (matchesFilter("OP_SIGNEXTEND", filter)) try bench.add("OP_SIGNEXTEND", OpRunner(opcodes.opSignextend).run, .{ .hooks = .{ .before_each = resetSignextend } });
    if (matchesFilter("OP_SIGNEXTEND (0-3)", filter)) try bench.add("OP_SIGNEXTEND (0-3)", OpRunner(opcodes.opSignextend).run, .{ .hooks = .{ .before_each = resetSignextendLow } });
    if (matchesFilter("OP_SIGNEXTEND (28-31)", filter)) try bench.add("OP_SIGNEXTEND (28-31)", OpRunner(opcodes.opSignextend).run, .{ .hooks = .{ .before_each = resetSignextendHigh } });
    if (matchesFilter("OP_ADDMOD", filter)) try bench.add("OP_ADDMOD", OpRunner(opcodes.opAddmod).run, .{ .hooks = .{ .before_each = resetAddmod } });
    if (matchesFilter("OP_ADDMOD (MAX)", filter)) try bench.add("OP_ADDMOD (MAX)", OpRunner(opcodes.opAddmod).run, .{ .hooks = .{ .before_each = resetAddmodOverflow } });
    if (matchesFilter("OP_MULMOD", filter)) try bench.add("OP_MULMOD", OpRunner(opcodes.opMulmod).run, .{ .hooks = .{ .before_each = resetMulmod } });
    if (matchesFilter("OP_MULMOD (MAX)", filter)) try bench.add("OP_MULMOD (MAX)", OpRunner(opcodes.opMulmod).run, .{ .hooks = .{ .before_each = resetMulmodMax } });
    if (matchesFilter("OP_EXP (1B)", filter)) try bench.add("OP_EXP (1B)", OpRunner(opcodes.opExp).run, .{ .hooks = .{ .before_each = resetExpSmall } });
    if (matchesFilter("OP_EXP (32B)", filter)) try bench.add("OP_EXP (32B)", OpRunner(opcodes.opExp).run, .{ .hooks = .{ .before_each = resetExpLarge } });

    // --- Bitwise benchmarks ---
    if (matchesFilter("OP_AND", filter)) try bench.add("OP_AND", OpRunner(opcodes.opAnd).run, .{ .hooks = .{ .before_each = resetAnd } });
    if (matchesFilter("OP_OR", filter)) try bench.add("OP_OR", OpRunner(opcodes.opOr).run, .{ .hooks = .{ .before_each = resetOr } });
    if (matchesFilter("OP_XOR", filter)) try bench.add("OP_XOR", OpRunner(opcodes.opXor).run, .{ .hooks = .{ .before_each = resetXor } });
    if (matchesFilter("OP_NOT", filter)) try bench.add("OP_NOT", OpRunner(opcodes.opNot).run, .{ .hooks = .{ .before_each = resetNot } });
    if (matchesFilter("OP_BYTE", filter)) try bench.add("OP_BYTE", OpRunner(opcodes.opByte).run, .{ .hooks = .{ .before_each = resetByte } });
    if (matchesFilter("OP_SHL", filter)) try bench.add("OP_SHL", OpRunner(opcodes.opShl).run, .{ .hooks = .{ .before_each = resetShl } });
    if (matchesFilter("OP_SHL (0-63)", filter)) try bench.add("OP_SHL (0-63)", OpRunner(opcodes.opShl).run, .{ .hooks = .{ .before_each = resetShlSmall } });
    if (matchesFilter("OP_SHR", filter)) try bench.add("OP_SHR", OpRunner(opcodes.opShr).run, .{ .hooks = .{ .before_each = resetShr } });
    if (matchesFilter("OP_SHR (0-63)", filter)) try bench.add("OP_SHR (0-63)", OpRunner(opcodes.opShr).run, .{ .hooks = .{ .before_each = resetShrSmall } });
    if (matchesFilter("OP_SAR", filter)) try bench.add("OP_SAR", OpRunner(opcodes.opSar).run, .{ .hooks = .{ .before_each = resetSar } });
    if (matchesFilter("OP_SAR (negative)", filter)) try bench.add("OP_SAR (negative)", OpRunner(opcodes.opSar).run, .{ .hooks = .{ .before_each = resetSarNegative } });

    // Print results
    try writer.print("{s:<20}{s:<10}{s:<15}{s:<24}{s:<30}{s:<12}{s:<12}{s}\n", .{
        "benchmark", "runs", "total time", "time/op (avg ± σ)", "(min ... max)", "p75", "p99", "MGas/sec",
    });
    try writer.writeAll("-" ** 135 ++ "\n");

    var current_category: []const u8 = "";
    var it = try bench.iterator();
    while (try it.next()) |step| {
        switch (step) {
            .progress => {},
            .result => |result| {
                defer result.deinit();

                // Print category separators
                const category = getOpcodeCategory(result.name);
                if (!std.mem.eql(u8, category, current_category)) {
                    if (current_category.len > 0) try writer.writeAll("\n");
                    try writer.print("--- {s} OPCODES ---\n\n", .{category});
                }
                current_category = category;

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
