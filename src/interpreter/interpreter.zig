const std = @import("std");
const primitives = @import("primitives");
const bytecode = @import("bytecode");
const context = @import("context");
const Gas = @import("gas.zig").Gas;
const Stack = @import("stack.zig").Stack;
const Memory = @import("memory.zig").Memory;
const InstructionResult = @import("instruction_result.zig").InstructionResult;
const InterpreterAction = @import("interpreter_action.zig").InterpreterAction;
const CallScheme = @import("interpreter_action.zig").CallScheme;
const InstructionContext = @import("instruction_context.zig").InstructionContext;

/// Input data for current execution context
pub const InputsImpl = struct {
    /// Caller address
    caller: primitives.Address,
    /// Target address
    target: primitives.Address,
    /// Value
    value: primitives.U256,
    /// Data
    data: primitives.Bytes,
    /// Gas limit
    gas_limit: u64,
    /// Call scheme
    scheme: CallScheme,
    /// Is static call
    is_static: bool,
    /// Depth
    depth: usize,

    /// Create new inputs
    pub fn new(
        caller: primitives.Address,
        target: primitives.Address,
        value: primitives.U256,
        data: primitives.Bytes,
        gas_limit: u64,
        scheme: CallScheme,
        is_static: bool,
        depth: usize,
    ) InputsImpl {
        return InputsImpl{
            .caller = caller,
            .target = target,
            .value = value,
            .data = data,
            .gas_limit = gas_limit,
            .scheme = scheme,
            .is_static = is_static,
            .depth = depth,
        };
    }

    /// Create default inputs
    pub fn default() InputsImpl {
        return InputsImpl{
            .caller = primitives.Address.zero(),
            .target = primitives.Address.zero(),
            .value = primitives.U256.zero(),
            .data = primitives.Bytes.init(std.heap.page_allocator, 0) catch unreachable,
            .gas_limit = 0,
            .scheme = .call,
            .is_static = false,
            .depth = 0,
        };
    }

    /// Get caller
    pub fn getCaller(self: InputsImpl) primitives.Address {
        return self.caller;
    }

    /// Get target
    pub fn getTarget(self: InputsImpl) primitives.Address {
        return self.target;
    }

    /// Get value
    pub fn getValue(self: InputsImpl) primitives.U256 {
        return self.value;
    }

    /// Get data
    pub fn getData(self: InputsImpl) primitives.Bytes {
        return self.data;
    }

    /// Get gas limit
    pub fn getGasLimit(self: InputsImpl) u64 {
        return self.gas_limit;
    }

    /// Get scheme
    pub fn getScheme(self: InputsImpl) CallScheme {
        return self.scheme;
    }

    /// Get is static
    pub fn getIsStatic(self: InputsImpl) bool {
        return self.is_static;
    }

    /// Get depth
    pub fn getDepth(self: InputsImpl) usize {
        return self.depth;
    }
};

/// Return data buffer
pub const ReturnDataImpl = struct {
    /// Return data
    data: primitives.Bytes,
    /// Gas used
    gas_used: u64,
    /// Success
    success: bool,

    /// Create new return data
    pub fn new(data: primitives.Bytes, gas_used: u64, success: bool) ReturnDataImpl {
        return ReturnDataImpl{
            .data = data,
            .gas_used = gas_used,
            .success = success,
        };
    }

    /// Create default return data
    pub fn default() ReturnDataImpl {
        return ReturnDataImpl{
            .data = &[_]u8{},
            .gas_used = 0,
            .success = false,
        };
    }

    /// Get data
    pub fn getData(self: ReturnDataImpl) primitives.Bytes {
        return self.data;
    }

    /// Get gas used
    pub fn getGasUsed(self: ReturnDataImpl) u64 {
        return self.gas_used;
    }

    /// Get success
    pub fn getSuccess(self: ReturnDataImpl) bool {
        return self.success;
    }

    /// Set data
    pub fn setData(self: *ReturnDataImpl, data: primitives.Bytes) void {
        self.data = data;
    }

    /// Set gas used
    pub fn setGasUsed(self: *ReturnDataImpl, gas_used: u64) void {
        self.gas_used = gas_used;
    }

    /// Set success
    pub fn setSuccess(self: *ReturnDataImpl, success: bool) void {
        self.success = success;
    }
};

/// Runtime flags controlling execution behavior
pub const RuntimeFlags = struct {
    /// Is static call
    is_static: bool,
    /// Spec ID
    spec_id: primitives.SpecId,

    /// Create new runtime flags
    pub fn new(is_static: bool, spec_id: primitives.SpecId) RuntimeFlags {
        return RuntimeFlags{
            .is_static = is_static,
            .spec_id = spec_id,
        };
    }

    /// Create default runtime flags
    pub fn default() RuntimeFlags {
        return RuntimeFlags{
            .is_static = false,
            .spec_id = primitives.SpecId.default(),
        };
    }

    /// Get is static
    pub fn getIsStatic(self: RuntimeFlags) bool {
        return self.is_static;
    }

    /// Get spec ID
    pub fn getSpecId(self: RuntimeFlags) primitives.SpecId {
        return self.spec_id;
    }

    /// Set is static
    pub fn setIsStatic(self: *RuntimeFlags, is_static: bool) void {
        self.is_static = is_static;
    }

    /// Set spec ID
    pub fn setSpecId(self: *RuntimeFlags, spec_id: primitives.SpecId) void {
        self.spec_id = spec_id;
    }
};

/// Extended bytecode functionality
pub const ExtBytecode = struct {
    /// Bytecode
    bytecode: bytecode.Bytecode,
    /// Is EOF
    is_eof: bool,
    /// EOF version
    eof_version: ?u8,
    /// EOF sections
    eof_sections: ?std.ArrayList(EofSection),

    /// Create new extended bytecode
    pub fn new(bytecode_data: bytecode.Bytecode) ExtBytecode {
        return ExtBytecode{
            .bytecode = bytecode_data,
            .is_eof = false,
            .eof_version = null,
            .eof_sections = null,
        };
    }

    /// Create default extended bytecode
    pub fn default() ExtBytecode {
        return ExtBytecode{
            .bytecode = bytecode.Bytecode.default(),
            .is_eof = false,
            .eof_version = null,
            .eof_sections = null,
        };
    }

    /// Deinitialize
    pub fn deinit(self: *ExtBytecode) void {
        if (self.eof_sections) |*sections| {
            sections.deinit();
        }
    }

    /// Get bytecode
    pub fn getBytecode(self: ExtBytecode) bytecode.Bytecode {
        return self.bytecode;
    }

    /// Get is EOF
    pub fn getIsEof(self: ExtBytecode) bool {
        return self.is_eof;
    }

    /// Get EOF version
    pub fn getEofVersion(self: ExtBytecode) ?u8 {
        return self.eof_version;
    }

    /// Get EOF sections
    pub fn getEofSections(self: ExtBytecode) ?std.ArrayList(EofSection) {
        return self.eof_sections;
    }

    /// Set bytecode
    pub fn setBytecode(self: *ExtBytecode, bytecode_data: bytecode.Bytecode) void {
        self.bytecode = bytecode_data;
    }

    /// Set is EOF
    pub fn setIsEof(self: *ExtBytecode, is_eof: bool) void {
        self.is_eof = is_eof;
    }

    /// Set EOF version
    pub fn setEofVersion(self: *ExtBytecode, version: ?u8) void {
        self.eof_version = version;
    }

    /// Set EOF sections
    pub fn setEofSections(self: *ExtBytecode, sections: ?std.ArrayList(EofSection)) void {
        self.eof_sections = sections;
    }
};

/// EOF section
pub const EofSection = struct {
    /// Section type
    section_type: u8,
    /// Section data
    data: primitives.Bytes,

    /// Create new EOF section
    pub fn new(section_type: u8, data: primitives.Bytes) EofSection {
        return EofSection{
            .section_type = section_type,
            .data = data,
        };
    }

    /// Get section type
    pub fn getSectionType(self: EofSection) u8 {
        return self.section_type;
    }

    /// Get data
    pub fn getData(self: EofSection) primitives.Bytes {
        return self.data;
    }

    /// Set section type
    pub fn setSectionType(self: *EofSection, section_type: u8) void {
        self.section_type = section_type;
    }

    /// Set data
    pub fn setData(self: *EofSection, data: primitives.Bytes) void {
        self.data = data;
    }
};

/// Main interpreter structure that contains all components
pub const Interpreter = struct {
    /// Bytecode being executed
    bytecode: ExtBytecode,
    /// Gas tracking for execution costs
    gas: Gas,
    /// EVM stack for computation
    stack: Stack,
    /// Buffer for return data from calls
    return_data: ReturnDataImpl,
    /// EVM memory for data storage
    memory: Memory,
    /// Input data for current execution context
    input: InputsImpl,
    /// Runtime flags controlling execution behavior
    runtime_flags: RuntimeFlags,
    /// Extended functionality and customizations
    extend: void,

    /// Create new interpreter
    pub fn new(
        memory: Memory,
        bytecode_data: ExtBytecode,
        input: InputsImpl,
        is_static: bool,
        spec_id: primitives.SpecId,
        gas_limit: u64,
    ) Interpreter {
        return Interpreter{
            .bytecode = bytecode_data,
            .gas = Gas.new(gas_limit),
            .stack = Stack.new(),
            .return_data = ReturnDataImpl.default(),
            .memory = memory,
            .input = input,
            .runtime_flags = RuntimeFlags.new(is_static, spec_id),
            .extend = {},
        };
    }

    /// Create a new interpreter with default extended functionality
    pub fn defaultExt() Interpreter {
        return Interpreter.new(
            Memory.new(),
            ExtBytecode.default(),
            InputsImpl.default(),
            false,
            primitives.SpecId.default(),
            std.math.maxInt(u64),
        );
    }

    /// Create a new invalid interpreter
    pub fn invalid() Interpreter {
        return Interpreter.new(
            Memory.new(),
            ExtBytecode.default(),
            InputsImpl.default(),
            false,
            primitives.SpecId.default(),
            0,
        );
    }

    /// Deinitialize the interpreter
    pub fn deinit(self: *Interpreter) void {
        self.bytecode.deinit();
        self.memory.deinit();
    }

    /// Clear and reinitialize the interpreter with new parameters
    pub fn clear(
        self: *Interpreter,
        memory: Memory,
        bytecode_data: ExtBytecode,
        input: InputsImpl,
        is_static: bool,
        spec_id: primitives.SpecId,
        gas_limit: u64,
    ) void {
        self.bytecode = bytecode_data;
        self.gas = Gas.new(gas_limit);
        self.stack.clear();
        self.return_data = ReturnDataImpl.default();
        self.memory = memory;
        self.input = input;
        self.runtime_flags = RuntimeFlags.new(is_static, spec_id);
        self.extend = {};
    }

    /// Get bytecode
    pub fn getBytecode(self: Interpreter) ExtBytecode {
        return self.bytecode;
    }

    /// Get gas
    pub fn getGas(self: Interpreter) Gas {
        return self.gas;
    }

    /// Get gas mutably
    pub fn getGasMut(self: *Interpreter) *Gas {
        return &self.gas;
    }

    /// Get stack
    pub fn getStack(self: Interpreter) Stack {
        return self.stack;
    }

    /// Get stack mutably
    pub fn getStackMut(self: *Interpreter) *Stack {
        return &self.stack;
    }

    /// Get return data
    pub fn getReturnData(self: Interpreter) ReturnDataImpl {
        return self.return_data;
    }

    /// Get return data mutably
    pub fn getReturnDataMut(self: *Interpreter) *ReturnDataImpl {
        return &self.return_data;
    }

    /// Get memory
    pub fn getMemory(self: Interpreter) Memory {
        return self.memory;
    }

    /// Get memory mutably
    pub fn getMemoryMut(self: *Interpreter) *Memory {
        return &self.memory;
    }

    /// Get input
    pub fn getInput(self: Interpreter) InputsImpl {
        return self.input;
    }

    /// Get input mutably
    pub fn getInputMut(self: *Interpreter) *InputsImpl {
        return &self.input;
    }

    /// Get runtime flags
    pub fn getRuntimeFlags(self: Interpreter) RuntimeFlags {
        return self.runtime_flags;
    }

    /// Get runtime flags mutably
    pub fn getRuntimeFlagsMut(self: *Interpreter) *RuntimeFlags {
        return &self.runtime_flags;
    }

    /// Get extend
    pub fn getExtend(self: Interpreter) void {
        return self.extend;
    }

    /// Get extend mutably
    pub fn getExtendMut(self: *Interpreter) *void {
        return &self.extend;
    }
};

/// Calculate number of words from bytes
pub fn numWords(bytes: usize) usize {
    return (bytes + 31) / 32;
}

/// Resize memory to accommodate new size
pub fn resizeMemory(memory: *Memory, new_size: usize) !void {
    try memory.resize(new_size);
}
