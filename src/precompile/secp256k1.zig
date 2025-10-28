const std = @import("std");
const primitives = @import("primitives");
const main = @import("main.zig");

/// ECRECOVER precompile
pub const ECRECOVER = main.Precompile.new(
    main.PrecompileId.EcRec,
    main.u64ToAddress(1),
    ecRecoverRun,
);

/// Right pad input to specified length
fn rightPad(comptime len: usize, input: []const u8) [len]u8 {
    var output: [len]u8 = [_]u8{0} ** len;
    const copy_len = @min(input.len, len);
    std.mem.copyForwards(u8, output[0..copy_len], input[0..copy_len]);
    return output;
}

/// ECRECOVER precompile function
///
/// Input format:
/// [32 bytes for message][64 bytes for signature][1 byte for recovery id]
///
/// Output format:
/// [32 bytes for recovered address]
pub fn ecRecoverRun(input: []const u8, gas_limit: u64) main.PrecompileResult {
    const ECRECOVER_BASE: u64 = 3_000;

    if (ECRECOVER_BASE > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    const padded_input = rightPad(128, input);

    // `v` must be a 32-byte big-endian integer equal to 27 or 28.
    const v_valid = std.mem.allEqual(u8, padded_input[32..63], 0) and
        (padded_input[63] == 27 or padded_input[63] == 28);

    if (!v_valid) {
        return main.PrecompileResult{ .success = main.PrecompileOutput.new(ECRECOVER_BASE, &[_]u8{}) };
    }

    const msg = padded_input[0..32];
    const recid = padded_input[63] - 27;
    const sig = padded_input[64..128];

    // For now, return empty result (would need proper secp256k1 implementation)
    // In a real implementation, this would use a secp256k1 library
    _ = msg;
    _ = recid;
    _ = sig;

    return main.PrecompileResult{ .success = main.PrecompileOutput.new(ECRECOVER_BASE, &[_]u8{}) };
}
