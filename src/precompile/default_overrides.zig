/// Default precompile overrides — all null, meaning the built-in implementations are used.
///
/// To override specific precompiles at build time:
///   1. Create your own override module (e.g. src/zisk/precompile_overrides.zig)
///   2. Import "precompile_types" (injected by build.zig) for the PrecompileFn type
///   3. Set non-null values for the precompiles you want to replace
///   4. In your build.zig, call:
///        precompile_module.addImport("precompile_overrides", your_module);
///
/// The override module must export all of the same pub const names as this file.
/// Any name left null will fall through to the default implementation.

const T = @import("precompile_types");

// ── Homestead ──────────────────────────────────────────────────────────────
pub const ecrecover: ?T.PrecompileFn = null;
pub const sha256: ?T.PrecompileFn = null;
pub const ripemd160: ?T.PrecompileFn = null;
pub const identity: ?T.PrecompileFn = null;

// ── Byzantium ──────────────────────────────────────────────────────────────
pub const modexp_byzantium: ?T.PrecompileFn = null;
pub const bn254_add_byzantium: ?T.PrecompileFn = null;
pub const bn254_mul_byzantium: ?T.PrecompileFn = null;
pub const bn254_pairing_byzantium: ?T.PrecompileFn = null;

// ── Istanbul ───────────────────────────────────────────────────────────────
pub const bn254_add_istanbul: ?T.PrecompileFn = null;
pub const bn254_mul_istanbul: ?T.PrecompileFn = null;
pub const bn254_pairing_istanbul: ?T.PrecompileFn = null;
pub const blake2f: ?T.PrecompileFn = null;

// ── Berlin ─────────────────────────────────────────────────────────────────
pub const modexp_berlin: ?T.PrecompileFn = null;

// ── Cancun ─────────────────────────────────────────────────────────────────
pub const kzg_point_evaluation: ?T.PrecompileFn = null;

// ── Prague / BLS12-381 ─────────────────────────────────────────────────────
pub const bls12_g1_add: ?T.PrecompileFn = null;
pub const bls12_g1_msm: ?T.PrecompileFn = null;
pub const bls12_g2_add: ?T.PrecompileFn = null;
pub const bls12_g2_msm: ?T.PrecompileFn = null;
pub const bls12_pairing: ?T.PrecompileFn = null;
pub const bls12_map_fp_to_g1: ?T.PrecompileFn = null;
pub const bls12_map_fp2_to_g2: ?T.PrecompileFn = null;

// ── Osaka ──────────────────────────────────────────────────────────────────
pub const modexp_osaka: ?T.PrecompileFn = null;
pub const p256verify: ?T.PrecompileFn = null;
pub const p256verify_osaka: ?T.PrecompileFn = null;
