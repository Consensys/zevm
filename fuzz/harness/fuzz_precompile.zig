// fuzz_precompile.zig — Individual precompile fuzzing harness.
//
// Calls precompile functions directly without EVM overhead.
// Useful for finding bugs in the C library bindings (blst, mcl, secp256k1, openssl).
//
// Input format (min 10 bytes):
//   [0]      precompile_index (0..17 mapped to PrecompileId variants)
//   [1]      spec_variant (0=Homestead, 1=Byzantium, 2=Istanbul, 3=Berlin,
//                          4=Cancun, 5=Prague, 6+=Osaka)
//   [2..9]   gas_limit (u64 LE)
//   [10..]   raw precompile input data

const std = @import("std");
const primitives = @import("primitives");
const precompile_mod = @import("precompile");

const input_decoder = @import("input_decoder.zig");

/// Number of addressable standard precompiles (EcRec through P256Verify)
const NUM_PRECOMPILES: u8 = 18;

/// Map a spec_variant byte to PrecompileSpecId
fn specVariantToPrecompileSpec(v: u8) precompile_mod.PrecompileSpecId {
    return switch (v % 7) {
        0 => .Homestead,
        1 => .Byzantium,
        2 => .Istanbul,
        3 => .Berlin,
        4 => .Cancun,
        5 => .Prague,
        else => .Osaka,
    };
}

/// Map a precompile index to a PrecompileId
fn indexToPrecompileId(idx: u8) ?precompile_mod.PrecompileId {
    return switch (idx % NUM_PRECOMPILES) {
        0 => .EcRec,
        1 => .Sha256,
        2 => .Ripemd160,
        3 => .Identity,
        4 => .ModExp,
        5 => .Bn254Add,
        6 => .Bn254Mul,
        7 => .Bn254Pairing,
        8 => .Blake2F,
        9 => .KzgPointEvaluation,
        10 => .Bls12G1Add,
        11 => .Bls12G1Msm,
        12 => .Bls12G2Add,
        13 => .Bls12G2Msm,
        14 => .Bls12Pairing,
        15 => .Bls12MapFpToGp1,
        16 => .Bls12MapFp2ToGp2,
        17 => .P256Verify,
        else => null,
    };
}

/// Precompile fuzzing harness entry point.
pub fn zevm_fuzz_precompile(data: [*]const u8, len: usize) c_int {
    const input = input_decoder.decodePrecompileFuzzInput(data[0..len]) orelse return 0;

    const pc_id = indexToPrecompileId(input.precompile_index) orelse return 0;
    const spec = specVariantToPrecompileSpec(input.spec_variant);

    const pc = pc_id.precompile(spec) orelse return 0;
    const result = pc.func(input.input_data, input.gas_limit);

    // All PrecompileError variants are expected outcomes — not crashes.
    _ = result;
    return 0;
}
