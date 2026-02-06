const std = @import("std");
const primitives = @import("primitives");
const Stack = @import("../stack.zig").Stack;
const Gas = @import("../gas.zig").Gas;
const InstructionResult = @import("../instruction_result.zig").InstructionResult;

pub const GAS_VERYLOW: u64 = 3;
pub const GAS_LOW: u64 = 5;
pub const GAS_MID: u64 = 8;
pub const GAS_EXP: u64 = 10;
pub const GAS_EXP_BYTE: u64 = 50;

/// ADD opcode (0x01): a + b (wrapping mod 2^256)
/// Stack: [a, b] -> [a + b]   Gas: 3 (VERYLOW)
pub inline fn opAdd(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = a +% b;
    return .continue_;
}

/// DIV opcode (0x04): a / b (unsigned, division by zero returns 0)
/// Stack: [a, b] -> [a / b]   Gas: 5 (LOW)
pub inline fn opDiv(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_LOW)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = if (b != 0) a / b else 0;
    return .continue_;
}

/// SUB opcode (0x03): a - b (wrapping mod 2^256)
/// Stack: [a, b] -> [a - b]   Gas: 3 (VERYLOW)
pub inline fn opSub(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_VERYLOW)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = a -% b;
    return .continue_;
}

/// MUL opcode (0x02): a * b (wrapping mod 2^256)
/// Stack: [a, b] -> [a * b]   Gas: 5 (LOW)
pub inline fn opMul(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_LOW)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = a *% b;
    return .continue_;
}

/// MOD opcode (0x06): a % b (unsigned, mod by zero returns 0)
/// Stack: [a, b] -> [a % b]   Gas: 5 (LOW)
pub inline fn opMod(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(GAS_LOW)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = if (b != 0) a % b else 0;
    return .continue_;
}

/// ADDMOD opcode (0x08): (a + b) % N with u257 intermediate
/// Stack: [a, b, N] -> [(a + b) % N]   Gas: 8 (MID)
pub inline fn opAddmod(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(3)) return .stack_underflow;
    if (!gas.spend(GAS_MID)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    const n = stack.peekUnsafe(2);
    stack.shrinkUnsafe(2);
    stack.setTopUnsafe().* = addmod(a, b, n);
    return .continue_;
}

/// MULMOD opcode (0x09): (a * b) % N with u512 intermediate
/// Stack: [a, b, N] -> [(a * b) % N]   Gas: 8 (MID)
pub inline fn opMulmod(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(3)) return .stack_underflow;
    if (!gas.spend(GAS_MID)) return .out_of_gas;
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    const n = stack.peekUnsafe(2);
    stack.shrinkUnsafe(2);
    stack.setTopUnsafe().* = mulmod(a, b, n);
    return .continue_;
}

/// EXP opcode (0x0A): base ^ exponent (mod 2^256)
/// Stack: [base, exponent] -> [base ^ exponent]
/// Gas: 10 + 50 * byteSize(exponent)
pub inline fn opExp(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    const exponent = stack.peekUnsafe(1);
    const gas_cost = GAS_EXP + GAS_EXP_BYTE * byteSize(exponent);
    if (!gas.spend(gas_cost)) return .out_of_gas;
    const base = stack.peekUnsafe(0);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = expMod256(base, exponent);
    return .continue_;
}

// --- Helpers ---

/// Compute (a + b) % n using only u256 arithmetic.
/// Reduces inputs mod n first, then uses overflow detection to avoid wider types.
/// Returns 0 when n == 0 (per EVM spec).
pub fn addmod(a: primitives.U256, b: primitives.U256, n: primitives.U256) primitives.U256 {
    if (n == 0) return 0;
    const ar = a % n;
    const br = b % n;
    const sum = ar +% br;
    // Overflow (sum wrapped) or sum >= n means we need to subtract n.
    // Both ar < n and br < n, so the true sum < 2n, making one subtract sufficient.
    return if (sum < ar or sum >= n) sum -% n else sum;
}

/// Compute (a * b) % n using double-and-add with u256 arithmetic only.
/// Iterates over bits of the smaller operand, calling addmod at each step.
/// Returns 0 when n == 0 (per EVM spec).
pub fn mulmod(a: primitives.U256, b: primitives.U256, n: primitives.U256) primitives.U256 {
    if (n == 0) return 0;
    var x = a % n;
    var y = b % n;
    if (x == 0 or y == 0) return 0;
    // Iterate over the operand with fewer significant bits
    if (@clz(x) > @clz(y)) {
        const tmp = x;
        x = y;
        y = tmp;
    }
    var result: primitives.U256 = 0;
    while (y != 0) {
        if (y & 1 != 0) {
            result = addmod(result, x, n);
        }
        y >>= 1;
        if (y != 0) {
            x = addmod(x, x, n);
        }
    }
    return result;
}

/// Square-and-multiply modular exponentiation (mod 2^256).
pub fn expMod256(base: primitives.U256, exp: primitives.U256) primitives.U256 {
    if (exp == 0) return 1;
    var result: primitives.U256 = 1;
    var b = base;
    var e = exp;
    while (e != 0) {
        if (e & 1 == 1) {
            result = result *% b;
        }
        e >>= 1;
        if (e != 0) {
            b = b *% b;
        }
    }
    return result;
}

/// Number of bytes needed to represent x (0 returns 0).
pub fn byteSize(x: primitives.U256) u64 {
    if (x == 0) return 0;
    return (256 - @as(u64, @clz(x)) + 7) / 8;
}

test {
    _ = @import("arithmetic_tests.zig");
}
