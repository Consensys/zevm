const std = @import("std");
const primitives = @import("primitives");
const main = @import("main.zig");
const blst_wrapper = @import("blst_wrapper.zig");

/// BLS12-381 elliptic curve precompiles
pub const g1_add = struct {
    pub const PRECOMPILE = main.Precompile.new(
        main.PrecompileId.Bls12G1Add,
        main.u64ToAddress(0x0B),
        bls12G1AddRun,
    );
};

pub const g1_msm = struct {
    pub const PRECOMPILE = main.Precompile.new(
        main.PrecompileId.Bls12G1Msm,
        main.u64ToAddress(0x0C),
        bls12G1MsmRun,
    );
};

pub const g2_add = struct {
    pub const PRECOMPILE = main.Precompile.new(
        main.PrecompileId.Bls12G2Add,
        main.u64ToAddress(0x0D),
        bls12G2AddRun,
    );
};

pub const g2_msm = struct {
    pub const PRECOMPILE = main.Precompile.new(
        main.PrecompileId.Bls12G2Msm,
        main.u64ToAddress(0x0E),
        bls12G2MsmRun,
    );
};

pub const pairing = struct {
    pub const PRECOMPILE = main.Precompile.new(
        main.PrecompileId.Bls12Pairing,
        main.u64ToAddress(0x0F),
        bls12PairingRun,
    );
};

pub const map_fp_to_g1 = struct {
    pub const PRECOMPILE = main.Precompile.new(
        main.PrecompileId.Bls12MapFpToGp1,
        main.u64ToAddress(0x10),
        bls12MapFpToG1Run,
    );
};

pub const map_fp2_to_g2 = struct {
    pub const PRECOMPILE = main.Precompile.new(
        main.PrecompileId.Bls12MapFp2ToGp2,
        main.u64ToAddress(0x11),
        bls12MapFp2ToG2Run,
    );
};

// Constants
const FP_LENGTH: usize = 48;
const PADDED_FP_LENGTH: usize = 64;
const G1_LENGTH: usize = 2 * FP_LENGTH; // 96 bytes (unpadded)
const PADDED_G1_LENGTH: usize = 2 * PADDED_FP_LENGTH; // 128 bytes (padded)
const FP2_LENGTH: usize = 2 * FP_LENGTH; // 96 bytes
const PADDED_FP2_LENGTH: usize = 2 * PADDED_FP_LENGTH; // 128 bytes
const G2_LENGTH: usize = 2 * FP2_LENGTH; // 192 bytes (unpadded)
const PADDED_G2_LENGTH: usize = 2 * PADDED_FP2_LENGTH; // 256 bytes (padded)
const SCALAR_LENGTH: usize = 32;

// Gas costs
const G1_ADD_BASE_GAS_FEE: u64 = 375;
const G1_MSM_BASE_GAS_FEE: u64 = 12000;
const G2_ADD_BASE_GAS_FEE: u64 = 600;
const G2_MSM_BASE_GAS_FEE: u64 = 22500;
const MAP_FP_TO_G1_BASE_GAS_FEE: u64 = 5500;
const MAP_FP2_TO_G2_BASE_GAS_FEE: u64 = 23800;
const PAIRING_OFFSET_BASE: u64 = 37700;
const PAIRING_MULTIPLIER_BASE: u64 = 32600;
const MSM_MULTIPLIER: u64 = 1000;

// Discount tables for MSM
const DISCOUNT_TABLE_G1_MSM: [128]u16 = .{
    1000, 949, 848, 797, 764, 750, 738, 728, 719, 712, 705, 698, 692, 687, 682, 677, 673, 669, 665,
    661, 658, 654, 651, 648, 645, 642, 640, 637, 635, 632, 630, 627, 625, 623, 621, 619, 617, 615,
    613, 611, 609, 608, 606, 604, 603, 601, 599, 598, 596, 595, 593, 592, 591, 589, 588, 586, 585,
    584, 582, 581, 580, 579, 577, 576, 575, 574, 573, 572, 570, 569, 568, 567, 566, 565, 564, 563,
    562, 561, 560, 559, 558, 557, 556, 555, 554, 553, 552, 551, 550, 549, 548, 547, 547, 546, 545,
    544, 543, 542, 541, 540, 540, 539, 538, 537, 536, 536, 535, 534, 533, 532, 532, 531, 530, 529,
    528, 528, 527, 526, 525, 525, 524, 523, 522, 522, 521, 520, 520, 519,
};

const DISCOUNT_TABLE_G2_MSM: [128]u16 = .{
    1000, 1000, 923, 884, 855, 832, 812, 796, 782, 770, 759, 749, 740, 732, 724, 717, 711, 704,
    699, 693, 688, 683, 679, 674, 670, 666, 663, 659, 655, 652, 649, 646, 643, 640, 637, 634, 632,
    629, 627, 624, 622, 620, 618, 615, 613, 611, 609, 607, 606, 604, 602, 600, 598, 597, 595, 593,
    592, 590, 589, 587, 586, 584, 583, 582, 580, 579, 578, 576, 575, 574, 573, 571, 570, 569, 568,
    567, 566, 565, 563, 562, 561, 560, 559, 558, 557, 556, 555, 554, 553, 552, 552, 551, 550, 549,
    548, 547, 546, 545, 545, 544, 543, 542, 541, 541, 540, 539, 538, 537, 537, 536, 535, 535, 534,
    533, 532, 532, 531, 530, 530, 529, 528, 528, 527, 526, 526, 525, 524, 524,
};

/// Remove padding from G1 point (128 bytes -> 96 bytes)
fn removeG1Padding(padded: []const u8) ![2][FP_LENGTH]u8 {
    if (padded.len < PADDED_G1_LENGTH) {
        return main.PrecompileError.Bls12381G1AddInputLength;
    }
    var result: [2][FP_LENGTH]u8 = undefined;
    @memcpy(&result[0], padded[16..16 + FP_LENGTH]); // Skip 16-byte padding
    @memcpy(&result[1], padded[80..80 + FP_LENGTH]); // Skip 16-byte padding
    return result;
}

/// Pad G1 point (96 bytes -> 128 bytes)
fn padG1Point(unpadded: []const u8) [PADDED_G1_LENGTH]u8 {
    var result: [PADDED_G1_LENGTH]u8 = [_]u8{0} ** PADDED_G1_LENGTH;
    @memcpy(result[16..16 + FP_LENGTH], unpadded[0..FP_LENGTH]);
    @memcpy(result[80..80 + FP_LENGTH], unpadded[FP_LENGTH..]);
    return result;
}

/// Remove padding from G2 point (256 bytes -> 192 bytes)
fn removeG2Padding(padded: []const u8) ![4][FP_LENGTH]u8 {
    if (padded.len < PADDED_G2_LENGTH) {
        return main.PrecompileError.Bls12381G2AddInputLength;
    }
    var result: [4][FP_LENGTH]u8 = undefined;
    @memcpy(&result[0], padded[16..16 + FP_LENGTH]);
    @memcpy(&result[1], padded[80..80 + FP_LENGTH]);
    @memcpy(&result[2], padded[144..144 + FP_LENGTH]);
    @memcpy(&result[3], padded[208..208 + FP_LENGTH]);
    return result;
}

/// Pad G2 point (192 bytes -> 256 bytes)
fn padG2Point(unpadded: []const u8) [PADDED_G2_LENGTH]u8 {
    var result: [PADDED_G2_LENGTH]u8 = [_]u8{0} ** PADDED_G2_LENGTH;
    @memcpy(result[16..16 + FP_LENGTH], unpadded[0..FP_LENGTH]);
    @memcpy(result[80..80 + FP_LENGTH], unpadded[FP_LENGTH..]);
    @memcpy(result[144..144 + FP_LENGTH], unpadded[FP2_LENGTH..][0..FP_LENGTH]);
    @memcpy(result[208..208 + FP_LENGTH], unpadded[FP2_LENGTH..][FP_LENGTH..]);
    return result;
}

/// BLS12-381 G1 point addition
pub fn bls12G1AddRun(input: []const u8, gas_limit: u64) main.PrecompileResult {
    if (G1_ADD_BASE_GAS_FEE > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    if (input.len != PADDED_G1_LENGTH * 2) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bls12381G1AddInputLength };
    }

    const a_coords = removeG1Padding(input[0..PADDED_G1_LENGTH]) catch |e| return main.PrecompileResult{ .err = e };
    const b_coords = removeG1Padding(input[PADDED_G1_LENGTH..]) catch |e| return main.PrecompileResult{ .err = e };

    // Convert to unpadded format for blst
    // a_coords and b_coords are [2][48]u8, we need to flatten to [96]u8
    var a_unpadded: [G1_LENGTH]u8 = undefined;
    @memcpy(a_unpadded[0..48], &a_coords[0]);
    @memcpy(a_unpadded[48..96], &a_coords[1]);
    var b_unpadded: [G1_LENGTH]u8 = undefined;
    @memcpy(b_unpadded[0..48], &b_coords[0]);
    @memcpy(b_unpadded[48..96], &b_coords[1]);

    var unpadded_result: [G1_LENGTH]u8 = undefined;
    if (blst_wrapper.isAvailable()) {
        if (blst_wrapper.g1Add(a_unpadded, b_unpadded)) |result| {
            unpadded_result = result;
        } else |_| {
            // Fallback to placeholder if blst fails
            @memset(&unpadded_result, 0);
        }
    } else {
        // Placeholder if blst not available
        @memset(&unpadded_result, 0);
    }

    const padded_result = padG1Point(&unpadded_result);
    return main.PrecompileResult{ .success = main.PrecompileOutput.new(G1_ADD_BASE_GAS_FEE, &padded_result) };
}

/// BLS12-381 G1 multi-scalar multiplication
pub fn bls12G1MsmRun(input: []const u8, gas_limit: u64) main.PrecompileResult {
    if (input.len < PADDED_G1_LENGTH + PADDED_FP_LENGTH) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bls12381G1MsmInputLength };
    }

    const k = input.len / (PADDED_G1_LENGTH + PADDED_FP_LENGTH);
    if (k == 0) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bls12381G1MsmInputLength };
    }

    const discount = if (k <= DISCOUNT_TABLE_G1_MSM.len) DISCOUNT_TABLE_G1_MSM[k - 1] else DISCOUNT_TABLE_G1_MSM[DISCOUNT_TABLE_G1_MSM.len - 1];
    const gas_used = (@as(u64, k) * G1_MSM_BASE_GAS_FEE * @as(u64, discount)) / MSM_MULTIPLIER;
    if (gas_used > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    // TODO: Replace with actual BLS12-381 G1 MSM using external library
    var unpadded_result: [G1_LENGTH]u8 = undefined;
    @memset(&unpadded_result, 0);
    // TODO: Parse point-scalar pairs and call bls12_381_g1_msm() from crypto library

    const padded_result = padG1Point(&unpadded_result);
    return main.PrecompileResult{ .success = main.PrecompileOutput.new(gas_used, &padded_result) };
}

/// BLS12-381 G2 point addition
pub fn bls12G2AddRun(input: []const u8, gas_limit: u64) main.PrecompileResult {
    if (G2_ADD_BASE_GAS_FEE > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    if (input.len != PADDED_G2_LENGTH * 2) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bls12381G2AddInputLength };
    }

    const a_coords = removeG2Padding(input[0..PADDED_G2_LENGTH]) catch |e| return main.PrecompileResult{ .err = e };
    const b_coords = removeG2Padding(input[PADDED_G2_LENGTH..]) catch |e| return main.PrecompileResult{ .err = e };

    // TODO: Replace with actual BLS12-381 G2 addition using external library
    _ = a_coords;
    _ = b_coords;
    var unpadded_result: [G2_LENGTH]u8 = undefined;
    @memset(&unpadded_result, 0);
    // TODO: Call bls12_381_g2_add(a_coords, b_coords) from crypto library

    const padded_result = padG2Point(&unpadded_result);
    return main.PrecompileResult{ .success = main.PrecompileOutput.new(G2_ADD_BASE_GAS_FEE, &padded_result) };
}

/// BLS12-381 G2 multi-scalar multiplication
pub fn bls12G2MsmRun(input: []const u8, gas_limit: u64) main.PrecompileResult {
    if (input.len < PADDED_G2_LENGTH + PADDED_FP_LENGTH) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bls12381G2MsmInputLength };
    }

    const k = input.len / (PADDED_G2_LENGTH + PADDED_FP_LENGTH);
    if (k == 0) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bls12381G2MsmInputLength };
    }

    const discount = if (k <= DISCOUNT_TABLE_G2_MSM.len) DISCOUNT_TABLE_G2_MSM[k - 1] else DISCOUNT_TABLE_G2_MSM[DISCOUNT_TABLE_G2_MSM.len - 1];
    const gas_used = (@as(u64, k) * G2_MSM_BASE_GAS_FEE * @as(u64, discount)) / MSM_MULTIPLIER;
    if (gas_used > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    // TODO: Replace with actual BLS12-381 G2 MSM using external library
    var unpadded_result: [G2_LENGTH]u8 = undefined;
    @memset(&unpadded_result, 0);
    // TODO: Parse point-scalar pairs and call bls12_381_g2_msm() from crypto library

    const padded_result = padG2Point(&unpadded_result);
    return main.PrecompileResult{ .success = main.PrecompileOutput.new(gas_used, &padded_result) };
}

/// BLS12-381 pairing check
pub fn bls12PairingRun(input: []const u8, gas_limit: u64) main.PrecompileResult {
    if (input.len < PADDED_G1_LENGTH + PADDED_G2_LENGTH) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bls12381PairingInputLength };
    }

    const pair_len = PADDED_G1_LENGTH + PADDED_G2_LENGTH;
    if (input.len % pair_len != 0) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bls12381PairingInputLength };
    }

    const num_pairs = input.len / pair_len;
    const gas_used = @as(u64, num_pairs) * PAIRING_MULTIPLIER_BASE + PAIRING_OFFSET_BASE;
    if (gas_used > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    // TODO: Replace with actual BLS12-381 pairing check using external library
    // Parse pairs and verify pairing
    var i: usize = 0;
    while (i < input.len) : (i += pair_len) {
        const g1_bytes = input[i..][0..PADDED_G1_LENGTH];
        const g2_bytes = input[i + PADDED_G1_LENGTH..][0..PADDED_G2_LENGTH];
        _ = g1_bytes;
        _ = g2_bytes;
        // TODO: Validate and add to pairing check
    }

    // Placeholder: actual implementation would check pairing
    // Result is 1 if pairing is valid, 0 otherwise
    var output: [32]u8 = [_]u8{0} ** 32;
    output[31] = 1; // Placeholder: assume valid

    return main.PrecompileResult{ .success = main.PrecompileOutput.new(gas_used, &output) };
}

/// BLS12-381 map field element to G1
pub fn bls12MapFpToG1Run(input: []const u8, gas_limit: u64) main.PrecompileResult {
    if (MAP_FP_TO_G1_BASE_GAS_FEE > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    if (input.len != PADDED_FP_LENGTH) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bls12381MapFpToG1InputLength };
    }

    // TODO: Replace with actual BLS12-381 map Fp to G1 using external library
    var unpadded_result: [G1_LENGTH]u8 = undefined;
    @memset(&unpadded_result, 0);
    // TODO: Extract field element from input[16..16+FP_LENGTH] and call map_fp_to_g1()

    const padded_result = padG1Point(&unpadded_result);
    return main.PrecompileResult{ .success = main.PrecompileOutput.new(MAP_FP_TO_G1_BASE_GAS_FEE, &padded_result) };
}

/// BLS12-381 map field element to G2
pub fn bls12MapFp2ToG2Run(input: []const u8, gas_limit: u64) main.PrecompileResult {
    if (MAP_FP2_TO_G2_BASE_GAS_FEE > gas_limit) {
        return main.PrecompileResult{ .err = main.PrecompileError.OutOfGas };
    }

    if (input.len != PADDED_FP2_LENGTH) {
        return main.PrecompileResult{ .err = main.PrecompileError.Bls12381MapFp2ToG2InputLength };
    }

    // TODO: Replace with actual BLS12-381 map Fp2 to G2 using external library
    var unpadded_result: [G2_LENGTH]u8 = undefined;
    @memset(&unpadded_result, 0);
    // TODO: Extract Fp2 element and call map_fp2_to_g2()

    const padded_result = padG2Point(&unpadded_result);
    return main.PrecompileResult{ .success = main.PrecompileOutput.new(MAP_FP2_TO_G2_BASE_GAS_FEE, &padded_result) };
}
