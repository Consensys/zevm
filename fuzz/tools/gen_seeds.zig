// gen_seeds.zig — Generate binary seed corpus from existing spec test fixtures.
//
// Reads spec test JSON fixtures and encodes each test case into the binary
// format expected by fuzz_transaction.zig. Outputs one .bin file per test case
// in the specified output directory.
//
// Usage: gen-seeds <fixtures-dir> <output-dir>
//   fixtures-dir: path to spec-tests/fixtures/state_tests or similar
//   output-dir:   path to fuzz/seeds/transaction/
//
// Only handles legacy (type-0) and EIP-1559 (type-2) transactions.
// EIP-4844 and EIP-7702 test cases are skipped (precompile fuzzer covers those).

const std = @import("std");
const primitives = @import("primitives");
const input_decoder = @import("input_decoder");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 3) {
        std.debug.print("Usage: gen-seeds <fixtures-dir> <output-dir>\n", .{});
        std.process.exit(1);
    }

    const fixtures_dir_path = args[1];
    const output_dir_path = args[2];

    // Create output directory if needed
    std.fs.cwd().makeDir(output_dir_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const output_dir = try std.fs.cwd().openDir(output_dir_path, .{});

    var count: usize = 0;
    var skipped: usize = 0;

    // Walk fixtures directory recursively
    var fixtures_dir = try std.fs.cwd().openDir(fixtures_dir_path, .{ .iterate = true });
    defer fixtures_dir.close();

    var walker = try fixtures_dir.walk(alloc);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".json")) continue;

        const file_data = fixtures_dir.readFileAlloc(alloc, entry.path, 4 * 1024 * 1024) catch continue;
        defer alloc.free(file_data);

        processFixtureFile(alloc, file_data, output_dir, &count, &skipped) catch |err| {
            std.debug.print("Warning: error processing {s}: {}\n", .{ entry.path, err });
        };
    }

    std.debug.print("Generated {} seed files ({} skipped)\n", .{ count, skipped });
}

fn processFixtureFile(
    alloc: std.mem.Allocator,
    file_data: []const u8,
    output_dir: std.fs.Dir,
    count: *usize,
    skipped: *usize,
) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, file_data, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    var test_it = root.iterator();

    while (test_it.next()) |test_entry| {
        const test_obj = test_entry.value_ptr.object;

        // Parse env (existence check — fields parsed from block env as needed)
        _ = test_obj.get("env") orelse continue;

        // Parse transaction template
        const tx_template = test_obj.get("transaction") orelse continue;
        const tx_obj = tx_template.object;

        // Parse pre-state
        const pre = test_obj.get("pre") orelse continue;
        const pre_obj = pre.object;

        // Parse post section to find fork names and select first valid test case
        const post = test_obj.get("post") orelse continue;
        const post_obj = post.object;

        // Find the most advanced fork available
        const preferred_forks = [_][]const u8{
            "Osaka", "Prague", "Cancun", "Shanghai", "Paris",
            "London", "Berlin",  "Istanbul",
        };
        var fork_name: ?[]const u8 = null;
        var post_cases: ?std.json.Value = null;
        for (preferred_forks) |pf| {
            if (post_obj.get(pf)) |cases| {
                fork_name = pf;
                post_cases = cases;
                break;
            }
        }
        if (fork_name == null) {
            skipped.* += 1;
            continue;
        }

        const cases_arr = post_cases.?.array;
        if (cases_arr.items.len == 0) {
            skipped.* += 1;
            continue;
        }

        // Use the first post case to get data/gas/value indexes
        const first_case = cases_arr.items[0].object;
        const indexes = (first_case.get("indexes") orelse continue).object;
        const data_idx = @as(usize, @intCast(indexes.get("data").?.integer));
        const gas_idx = @as(usize, @intCast(indexes.get("gas").?.integer));
        const value_idx = @as(usize, @intCast(indexes.get("value").?.integer));

        // Extract transaction fields
        const sender_str = (tx_obj.get("sender") orelse continue).string;
        const to_val = tx_obj.get("to");
        const is_create = to_val == null or to_val.?.string.len == 0;

        const data_arr = (tx_obj.get("data") orelse continue).array;
        const gas_arr = (tx_obj.get("gasLimit") orelse continue).array;
        const value_arr = (tx_obj.get("value") orelse continue).array;

        if (data_idx >= data_arr.items.len) { skipped.* += 1; continue; }
        if (gas_idx >= gas_arr.items.len) { skipped.* += 1; continue; }
        if (value_idx >= value_arr.items.len) { skipped.* += 1; continue; }

        const calldata_hex = data_arr.items[data_idx].string;
        const gas_hex = gas_arr.items[gas_idx].string;
        const value_hex = value_arr.items[value_idx].string;

        // Parse values
        const caller = parseAddress(sender_str) catch { skipped.* += 1; continue; };
        const target = if (!is_create) blk: {
            break :blk parseAddress(to_val.?.string) catch { skipped.* += 1; continue; };
        } else [_]u8{0} ** 20;

        const gas_limit = parseHexU64(gas_hex) catch { skipped.* += 1; continue; };
        const value_u256 = parseHexU256(value_hex) catch { skipped.* += 1; continue; };

        const calldata = parseHexBytes(alloc, calldata_hex) catch { skipped.* += 1; continue; };
        defer alloc.free(calldata);

        // Find target's bytecode from pre-state
        var bytecode_bytes: []const u8 = &[_]u8{};
        var bytecode_owned: ?[]u8 = null;
        defer if (bytecode_owned) |b| alloc.free(b);

        if (!is_create) {
            const target_hex = to_val.?.string;
            if (pre_obj.get(target_hex) orelse pre_obj.get(target_hex[2..])) |target_acct| {
                if (target_acct.object.get("code")) |code_val| {
                    const code_hex = code_val.string;
                    if (code_hex.len > 2) { // not "0x"
                        bytecode_owned = parseHexBytes(alloc, code_hex) catch null;
                        if (bytecode_owned) |b| bytecode_bytes = b;
                    }
                }
            }
        }

        // Map fork name to spec_id
        const spec_id: u8 = forkNameToSpecId(fork_name.?);

        // Cap gas for fuzzing
        const capped_gas = @min(gas_limit, input_decoder.MAX_GAS);

        // Encode the binary seed
        var buf = std.ArrayList(u8){};
        defer buf.deinit(alloc);

        const flags: u8 = if (is_create) 0x01 else 0x00;
        try buf.append(alloc, spec_id);
        try buf.append(alloc, flags);
        var gas_le: [8]u8 = undefined;
        std.mem.writeInt(u64, &gas_le, capped_gas, .little);
        try buf.appendSlice(alloc, &gas_le);
        try buf.appendSlice(alloc, &caller);
        try buf.appendSlice(alloc, &target);

        // Value: 32 bytes LE
        var value_le: [32]u8 = undefined;
        std.mem.writeInt(primitives.U256, &value_le, value_u256, .little);
        try buf.appendSlice(alloc, &value_le);

        // Calldata
        const cd_len = @min(calldata.len, input_decoder.MAX_CALLDATA);
        var cd_len_le: [2]u8 = undefined;
        std.mem.writeInt(u16, &cd_len_le, @as(u16, @intCast(cd_len)), .little);
        try buf.appendSlice(alloc, &cd_len_le);
        try buf.appendSlice(alloc, calldata[0..cd_len]);

        // Bytecode
        const bc_len = @min(bytecode_bytes.len, input_decoder.MAX_BYTECODE);
        var bc_len_le: [2]u8 = undefined;
        std.mem.writeInt(u16, &bc_len_le, @as(u16, @intCast(bc_len)), .little);
        try buf.appendSlice(alloc, &bc_len_le);
        try buf.appendSlice(alloc, bytecode_bytes[0..bc_len]);

        // Write seed file
        const seed_name = try std.fmt.allocPrint(
            alloc,
            "{s}_{s}_{}.bin",
            .{ test_entry.key_ptr.*, fork_name.?, count.* },
        );
        defer alloc.free(seed_name);

        // Replace characters that are problematic in filenames
        const safe_name = try alloc.dupe(u8, seed_name);
        defer alloc.free(safe_name);
        for (safe_name) |*c| {
            if (c.* == '/' or c.* == '\\' or c.* == ':') c.* = '_';
        }

        const out_file = output_dir.createFile(safe_name, .{}) catch continue;
        defer out_file.close();
        try out_file.writeAll(buf.items);
        count.* += 1;
    }
}

fn forkNameToSpecId(fork: []const u8) u8 {
    if (std.mem.eql(u8, fork, "Frontier")) return 0;
    if (std.mem.eql(u8, fork, "Homestead")) return 2;
    if (std.mem.eql(u8, fork, "EIP150")) return 4;
    if (std.mem.eql(u8, fork, "EIP158")) return 5;
    if (std.mem.eql(u8, fork, "Byzantium")) return 6;
    if (std.mem.eql(u8, fork, "Constantinople")) return 7;
    if (std.mem.eql(u8, fork, "ConstantinopleFix")) return 8;
    if (std.mem.eql(u8, fork, "Istanbul")) return 9;
    if (std.mem.eql(u8, fork, "Berlin")) return 11;
    if (std.mem.eql(u8, fork, "London")) return 12;
    if (std.mem.eql(u8, fork, "Paris")) return 14;
    if (std.mem.eql(u8, fork, "Shanghai")) return 15;
    if (std.mem.eql(u8, fork, "Cancun")) return 16;
    if (std.mem.eql(u8, fork, "Prague")) return 17;
    if (std.mem.eql(u8, fork, "Osaka")) return 18;
    return 17; // default to Prague
}

fn parseAddress(s: []const u8) !primitives.Address {
    const hex = if (std.mem.startsWith(u8, s, "0x") or std.mem.startsWith(u8, s, "0X"))
        s[2..]
    else
        s;
    if (hex.len != 40) return error.InvalidAddress;
    var addr: primitives.Address = undefined;
    _ = try std.fmt.hexToBytes(&addr, hex);
    return addr;
}

fn parseHexU64(s: []const u8) !u64 {
    const hex = if (std.mem.startsWith(u8, s, "0x") or std.mem.startsWith(u8, s, "0X"))
        s[2..]
    else
        s;
    return std.fmt.parseUnsigned(u64, hex, 16) catch error.ParseError;
}

fn parseHexU256(s: []const u8) !primitives.U256 {
    const hex = if (std.mem.startsWith(u8, s, "0x") or std.mem.startsWith(u8, s, "0X"))
        s[2..]
    else
        s;
    return std.fmt.parseUnsigned(primitives.U256, hex, 16) catch error.ParseError;
}

fn parseHexBytes(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    const hex = if (std.mem.startsWith(u8, s, "0x") or std.mem.startsWith(u8, s, "0X"))
        s[2..]
    else
        s;
    if (hex.len == 0) return alloc.alloc(u8, 0);
    const out = try alloc.alloc(u8, hex.len / 2);
    _ = try std.fmt.hexToBytes(out, hex);
    return out;
}
