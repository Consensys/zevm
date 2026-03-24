// fuzz_bytecode.zig — Bytecode-focused interpreter fuzzing harness.
//
// Simpler than the transaction harness: the fuzz input is mostly raw bytecode.
// Uses the full pipeline (all 4 phases) but with a fixed minimal context so
// AFL++ can concentrate mutations on the bytecode bytes themselves rather than
// the transaction envelope.

const std = @import("std");
const primitives = @import("primitives");
const bytecode_mod = @import("bytecode");
const context = @import("context");
const database = @import("database");
const state_mod = @import("state");
const handler_mod = @import("handler");
const alloc_mod = @import("zevm_allocator");

const input_decoder = @import("input_decoder.zig");

/// Fixed addresses used by the bytecode harness
const CALLER: primitives.Address = [_]u8{0x10} ** 20;
const TARGET: primitives.Address = [_]u8{0x20} ** 20;

/// Bytecode fuzzing harness entry point.
///
/// Input format (min 9 bytes):
///   [0]      spec_id
///   [1..8]   gas_limit (u64 LE)
///   [9..]    raw bytecode
pub fn zevm_fuzz_bytecode(data: [*]const u8, len: usize) c_int {
    const input = input_decoder.decodeBytecodeFuzzInput(data[0..len]) orelse return 0;
    fuzzBytecode(input) catch {};
    return 0;
}

fn fuzzBytecode(input: input_decoder.BytecodeFuzzInput) !void {
    const alloc = alloc_mod.get();

    var db = database.InMemoryDB.init(alloc);

    // Seed caller with balance
    try db.insertAccount(CALLER, state_mod.AccountInfo.fromBalance(std.math.maxInt(u64)));

    // Target account carries the fuzz bytecode
    if (input.bytecode.len > 0) {
        const code = bytecode_mod.Bytecode.newLegacy(input.bytecode);
        var target_info = state_mod.AccountInfo.default();
        target_info.code_hash = code.hashSlow();
        target_info.code = code;
        try db.insertAccount(TARGET, target_info);
    } else {
        try db.insertAccount(TARGET, state_mod.AccountInfo.default());
    }

    var ctx = context.Context.new(db, input.spec_id);
    defer ctx.journaled_state.database.deinit();

    ctx.cfg.disable_balance_check = true;
    ctx.cfg.disable_nonce_check = true;
    ctx.cfg.disable_base_fee = true;
    ctx.cfg.disable_block_gas_limit = true;
    ctx.cfg.disable_eip3607 = true;
    ctx.cfg.disable_fee_charge = true;
    ctx.cfg.tx_chain_id_check = false;
    ctx.cfg.memory_limit = input_decoder.FUZZ_MEMORY_LIMIT;

    _ = ctx.journaled_state.loadAccount(CALLER) catch {};
    _ = ctx.journaled_state.loadAccount(TARGET) catch {};
    ctx.journaled_state.inner.transaction_id += 1;

    ctx.setBlock(context.BlockEnv{
        .number = 1,
        .beneficiary = [_]u8{0} ** 20,
        .timestamp = 1,
        .gas_limit = std.math.maxInt(u64),
        .basefee = 0,
        .difficulty = 0,
        .prevrandao = null,
        .blob_excess_gas_and_price = null,
        .slot_number = null,
    });

    ctx.tx = context.TxEnv.default();
    ctx.tx.caller = CALLER;
    ctx.tx.kind = context.TxKind{ .Call = TARGET };
    ctx.tx.gas_limit = input.gas_limit;
    ctx.tx.gas_price = 0;
    ctx.tx.chain_id = null;

    const evm = handler_mod.MainBuilder.buildMainnet(&ctx);
    defer evm.destroy();

    var result = evm.execute() catch return;
    defer result.deinit();
}
