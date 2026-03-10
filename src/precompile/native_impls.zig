/// Native (host-OS) precompile implementations.
///
/// This is the root source file for the "precompile_implementations" module
/// used by zevm's native builds.  It owns secp256k1.zig, bn254.zig,
/// secp256r1.zig, kzg_point_evaluation.zig, and bls12_381.zig — none of
/// which are imported anywhere else in the precompile module, so module
/// ownership is unambiguous.
///
/// Downstream builds that target freestanding environments (e.g. Zisk zkVM)
/// should inject their own "precompile_implementations" module via:
///
///   precompile_module.addImport("precompile_implementations", your_module);
///
/// That module must export all of the same pub const names defined here.
const T = @import("precompile_types");

const secp256k1_impl = @import("secp256k1.zig");
const bn254_impl = @import("bn254.zig");
const secp256r1_impl = @import("secp256r1.zig");
const kzg_impl = @import("kzg_point_evaluation.zig");
const bls12_impl = @import("bls12_381.zig");

// ── Homestead ──────────────────────────────────────────────────────────────
pub const ecrecover: T.PrecompileFn = secp256k1_impl.ecRecoverRun;

// ── Byzantium ──────────────────────────────────────────────────────────────
pub const bn254_add_byzantium: T.PrecompileFn = bn254_impl.bn254AddRunByzantium;
pub const bn254_mul_byzantium: T.PrecompileFn = bn254_impl.bn254MulRunByzantium;
pub const bn254_pairing_byzantium: T.PrecompileFn = bn254_impl.bn254PairingRunByzantium;

// ── Istanbul ───────────────────────────────────────────────────────────────
pub const bn254_add_istanbul: T.PrecompileFn = bn254_impl.bn254AddRunIstanbul;
pub const bn254_mul_istanbul: T.PrecompileFn = bn254_impl.bn254MulRunIstanbul;
pub const bn254_pairing_istanbul: T.PrecompileFn = bn254_impl.bn254PairingRunIstanbul;

// ── Cancun ─────────────────────────────────────────────────────────────────
pub const kzg_point_evaluation: T.PrecompileFn = kzg_impl.kzgPointEvaluationRun;

// ── Prague / BLS12-381 ─────────────────────────────────────────────────────
pub const bls12_g1_add: T.PrecompileFn = bls12_impl.bls12G1AddRun;
pub const bls12_g1_msm: T.PrecompileFn = bls12_impl.bls12G1MsmRun;
pub const bls12_g2_add: T.PrecompileFn = bls12_impl.bls12G2AddRun;
pub const bls12_g2_msm: T.PrecompileFn = bls12_impl.bls12G2MsmRun;
pub const bls12_pairing: T.PrecompileFn = bls12_impl.bls12PairingRun;
pub const bls12_map_fp_to_g1: T.PrecompileFn = bls12_impl.bls12MapFpToG1Run;
pub const bls12_map_fp2_to_g2: T.PrecompileFn = bls12_impl.bls12MapFp2ToG2Run;

// ── Osaka ──────────────────────────────────────────────────────────────────
pub const p256verify: T.PrecompileFn = secp256r1_impl.p256Verify;
pub const p256verify_osaka: T.PrecompileFn = secp256r1_impl.p256VerifyOsaka;
