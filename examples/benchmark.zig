const std = @import("std");
const primitives = @import("primitives");
const interpreter = @import("interpreter");
const zbench = @import("zbench");

// ---------------------------------------------------------------------------
// File-scope globals for hooks (hooks are fn() void, no parameters)
// ---------------------------------------------------------------------------
var g_stack: interpreter.Stack = interpreter.Stack.new();
var g_gas: interpreter.Gas = interpreter.Gas.new(0);

const ADD_GAS_COST = 3;
const PREFILL = 900;
const OPS_PER_BATCH = 400;

fn resetStackAndGas() void {
    g_stack.clear();
    for (0..PREFILL) |i| {
        g_stack.pushUnsafe(@as(primitives.U256, i));
    }
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * ADD_GAS_COST + 1000);
}

fn benchOpAdd(_: std.mem.Allocator) void {
    for (0..OPS_PER_BATCH) |_| {
        _ = interpreter.opcodes.opAdd(&g_stack, &g_gas);
    }
    std.mem.doNotOptimizeAway(&g_stack);
}

pub fn main() !void {
    var stdout = std.fs.File.stdout().writerStreaming(&.{});
    const writer = &stdout.interface;
    const allocator = std.heap.page_allocator;

    try writer.writeAll("\n=== ZEVM Opcode Benchmark (zBench) ===\n\n");

    var bench = zbench.Benchmark.init(allocator, .{});
    defer bench.deinit();

    try bench.add("OP_ADD", benchOpAdd, .{
        .hooks = .{ .before_each = resetStackAndGas },
    });

    try writer.print("{s:<15}{s:<10}{s:<15}{s:<24}{s:<30}{s:<12}{s:<12}{s}\n", .{
        "benchmark", "runs", "total time", "time/op (avg ± σ)", "(min ... max)", "p75", "p99", "MGas/sec",
    });
    try writer.writeAll("-" ** 128 ++ "\n");

    var it = try bench.iterator();
    while (try it.next()) |step| {
        switch (step) {
            .progress => {},
            .result => |result| {
                defer result.deinit();
                const timings = result.readings.timings_ns;
                if (timings.len == 0) continue;
                const n: f64 = @floatFromInt(timings.len);
                const ops: f64 = @floatFromInt(OPS_PER_BATCH);

                var sum_f: f64 = 0;
                var min_f: f64 = std.math.floatMax(f64);
                var max_f: f64 = 0;
                for (timings) |t| {
                    const per_op: f64 = @as(f64, @floatFromInt(t)) / ops;
                    sum_f += per_op;
                    min_f = @min(min_f, per_op);
                    max_f = @max(max_f, per_op);
                }
                const mean_f = sum_f / n;

                var var_sum_f: f64 = 0;
                for (timings) |t| {
                    const per_op: f64 = @as(f64, @floatFromInt(t)) / ops;
                    const diff = per_op - mean_f;
                    var_sum_f += diff * diff;
                }
                const stddev_f = if (timings.len > 1) @sqrt(var_sum_f / (n - 1)) else 0;

                const per_op_buf = allocator.alloc(f64, timings.len) catch continue;
                defer allocator.free(per_op_buf);
                for (per_op_buf, timings) |*dst, t| dst.* = @as(f64, @floatFromInt(t)) / ops;
                std.mem.sort(f64, per_op_buf, {}, std.sort.asc(f64));
                const p75 = per_op_buf[timings.len * 75 / 100];
                const p99 = per_op_buf[timings.len * 99 / 100];

                const gas_per_op: f64 = @floatFromInt(ADD_GAS_COST);
                const mgas_per_sec = if (mean_f > 0) (gas_per_op * 1_000.0) / mean_f else 0;

                var total_ns: u64 = 0;
                for (timings) |t| total_ns += t;

                // Format each cell into a buffer, then print with fixed column widths
                var buf_runs: [32]u8 = undefined;
                var buf_total: [32]u8 = undefined;
                var buf_avg: [64]u8 = undefined;
                var buf_range: [64]u8 = undefined;
                var buf_p75: [32]u8 = undefined;
                var buf_p99: [32]u8 = undefined;
                var buf_mgas: [32]u8 = undefined;

                const s_runs = std.fmt.bufPrint(&buf_runs, "{d}", .{timings.len}) catch continue;
                const s_total = std.fmt.bufPrint(&buf_total, "{d}ms", .{total_ns / 1_000_000}) catch continue;
                const s_avg = std.fmt.bufPrint(&buf_avg, "{d:.2}ns ± {d:.2}ns", .{ mean_f, stddev_f }) catch continue;
                const s_range = std.fmt.bufPrint(&buf_range, "({d:.2}ns ... {d:.2}ns)", .{ min_f, max_f }) catch continue;
                const s_p75 = std.fmt.bufPrint(&buf_p75, "{d:.2}ns", .{p75}) catch continue;
                const s_p99 = std.fmt.bufPrint(&buf_p99, "{d:.2}ns", .{p99}) catch continue;
                const s_mgas = std.fmt.bufPrint(&buf_mgas, "{d:.0}", .{mgas_per_sec}) catch continue;

                try writer.print("{s:<15}{s:<10}{s:<15}{s:<24}{s:<30}{s:<12}{s:<12}{s}\n", .{
                    result.name, s_runs, s_total, s_avg, s_range, s_p75, s_p99, s_mgas,
                });
            },
        }
    }

    try writer.writeAll("\n");
}
