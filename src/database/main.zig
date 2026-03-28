const std = @import("std");
const primitives = @import("primitives");
const state = @import("state");
const bytecode = @import("bytecode");

/// Database interface and implementations for the EVM.
/// Address with all 0xff..ff in it. Used for testing.
pub const FFADDRESS: primitives.Address = [_]u8{0xff} ** 20;
/// BENCH_TARGET address
pub const BENCH_TARGET: primitives.Address = FFADDRESS;
/// Common test balance used for benchmark addresses
pub const TEST_BALANCE: primitives.U256 = primitives.U256{10_000_000_000_000_000};
/// BENCH_TARGET_BALANCE balance
pub const BENCH_TARGET_BALANCE: primitives.U256 = TEST_BALANCE;
/// Address with all 0xee..ee in it. Used for testing.
pub const EEADDRESS: primitives.Address = [_]u8{0xee} ** 20;
/// BENCH_CALLER address
pub const BENCH_CALLER: primitives.Address = EEADDRESS;
/// BENCH_CALLER_BALANCE balance
pub const BENCH_CALLER_BALANCE: primitives.U256 = TEST_BALANCE;

/// Database error marker
pub fn DBErrorMarker(comptime T: type) type {
    return struct {
        const Self = @This();
        pub fn isDBError(_: T) bool {
            return true;
        }
    };
}

/// EVM database interface.
pub fn Database(comptime Self: type) type {
    return struct {
        const DatabaseTrait = @This();

        /// Gets basic account information.
        pub fn basic(self: *Self, address: primitives.Address) !?state.AccountInfo {
            return self.basic(address);
        }

        /// Gets account code by its hash.
        pub fn codeByHash(self: *Self, code_hash: primitives.Hash) !bytecode.Bytecode {
            return self.codeByHash(code_hash);
        }

        /// Gets storage value of address at index.
        pub fn storage(self: *Self, address: primitives.Address, index: primitives.StorageKey) !primitives.StorageValue {
            return self.storage_map(address, index);
        }

        /// Gets block hash by block number.
        pub fn blockHash(self: *Self, number: u64) !primitives.Hash {
            return self.blockHash(number);
        }
    };
}

/// EVM database commit interface.
pub fn DatabaseCommit(comptime Self: type) type {
    return struct {
        const DatabaseCommitTrait = @This();

        /// Commit changes to the database.
        pub fn commit(self: *Self, changes: std.HashMap(primitives.Address, state.Account, std.hash_map.default_hash_fn(primitives.Address), std.hash_map.default_eql_fn(primitives.Address))) void {
            return self.commit(changes);
        }
    };
}

/// EVM database interface with immutable reference.
/// Contains the same methods as Database, but with immutable receivers instead of mutable ones.
pub fn DatabaseRef(comptime Self: type) type {
    return struct {
        const DatabaseRefTrait = @This();

        /// Gets basic account information.
        pub fn basicRef(self: Self, address: primitives.Address) !?state.AccountInfo {
            return self.basicRef(address);
        }

        /// Gets account code by its hash.
        pub fn codeByHashRef(self: Self, code_hash: primitives.Hash) !bytecode.Bytecode {
            return self.codeByHashRef(code_hash);
        }

        /// Gets storage value of address at index.
        pub fn storageRef(self: Self, address: primitives.Address, index: primitives.StorageKey) !primitives.StorageValue {
            return self.storage_mapRef(address, index);
        }

        /// Gets block hash by block number.
        pub fn blockHashRef(self: Self, number: u64) !primitives.Hash {
            return self.blockHashRef(number);
        }
    };
}

/// Wraps a DatabaseRef to provide a Database implementation.
pub fn WrapDatabaseRef(comptime T: type) type {
    return struct {
        inner: T,

        const Self = @This();

        pub fn init(inner: T) Self {
            return Self{ .inner = inner };
        }

        pub fn basic(self: *Self, address: primitives.Address) !?state.AccountInfo {
            return self.inner.basicRef(address);
        }

        pub fn codeByHash(self: *Self, code_hash: primitives.Hash) !bytecode.Bytecode {
            return self.inner.codeByHashRef(code_hash);
        }

        pub fn storage(self: *Self, address: primitives.Address, index: primitives.StorageKey) !primitives.StorageValue {
            return self.inner.storageRef(address, index);
        }

        pub fn blockHash(self: *Self, number: u64) !primitives.Hash {
            return self.inner.blockHashRef(number);
        }

        pub fn basicRef(self: Self, address: primitives.Address) !?state.AccountInfo {
            return self.inner.basicRef(address);
        }

        pub fn codeByHashRef(self: Self, code_hash: primitives.Hash) !bytecode.Bytecode {
            return self.inner.codeByHashRef(code_hash);
        }

        pub fn storageRef(self: Self, address: primitives.Address, index: primitives.StorageKey) !primitives.StorageValue {
            return self.inner.storageRef(address, index);
        }

        pub fn blockHashRef(self: Self, number: u64) !primitives.Hash {
            return self.inner.blockHashRef(number);
        }
    };
}

/// Empty database implementation for testing and development.
pub const EmptyDB = struct {
    const Self = @This();

    pub fn basic(self: *Self, address: primitives.Address) !?state.AccountInfo {
        _ = self;
        _ = address;
        return null;
    }

    pub fn codeByHash(self: *Self, code_hash: primitives.Hash) !bytecode.Bytecode {
        _ = self;
        _ = code_hash;
        return bytecode.Bytecode.new();
    }

    pub fn storage(self: *Self, address: primitives.Address, index: primitives.StorageKey) !primitives.StorageValue {
        _ = self;
        _ = address;
        _ = index;
        return @as(primitives.StorageValue, 0);
    }

    pub fn blockHash(self: *Self, number: u64) !primitives.Hash {
        _ = self;
        _ = number;
        return [_]u8{0} ** 32;
    }

    pub fn basicRef(self: Self, address: primitives.Address) !?state.AccountInfo {
        _ = self;
        _ = address;
        return null;
    }

    pub fn codeByHashRef(self: Self, code_hash: primitives.Hash) !bytecode.Bytecode {
        _ = self;
        _ = code_hash;
        return bytecode.Bytecode.new();
    }

    pub fn storageRef(self: Self, address: primitives.Address, index: primitives.StorageKey) !primitives.StorageValue {
        _ = self;
        _ = address;
        _ = index;
        return @as(primitives.StorageValue, 0);
    }

    pub fn blockHashRef(self: Self, number: u64) !primitives.Hash {
        _ = self;
        _ = number;
        return [_]u8{0} ** 32;
    }
};

/// Storage key context for HashMap
const StorageKeyContext = struct {
    pub fn hash(ctx: @This(), key: struct { primitives.Address, primitives.StorageKey }) u64 {
        _ = ctx;
        var hasher = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hasher, key[0]);
        std.hash.autoHash(&hasher, key[1]);
        return hasher.final();
    }
    pub fn eql(ctx: @This(), a: struct { primitives.Address, primitives.StorageKey }, b: struct { primitives.Address, primitives.StorageKey }) bool {
        _ = ctx;
        return std.mem.eql(u8, &a[0], &b[0]) and a[1] == b[1];
    }
};

/// Vtable for an optional fallback database on InMemoryDB.
/// When a lookup misses the in-memory maps the corresponding fallback function
/// is called (if set).  Set `InMemoryDB.fallback` before execution to wire a
/// stateless witness database.
pub const FallbackFns = struct {
    ctx: *anyopaque,
    basic: *const fn (*anyopaque, primitives.Address) anyerror!?state.AccountInfo,
    code_by_hash: *const fn (*anyopaque, primitives.Hash) anyerror!bytecode.Bytecode,
    storage: *const fn (*anyopaque, primitives.Address, primitives.StorageKey) anyerror!primitives.StorageValue,
    block_hash: *const fn (*anyopaque, u64) anyerror!primitives.Hash,
    /// Called when a transaction commits its state (success path).
    /// The fallback may flush any per-tx pending tracking to permanent state.
    commit_tx: ?*const fn (*anyopaque) void = null,
    /// Called when a transaction is discarded (revert / invalid tx path).
    /// The fallback should drop any per-tx pending tracking.
    discard_tx: ?*const fn (*anyopaque) void = null,
    /// Called when a new execution frame (CALL/CREATE) opens a journal checkpoint.
    /// The fallback should push a new frame level for per-frame pending tracking.
    snapshot_frame: ?*const fn (*anyopaque) void = null,
    /// Called when an execution frame commits its journal checkpoint successfully.
    /// The fallback should merge the current frame's pending into the parent frame.
    commit_frame: ?*const fn (*anyopaque) void = null,
    /// Called when an execution frame reverts its journal checkpoint.
    /// The fallback should discard all pending accesses from the current frame.
    revert_frame: ?*const fn (*anyopaque) void = null,
    /// Called to un-record a pending address access (e.g., CALL loaded address for
    /// gas calculation but then went OOG before the call executed).
    /// Only removes the address if it was not already committed to the permanent log.
    untrack_address: ?*const fn (*anyopaque, primitives.Address) void = null,
    /// Called to force-add an address to the current-tx access log even when its
    /// account state is not in the witness (e.g., EIP-7702 delegation targets).
    force_track_address: ?*const fn (*anyopaque, primitives.Address) void = null,
    /// Called for each storage slot whose present_value differs from original_value,
    /// BEFORE commitTx() resets original_value. Allows the fallback to track cross-tx
    /// intermediate writes for EIP-7928 BAL validation (storageChanges vs storageReads).
    /// `committed_value` is the value being committed (present_value at commit time).
    pre_commit_tx_slot: ?*const fn (*anyopaque, primitives.Address, primitives.StorageKey, primitives.StorageValue) void = null,
    /// Called when a storage slot is read from a newly-created account (is_newly_created=true).
    /// The EVM returns 0 for all such reads without consulting the database, so this
    /// lightweight hook lets the fallback (e.g. WitnessDatabase) record the access for
    /// EIP-7928 BAL tracking without performing MPT verification.
    notify_storage_read: ?*const fn (*anyopaque, primitives.Address, primitives.StorageKey) void = null,
};

/// In-memory database implementation.
pub const InMemoryDB = struct {
    accounts: std.AutoHashMap(primitives.Address, state.AccountInfo),
    code: std.AutoHashMap(primitives.Hash, bytecode.Bytecode),
    storage_map: std.HashMap(struct { primitives.Address, primitives.StorageKey }, primitives.StorageValue, StorageKeyContext, std.hash_map.default_max_load_percentage),
    block_hashes: std.AutoHashMap(u64, primitives.Hash),
    /// Optional fallback: called on cache miss for account/storage/code/blockHash.
    fallback: ?FallbackFns = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .accounts = std.AutoHashMap(primitives.Address, state.AccountInfo).init(allocator),
            .code = std.AutoHashMap(primitives.Hash, bytecode.Bytecode).init(allocator),
            .storage_map = std.HashMap(struct { primitives.Address, primitives.StorageKey }, primitives.StorageValue, StorageKeyContext, std.hash_map.default_max_load_percentage).init(allocator),
            .block_hashes = std.AutoHashMap(u64, primitives.Hash).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.accounts.deinit();
        self.code.deinit();
        self.storage_map.deinit();
        self.block_hashes.deinit();
    }

    pub fn basic(self: *Self, address: primitives.Address) !?state.AccountInfo {
        if (self.accounts.get(address)) |acct| {
            return acct;
        }
        if (self.fallback) |fb| return fb.basic(fb.ctx, address);
        return null;
    }

    pub fn codeByHash(self: *Self, code_hash: primitives.Hash) !bytecode.Bytecode {
        if (self.code.get(code_hash)) |bc| return bc;
        if (self.fallback) |fb| return fb.code_by_hash(fb.ctx, code_hash);
        return bytecode.Bytecode.new();
    }

    pub fn storage(self: *Self, address: primitives.Address, index: primitives.StorageKey) !primitives.StorageValue {
        return self.getStorage(address, index);
    }

    pub fn getStorage(self: *Self, address: primitives.Address, index: primitives.StorageKey) !primitives.StorageValue {
        if (self.storage_map.get(.{ address, index })) |val| return val;
        if (self.fallback) |fb| return fb.storage(fb.ctx, address, index);
        return @as(primitives.StorageValue, 0);
    }

    pub fn blockHash(self: *Self, number: u64) !primitives.Hash {
        if (self.block_hashes.get(number)) |hash| return hash;
        if (self.fallback) |fb| return fb.block_hash(fb.ctx, number);
        return [_]u8{0} ** 32;
    }

    /// Notify the fallback that a transaction committed successfully.
    /// No-op if no fallback or fallback has no commit_tx callback.
    pub fn commitTracking(self: *Self) void {
        if (self.fallback) |fb| if (fb.commit_tx) |f| f(fb.ctx);
    }

    /// Notify the fallback that a transaction was discarded (reverted / invalid).
    /// No-op if no fallback or fallback has no discard_tx callback.
    pub fn discardTracking(self: *Self) void {
        if (self.fallback) |fb| if (fb.discard_tx) |f| f(fb.ctx);
    }

    /// Notify the fallback that a new execution frame opened a journal checkpoint.
    pub fn snapshotFrame(self: *Self) void {
        if (self.fallback) |fb| if (fb.snapshot_frame) |f| f(fb.ctx);
    }

    /// Notify the fallback that the current execution frame committed successfully.
    pub fn commitFrame(self: *Self) void {
        if (self.fallback) |fb| if (fb.commit_frame) |f| f(fb.ctx);
    }

    /// Notify the fallback that the current execution frame was reverted.
    pub fn revertFrame(self: *Self) void {
        if (self.fallback) |fb| if (fb.revert_frame) |f| f(fb.ctx);
    }

    /// Un-record a pending address access in the fallback.
    /// Called when a CALL loaded an address for gas calculation but then went OOG.
    pub fn untrackAddress(self: *Self, address: primitives.Address) void {
        if (self.fallback) |fb| if (fb.untrack_address) |f| f(fb.ctx, address);
    }

    /// Force-add an address to the current-tx access log regardless of witness state.
    /// Called for EIP-7702 delegation targets that execute but are not in the witness.
    pub fn forceTrackAddress(self: *Self, address: primitives.Address) void {
        if (self.fallback) |fb| if (fb.force_track_address) |f| f(fb.ctx, address);
    }

    /// Notify the fallback about a storage slot being committed with a changed value,
    /// called BEFORE commitTx() resets original_value. Only called when present_value
    /// differs from original_value (i.e., the slot was actually modified this tx).
    pub fn notifyStorageSlotCommit(self: *Self, address: primitives.Address, slot: primitives.StorageKey, committed_value: primitives.StorageValue) void {
        if (self.fallback) |fb| if (fb.pre_commit_tx_slot) |f| f(fb.ctx, address, slot, committed_value);
    }

    /// Notify the fallback that a storage slot was read from a newly-created account.
    /// The EVM returns 0 for all such reads without consulting the database; this hook
    /// lets the fallback record the access for EIP-7928 BAL tracking.
    pub fn notifyStorageRead(self: *Self, address: primitives.Address, slot: primitives.StorageKey) void {
        if (self.fallback) |fb| if (fb.notify_storage_read) |f| f(fb.ctx, address, slot);
    }

    pub fn basicRef(self: Self, address: primitives.Address) !?state.AccountInfo {
        return self.accounts.get(address);
    }

    pub fn codeByHashRef(self: Self, code_hash: primitives.Hash) !bytecode.Bytecode {
        return self.code.get(code_hash) orelse bytecode.Bytecode.new();
    }

    pub fn storageRef(self: Self, address: primitives.Address, index: primitives.StorageKey) !primitives.StorageValue {
        return self.storage_map.get(.{ address, index }) orelse @as(primitives.StorageValue, 0);
    }

    pub fn blockHashRef(self: Self, number: u64) !primitives.Hash {
        return self.block_hashes.get(number) orelse [_]u8{0} ** 32;
    }

    pub fn commit(self: *Self, changes: std.HashMap(primitives.Address, state.Account, std.hash_map.default_hash_fn(primitives.Address), std.hash_map.default_eql_fn(primitives.Address))) void {
        var iterator = changes.iterator();
        while (iterator.next()) |entry| {
            const address = entry.key_ptr.*;
            const account = entry.value_ptr.*;

            // Update account info
            self.accounts.put(address, account.info) catch return;

            // Update storage
            var storage_iterator = account.storage.iterator();
            while (storage_iterator.next()) |storage_entry| {
                const key = storage_entry.key_ptr.*;
                const slot = storage_entry.value_ptr.*;
                self.storage_map.put(.{ address, key }, slot.presentValue()) catch return;
            }
        }
    }

    /// Insert an account into the database
    pub fn insertAccount(self: *Self, address: primitives.Address, account_info: state.AccountInfo) !void {
        try self.accounts.put(address, account_info);
    }

    /// Insert code into the database
    pub fn insertCode(self: *Self, code_hash: primitives.Hash, code: bytecode.Bytecode) !void {
        try self.code.put(code_hash, code);
    }

    /// Insert storage value into the database
    pub fn insertStorage(self: *Self, address: primitives.Address, key: primitives.StorageKey, value: primitives.StorageValue) !void {
        try self.storage_map.put(.{ address, key }, value);
    }

    /// Insert block hash into the database
    pub fn insertBlockHash(self: *Self, number: u64, hash: primitives.Hash) !void {
        try self.block_hashes.put(number, hash);
    }
};

/// State management and tracking structures
pub const State = struct {
    accounts: std.AutoHashMap(primitives.Address, state.Account),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .accounts = std.AutoHashMap(primitives.Address, state.Account).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.accounts.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.storage.deinit();
        }
        self.accounts.deinit();
    }

    /// Get account from state
    pub fn getAccount(self: *Self, address: primitives.Address) ?*state.Account {
        return self.accounts.getPtr(address);
    }

    /// Insert or update account in state
    pub fn insertAccount(self: *Self, address: primitives.Address, account: state.Account) !void {
        try self.accounts.put(address, account);
    }

    /// Remove account from state
    pub fn removeAccount(self: *Self, address: primitives.Address) ?state.Account {
        if (self.accounts.fetchRemove(address)) |kv| {
            return kv.value;
        }
        return null;
    }

    /// Get all accounts
    pub fn getAccounts(self: Self) std.AutoHashMap(primitives.Address, state.Account) {
        return self.accounts;
    }
};
