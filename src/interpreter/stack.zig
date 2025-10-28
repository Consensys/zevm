const std = @import("std");
const primitives = @import("primitives");

/// EVM interpreter stack limit.
pub const STACK_LIMIT: usize = 1024;

/// EVM stack with STACK_LIMIT capacity of words.
pub const Stack = struct {
    /// The underlying data of the stack.
    data: ?std.ArrayList(primitives.U256),

    /// Create a new stack
    pub fn new() Stack {
        return Stack{
            .data = null,
        };
    }

    /// Create a new stack with capacity
    pub fn withCapacity(capacity: usize) Stack {
        _ = capacity;
        return Stack{
            .data = null,
        };
    }

    /// Create an invalid stack
    pub fn invalid() Stack {
        return Stack{
            .data = null,
        };
    }

    /// Deinitialize the stack
    pub fn deinit(self: *Stack) void {
        if (self.data) |*data| {
            data.deinit(std.heap.c_allocator);
        }
    }

    /// Get the length of the stack
    pub fn len(self: Stack) usize {
        if (self.data) |data| {
            return data.items.len;
        }
        return 0;
    }

    /// Get the data slice
    pub fn getData(self: Stack) []const primitives.U256 {
        if (self.data) |data| {
            return data.items;
        }
        return &[_]primitives.U256{};
    }

    /// Clear the stack
    pub fn clear(self: *Stack) void {
        if (self.data) |*data| {
            data.clearRetainingCapacity();
        }
    }

    /// Push a value onto the stack
    pub fn push(self: *Stack, value: primitives.U256) !void {
        if (self.data) |*data| {
            if (data.items.len >= STACK_LIMIT) {
                return error.StackOverflow;
            }

            try data.append(std.heap.c_allocator, value);
        } else {
            // Initialize the ArrayList if it's null
            self.data = std.ArrayList(primitives.U256){ .items = &[_]primitives.U256{}, .capacity = 0 };
            try self.data.?.append(std.heap.c_allocator, value);
        }
    }

    /// Pop a value from the stack
    pub fn pop(self: *Stack) ?primitives.U256 {
        if (self.data) |*data| {
            if (data.items.len == 0) {
                return null;
            }
            return data.pop();
        }
        return null;
    }

    /// Peek at the top value without removing it
    pub fn peek(self: *Stack) ?primitives.U256 {
        if (self.data) |data| {
            if (data.items.len == 0) {
                return null;
            }
            return data.items[data.items.len - 1];
        }
        return null;
    }

    /// Peek at a value at a specific depth
    pub fn peekAt(self: *Stack, depth: usize) ?primitives.U256 {
        if (self.data) |data| {
            if (depth >= data.items.len) {
                return null;
            }
            return data.items[data.items.len - 1 - depth];
        }
        return null;
    }

    /// Pop multiple values from the stack
    pub fn popN(self: *Stack, comptime N: usize) ?[N]primitives.U256 {
        if (self.data) |*data| {
            if (data.items.len < N) {
                return null;
            }

            var result: [N]primitives.U256 = undefined;
            for (0..N) |i| {
                result[i] = data.items[data.items.len - N + i];
            }

            data.items.len -= N;
            return result;
        }
        return null;
    }

    /// Pop N values and return the top value
    pub fn popNTop(self: *Stack, comptime POPN: usize) ?struct { [POPN]primitives.U256, primitives.U256 } {
        if (self.data) |*data| {
            if (data.items.len < POPN + 1) {
                return null;
            }

            const top = data.items[data.items.len - 1];
            const popped = self.popN(POPN) orelse return null;

            return .{ popped, top };
        }
        return null;
    }

    /// Exchange two values on the stack
    pub fn exchange(self: *Stack, n: usize, m: usize) bool {
        if (self.data) |*data| {
            if (n >= data.items.len or m >= data.items.len) {
                return false;
            }

            const stack_len = data.items.len;
            const temp = data.items[stack_len - 1 - n];
            data.items[stack_len - 1 - n] = data.items[stack_len - 1 - m];
            data.items[stack_len - 1 - m] = temp;

            return true;
        }
        return false;
    }

    /// Duplicate a value on the stack
    pub fn dup(self: *Stack, n: usize) !void {
        if (self.data) |*data| {
            if (n == 0 or n > data.items.len) {
                return error.InvalidDupIndex;
            }

            if (data.items.len >= STACK_LIMIT) {
                return error.StackOverflow;
            }

            const value = data.items[data.items.len - n];
            try data.append(std.heap.c_allocator, value);
        }
    }

    /// Push a slice of bytes as a U256
    pub fn pushSlice(self: *Stack, slice: []const u8) !void {
        if (slice.len > 32) {
            return error.InvalidSliceLength;
        }

        var bytes: [32]u8 = [_]u8{0} ** 32;
        @memcpy(bytes[32 - slice.len ..], slice);

        try self.push(@bitCast(bytes));
    }

    /// Set a value at a specific position
    pub fn set(self: *Stack, index: usize, value: primitives.U256) bool {
        if (self.data) |*data| {
            if (index >= data.items.len) {
                return false;
            }

            data.items[data.items.len - 1 - index] = value;
            return true;
        }
        return false;
    }

    /// Get a value at a specific position
    pub fn get(self: *Stack, index: usize) ?primitives.U256 {
        if (self.data) |data| {
            if (index >= data.items.len) {
                return null;
            }

            return data.items[data.items.len - 1 - index];
        }
        return null;
    }

    /// Format the stack for debugging
    pub fn format(self: Stack, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.writeAll("[");
        if (self.data) |data| {
            for (data.items, 0..) |item, i| {
                if (i > 0) {
                    try writer.writeAll(", ");
                }
                try std.fmt.format(writer, "{}", .{item});
            }
        }
        try writer.writeAll("]");
    }
};
