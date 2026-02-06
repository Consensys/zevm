const std = @import("std");
const primitives = @import("primitives");
const Stack = @import("../stack.zig").Stack;
const Gas = @import("../gas.zig").Gas;
const InstructionResult = @import("../instruction_result.zig").InstructionResult;

pub const GAS_VERYLOW: u64 = 3;

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

// --- Tests ---

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const U = primitives.U256;
const MAX = std.math.maxInt(U);

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
