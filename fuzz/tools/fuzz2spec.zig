// fuzz2spec.zig — Convert a binary fuzz input file to a spec test JSON fixture.
//
// Usage: fuzz2spec <binary-fuzz-input-file> [harness]
//   harness: "transaction" (default), "bytecode"
//
// Output: JSON to stdout, compatible with src/spec_test/main.zig format.
// The "post" state is intentionally empty — the JSON documents the crash/finding
// input. After fixing the bug, populate expected post-state or keep it empty as
// a "must not crash" regression test.
//
// Example:
//   fuzz2spec fuzz/findings/transaction/crashes/id:000000 > spec-tests/fuzz/crash_001.json

const std = @import("std");
const primitives = @import("primitives");
const input_decoder = @import("input_decoder");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) {
        std.debug.print("Usage: fuzz2spec <fuzz-input-file> [transaction|bytecode]\n", .{});
        std.process.exit(1);
    }

    const harness = if (args.len >= 3) args[2] else "transaction";
    const file_data = try std.fs.cwd().readFileAlloc(alloc, args[1], 1 << 20);
    defer alloc.free(file_data);

    var out_buf: [1 << 16]u8 = undefined;
    var stdout_streamer = std.fs.File.stdout().writerStreaming(&out_buf);
    const stdout = &stdout_streamer.interface;

    if (std.mem.eql(u8, harness, "bytecode")) {
        try emitBytecodeSpec(stdout, file_data, args[1]);
    } else {
        try emitTransactionSpec(stdout, file_data, args[1]);
    }
    try stdout_streamer.interface.flush();
}

fn emitTransactionSpec(writer: anytype, data: []const u8, source_name: []const u8) !void {
    const input = input_decoder.decodeTxInput(data) orelse {
        std.debug.print("Error: input too short for transaction format (need >= 84 bytes, got {})\n", .{data.len});
        std.process.exit(1);
    };

    // Derive test name from source file basename
    const basename = std.fs.path.basename(source_name);
    const fork_name = specIdToForkName(input.spec_id);

    try writer.print("{{\n", .{});
    try writer.print("  \"{s}_{s}\": {{\n", .{ basename, fork_name });

    // env block
    try writer.print("    \"env\": {{\n", .{});
    try writer.print("      \"currentCoinbase\": \"0x{s}\",\n", .{fmtAddr([_]u8{0} ** 20)});
    try writer.print("      \"currentNumber\": \"0x1\",\n", .{});
    try writer.print("      \"currentTimestamp\": \"0x1\",\n", .{});
    try writer.print("      \"currentGasLimit\": \"0x7fffffffffffffff\",\n", .{});
    try writer.print("      \"currentBaseFee\": \"0x0\",\n", .{});
    try writer.print("      \"currentDifficulty\": \"0x0\",\n", .{});
    try writer.print("      \"currentRandom\": \"0x{s}\"\n", .{fmtHash([_]u8{0} ** 32)});
    try writer.print("    }},\n", .{});

    // pre block
    try writer.print("    \"pre\": {{\n", .{});
    // Caller with large balance
    try writer.print("      \"0x{s}\": {{\n", .{fmtAddr(input.caller)});
    try writer.print("        \"balance\": \"0xffffffffffffffffffffffffffffffff\",\n", .{});
    try writer.print("        \"nonce\": \"0x0\",\n", .{});
    try writer.print("        \"code\": \"0x\",\n", .{});
    try writer.print("        \"storage\": {{}}\n", .{});
    if (input.is_create or input.bytecode.len == 0) {
        try writer.print("      }}\n", .{});
    } else {
        try writer.print("      }},\n", .{});
        // Target with bytecode
        try writer.print("      \"0x{s}\": {{\n", .{fmtAddr(input.target)});
        try writer.print("        \"balance\": \"0x0\",\n", .{});
        try writer.print("        \"nonce\": \"0x0\",\n", .{});
        try writer.print("        \"code\": \"0x", .{});
        for (input.bytecode) |b| try writer.print("{x:0>2}", .{b});
        try writer.print("\",\n", .{});
        try writer.print("        \"storage\": {{}}\n", .{});
        try writer.print("      }}\n", .{});
    }
    try writer.print("    }},\n", .{});

    // transaction block
    try writer.print("    \"transaction\": {{\n", .{});
    try writer.print("      \"sender\": \"0x{s}\",\n", .{fmtAddr(input.caller)});
    if (input.is_create) {
        try writer.print("      \"to\": \"\",\n", .{});
    } else {
        try writer.print("      \"to\": \"0x{s}\",\n", .{fmtAddr(input.target)});
    }
    try writer.print("      \"data\": [\"0x", .{});
    for (input.calldata) |b| try writer.print("{x:0>2}", .{b});
    try writer.print("\"],\n", .{});
    try writer.print("      \"gasLimit\": [\"0x{x}\"],\n", .{input.gas_limit});
    const value_bytes: [32]u8 = @bitCast(@byteSwap(input.value));
    try writer.print("      \"value\": [\"0x{s}\"],\n", .{fmtHash(value_bytes)});
    try writer.print("      \"gasPrice\": \"0x1\",\n", .{});
    try writer.print("      \"nonce\": \"0x0\"\n", .{});
    try writer.print("    }},\n", .{});

    // post block — empty state, documents the crash input
    try writer.print("    \"post\": {{\n", .{});
    try writer.print("      \"{s}\": [\n", .{fork_name});
    try writer.print("        {{\n", .{});
    try writer.print("          \"indexes\": {{\"data\": 0, \"gas\": 0, \"value\": 0}},\n", .{});
    try writer.print("          \"state\": {{}}\n", .{});
    try writer.print("        }}\n", .{});
    try writer.print("      ]\n", .{});
    try writer.print("    }}\n", .{});
    try writer.print("  }}\n", .{});
    try writer.print("}}\n", .{});
}

fn emitBytecodeSpec(writer: anytype, data: []const u8, source_name: []const u8) !void {
    const input = input_decoder.decodeBytecodeFuzzInput(data) orelse {
        std.debug.print("Error: input too short for bytecode format (need >= 9 bytes, got {})\n", .{data.len});
        std.process.exit(1);
    };

    const basename = std.fs.path.basename(source_name);
    const fork_name = specIdToForkName(input.spec_id);
    const caller: primitives.Address = [_]u8{0x10} ** 20;
    const target: primitives.Address = [_]u8{0x20} ** 20;

    try writer.print("{{\n", .{});
    try writer.print("  \"{s}_{s}\": {{\n", .{ basename, fork_name });
    try writer.print("    \"env\": {{\n", .{});
    try writer.print("      \"currentCoinbase\": \"0x{s}\",\n", .{fmtAddr([_]u8{0} ** 20)});
    try writer.print("      \"currentNumber\": \"0x1\",\n", .{});
    try writer.print("      \"currentTimestamp\": \"0x1\",\n", .{});
    try writer.print("      \"currentGasLimit\": \"0x7fffffffffffffff\",\n", .{});
    try writer.print("      \"currentBaseFee\": \"0x0\",\n", .{});
    try writer.print("      \"currentDifficulty\": \"0x0\",\n", .{});
    try writer.print("      \"currentRandom\": \"0x{s}\"\n", .{fmtHash([_]u8{0} ** 32)});
    try writer.print("    }},\n", .{});
    try writer.print("    \"pre\": {{\n", .{});
    try writer.print("      \"0x{s}\": {{\"balance\": \"0xffffffffffffffffffffffffffffffff\", \"nonce\": \"0x0\", \"code\": \"0x\", \"storage\": {{}}}},\n", .{fmtAddr(caller)});
    try writer.print("      \"0x{s}\": {{\n", .{fmtAddr(target)});
    try writer.print("        \"balance\": \"0x0\", \"nonce\": \"0x0\",\n", .{});
    try writer.print("        \"code\": \"0x", .{});
    for (input.bytecode) |b| try writer.print("{x:0>2}", .{b});
    try writer.print("\",\n", .{});
    try writer.print("        \"storage\": {{}}\n", .{});
    try writer.print("      }}\n", .{});
    try writer.print("    }},\n", .{});
    try writer.print("    \"transaction\": {{\n", .{});
    try writer.print("      \"sender\": \"0x{s}\",\n", .{fmtAddr(caller)});
    try writer.print("      \"to\": \"0x{s}\",\n", .{fmtAddr(target)});
    try writer.print("      \"data\": [\"0x\"],\n", .{});
    try writer.print("      \"gasLimit\": [\"0x{x}\"],\n", .{input.gas_limit});
    try writer.print("      \"value\": [\"0x0\"],\n", .{});
    try writer.print("      \"gasPrice\": \"0x1\",\n", .{});
    try writer.print("      \"nonce\": \"0x0\"\n", .{});
    try writer.print("    }},\n", .{});
    try writer.print("    \"post\": {{\n", .{});
    try writer.print("      \"{s}\": [\n", .{fork_name});
    try writer.print("        {{\"indexes\": {{\"data\": 0, \"gas\": 0, \"value\": 0}}, \"state\": {{}}}}\n", .{});
    try writer.print("      ]\n", .{});
    try writer.print("    }}\n", .{});
    try writer.print("  }}\n", .{});
    try writer.print("}}\n", .{});
}

fn specIdToForkName(spec: primitives.SpecId) []const u8 {
    return switch (spec) {
        .frontier, .frontier_thawing => "Frontier",
        .homestead, .dao_fork => "Homestead",
        .tangerine => "EIP150",
        .spurious_dragon => "EIP158",
        .byzantium => "Byzantium",
        .constantinople => "Constantinople",
        .petersburg => "ConstantinopleFix",
        .istanbul, .muir_glacier => "Istanbul",
        .berlin => "Berlin",
        .london, .arrow_glacier, .gray_glacier => "London",
        .merge => "Paris",
        .shanghai => "Shanghai",
        .cancun => "Cancun",
        .prague => "Prague",
        .osaka, .bpo1, .bpo2, .amsterdam => "Osaka",
    };
}

fn fmtAddr(addr: primitives.Address) [40]u8 {
    const hex = "0123456789abcdef";
    var buf: [40]u8 = undefined;
    for (addr, 0..) |b, i| {
        buf[i * 2] = hex[b >> 4];
        buf[i * 2 + 1] = hex[b & 0xf];
    }
    return buf;
}

fn fmtHash(h: [32]u8) [64]u8 {
    const hex = "0123456789abcdef";
    var buf: [64]u8 = undefined;
    for (h, 0..) |b, i| {
        buf[i * 2] = hex[b >> 4];
        buf[i * 2 + 1] = hex[b & 0xf];
    }
    return buf;
}
