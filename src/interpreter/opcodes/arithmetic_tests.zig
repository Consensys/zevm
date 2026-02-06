const std = @import("std");
const primitives = @import("primitives");
const Stack = @import("../stack.zig").Stack;
const Gas = @import("../gas.zig").Gas;
const InstructionResult = @import("../instruction_result.zig").InstructionResult;
const arithmetic = @import("arithmetic.zig");

const opAdd = arithmetic.opAdd;
const opSub = arithmetic.opSub;
const opMul = arithmetic.opMul;
const opDiv = arithmetic.opDiv;
const opMod = arithmetic.opMod;
const opAddmod = arithmetic.opAddmod;
const opMulmod = arithmetic.opMulmod;
const opExp = arithmetic.opExp;

const expectEqual = std.testing.expectEqual;
const U = primitives.U256;
const MAX = std.math.maxInt(U);

// --- ADD tests ---

test "ADD: 5 + 3 = 8" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 5));
    stack.pushUnsafe(@as(U, 3));
    const result = opAdd(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 1), stack.len());
    try expectEqual(@as(U, 8), stack.popUnsafe());
    try expectEqual(@as(u64, 97), gas.getRemaining());
}

test "ADD: zero identity" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 42));
    stack.pushUnsafe(@as(U, 0));
    const result = opAdd(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 42), stack.popUnsafe());
}

test "ADD: commutative" {
    var s1 = Stack.new();
    var g1 = Gas.new(100);
    s1.pushUnsafe(@as(U, 100));
    s1.pushUnsafe(@as(U, 200));
    _ = opAdd(&s1, &g1);
    const r1 = s1.popUnsafe();

    var s2 = Stack.new();
    var g2 = Gas.new(100);
    s2.pushUnsafe(@as(U, 200));
    s2.pushUnsafe(@as(U, 100));
    _ = opAdd(&s2, &g2);
    const r2 = s2.popUnsafe();

    try expectEqual(r1, r2);
    try expectEqual(@as(U, 300), r1);
}

test "ADD: wrapping overflow MAX + 1 = 0" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(MAX);
    stack.pushUnsafe(@as(U, 1));
    const result = opAdd(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "ADD: MAX + MAX = MAX - 1" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(MAX);
    stack.pushUnsafe(MAX);
    const result = opAdd(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(MAX -% 1, stack.popUnsafe());
}

test "ADD: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const result = opAdd(&stack, &gas);
    try expectEqual(InstructionResult.stack_underflow, result);
    try expectEqual(@as(usize, 0), stack.len());
    try expectEqual(@as(u64, 100), gas.getRemaining());
}

test "ADD: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(2);
    stack.pushUnsafe(@as(U, 1));
    stack.pushUnsafe(@as(U, 2));
    const result = opAdd(&stack, &gas);
    try expectEqual(InstructionResult.out_of_gas, result);
    try expectEqual(@as(usize, 2), stack.len());
}

test "ADD: gas deduction" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 10));
    stack.pushUnsafe(@as(U, 20));
    _ = opAdd(&stack, &gas);
    try expectEqual(@as(u64, 97), gas.getRemaining());
    try expectEqual(@as(u64, 3), gas.getSpent());
}

test "ADD: chained 1 + 2 + 3 = 6" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 1));
    stack.pushUnsafe(@as(U, 2));
    stack.pushUnsafe(@as(U, 3));
    _ = opAdd(&stack, &gas); // 3 + 2 = 5
    try expectEqual(@as(usize, 2), stack.len());
    _ = opAdd(&stack, &gas); // 5 + 1 = 6
    try expectEqual(@as(usize, 1), stack.len());
    try expectEqual(@as(U, 6), stack.popUnsafe());
    try expectEqual(@as(u64, 94), gas.getRemaining());
}

// --- DIV tests ---

test "DIV: 10 / 3 = 3" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 3)); // b (divisor)
    stack.pushUnsafe(@as(U, 10)); // a (dividend)
    const result = opDiv(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 1), stack.len());
    try expectEqual(@as(U, 3), stack.popUnsafe());
    try expectEqual(@as(u64, 95), gas.getRemaining());
}

test "DIV: division by zero returns 0" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 0)); // b (divisor)
    stack.pushUnsafe(@as(U, 42)); // a (dividend)
    const result = opDiv(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "DIV: exact division" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 25)); // b (divisor)
    stack.pushUnsafe(@as(U, 100)); // a (dividend)
    const result = opDiv(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 4), stack.popUnsafe());
}

test "DIV: dividend < divisor = 0" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 10)); // b (divisor)
    stack.pushUnsafe(@as(U, 3)); // a (dividend)
    const result = opDiv(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "DIV: MAX / 1 = MAX" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 1)); // b (divisor)
    stack.pushUnsafe(MAX); // a (dividend)
    const result = opDiv(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(MAX, stack.popUnsafe());
}

test "DIV: MAX / MAX = 1" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(MAX);
    stack.pushUnsafe(MAX);
    const result = opDiv(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1), stack.popUnsafe());
}

test "DIV: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const result = opDiv(&stack, &gas);
    try expectEqual(InstructionResult.stack_underflow, result);
    try expectEqual(@as(usize, 0), stack.len());
    try expectEqual(@as(u64, 100), gas.getRemaining());
}

test "DIV: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(4);
    stack.pushUnsafe(@as(U, 10));
    stack.pushUnsafe(@as(U, 2));
    const result = opDiv(&stack, &gas);
    try expectEqual(InstructionResult.out_of_gas, result);
    try expectEqual(@as(usize, 2), stack.len());
}

// --- SUB tests ---

test "SUB: 8 - 3 = 5" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 3)); // b
    stack.pushUnsafe(@as(U, 8)); // a
    const result = opSub(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 5), stack.popUnsafe());
    try expectEqual(@as(u64, 97), gas.getRemaining());
}

test "SUB: wrapping underflow 0 - 1 = MAX" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 1)); // b
    stack.pushUnsafe(@as(U, 0)); // a
    const result = opSub(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(MAX, stack.popUnsafe());
}

test "SUB: zero identity a - 0 = a" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 0)); // b
    stack.pushUnsafe(@as(U, 42)); // a
    const result = opSub(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 42), stack.popUnsafe());
}

test "SUB: self-sub a - a = 0" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 999)); // b
    stack.pushUnsafe(@as(U, 999)); // a
    const result = opSub(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "SUB: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const result = opSub(&stack, &gas);
    try expectEqual(InstructionResult.stack_underflow, result);
    try expectEqual(@as(u64, 100), gas.getRemaining());
}

test "SUB: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(2);
    stack.pushUnsafe(@as(U, 1));
    stack.pushUnsafe(@as(U, 2));
    const result = opSub(&stack, &gas);
    try expectEqual(InstructionResult.out_of_gas, result);
    try expectEqual(@as(usize, 2), stack.len());
}

// --- MUL tests ---

test "MUL: 3 * 4 = 12" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 4)); // b
    stack.pushUnsafe(@as(U, 3)); // a
    const result = opMul(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 12), stack.popUnsafe());
    try expectEqual(@as(u64, 95), gas.getRemaining());
}

test "MUL: zero" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 0));
    stack.pushUnsafe(@as(U, 42));
    const result = opMul(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "MUL: identity a * 1 = a" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 1));
    stack.pushUnsafe(@as(U, 42));
    const result = opMul(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 42), stack.popUnsafe());
}

test "MUL: wrapping MAX * 2 = MAX - 1" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 2));
    stack.pushUnsafe(MAX);
    const result = opMul(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(MAX -% 1, stack.popUnsafe());
}

test "MUL: commutative" {
    var s1 = Stack.new();
    var g1 = Gas.new(100);
    s1.pushUnsafe(@as(U, 7));
    s1.pushUnsafe(@as(U, 13));
    _ = opMul(&s1, &g1);
    const r1 = s1.popUnsafe();

    var s2 = Stack.new();
    var g2 = Gas.new(100);
    s2.pushUnsafe(@as(U, 13));
    s2.pushUnsafe(@as(U, 7));
    _ = opMul(&s2, &g2);
    const r2 = s2.popUnsafe();

    try expectEqual(r1, r2);
    try expectEqual(@as(U, 91), r1);
}

test "MUL: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const result = opMul(&stack, &gas);
    try expectEqual(InstructionResult.stack_underflow, result);
}

test "MUL: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(4);
    stack.pushUnsafe(@as(U, 2));
    stack.pushUnsafe(@as(U, 3));
    const result = opMul(&stack, &gas);
    try expectEqual(InstructionResult.out_of_gas, result);
    try expectEqual(@as(usize, 2), stack.len());
}

// --- MOD tests ---

test "MOD: 10 % 3 = 1" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 3)); // b
    stack.pushUnsafe(@as(U, 10)); // a
    const result = opMod(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1), stack.popUnsafe());
    try expectEqual(@as(u64, 95), gas.getRemaining());
}

test "MOD: mod by zero = 0" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 0)); // b
    stack.pushUnsafe(@as(U, 42)); // a
    const result = opMod(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "MOD: dividend < divisor" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 10)); // b
    stack.pushUnsafe(@as(U, 3)); // a
    const result = opMod(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 3), stack.popUnsafe());
}

test "MOD: MAX % 2 = 1" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 2)); // b
    stack.pushUnsafe(MAX); // a
    const result = opMod(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1), stack.popUnsafe());
}

test "MOD: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const result = opMod(&stack, &gas);
    try expectEqual(InstructionResult.stack_underflow, result);
}

test "MOD: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(4);
    stack.pushUnsafe(@as(U, 3));
    stack.pushUnsafe(@as(U, 10));
    const result = opMod(&stack, &gas);
    try expectEqual(InstructionResult.out_of_gas, result);
}

// --- ADDMOD tests ---

test "ADDMOD: (10 + 7) % 3 = 2" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 3)); // N
    stack.pushUnsafe(@as(U, 7)); // b
    stack.pushUnsafe(@as(U, 10)); // a
    const result = opAddmod(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 1), stack.len());
    try expectEqual(@as(U, 2), stack.popUnsafe());
    try expectEqual(@as(u64, 92), gas.getRemaining());
}

test "ADDMOD: N=0 returns 0" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 0)); // N
    stack.pushUnsafe(@as(U, 7)); // b
    stack.pushUnsafe(@as(U, 10)); // a
    const result = opAddmod(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "ADDMOD: MAX + 1 carry" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 2)); // N
    stack.pushUnsafe(@as(U, 1)); // b
    stack.pushUnsafe(MAX); // a
    // (MAX + 1) % 2 = 2^256 % 2 = 0
    const result = opAddmod(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "ADDMOD: MAX + MAX" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(MAX); // N = MAX
    stack.pushUnsafe(MAX); // b
    stack.pushUnsafe(MAX); // a
    // (MAX + MAX) % MAX = (2*MAX) % MAX = 0
    const result = opAddmod(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "ADDMOD: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 1));
    stack.pushUnsafe(@as(U, 2));
    const result = opAddmod(&stack, &gas);
    try expectEqual(InstructionResult.stack_underflow, result);
    try expectEqual(@as(usize, 2), stack.len());
}

test "ADDMOD: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(7);
    stack.pushUnsafe(@as(U, 3));
    stack.pushUnsafe(@as(U, 7));
    stack.pushUnsafe(@as(U, 10));
    const result = opAddmod(&stack, &gas);
    try expectEqual(InstructionResult.out_of_gas, result);
    try expectEqual(@as(usize, 3), stack.len());
}

// --- MULMOD tests ---

test "MULMOD: (10 * 7) % 3 = 1" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 3)); // N
    stack.pushUnsafe(@as(U, 7)); // b
    stack.pushUnsafe(@as(U, 10)); // a
    const result = opMulmod(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 1), stack.len());
    try expectEqual(@as(U, 1), stack.popUnsafe());
    try expectEqual(@as(u64, 92), gas.getRemaining());
}

test "MULMOD: N=0 returns 0" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 0)); // N
    stack.pushUnsafe(@as(U, 7)); // b
    stack.pushUnsafe(@as(U, 10)); // a
    const result = opMulmod(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "MULMOD: MAX * MAX % MAX = 0" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(MAX); // N
    stack.pushUnsafe(MAX); // b
    stack.pushUnsafe(MAX); // a
    const result = opMulmod(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "MULMOD: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(@as(U, 1));
    stack.pushUnsafe(@as(U, 2));
    const result = opMulmod(&stack, &gas);
    try expectEqual(InstructionResult.stack_underflow, result);
}

test "MULMOD: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(7);
    stack.pushUnsafe(@as(U, 3));
    stack.pushUnsafe(@as(U, 7));
    stack.pushUnsafe(@as(U, 10));
    const result = opMulmod(&stack, &gas);
    try expectEqual(InstructionResult.out_of_gas, result);
}

// --- EXP tests ---

test "EXP: 2 ^ 10 = 1024" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    stack.pushUnsafe(@as(U, 10)); // exponent
    stack.pushUnsafe(@as(U, 2)); // base
    const result = opExp(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1024), stack.popUnsafe());
    // gas: 10 + 50*1 = 60 (exponent 10 fits in 1 byte)
    try expectEqual(@as(u64, 940), gas.getRemaining());
}

test "EXP: a ^ 0 = 1" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    stack.pushUnsafe(@as(U, 0)); // exponent
    stack.pushUnsafe(@as(U, 42)); // base
    const result = opExp(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1), stack.popUnsafe());
    // gas: 10 + 50*0 = 10 (exponent 0 = 0 bytes)
    try expectEqual(@as(u64, 990), gas.getRemaining());
}

test "EXP: 0 ^ 0 = 1" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    stack.pushUnsafe(@as(U, 0)); // exponent
    stack.pushUnsafe(@as(U, 0)); // base
    const result = opExp(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 1), stack.popUnsafe());
}

test "EXP: a ^ 1 = a" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    stack.pushUnsafe(@as(U, 1)); // exponent
    stack.pushUnsafe(@as(U, 42)); // base
    const result = opExp(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 42), stack.popUnsafe());
}

test "EXP: 0 ^ n = 0 (n > 0)" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    stack.pushUnsafe(@as(U, 5)); // exponent
    stack.pushUnsafe(@as(U, 0)); // base
    const result = opExp(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "EXP: 2 ^ 256 = 0 (wrapping)" {
    var stack = Stack.new();
    var gas = Gas.new(10000);
    stack.pushUnsafe(@as(U, 256)); // exponent
    stack.pushUnsafe(@as(U, 2)); // base
    const result = opExp(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
    // gas: 10 + 50*2 = 110 (exponent 256 = 0x100, 2 bytes)
    try expectEqual(@as(u64, 9890), gas.getRemaining());
}

test "EXP: gas cost with 32-byte exponent" {
    var stack = Stack.new();
    var gas = Gas.new(10000);
    stack.pushUnsafe(MAX); // exponent = MAX (32 bytes)
    stack.pushUnsafe(@as(U, 2)); // base
    const result = opExp(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    // gas: 10 + 50*32 = 1610
    try expectEqual(@as(u64, 8390), gas.getRemaining());
}

test "EXP: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    const result = opExp(&stack, &gas);
    try expectEqual(InstructionResult.stack_underflow, result);
    try expectEqual(@as(u64, 1000), gas.getRemaining());
}

test "EXP: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(50);
    stack.pushUnsafe(MAX); // exponent = MAX (32 bytes, needs 1610 gas)
    stack.pushUnsafe(@as(U, 2));
    const result = opExp(&stack, &gas);
    try expectEqual(InstructionResult.out_of_gas, result);
    try expectEqual(@as(usize, 2), stack.len());
}

// --- Helper function tests ---

test "byteSize" {
    try expectEqual(@as(u64, 0), arithmetic.byteSize(0));
    try expectEqual(@as(u64, 1), arithmetic.byteSize(1));
    try expectEqual(@as(u64, 1), arithmetic.byteSize(255));
    try expectEqual(@as(u64, 2), arithmetic.byteSize(256));
    try expectEqual(@as(u64, 32), arithmetic.byteSize(MAX));
}

test "addmod helper" {
    try expectEqual(@as(U, 2), arithmetic.addmod(10, 7, 3));
    try expectEqual(@as(U, 0), arithmetic.addmod(10, 7, 0));
    // MAX + 1 = 2^256, handled by overflow detection
    try expectEqual(@as(U, 0), arithmetic.addmod(MAX, 1, 2));
}

test "mulmod helper" {
    try expectEqual(@as(U, 1), arithmetic.mulmod(10, 7, 3));
    try expectEqual(@as(U, 0), arithmetic.mulmod(10, 7, 0));
    try expectEqual(@as(U, 0), arithmetic.mulmod(MAX, MAX, MAX));
}

test "expMod256 helper" {
    try expectEqual(@as(U, 1), arithmetic.expMod256(2, 0));
    try expectEqual(@as(U, 1024), arithmetic.expMod256(2, 10));
    try expectEqual(@as(U, 0), arithmetic.expMod256(2, 256));
    try expectEqual(@as(U, 1), arithmetic.expMod256(1, MAX));
}
