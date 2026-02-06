// Arithmetic operations
pub const arithmetic = @import("arithmetic.zig");
pub const opAdd = arithmetic.opAdd;
pub const opSub = arithmetic.opSub;
pub const opMul = arithmetic.opMul;
pub const opDiv = arithmetic.opDiv;
pub const opMod = arithmetic.opMod;
pub const opAddmod = arithmetic.opAddmod;
pub const opMulmod = arithmetic.opMulmod;
pub const opExp = arithmetic.opExp;

// Bitwise operations
pub const bitwise = @import("bitwise.zig");
pub const opAnd = bitwise.opAnd;
pub const opOr = bitwise.opOr;
pub const opXor = bitwise.opXor;
pub const opNot = bitwise.opNot;
pub const opByte = bitwise.opByte;
pub const opShl = bitwise.opShl;
pub const opShr = bitwise.opShr;
pub const opSar = bitwise.opSar;

// Comparison operations
pub const comparison = @import("comparison.zig");
pub const opLt = comparison.opLt;
pub const opGt = comparison.opGt;
pub const opSlt = comparison.opSlt;
pub const opSgt = comparison.opSgt;
pub const opEq = comparison.opEq;
pub const opIsZero = comparison.opIsZero;

// Gas constants
pub const GAS_VERYLOW = arithmetic.GAS_VERYLOW;
pub const GAS_LOW = arithmetic.GAS_LOW;
pub const GAS_MID = arithmetic.GAS_MID;
pub const GAS_EXP = arithmetic.GAS_EXP;
pub const GAS_EXP_BYTE = arithmetic.GAS_EXP_BYTE;
