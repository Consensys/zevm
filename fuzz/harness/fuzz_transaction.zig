// fuzz_transaction.zig — Full transaction pipeline fuzzing harness.
//
// Exports C-callable functions for AFL++ via the C shim in afl_shim.c.
// Exercises the complete validate → preExecution → executeFrame → postExecution pipeline.
//
// Re-exports all three harness entry points so build.zig only needs one root file.

const std = @import("std");
const primitives = @import("primitives");
const bytecode_mod = @import("bytecode");
const context = @import("context");
const database = @import("database");
const state_mod = @import("state");
const handler_mod = @import("handler");
const alloc_mod = @import("zevm_allocator");

const input_decoder = @import("input_decoder.zig");
const fuzz_bytecode_mod = @import("fuzz_bytecode.zig");
const fuzz_precompile_mod = @import("fuzz_precompile.zig");

// Re-export the other harness functions so the C shim can call all three
// from a single linked library. Must use `pub export fn` wrappers — a `pub const`
// alias is only a Zig-level alias and does not emit a C-visible symbol.
pub export fn zevm_fuzz_bytecode(data: [*]const u8, len: usize) c_int {
    return fuzz_bytecode_mod.zevm_fuzz_bytecode(data, len);
}
pub export fn zevm_fuzz_precompile(data: [*]const u8, len: usize) c_int {
    return fuzz_precompile_mod.zevm_fuzz_precompile(data, len);
}

/// Full transaction fuzzing harness.
///
/// Parses the binary fuzz input and runs the EVM through the complete
/// mainnet handler pipeline with validation checks relaxed for fuzzing.
/// Returns 0 for all expected outcomes; AFL++ captures genuine crashes.
pub export fn zevm_fuzz_transaction(data: [*]const u8, len: usize) c_int {
    const input = input_decoder.decodeTxInput(data[0..len]) orelse return 0;
    fuzzTransaction(input) catch {};
    return 0;
}

fn fuzzTransaction(input: input_decoder.TxFuzzInput) !void {
    const alloc = alloc_mod.get();

    // Build InMemoryDB and seed pre-state
    var db = database.InMemoryDB.init(alloc);

    // Caller: large balance so balance checks pass even if not disabled.
    // Use insertAccount which takes ownership of AccountInfo.
    const caller_info = state_mod.AccountInfo.fromBalance(
        std.math.maxInt(u64), // generous balance
    );
    try db.insertAccount(input.caller, caller_info);

    // Target: given bytecode (or empty for CREATE)
    if (!input.is_create and input.bytecode.len > 0) {
        const code = bytecode_mod.Bytecode.newLegacy(input.bytecode);
        var target_info = state_mod.AccountInfo.default();
        target_info.code_hash = code.hashSlow();
        target_info.code = code;
        try db.insertAccount(input.target, target_info);
    } else if (!input.is_create) {
        try db.insertAccount(input.target, state_mod.AccountInfo.default());
    }

    // Build context — db is moved in by value
    var ctx = context.Context.new(db, input.spec_id);
    defer ctx.journaled_state.database.deinit();

    // Relax validation flags for fuzzing — we want to reach execution code,
    // not spend cycles on environment rejections.
    ctx.cfg.disable_balance_check = true;
    ctx.cfg.disable_nonce_check = true;
    ctx.cfg.disable_base_fee = true;
    ctx.cfg.disable_block_gas_limit = true;
    ctx.cfg.disable_eip3607 = true;
    ctx.cfg.disable_fee_charge = true;
    ctx.cfg.tx_chain_id_check = false;
    ctx.cfg.memory_limit = input_decoder.FUZZ_MEMORY_LIMIT;

    // Pre-load accounts into journal so sload/sstore can find them.
    // Bump transaction_id so pre-loaded accounts appear cold at tx start (EIP-2929).
    _ = ctx.journaled_state.loadAccount(input.caller) catch {};
    if (!input.is_create) {
        _ = ctx.journaled_state.loadAccount(input.target) catch {};
    }
    ctx.journaled_state.inner.transaction_id += 1;

    // Set minimal block environment
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

    // Build calldata ArrayList (page_allocator, transient — not freed)
    var calldata_list: ?std.ArrayList(u8) = null;
    if (input.calldata.len > 0) {
        var cd = std.ArrayList(u8){};
        cd.appendSlice(std.heap.page_allocator, input.calldata) catch {};
        calldata_list = cd;
    }

    // Set transaction environment
    ctx.tx = context.TxEnv.default();
    ctx.tx.caller = input.caller;
    ctx.tx.gas_limit = input.gas_limit;
    ctx.tx.gas_price = 0;
    ctx.tx.value = input.value;
    ctx.tx.nonce = 0;
    ctx.tx.chain_id = null;
    ctx.tx.data = calldata_list;

    if (input.is_create) {
        ctx.tx.tx_type = 0;
        ctx.tx.kind = context.TxKind{ .Create = {} };
    } else {
        ctx.tx.tx_type = 0;
        ctx.tx.kind = context.TxKind{ .Call = input.target };
    }

    // Build and execute the EVM
    const evm = handler_mod.MainBuilder.buildMainnet(&ctx);
    defer evm.destroy();

    var result = evm.execute() catch return;
    defer result.deinit();
}
