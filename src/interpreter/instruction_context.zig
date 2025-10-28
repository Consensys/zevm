const std = @import("std");
const primitives = @import("primitives");
const bytecode = @import("bytecode");
const context = @import("context");

/// Context passed to instruction implementations.
pub fn InstructionContext(comptime HostType: type, comptime InterpreterType: type, comptime GasType: type, comptime StackType: type, comptime MemoryType: type, comptime ReturnDataType: type, comptime InputType: type, comptime RuntimeFlagsType: type, comptime ExtendType: type) type {
    return struct {
        /// Host interface
        host: HostType,
        /// Interpreter state
        interpreter: InterpreterType,
        /// Gas
        gas: *GasType,
        /// Stack
        stack: *StackType,
        /// Memory
        memory: *MemoryType,
        /// Return data
        return_data: *ReturnDataType,
        /// Input
        input: *InputType,
        /// Runtime flags
        runtime_flags: *RuntimeFlagsType,
        /// Extended functionality
        extend: *ExtendType,

        /// Create a new instruction context
        pub fn new(
            host: HostType,
            interpreter: InterpreterType,
            gas: *GasType,
            stack: *StackType,
            memory: *MemoryType,
            return_data: *ReturnDataType,
            input: *InputType,
            runtime_flags: *RuntimeFlagsType,
            extend: *ExtendType,
        ) @This() {
            return @This(){
                .host = host,
                .interpreter = interpreter,
                .gas = gas,
                .stack = stack,
                .memory = memory,
                .return_data = return_data,
                .input = input,
                .runtime_flags = runtime_flags,
                .extend = extend,
            };
        }

        /// Get the host
        pub fn getHost(self: @This()) HostType {
            return self.host;
        }

        /// Get the interpreter
        pub fn getInterpreter(self: @This()) InterpreterType {
            return self.interpreter;
        }

        /// Get the gas
        pub fn getGas(self: @This()) *GasType {
            return self.gas;
        }

        /// Get the stack
        pub fn getStack(self: @This()) *StackType {
            return self.stack;
        }

        /// Get the memory
        pub fn getMemory(self: @This()) *MemoryType {
            return self.memory;
        }

        /// Get the return data
        pub fn getReturnData(self: @This()) *ReturnDataType {
            return self.return_data;
        }

        /// Get the input
        pub fn getInput(self: @This()) *InputType {
            return self.input;
        }

        /// Get the runtime flags
        pub fn getRuntimeFlags(self: @This()) *RuntimeFlagsType {
            return self.runtime_flags;
        }

        /// Get the extended functionality
        pub fn getExtend(self: @This()) *ExtendType {
            return self.extend;
        }
    };
}

/// Host interface for EVM operations
pub const Host = struct {
    /// Load account
    load_account: fn (address: primitives.Address) void,
    /// Load storage
    load_storage: fn (address: primitives.Address, key: primitives.StorageKey) void,
    /// Store storage
    store_storage: fn (address: primitives.Address, key: primitives.StorageKey, value: primitives.StorageValue) void,
    /// Load code
    load_code: fn (address: primitives.Address) void,
    /// Load code hash
    load_code_hash: fn (address: primitives.Address) void,
    /// Load balance
    load_balance: fn (address: primitives.Address) void,
    /// Load nonce
    load_nonce: fn (address: primitives.Address) void,
    /// Load block hash
    load_block_hash: fn (number: primitives.U256) void,
    /// Load block number
    load_block_number: fn () void,
    /// Load block timestamp
    load_block_timestamp: fn () void,
    /// Load block gas limit
    load_block_gas_limit: fn () void,
    /// Load block base fee
    load_block_base_fee: fn () void,
    /// Load block difficulty
    load_block_difficulty: fn () void,
    /// Load block prevrandao
    load_block_prevrandao: fn () void,
    /// Load block beneficiary
    load_block_beneficiary: fn () void,
    /// Load transaction origin
    load_tx_origin: fn () void,
    /// Load transaction gas price
    load_tx_gas_price: fn () void,
    /// Load transaction gas limit
    load_tx_gas_limit: fn () void,
    /// Load transaction value
    load_tx_value: fn () void,
    /// Load transaction data
    load_tx_data: fn () void,
    /// Load transaction nonce
    load_tx_nonce: fn () void,
    /// Load transaction chain id
    load_tx_chain_id: fn () void,
    /// Load transaction access list
    load_tx_access_list: fn () void,
    /// Load transaction gas priority fee
    load_tx_gas_priority_fee: fn () void,
    /// Load transaction blob hashes
    load_tx_blob_hashes: fn () void,
    /// Load transaction max fee per blob gas
    load_tx_max_fee_per_blob_gas: fn () void,
    /// Load transaction authorization list
    load_tx_authorization_list: fn () void,
    /// Load caller
    load_caller: fn () void,
    /// Load address
    load_address: fn () void,
    /// Load call value
    load_call_value: fn () void,
    /// Load call data
    load_call_data: fn () void,
    /// Load call data length
    load_call_data_length: fn () void,
    /// Load call gas limit
    load_call_gas_limit: fn () void,
    /// Load call depth
    load_call_depth: fn () void,
    /// Load call scheme
    load_call_scheme: fn () void,
    /// Load call is static
    load_call_is_static: fn () void,
    /// Load call is delegate call
    load_call_is_delegate_call: fn () void,
    /// Load call is static call
    load_call_is_static_call: fn () void,
    /// Load call is call code
    load_call_is_call_code: fn () void,
    /// Load call is create
    load_call_is_create: fn () void,
    /// Load call is create2
    load_call_is_create2: fn () void,
    /// Load call is selfdestruct
    load_call_is_selfdestruct: fn () void,
    /// Load call is return
    load_call_is_return: fn () void,
    /// Load call is revert
    load_call_is_revert: fn () void,
    /// Load call is stop
    load_call_is_stop: fn () void,
    /// Load call is invalid
    load_call_is_invalid: fn () void,
    /// Load call is out of gas
    load_call_is_out_of_gas: fn () void,
    /// Load call is memory oog
    load_call_is_memory_oog: fn () void,
    /// Load call is memory limit oog
    load_call_is_memory_limit_oog: fn () void,
    /// Load call is precompile oog
    load_call_is_precompile_oog: fn () void,
    /// Load call is invalid operand oog
    load_call_is_invalid_operand_oog: fn () void,
    /// Load call is reentrancy sentry oog
    load_call_is_reentrancy_sentry_oog: fn () void,
    /// Load call is invalid opcode
    load_call_is_invalid_opcode: fn () void,
    /// Load call is invalid jump
    load_call_is_invalid_jump: fn () void,
    /// Load call is invalid call
    load_call_is_invalid_call: fn () void,
    /// Load call is invalid return
    load_call_is_invalid_return: fn () void,
    /// Load call is invalid create
    load_call_is_invalid_create: fn () void,
    /// Load call is invalid selfdestruct
    load_call_is_invalid_selfdestruct: fn () void,
    /// Load call is invalid log
    load_call_is_invalid_log: fn () void,
    /// Load call is invalid address
    load_call_is_invalid_address: fn () void,
    /// Load call is invalid data
    load_call_is_invalid_data: fn () void,
    /// Load call is invalid gas
    load_call_is_invalid_gas: fn () void,
    /// Load call is invalid value
    load_call_is_invalid_value: fn () void,
    /// Load call is invalid depth
    load_call_is_invalid_depth: fn () void,
    /// Load call is invalid static
    load_call_is_invalid_static: fn () void,
    /// Load call is invalid access
    load_call_is_invalid_access: fn () void,
    /// Load call is invalid warmth
    load_call_is_invalid_warmth: fn () void,
    /// Load call is invalid cold
    load_call_is_invalid_cold: fn () void,
    /// Load call is invalid hot
    load_call_is_invalid_hot: fn () void,
    /// Load call is invalid touched
    load_call_is_invalid_touched: fn () void,
    /// Load call is invalid created
    load_call_is_invalid_created: fn () void,
    /// Load call is invalid destroyed
    load_call_is_invalid_destroyed: fn () void,
    /// Load call is invalid reverted
    load_call_is_invalid_reverted: fn () void,
    /// Load call is invalid committed
    load_call_is_invalid_committed: fn () void,
    /// Load call is invalid discarded
    load_call_is_invalid_discarded: fn () void,
    /// Load call is invalid finalized
    load_call_is_invalid_finalized: fn () void,
    /// Load call is invalid checkpoint
    load_call_is_invalid_checkpoint: fn () void,
    /// Load call is invalid revert
    load_call_is_invalid_revert: fn () void,
    /// Load call is invalid commit
    load_call_is_invalid_commit: fn () void,
    /// Load call is invalid transfer
    load_call_is_invalid_transfer: fn () void,
    /// Load call is invalid refund
    load_call_is_invalid_refund: fn () void,
    /// Load call is invalid cost
    load_call_is_invalid_cost: fn () void,
    /// Load call is invalid limit
    load_call_is_invalid_limit: fn () void,
    /// Load call is invalid cap
    load_call_is_invalid_cap: fn () void,
    /// Load call is invalid size
    load_call_is_invalid_size: fn () void,
    /// Load call is invalid length
    load_call_is_invalid_length: fn () void,
    /// Load call is invalid offset
    load_call_is_invalid_offset: fn () void,
    /// Load call is invalid index
    load_call_is_invalid_index: fn () void,
    /// Load call is invalid key
    load_call_is_invalid_key: fn () void,
    /// Load call is invalid hash
    load_call_is_invalid_hash: fn () void,
    /// Load call is invalid signature
    load_call_is_invalid_signature: fn () void,
    /// Load call is invalid authorization
    load_call_is_invalid_authorization: fn () void,
    /// Load call is invalid permission
    load_call_is_invalid_permission: fn () void,
    /// Load call is invalid authority
    load_call_is_invalid_authority: fn () void,
    /// Load call is invalid delegation
    load_call_is_invalid_delegation: fn () void,
    /// Load call is invalid proxy
    load_call_is_invalid_proxy: fn () void,
    /// Load call is invalid implementation
    load_call_is_invalid_implementation: fn () void,
    /// Load call is invalid interface
    load_call_is_invalid_interface: fn () void,
    /// Load call is invalid ABI
    load_call_is_invalid_abi: fn () void,
    /// Load call is invalid selector
    load_call_is_invalid_selector: fn () void,
    /// Load call is invalid calldata
    load_call_is_invalid_calldata: fn () void,
    /// Load call is invalid returndata
    load_call_is_invalid_returndata: fn () void,
    /// Load call is invalid event
    load_call_is_invalid_event: fn () void,
    /// Load call is invalid topic
    load_call_is_invalid_topic: fn () void,
    /// Load call is invalid logs
    load_call_is_invalid_logs: fn () void,
    /// Load call is invalid bloom
    load_call_is_invalid_bloom: fn () void,
    /// Load call is invalid receipt
    load_call_is_invalid_receipt: fn () void,
    /// Load call is invalid transaction
    load_call_is_invalid_transaction: fn () void,
    /// Load call is invalid block
    load_call_is_invalid_block: fn () void,
    /// Load call is invalid header
    load_call_is_invalid_header: fn () void,
    /// Load call is invalid body
    load_call_is_invalid_body: fn () void,
    /// Load call is invalid state
    load_call_is_invalid_state: fn () void,
    /// Load call is invalid account
    load_call_is_invalid_account: fn () void,
    /// Load call is invalid code hash
    load_call_is_invalid_code_hash: fn () void,
    /// Load call is invalid storage root
    load_call_is_invalid_storage_root: fn () void,
    /// Load call is invalid state root
    load_call_is_invalid_state_root: fn () void,
    /// Load call is invalid receipt root
    load_call_is_invalid_receipt_root: fn () void,
    /// Load call is invalid transactions root
    load_call_is_invalid_transactions_root: fn () void,
    /// Load call is invalid uncles hash
    load_call_is_invalid_uncles_hash: fn () void,
    /// Load call is invalid mix hash
    load_call_is_invalid_mix_hash: fn () void,
    /// Load call is invalid nonce value
    load_call_is_invalid_nonce_value: fn () void,
    /// Load call is invalid difficulty
    load_call_is_invalid_difficulty: fn () void,
    /// Load call is invalid timestamp
    load_call_is_invalid_timestamp: fn () void,
    /// Load call is invalid gas limit
    load_call_is_invalid_gas_limit: fn () void,
    /// Load call is invalid gas used
    load_call_is_invalid_gas_used: fn () void,
    /// Load call is invalid base fee
    load_call_is_invalid_base_fee: fn () void,
    /// Load call is invalid extra data
    load_call_is_invalid_extra_data: fn () void,
    /// Load call is invalid bloom filter
    load_call_is_invalid_bloom_filter: fn () void,
    /// Load call is invalid logs bloom
    load_call_is_invalid_logs_bloom: fn () void,
    /// Load call is invalid receipts bloom
    load_call_is_invalid_receipts_bloom: fn () void,
    /// Load call is invalid transactions bloom
    load_call_is_invalid_transactions_bloom: fn () void,
    /// Load call is invalid uncles bloom
    load_call_is_invalid_uncles_bloom: fn () void,
    /// Load call is invalid state bloom
    load_call_is_invalid_state_bloom: fn () void,
    /// Load call is invalid storage bloom
    load_call_is_invalid_storage_bloom: fn () void,
    /// Load call is invalid account bloom
    load_call_is_invalid_account_bloom: fn () void,
    /// Load call is invalid balance bloom
    load_call_is_invalid_balance_bloom: fn () void,
    /// Load call is invalid nonce bloom
    load_call_is_invalid_nonce_bloom: fn () void,
    /// Load call is invalid code bloom
    load_call_is_invalid_code_bloom: fn () void,
    /// Load call is invalid code hash bloom
    load_call_is_invalid_code_hash_bloom: fn () void,
    /// Load call is invalid storage root bloom
    load_call_is_invalid_storage_root_bloom: fn () void,
    /// Load call is invalid state root bloom
    load_call_is_invalid_state_root_bloom: fn () void,
    /// Load call is invalid receipt root bloom
    load_call_is_invalid_receipt_root_bloom: fn () void,
    /// Load call is invalid transactions root bloom
    load_call_is_invalid_transactions_root_bloom: fn () void,
    /// Load call is invalid uncles hash bloom
    load_call_is_invalid_uncles_hash_bloom: fn () void,
    /// Load call is invalid mix hash bloom
    load_call_is_invalid_mix_hash_bloom: fn () void,
    /// Load call is invalid nonce value bloom
    load_call_is_invalid_nonce_value_bloom: fn () void,
    /// Load call is invalid difficulty bloom
    load_call_is_invalid_difficulty_bloom: fn () void,
    /// Load call is invalid timestamp bloom
    load_call_is_invalid_timestamp_bloom: fn () void,
    /// Load call is invalid gas limit bloom
    load_call_is_invalid_gas_limit_bloom: fn () void,
    /// Load call is invalid gas used bloom
    load_call_is_invalid_gas_used_bloom: fn () void,
    /// Load call is invalid base fee bloom
    load_call_is_invalid_base_fee_bloom: fn () void,
    /// Load call is invalid extra data bloom
    load_call_is_invalid_extra_data_bloom: fn () void,
};
