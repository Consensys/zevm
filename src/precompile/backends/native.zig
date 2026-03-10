/// Native C-library backends for EVM precompile operations.
///
/// Each sub-namespace wraps a C library and is conditionally compiled
/// based on the corresponding build_options flag:
///   enable_secp256k1  →  secp256k1 (ECRECOVER)
///   enable_openssl    →  openssl   (P256VERIFY)
///   enable_blst       →  blst      (BLS12-381, KZG)
///   enable_mcl        →  mcl       (BN254)
///
/// Import this via `precompile.backends.native.*` from external code, or
/// use the precompile functions directly — they dispatch here automatically.
pub const secp256k1 = @import("../secp256k1_wrapper.zig");
pub const openssl = @import("../openssl_wrapper.zig");
pub const blst = @import("../blst_wrapper.zig");
pub const mcl = @import("../mcl_wrapper.zig");
