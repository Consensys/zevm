const std = @import("std");
const primitives = @import("primitives");
const bytecode_mod = @import("bytecode");
const context_mod = @import("context");
const alloc_mod = @import("zevm_allocator");
const Interpreter = @import("interpreter.zig").Interpreter;
const InputsImpl = @import("interpreter.zig").InputsImpl;
const ExtBytecode = @import("interpreter.zig").ExtBytecode;
const Memory = @import("memory.zig").Memory;
const InstructionResult = @import("instruction_result.zig").InstructionResult;
const CallScheme = @import("interpreter_action.zig").CallScheme;
const gas_costs = @import("gas_costs.zig");
const precompile_mod = @import("precompile");
const protocol_schedule = @import("protocol_schedule.zig");
const JournalCheckpoint = context_mod.JournalCheckpoint;

/// Result of a sub-call dispatched via Host.call()
pub const CallResult = struct {
    success: bool,
    return_data: []const u8,
    gas_used: u64,
    gas_remaining: u64,
    /// Refund counter accumulated inside the sub-call (SSTORE clears, etc.).
    /// Must be added to the parent frame's gas.refunded on return.
    gas_refunded: i64,
    /// EIP-7702: gas charged for loading the delegation target (if any).
    /// Must be deducted from the parent frame's remaining gas after the call.
    delegation_gas: u64,
    /// EIP-8037 (Amsterdam+): state gas charged in the sub-call.
    /// Must be added to parent frame's gas.state_gas_used on return.
    state_gas_used: u64,
    /// EIP-8037 (Amsterdam+): reservoir remaining in the child after execution.
    /// On success: returned to parent's reservoir.
    /// On failure: added with state_gas_used to restore all state gas to parent's reservoir.
    state_gas_remaining: u64,

    /// Sub-call failed after execution (all gas consumed).
    pub fn failure(gas_limit: u64) CallResult {
        return .{ .success = false, .return_data = &[_]u8{}, .gas_used = gas_limit, .gas_remaining = 0, .gas_refunded = 0, .delegation_gas = 0, .state_gas_used = 0, .state_gas_remaining = 0 };
    }

    /// Sub-call failed BEFORE execution (depth limit, value-transfer failure).
    /// Per EVM spec: when no sub-code runs, all forwarded gas is returned to caller.
    pub fn preExecFailure(gas_limit: u64) CallResult {
        return .{ .success = false, .return_data = &[_]u8{}, .gas_used = 0, .gas_remaining = gas_limit, .gas_refunded = 0, .delegation_gas = 0, .state_gas_used = 0, .state_gas_remaining = 0 };
    }
};

/// Inputs for a sub-call
pub const CallInputs = struct {
    /// Sender of the call (msg.sender in callee)
    caller: primitives.Address,
    /// Execution context address (storage/balance ownership)
    target: primitives.Address,
    /// Contract whose code is executed
    callee: primitives.Address,
    /// Value transferred
    value: primitives.U256,
    /// Call data
    data: []const u8,
    /// Gas limit for the sub-call
    gas_limit: u64,
    /// Call scheme
    scheme: CallScheme,
    /// Whether this is a static (read-only) call
    is_static: bool,
    /// EIP-8037 (Amsterdam+): state gas reservoir forwarded from parent to child.
    reservoir: u64,
};

/// Result of a selfdestruct operation
pub const SelfDestructLoadResult = struct {
    had_value: bool,
    target_exists: bool,
    previously_destroyed: bool,
    is_cold: bool,
};

/// Result of a CREATE / CREATE2 operation
pub const CreateResult = struct {
    success: bool,
    /// True when the init-code explicitly executed REVERT (gas is returned, revert reason in
    /// return_data). False for any other failure (OOG, bad opcode, pre-execution guard, etc.).
    is_revert: bool,
    address: primitives.Address,
    gas_remaining: u64,
    return_data: []const u8,
    /// Refund counter accumulated inside the init-code sub-interpreter.
    gas_refunded: i64,
    /// EIP-8037 (Amsterdam+): state gas charged in the sub-call.
    /// Must be added to parent frame's gas.state_gas_used on return.
    state_gas_used: u64,
    /// EIP-8037 (Amsterdam+): reservoir remaining in the child after execution.
    state_gas_remaining: u64,

    /// Pre-execution failure: no sub-interpreter ran, return all forwarded gas.
    pub fn preExecFailure(gas_limit: u64) CreateResult {
        return .{ .success = false, .is_revert = false, .address = [_]u8{0} ** 20, .gas_remaining = gas_limit, .return_data = &[_]u8{}, .gas_refunded = 0, .state_gas_used = 0, .state_gas_remaining = 0 };
    }

    /// Post-execution failure: sub-interpreter ran and consumed gas.
    pub fn failure() CreateResult {
        return .{ .success = false, .is_revert = false, .address = [_]u8{0} ** 20, .gas_remaining = 0, .return_data = &[_]u8{}, .gas_refunded = 0, .state_gas_used = 0, .state_gas_remaining = 0 };
    }
};

/// The Host bridges opcode handlers to the EVM execution context.
/// It provides access to block/tx environment and account state via
/// the journaled state.
pub const Host = struct {
    ctx: *context_mod.Context,
    /// Precompile set for the current spec. Null disables precompile dispatch (benchmarks/unit tests).
    precompiles: ?*const precompile_mod.Precompiles = null,

    // -----------------------------------------------------------------------
    // Block / transaction environment (no state access required)
    // -----------------------------------------------------------------------

    pub fn origin(self: *Host) primitives.Address {
        return self.ctx.tx.caller;
    }

    pub fn gasPrice(self: *Host) primitives.U256 {
        const max_fee = self.ctx.tx.gas_price;
        if (self.ctx.tx.gas_priority_fee) |priority_fee| {
            const base_fee: u128 = @intCast(self.ctx.block.basefee);
            const effective = @min(max_fee, base_fee + priority_fee);
            return @as(primitives.U256, effective);
        }
        return @as(primitives.U256, max_fee);
    }

    pub fn coinbase(self: *Host) primitives.Address {
        return self.ctx.block.beneficiary;
    }

    pub fn blockNumber(self: *Host) primitives.U256 {
        return self.ctx.block.number;
    }

    pub fn timestamp(self: *Host) primitives.U256 {
        return self.ctx.block.timestamp;
    }

    pub fn blockGasLimit(self: *Host) u64 {
        return self.ctx.block.gas_limit;
    }

    pub fn difficulty(self: *Host) primitives.U256 {
        return self.ctx.block.difficulty;
    }

    pub fn prevrandao(self: *Host) ?primitives.Hash {
        return self.ctx.block.prevrandao;
    }

    pub fn chainId(self: *Host) u64 {
        return self.ctx.cfg.chain_id;
    }

    pub fn basefee(self: *Host) u64 {
        return self.ctx.block.basefee;
    }

    pub fn blobBasefee(self: *Host) u128 {
        if (self.ctx.block.blob_excess_gas_and_price) |b| return b.blob_gasprice;
        return 0;
    }

    pub fn blobHash(self: *Host, index: usize) ?primitives.U256 {
        const blob_hashes = self.ctx.tx.blob_hashes orelse return null;
        if (index >= blob_hashes.items.len) return null;
        return hashToU256(blob_hashes.items[index]);
    }

    pub fn blockHash(self: *Host, number: u64) ?primitives.Hash {
        return self.ctx.blockHash(number);
    }

    pub fn slotNumber(self: *Host) ?u64 {
        return self.ctx.block.slot_number;
    }

    // -----------------------------------------------------------------------
    // Account state access (via journaled_state)
    // -----------------------------------------------------------------------

    /// Check whether an address is cold WITHOUT loading it from the database.
    /// Used to pre-check gas costs before committing to a DB load (EIP-7928 BAL correctness).
    pub fn isAddressCold(self: *Host, addr: primitives.Address) bool {
        return self.ctx.journaled_state.isAddressCold(addr);
    }

    /// Check whether a storage slot is cold WITHOUT loading it from the database.
    pub fn isStorageCold(self: *Host, addr: primitives.Address, key: primitives.StorageKey) bool {
        return self.ctx.journaled_state.isStorageCold(addr, key);
    }

    /// Un-record a pending address access in the database fallback.
    /// Called when a CALL loaded an address for gas calculation but went OOG.
    pub fn untrackAddress(self: *Host, addr: primitives.Address) void {
        self.ctx.journaled_state.untrackAddress(addr);
    }

    /// Force-add an address to the current-tx access log in the database fallback.
    /// Used for EIP-7702 delegation targets that execute but are not in the witness.
    pub fn forceTrackAddress(self: *Host, addr: primitives.Address) void {
        self.ctx.journaled_state.forceTrackAddress(addr);
    }

    /// Check whether an address is already in the EVM state cache.
    /// Used to avoid un-tracking addresses that were legitimately accessed earlier in the tx.
    pub fn isAddressLoaded(self: *const Host, addr: primitives.Address) bool {
        return self.ctx.journaled_state.isAddressLoaded(addr);
    }

    /// Load account info. Returns null on database error.
    /// is_cold indicates whether this was a cold access (for gas charging).
    pub fn accountInfo(self: *Host, addr: primitives.Address) ?struct { balance: primitives.U256, is_cold: bool, is_empty: bool } {
        const load = self.ctx.journaled_state.loadAccountInfoSkipColdLoad(addr, false, false) catch return null;
        return .{
            .balance = load.info.balance,
            .is_cold = load.is_cold,
            .is_empty = load.is_empty,
        };
    }

    /// Load account with code. Returns null on database error.
    /// Per EIP-7702: EXTCODESIZE/EXTCODECOPY/EXTCODEHASH operate on the delegation POINTER bytes
    /// (23-byte 0xef0100||addr), NOT the delegation target's code. Return as-is.
    pub fn codeInfo(self: *Host, addr: primitives.Address) ?struct { bytecode: bytecode_mod.Bytecode, code_hash: primitives.Hash, is_cold: bool } {
        const load = self.ctx.journaled_state.loadAccountWithCode(addr) catch return null;
        const acc = load.data;
        const code = if (acc.info.code) |c| c else bytecode_mod.Bytecode.new();
        const code_hash = acc.info.code_hash;
        return .{
            .bytecode = code,
            .code_hash = code_hash,
            .is_cold = load.is_cold,
        };
    }

    /// Load account for external code hash. Returns null on database error.
    /// Per EIP-7702: EXTCODEHASH returns keccak256 of the delegation pointer bytes (not the target).
    /// code_hash is already stored as keccak256(delegation_pointer) when the account is loaded.
    pub fn extCodeHash(self: *Host, addr: primitives.Address) ?struct { hash: primitives.Hash, is_cold: bool, is_empty: bool } {
        const load = self.ctx.journaled_state.loadAccountWithCode(addr) catch return null;
        const acct = load.data;
        const hash = acct.info.code_hash;
        // An account is "non-existing" (returns 0) only if it was loaded as not-existing
        // from the DB AND has never been touched during this transaction.
        // Accounts that were touched (e.g., by EIP-7702 setCode clearing delegation to 0x0)
        // are considered existing and return KECCAK_EMPTY (not 0) even with empty code.
        const is_empty = acct.isLoadedAsNotExistingNotTouched();
        return .{
            .hash = hash,
            .is_cold = load.is_cold,
            .is_empty = is_empty,
        };
    }

    pub fn sload(self: *Host, addr: primitives.Address, key: primitives.U256) ?struct { value: primitives.U256, is_cold: bool } {
        const load = self.ctx.journaled_state.sload(addr, key) catch return null;
        return .{ .value = load.data, .is_cold = load.is_cold };
    }

    pub fn sstore(self: *Host, addr: primitives.Address, key: primitives.U256, val: primitives.U256) ?struct { original: primitives.U256, current: primitives.U256, new: primitives.U256, is_cold: bool } {
        const result = self.ctx.journaled_state.sstore(addr, key, val) catch return null;
        return .{
            .original = result.data.original_value,
            .current = result.data.present_value,
            .new = result.data.new_value,
            .is_cold = result.is_cold,
        };
    }

    pub fn tload(self: *Host, addr: primitives.Address, key: primitives.U256) primitives.U256 {
        return self.ctx.journaled_state.tload(addr, key);
    }

    pub fn tstore(self: *Host, addr: primitives.Address, key: primitives.U256, val: primitives.U256) void {
        self.ctx.journaled_state.tstore(addr, key, val);
    }

    pub fn emitLog(self: *Host, log_entry: primitives.Log) void {
        self.ctx.journaled_state.log(log_entry);
    }

    pub fn selfdestruct(self: *Host, addr: primitives.Address, target: primitives.Address) ?SelfDestructLoadResult {
        const result = self.ctx.journaled_state.selfdestruct(addr, target) catch return null;
        return .{
            .had_value = result.data.had_value,
            .target_exists = result.data.target_exists,
            .previously_destroyed = result.data.previously_destroyed,
            .is_cold = result.is_cold,
        };
    }

    // -----------------------------------------------------------------------
    // Sub-call dispatch: setup/finalize split for iterative frame runner
    // -----------------------------------------------------------------------

    /// Result of setupCall: either already resolved (precompile or failure),
    /// or ready to launch a sub-frame.
    pub const CallSetupResult = union(enum) {
        /// Pre-execution failure (depth, value transfer, etc.): all gas returned.
        failed: CallResult,
        /// Precompile executed synchronously: result is final.
        precompile: CallResult,
        /// Sub-frame needed: checkpoint taken, code loaded, delegation_gas computed.
        ready: struct {
            checkpoint: JournalCheckpoint,
            code: bytecode_mod.Bytecode,
            delegation_gas: u64,
        },
    };

    /// Result of setupCreate: either already resolved (failure) or ready to launch.
    pub const CreateSetupResult = union(enum) {
        failed: CreateResult,
        ready: struct {
            checkpoint: JournalCheckpoint,
            new_addr: primitives.Address,
        },
    };

    /// Performs all pre-execution steps for a CALL:
    ///   1. Depth check
    ///   2. Precompile dispatch (synchronous)
    ///   3. Code load + EIP-7702 delegation
    ///   4. Journal checkpoint
    ///   5. Value transfer
    /// Returns .ready with checkpoint+code on success, or .precompile/.failed with a
    /// final CallResult. The caller (frame runner) is responsible for finalizing via
    /// finalizeCall() after the sub-frame completes.
    pub fn setupCall(self: *Host, inputs: CallInputs, frame_depth: usize) CallSetupResult {
        const MAX_CALL_DEPTH = 1024;

        // 1. Depth check
        if (frame_depth >= MAX_CALL_DEPTH) {
            return .{ .failed = CallResult.preExecFailure(inputs.gas_limit) };
        }

        // 2. Precompile dispatch
        if (self.precompiles) |pcs| {
            if (pcs.get(inputs.callee)) |pc| {
                const cp = self.ctx.journaled_state.getCheckpoint();
                if (inputs.value > 0 and inputs.scheme != .delegatecall) {
                    const xfer_err = self.ctx.journaled_state.transfer(inputs.caller, inputs.target, inputs.value) catch {
                        self.ctx.journaled_state.checkpointRevert(cp);
                        return .{ .precompile = CallResult.preExecFailure(inputs.gas_limit) };
                    };
                    if (xfer_err != null) {
                        self.ctx.journaled_state.checkpointRevert(cp);
                        return .{ .precompile = CallResult.preExecFailure(inputs.gas_limit) };
                    }
                    // EIP-7708 (Amsterdam+): emit Transfer log for ETH sent to precompile.
                    if (primitives.isEnabledIn(self.ctx.cfg.spec, .amsterdam) and
                        !std.mem.eql(u8, &inputs.caller, &inputs.target))
                    {
                        self.ctx.journaled_state.emitTransferLog(inputs.caller, inputs.target, inputs.value);
                    }
                }
                const pc_result = pc.execute(inputs.data, inputs.gas_limit);
                switch (pc_result) {
                    .success => |out| {
                        if (out.reverted) {
                            self.ctx.journaled_state.checkpointRevert(cp);
                            return .{ .precompile = .{ .success = false, .return_data = out.bytes, .gas_used = inputs.gas_limit, .gas_remaining = 0, .gas_refunded = 0, .delegation_gas = 0, .state_gas_used = 0, .state_gas_remaining = inputs.reservoir } };
                        }
                        self.ctx.journaled_state.checkpointCommit();
                        // Touch the callee so it appears in post-state for pre-EIP-161 forks
                        // (Frontier/Homestead). The account was already loaded into evm_state by
                        // accountInfo() in the CALL opcode handler. For EIP-161+ forks, the
                        // empty account will be cleaned up by the state-clear logic anyway.
                        self.ctx.journaled_state.touchAccount(inputs.callee);
                        return .{ .precompile = .{ .success = true, .return_data = out.bytes, .gas_used = out.gas_used, .gas_remaining = inputs.gas_limit - out.gas_used, .gas_refunded = 0, .delegation_gas = 0, .state_gas_used = 0, .state_gas_remaining = inputs.reservoir } };
                    },
                    .err => {
                        self.ctx.journaled_state.checkpointRevert(cp);
                        return .{ .precompile = CallResult.failure(inputs.gas_limit) };
                    },
                }
            }
        }

        // 3. Load callee code + EIP-7702 delegation
        const callee_load = self.ctx.journaled_state.loadAccountWithCode(inputs.callee) catch {
            return .{ .failed = CallResult.failure(inputs.gas_limit) };
        };
        const callee_acc = callee_load.data;
        var code = if (callee_acc.info.code) |c| c else bytecode_mod.Bytecode.new();
        var delegation_gas: u64 = 0;
        if (code.isEip7702()) {
            const delegation_addr = code.eip7702.address;
            if (self.ctx.journaled_state.loadAccountWithCode(delegation_addr)) |del_load| {
                delegation_gas = if (del_load.is_cold)
                    gas_costs.COLD_ACCOUNT_ACCESS
                else
                    gas_costs.WARM_ACCOUNT_ACCESS;
                code = if (del_load.data.info.code) |del_code| del_code else bytecode_mod.Bytecode.new();
            } else |_| {
                code = bytecode_mod.Bytecode.new();
            }
        }

        // 4. Checkpoint
        const checkpoint = self.ctx.journaled_state.getCheckpoint();
        // Notify db fallback that a new frame has opened.
        self.ctx.journaled_state.database.snapshotFrame();

        // 5. Value transfer
        if (inputs.value > 0 and inputs.scheme != .delegatecall) {
            const transfer_err = self.ctx.journaled_state.transfer(inputs.caller, inputs.target, inputs.value) catch {
                self.ctx.journaled_state.checkpointRevert(checkpoint);
                return .{ .failed = CallResult.preExecFailure(inputs.gas_limit) };
            };
            if (transfer_err != null) {
                self.ctx.journaled_state.checkpointRevert(checkpoint);
                return .{ .failed = CallResult.preExecFailure(inputs.gas_limit) };
            }
            // EIP-7708 (Amsterdam+): emit Transfer log for ETH sent via CALL.
            if (primitives.isEnabledIn(self.ctx.cfg.spec, .amsterdam) and
                !std.mem.eql(u8, &inputs.caller, &inputs.target))
            {
                self.ctx.journaled_state.emitTransferLog(inputs.caller, inputs.target, inputs.value);
            }
        }

        return .{ .ready = .{ .checkpoint = checkpoint, .code = code, .delegation_gas = delegation_gas } };
    }

    /// Commits or reverts a call checkpoint and builds the final CallResult.
    /// Called by the frame runner after the sub-frame interpreter finishes.
    pub fn finalizeCall(
        self: *Host,
        checkpoint: JournalCheckpoint,
        result: InstructionResult,
        gas_limit: u64,
        gas_remaining: u64,
        gas_refunded: i64,
        return_data: []const u8,
    ) CallResult {
        if (result.isSuccess()) {
            self.ctx.journaled_state.checkpointCommit();
            self.ctx.journaled_state.database.commitFrame();
        } else {
            self.ctx.journaled_state.checkpointRevert(checkpoint);
            self.ctx.journaled_state.database.revertFrame();
        }
        const gas_rem: u64 = if (result.isSuccess() or result == .revert) gas_remaining else 0;
        const gas_used = if (gas_limit > gas_rem) gas_limit - gas_rem else 0;
        const refunded: i64 = if (result.isSuccess()) gas_refunded else 0;
        return .{
            .success = result.isSuccess(),
            .return_data = if (result.isSuccess() or result == .revert) return_data else &[_]u8{},
            .gas_used = gas_used,
            .gas_remaining = gas_rem,
            .gas_refunded = refunded,
            .delegation_gas = 0,
            .state_gas_used = 0, // set by frame runner after finalizeCall
            .state_gas_remaining = 0, // set by frame runner after finalizeCall
        };
    }

    /// Performs all pre-execution steps for a CREATE/CREATE2.
    /// On success returns .ready with {checkpoint, new_addr}.
    pub fn setupCreate(
        self: *Host,
        caller: primitives.Address,
        value: primitives.U256,
        init_code: []const u8,
        gas_limit: u64,
        is_create2: bool,
        salt: primitives.U256,
        skip_nonce_bump: bool,
        frame_depth: usize,
        /// EIP-8037 (Amsterdam+): true for CREATE/CREATE2 opcode; false for TX-level create.
        /// When true, new-account state gas (112*cpsb) is charged on late failures (after
        /// the target address is loaded) even if the CREATE ultimately fails.
        is_opcode_create: bool,
    ) CreateSetupResult {
        const MAX_CALL_DEPTH = 1024;
        const js = &self.ctx.journaled_state;
        const spec_id = js.inner.spec;

        if (frame_depth >= MAX_CALL_DEPTH) return .{ .failed = CreateResult.preExecFailure(gas_limit) };

        if (primitives.isEnabledIn(spec_id, .shanghai)) {
            const max_initcode: usize = if (primitives.isEnabledIn(spec_id, .amsterdam))
                primitives.AMSTERDAM_MAX_INITCODE_SIZE
            else
                primitives.MAX_INITCODE_SIZE;
            if (init_code.len > max_initcode) return .{ .failed = CreateResult.preExecFailure(gas_limit) };
        }

        // Pre-Amsterdam: check balance BEFORE nonce bump (original EVM behavior).
        // The caller nonce must not be bumped when CREATE fails due to insufficient balance.
        if (!primitives.isEnabledIn(spec_id, .amsterdam) and value > 0) {
            const acct = js.inner.evm_state.getPtr(caller) orelse
                return .{ .failed = CreateResult.preExecFailure(gas_limit) };
            if (acct.info.balance < value)
                return .{ .failed = CreateResult.preExecFailure(gas_limit) };
        }

        const caller_acc = js.inner.evm_state.getPtr(caller) orelse return .{ .failed = CreateResult.preExecFailure(gas_limit) };
        // EIP-8037 (Amsterdam+): take a checkpoint before nonce bump so we can revert
        // the nonce (and later loadAccount) on balance failure — caller nonce must not be
        // bumped when CREATE fails due to insufficient balance.
        const pre_bump_checkpoint = if (is_opcode_create and primitives.isEnabledIn(spec_id, .amsterdam))
            js.getCheckpoint()
        else
            @as(@TypeOf(js.getCheckpoint()), undefined);
        const caller_nonce: u64 = if (skip_nonce_bump)
            caller_acc.info.nonce -| 1
        else blk: {
            const n = caller_acc.info.nonce;
            if (n == std.math.maxInt(u64)) return .{ .failed = CreateResult.preExecFailure(gas_limit) };
            caller_acc.info.nonce = n + 1;
            js.nonceBumpJournalEntry(caller);
            break :blk n;
        };

        const new_addr: primitives.Address = if (is_create2) blk: {
            var init_hash: [32]u8 = undefined;
            std.crypto.hash.sha3.Keccak256.hash(init_code, &init_hash, .{});
            break :blk create2Address(caller, salt, init_hash);
        } else createAddress(caller, caller_nonce);

        _ = js.loadAccount(new_addr) catch return .{ .failed = CreateResult.preExecFailure(gas_limit) };
        // Record whether the CREATE target was a non-existent (empty) account.
        // Used below to un-track it from the EIP-7928 BAL when CREATE fails before init
        // code: a phantom CREATE target (no pre-state, no ETH received) should not appear
        // in the BAL, whereas a target with pre-existing state (nonce/code/balance) should.
        const new_addr_was_nonexistent = if (js.inner.evm_state.get(new_addr)) |na|
            na.status.loaded_as_not_existing
        else
            true;

        // EIP-8037 (Amsterdam+): new-account state gas is charged by the opcode (opCreate/opCreate2)
        // BEFORE setupCreate is called, so no additional state gas here on failures.
        // All forwarded regular gas is returned on balance/nonce/collision failures.

        // Balance check.
        // EIP-8037: new-account state gas was already charged by the opcode.
        // On balance failure, return all forwarded gas; revert the nonce bump for Amsterdam.
        if (value > 0) {
            const caller_acct = js.inner.evm_state.getPtr(caller) orelse {
                if (is_opcode_create and primitives.isEnabledIn(spec_id, .amsterdam))
                    js.checkpointRevert(pre_bump_checkpoint);
                // Phantom CREATE target: untrack so it doesn't appear in the EIP-7928 BAL.
                if (new_addr_was_nonexistent) js.database.untrackAddress(new_addr);
                return .{ .failed = CreateResult.preExecFailure(gas_limit) };
            };
            if (caller_acct.info.balance < value) {
                if (is_opcode_create and primitives.isEnabledIn(spec_id, .amsterdam))
                    js.checkpointRevert(pre_bump_checkpoint);
                // Phantom CREATE target: untrack so it doesn't appear in the EIP-7928 BAL.
                if (new_addr_was_nonexistent) js.database.untrackAddress(new_addr);
                return .{ .failed = CreateResult.preExecFailure(gas_limit) };
            }
        }

        // Address collision: storage already exists at the target address.
        // Pre-Amsterdam: consume all forwarded gas (original behavior).
        // Amsterdam+: consume all gas per EELS generic_create().
        if (js.inner.evm_state.get(new_addr)) |acct| {
            var slot_it = acct.storage.valueIterator();
            while (slot_it.next()) |slot| {
                if (slot.presentValue() != 0) {
                    return .{ .failed = CreateResult.failure() };
                }
            }
        }
        {
            // Skip DB storage check if the account's storage was explicitly wiped
            // (e.g. by SELFDESTRUCT in a previous tx). In that case, the DB still
            // holds the old pre-selfdestruct slots which must not cause a collision.
            const storage_wiped = if (js.inner.evm_state.get(new_addr)) |acct| acct.status.storage_wiped else false;
            if (!storage_wiped) {
                var db_it = js.database.storage_map.iterator();
                while (db_it.next()) |entry| {
                    if (std.mem.eql(u8, &entry.key_ptr.@"0", &new_addr) and entry.value_ptr.* != 0) {
                        return .{ .failed = CreateResult.failure() };
                    }
                }
            }
        }

        const checkpoint = js.createAccountCheckpoint(caller, new_addr, value, spec_id) catch {
            // createAccountCheckpoint fails on nonce/code collision or balance error.
            // In all cases (pre- and post-Amsterdam), consume all forwarded gas.
            return .{ .failed = CreateResult.failure() };
        };
        // Notify db fallback that a new CREATE frame has opened.
        js.database.snapshotFrame();

        // EIP-7708 (Amsterdam+): emit Transfer log for ETH sent to the new contract.
        if (value > 0 and primitives.isEnabledIn(spec_id, .amsterdam)) {
            js.emitTransferLog(caller, new_addr, value);
        }

        return .{ .ready = .{ .checkpoint = checkpoint, .new_addr = new_addr } };
    }

    /// Validates deployed code, applies deposit gas, stores bytecode, and commits/reverts.
    /// Called by the frame runner after the init-code sub-frame finishes.
    /// `gas_reservoir`: EIP-8037 — child's remaining reservoir at time of finalization.
    pub fn finalizeCreate(
        self: *Host,
        checkpoint: JournalCheckpoint,
        new_addr: primitives.Address,
        result: InstructionResult,
        gas_remaining: u64,
        gas_refunded: i64,
        return_data: []const u8,
        spec_id: primitives.SpecId,
        /// EIP-8037: true when called from CREATE/CREATE2 opcode. false for TX-level create.
        is_opcode_create: bool,
        /// EIP-8037: child's state gas reservoir remaining. Used for code-deposit state gas.
        gas_reservoir: u64,
    ) CreateResult {
        const MAX_CODE_SIZE: usize = if (primitives.isEnabledIn(spec_id, .amsterdam)) primitives.AMSTERDAM_MAX_CODE_SIZE else primitives.MAX_CODE_SIZE;
        const js = &self.ctx.journaled_state;

        if (!result.isSuccess()) {
            js.checkpointRevert(checkpoint);
            js.database.revertFrame();
            const gas_rem = if (result == .revert) gas_remaining else @as(u64, 0);
            const rd = if (result == .revert) return_data else &[_]u8{};
            // On failure: all state gas (used + remaining reservoir) returned to parent via frame runner.
            return .{ .success = false, .is_revert = (result == .revert), .address = [_]u8{0} ** 20, .gas_remaining = gas_rem, .return_data = rd, .gas_refunded = 0, .state_gas_used = 0, .state_gas_remaining = gas_reservoir };
        }

        const deployed_raw = return_data;
        if (deployed_raw.len > MAX_CODE_SIZE) {
            js.checkpointRevert(checkpoint);
            js.database.revertFrame();
            // Code-too-large is an ExceptionalHalt: all remaining regular gas is consumed.
            // State gas reservoir is preserved and returned to parent.
            return .{ .success = false, .is_revert = false, .address = [_]u8{0} ** 20, .gas_remaining = 0, .return_data = &[_]u8{}, .gas_refunded = 0, .state_gas_used = 0, .state_gas_remaining = gas_reservoir };
        }
        if (primitives.isEnabledIn(spec_id, .london)) {
            if (deployed_raw.len > 0 and deployed_raw[0] == 0xEF) {
                js.checkpointRevert(checkpoint);
                js.database.revertFrame();
                // InvalidContractPrefix (0xEF) is an ExceptionalHalt: all remaining regular gas consumed.
                // State gas reservoir is preserved and returned to parent.
                return .{ .success = false, .is_revert = false, .address = [_]u8{0} ** 20, .gas_remaining = 0, .return_data = &[_]u8{}, .gas_refunded = 0, .state_gas_used = 0, .state_gas_remaining = gas_reservoir };
            }
        }

        // EIP-8037 (Amsterdam+): code deposit regular cost = G_KECCAK256WORD per word.
        // Code deposit STATE cost = code_len * cpsb drawn from child's reservoir (spilling to remaining).
        var gas_after_deposit: u64 = undefined;
        var remaining_reservoir = gas_reservoir;
        var code_deposit_state_gas: u64 = 0;
        if (primitives.isEnabledIn(spec_id, .amsterdam)) {
            const code_words = (deployed_raw.len + 31) / 32;
            const regular_deposit = gas_costs.G_KECCAK256WORD * @as(u64, code_words);
            if (gas_remaining < regular_deposit) {
                js.checkpointRevert(checkpoint);
                js.database.revertFrame();
                return .{ .success = false, .is_revert = false, .address = [_]u8{0} ** 20, .gas_remaining = 0, .return_data = &[_]u8{}, .gas_refunded = 0, .state_gas_used = 0, .state_gas_remaining = remaining_reservoir };
            }
            var gas_after_regular = gas_remaining - regular_deposit;
            const cpsb = gas_costs.costPerStateByte(self.ctx.block.gas_limit);
            // EIP-8037: code deposit state gas = code_len * cpsb.
            // New-account bytes charged separately: by opcode (for opcode creates) or intrinsic (TX creates).
            code_deposit_state_gas = @as(u64, deployed_raw.len) * cpsb;
            if (code_deposit_state_gas > 0) {
                if (remaining_reservoir >= code_deposit_state_gas) {
                    remaining_reservoir -= code_deposit_state_gas;
                } else if (remaining_reservoir + gas_after_regular >= code_deposit_state_gas) {
                    const spill = code_deposit_state_gas - remaining_reservoir;
                    remaining_reservoir = 0;
                    gas_after_regular -= spill;
                } else {
                    // OOG on code deposit state gas — failure, preserve reservoir for return.
                    js.checkpointRevert(checkpoint);
                    js.database.revertFrame();
                    return .{ .success = false, .is_revert = false, .address = [_]u8{0} ** 20, .gas_remaining = 0, .return_data = &[_]u8{}, .gas_refunded = 0, .state_gas_used = 0, .state_gas_remaining = remaining_reservoir };
                }
            }
            _ = is_opcode_create; // new_account bytes handled by opcode
            gas_after_deposit = gas_after_regular;
        } else {
            const deposit_cost = gas_costs.G_CODEDEPOSIT * @as(u64, @intCast(deployed_raw.len));
            if (gas_remaining < deposit_cost) {
                if (primitives.isEnabledIn(spec_id, .homestead)) {
                    js.checkpointRevert(checkpoint);
                    js.database.revertFrame();
                    return CreateResult.failure();
                } else {
                    js.checkpointCommit();
                    js.database.commitFrame();
                    return .{ .success = true, .is_revert = false, .address = new_addr, .gas_remaining = gas_remaining, .return_data = &[_]u8{}, .gas_refunded = gas_refunded, .state_gas_used = 0, .state_gas_remaining = 0 };
                }
            }
            gas_after_deposit = gas_remaining - deposit_cost;
        }

        if (deployed_raw.len > 0) {
            const deployed_copy = alloc_mod.get().dupe(u8, deployed_raw) catch {
                js.checkpointRevert(checkpoint);
                js.database.revertFrame();
                return CreateResult.failure();
            };
            var code_hash: [32]u8 = undefined;
            std.crypto.hash.sha3.Keccak256.hash(deployed_copy, &code_hash, .{});
            const bc = bytecode_mod.Bytecode.newRaw(deployed_copy);
            js.setCodeWithHash(new_addr, bc, code_hash);
        }

        js.checkpointCommit();
        js.database.commitFrame();
        return .{ .success = true, .is_revert = false, .address = new_addr, .gas_remaining = gas_after_deposit, .return_data = &[_]u8{}, .gas_refunded = gas_refunded, .state_gas_used = code_deposit_state_gas, .state_gas_remaining = remaining_reservoir };
    }

    // -----------------------------------------------------------------------
    // Synchronous helpers (used by tests and call_integration_tests)
    // -----------------------------------------------------------------------

    /// Synchronous CALL — runs a complete sub-frame inline. For use in tests and
    /// simple callers that do not need the iterative frame runner.
    pub fn call(self: *Host, inputs: CallInputs) CallResult {
        const setup = self.setupCall(inputs, 0);
        switch (setup) {
            .failed => |r| return r,
            .precompile => |r| return r,
            .ready => |s| {
                const spec_id = self.ctx.journaled_state.inner.spec;
                var sub_interp = Interpreter.new(
                    Memory.new(),
                    ExtBytecode.new(s.code),
                    InputsImpl.new(inputs.caller, inputs.target, inputs.value, @constCast(inputs.data), inputs.gas_limit, inputs.scheme, inputs.is_static, 1),
                    inputs.is_static,
                    spec_id,
                    inputs.gas_limit,
                );
                sub_interp.gas.reservoir = inputs.reservoir;
                defer sub_interp.deinit();
                const table = protocol_schedule.makeInstructionTable(spec_id);
                _ = sub_interp.runWithHost(&table, self);
                const rd: []const u8 = if (sub_interp.result.isSuccess() or sub_interp.result == .revert)
                    sub_interp.return_data.data
                else
                    &[_]u8{};
                var rd_buf: std.ArrayList(u8) = .{};
                defer rd_buf.deinit(alloc_mod.get());
                rd_buf.appendSlice(alloc_mod.get(), rd) catch {};
                var call_result = self.finalizeCall(s.checkpoint, sub_interp.result, inputs.gas_limit, sub_interp.gas.remaining, sub_interp.gas.refunded, rd_buf.items);
                const sub_state_gas = sub_interp.gas.state_gas_used;
                const sub_reservoir = sub_interp.gas.reservoir;
                if (call_result.success) {
                    call_result.state_gas_used = sub_state_gas;
                    call_result.state_gas_remaining = sub_reservoir;
                } else {
                    call_result.state_gas_used = 0;
                    call_result.state_gas_remaining = sub_state_gas + sub_reservoir;
                }
                return call_result;
            },
        }
    }

    /// Synchronous CREATE/CREATE2 — runs a complete init-code frame inline. For tests only.
    pub fn create(
        self: *Host,
        caller: primitives.Address,
        value: primitives.U256,
        init_code: []const u8,
        gas_limit: u64,
        is_create2: bool,
        salt: primitives.U256,
        skip_nonce_bump: bool,
    ) CreateResult {
        const setup = self.setupCreate(caller, value, init_code, gas_limit, is_create2, salt, skip_nonce_bump, 0, true);
        switch (setup) {
            .failed => |r| return r,
            .ready => |s| {
                const spec_id = self.ctx.journaled_state.inner.spec;
                const init_bytecode = bytecode_mod.Bytecode.newRaw(init_code);
                var sub_interp = Interpreter.new(
                    Memory.new(),
                    ExtBytecode.newOwned(init_bytecode),
                    InputsImpl.new(caller, s.new_addr, value, @constCast(&[_]u8{}), gas_limit, .call, false, 1),
                    false,
                    spec_id,
                    gas_limit,
                );
                defer sub_interp.deinit();
                const table = protocol_schedule.makeInstructionTable(spec_id);
                _ = sub_interp.runWithHost(&table, self);
                const rd: []const u8 = if (sub_interp.result.isSuccess() or sub_interp.result == .revert)
                    sub_interp.return_data.data
                else
                    &[_]u8{};
                var rd_buf: std.ArrayList(u8) = .{};
                defer rd_buf.deinit(alloc_mod.get());
                rd_buf.appendSlice(alloc_mod.get(), rd) catch {};
                const sub_state_gas = sub_interp.gas.state_gas_used;
                const sub_reservoir = sub_interp.gas.reservoir;
                var create_result = self.finalizeCreate(s.checkpoint, s.new_addr, sub_interp.result, sub_interp.gas.remaining, sub_interp.gas.refunded, rd_buf.items, spec_id, true, sub_reservoir);
                if (create_result.success) {
                    create_result.state_gas_used += sub_state_gas;
                } else {
                    // On failure: state_gas_remaining already set by finalizeCreate; add sub_state_gas
                    create_result.state_gas_remaining += sub_state_gas;
                }
                return create_result;
            },
        }
    }
};

// ---------------------------------------------------------------------------
// Conversion helpers (exported for use by opcode handlers)
// ---------------------------------------------------------------------------

/// Convert an Address (20 bytes big-endian) to U256
pub fn addressToU256(addr: primitives.Address) primitives.U256 {
    var result: primitives.U256 = 0;
    for (addr) |byte| {
        result = (result << 8) | byte;
    }
    return result;
}

/// Convert U256 to Address (take low 20 bytes)
pub fn u256ToAddress(val: primitives.U256) primitives.Address {
    var addr: primitives.Address = [_]u8{0} ** 20;
    var v = val;
    var i: usize = 20;
    while (i > 0) {
        i -= 1;
        addr[i] = @intCast(v & 0xFF);
        v >>= 8;
    }
    return addr;
}

/// Convert a 32-byte Hash to U256 (big-endian)
pub fn hashToU256(h: primitives.Hash) primitives.U256 {
    var result: primitives.U256 = 0;
    for (h) |byte| {
        result = (result << 8) | byte;
    }
    return result;
}

/// Convert U256 to a 32-byte Hash (big-endian)
pub fn u256ToHash(val: primitives.U256) primitives.Hash {
    var h: primitives.Hash = [_]u8{0} ** 32;
    var v = val;
    var i: usize = 32;
    while (i > 0) {
        i -= 1;
        h[i] = @intCast(v & 0xFF);
        v >>= 8;
    }
    return h;
}

/// Derive CREATE contract address: keccak256(rlp([sender, nonce]))[12:]
pub fn createAddress(sender: primitives.Address, nonce: u64) primitives.Address {
    // Build RLP encoding of [sender, nonce]
    // RLP(address): 0x94 (= 0x80+20) prefix + 20 bytes
    // RLP(nonce): 0x80 for zero, single byte for 1-127, length-prefixed for >= 128
    // List header: 0xC0 + content_len
    var buf: [30]u8 = undefined; // 1 + 20 + 1..9 = at most 30 bytes of content
    var pos: usize = 0;
    buf[pos] = 0x94;
    pos += 1;
    @memcpy(buf[pos .. pos + 20], &sender);
    pos += 20;
    if (nonce == 0) {
        buf[pos] = 0x80;
        pos += 1;
    } else if (nonce < 0x80) {
        buf[pos] = @intCast(nonce);
        pos += 1;
    } else {
        // Encode nonce as minimal big-endian bytes
        var tmp: [8]u8 = undefined;
        var len: usize = 0;
        var n = nonce;
        while (n > 0) : (n >>= 8) {
            len += 1;
        }
        var m = nonce;
        var idx: usize = len;
        while (idx > 0) : (idx -= 1) {
            tmp[idx - 1] = @intCast(m & 0xFF);
            m >>= 8;
        }
        buf[pos] = @intCast(0x80 + len);
        pos += 1;
        @memcpy(buf[pos .. pos + len], tmp[0..len]);
        pos += len;
    }
    // List prefix: 0xC0 + content_len
    var rlp: [31]u8 = undefined;
    rlp[0] = @intCast(0xC0 + pos);
    @memcpy(rlp[1 .. 1 + pos], buf[0..pos]);
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha3.Keccak256.hash(rlp[0 .. 1 + pos], &hash, .{});
    var addr: primitives.Address = undefined;
    @memcpy(&addr, hash[12..32]);
    return addr;
}

/// Derive CREATE2 contract address: keccak256(0xff ++ sender ++ salt ++ keccak256(init_code))[12:]
pub fn create2Address(sender: primitives.Address, salt: primitives.U256, init_code_hash: [32]u8) primitives.Address {
    var preimage: [85]u8 = undefined; // 1 + 20 + 32 + 32
    preimage[0] = 0xFF;
    @memcpy(preimage[1..21], &sender);
    // Encode salt as 32-byte big-endian
    var salt_bytes: [32]u8 = undefined;
    var s = salt;
    var i: usize = 32;
    while (i > 0) : (i -= 1) {
        salt_bytes[i - 1] = @intCast(s & 0xFF);
        s >>= 8;
    }
    @memcpy(preimage[21..53], &salt_bytes);
    @memcpy(preimage[53..85], &init_code_hash);
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha3.Keccak256.hash(&preimage, &hash, .{});
    var addr: primitives.Address = undefined;
    @memcpy(&addr, hash[12..32]);
    return addr;
}
