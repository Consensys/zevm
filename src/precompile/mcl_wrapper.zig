//! mcl wrapper for BN254 (alt_bn128) operations
//! Requires mcl library to be installed and linked with C bindings
//!
//! mcl is required by default. Install mcl: https://github.com/herumi/mcl
const std = @import("std");

// Import mcl C API
// This will fail at compile time if mcl headers are not found
// Install mcl: https://github.com/herumi/mcl
const build_options = @import("build_options");

const c = if (build_options.enable_mcl) blk: {
    break :blk @cImport({
        @cDefine("MCL_FP_BIT", "256");
        @cDefine("MCL_FR_BIT", "256");
        @cInclude("mcl/bn_c256.h");
    });
} else struct {
    // Stub types when mcl is disabled (should not happen by default)
    pub const mclBnG1 = extern struct { d: [8]u64 = undefined };
    pub const mclBnG2 = extern struct { d: [16]u64 = undefined };
    pub const mclBnFr = extern struct { d: [4]u64 = undefined };
    pub const mclBnGT = extern struct { d: [12]u64 = undefined };
    pub const mclSize = usize;
    pub fn mclBnG1_deserialize(_: *mclBnG1, _: *const anyopaque, _: mclSize) mclSize {
        return 0;
    }
    pub fn mclBnG1_serialize(_: *anyopaque, _: mclSize, _: *const mclBnG1) mclSize {
        return 0;
    }
    pub fn mclBnG1_add(_: *mclBnG1, _: *const mclBnG1, _: *const mclBnG1) void {}
    pub fn mclBnG1_mul(_: *mclBnG1, _: *const mclBnG1, _: *const mclBnFr) void {}
    pub fn mclBnG2_deserialize(_: *mclBnG2, _: *const anyopaque, _: mclSize) mclSize {
        return 0;
    }
    pub fn mclBnFr_deserialize(_: *mclBnFr, _: *const anyopaque, _: mclSize) mclSize {
        return 0;
    }
    pub fn mclBn_pairing(_: *mclBnGT, _: *const mclBnG1, _: *const mclBnG2) void {}
    pub fn mclBnGT_setInt(_: *mclBnGT, _: c_int) void {}
    pub fn mclBnGT_mul(_: *mclBnGT, _: *const mclBnGT, _: *const mclBnGT) void {}
    pub fn mclBnGT_isOne(_: *const mclBnGT) i32 {
        return 0;
    }
    pub fn mclBnG1_isValid(_: *const mclBnG1) i32 {
        return 0;
    }
    pub fn mclBnG2_isValid(_: *const mclBnG2) i32 {
        return 0;
    }
};

// Initialize mcl once (thread-safe initialization)
var mcl_initialized: std.Thread.Mutex = .{};
var mcl_init_done: bool = false;

/// Initialize mcl library (call once before using)
fn initMcl() void {
    mcl_initialized.lock();
    defer mcl_initialized.unlock();

    if (mcl_init_done) return;

    if (build_options.enable_mcl) {
        // Initialize mcl with BN254 curve (curve type 1 = BN_SNARK1)
        // Enable ETH serialization (big-endian) to match Ethereum format
        _ = c.mclBn_init(1, 0); // 1 = BN_SNARK1 (BN254), 0 = compiled time var
        c.mclBn_setETHserialization(1); // Enable ETH serialization
        mcl_init_done = true;
    }
}

/// Check if mcl is available
/// mcl is enabled by default, but can be disabled with -Dmcl=false
pub fn isAvailable() bool {
    return build_options.enable_mcl;
}

/// BN254 G1 point addition
/// Input: two 64-byte G1 points (x || y, each 32 bytes, big-endian)
/// Output: 64-byte G1 point (x || y, big-endian)
pub fn g1Add(a: [64]u8, b: [64]u8) ![64]u8 {
    if (!isAvailable()) {
        return error.MclNotAvailable;
    }

    initMcl();

    // Deserialize G1 points from big-endian bytes
    var p1: c.mclBnG1 = undefined;
    var p2: c.mclBnG1 = undefined;

    const p1_size = c.mclBnG1_deserialize(&p1, &a, 64);
    if (p1_size == 0) {
        return error.InvalidG1Point;
    }

    const p2_size = c.mclBnG1_deserialize(&p2, &b, 64);
    if (p2_size == 0) {
        return error.InvalidG1Point;
    }

    // Validate points are on curve
    if (c.mclBnG1_isValid(&p1) == 0 or c.mclBnG1_isValid(&p2) == 0) {
        return error.InvalidG1Point;
    }

    // Perform addition
    var result: c.mclBnG1 = undefined;
    c.mclBnG1_add(&result, &p1, &p2);

    // Serialize result to big-endian bytes
    var output: [64]u8 = undefined;
    const output_size = c.mclBnG1_serialize(&output, 64, &result);
    if (output_size == 0) {
        return error.InvalidG1Point;
    }

    return output;
}

/// BN254 G1 scalar multiplication
/// Input: 64-byte G1 point, 32-byte scalar (big-endian)
/// Output: 64-byte G1 point (x || y, big-endian)
pub fn g1Mul(point: [64]u8, scalar: [32]u8) ![64]u8 {
    if (!isAvailable()) {
        return error.MclNotAvailable;
    }

    initMcl();

    // Deserialize G1 point from big-endian bytes
    var p: c.mclBnG1 = undefined;
    const p_size = c.mclBnG1_deserialize(&p, &point, 64);
    if (p_size == 0) {
        return error.InvalidG1Point;
    }

    // Validate point is on curve
    if (c.mclBnG1_isValid(&p) == 0) {
        return error.InvalidG1Point;
    }

    // Deserialize scalar from big-endian bytes
    var s: c.mclBnFr = undefined;
    const s_size = c.mclBnFr_deserialize(&s, &scalar, 32);
    if (s_size == 0) {
        return error.InvalidInput;
    }

    // Perform scalar multiplication
    var result: c.mclBnG1 = undefined;
    c.mclBnG1_mul(&result, &p, &s);

    // Serialize result to big-endian bytes
    var output: [64]u8 = undefined;
    const output_size = c.mclBnG1_serialize(&output, 64, &result);
    if (output_size == 0) {
        return error.InvalidG1Point;
    }

    return output;
}

/// BN254 pairing check
/// Input: array of (G1, G2) point pairs
/// Returns true if pairing product equals identity (pairing is valid)
pub fn pairingCheck(pairs: []const struct { g1: [64]u8, g2: [128]u8 }) !bool {
    if (!isAvailable()) {
        return error.MclNotAvailable;
    }

    if (pairs.len == 0) {
        return true; // Empty pairing is valid
    }

    initMcl();

    // Initialize GT element to identity (1)
    var gt_result: c.mclBnGT = undefined;
    c.mclBnGT_setInt(&gt_result, 1);

    // Process each pair
    for (pairs) |pair| {
        // Deserialize G1 point
        var g1: c.mclBnG1 = undefined;
        const g1_size = c.mclBnG1_deserialize(&g1, &pair.g1, 64);
        if (g1_size == 0) {
            return error.InvalidG1Point;
        }

        // Deserialize G2 point
        var g2: c.mclBnG2 = undefined;
        const g2_size = c.mclBnG2_deserialize(&g2, &pair.g2, 128);
        if (g2_size == 0) {
            return error.InvalidG2Point;
        }

        // Validate points are on curve
        if (c.mclBnG1_isValid(&g1) == 0 or c.mclBnG2_isValid(&g2) == 0) {
            return error.InvalidInput;
        }

        // Compute pairing for this pair
        var temp_gt: c.mclBnGT = undefined;
        c.mclBn_pairing(&temp_gt, &g1, &g2);

        // Multiply into result (accumulate product)
        var new_result: c.mclBnGT = undefined;
        c.mclBnGT_mul(&new_result, &gt_result, &temp_gt);
        gt_result = new_result;
    }

    // Check if result is identity (1)
    return c.mclBnGT_isOne(&gt_result) != 0;
}

pub const MclError = error{
    MclNotAvailable,
    InvalidG1Point,
    InvalidG2Point,
    InvalidInput,
};
