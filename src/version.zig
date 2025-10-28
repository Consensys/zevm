// Version information for ZEVM
pub const VERSION = "0.1.0";
pub const VERSION_MAJOR = 0;
pub const VERSION_MINOR = 1;
pub const VERSION_PATCH = 0;
pub const VERSION_STRING = "ZEVM v" ++ VERSION;
pub const RELEASE_DATE = "2025-10-27";

// Build information
pub const BUILD_DATE = @compileError("Build date should be set by build system");
pub const GIT_COMMIT = @compileError("Git commit should be set by build system");
pub const GIT_BRANCH = @compileError("Git branch should be set by build system");
