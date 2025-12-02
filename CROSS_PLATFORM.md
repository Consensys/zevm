# Cross-Platform Build Guide

This document explains how to build ZEVM on different platforms (macOS, Linux, Windows).

## Platform Support

ZEVM is designed to work on:
- **macOS** (tested on macOS 14+)
- **Linux** (tested on Ubuntu/Debian-based systems)
- **Windows** (Windows 10/11, requires MSVC or MinGW toolchain)

## Build System

The build system (`build.zig`) automatically detects the target platform and adjusts:
- Default include paths for required libraries
- Library linking (e.g., math library `libm` is Unix-only)
- Platform-specific library names

**⚠️ Important**: All precompile dependencies (`blst` and `mcl`) are **required by default**. If you see "library not found" errors, you need to install these libraries before building. See the "Required Libraries" section below for installation instructions.

## Quick Start

**Easiest way to build:**
```bash
make                    # Auto-detects OS, installs deps, and builds
make install-deps       # Install dependencies only
make build             # Build only (assumes deps are installed)
make test              # Run tests
```

The Makefile automatically:
- Detects your operating system
- Installs required dependencies
- Builds the project with correct options

See the Makefile for more options and customization.

## Building on Different Platforms

### Using Makefile (Recommended)

```bash
# Auto-detect OS and build
make

# Install dependencies only
make install-deps

# Build without blst or mcl
make BLST_ENABLED=false MCL_ENABLED=false

# Custom include paths
make BLST_INCLUDE=/path/to/blst/bindings MCL_INCLUDE=/path/to/mcl/include
```

### Manual Build

#### macOS

```bash
# Standard build (blst is required by default)
zig build

# Build with custom include path (if blst built from source)
zig build -Dblst-include=/path/to/blst/bindings

# Disable blst if needed (not recommended)
zig build -Dblst=false
```

**Installing dependencies:**
```bash
brew install libsecp256k1 openssl

# Build blst from source (required, not available via Homebrew)
# See "Required Libraries" section below for installation instructions
```

### Linux

```bash
# Standard build (blst is required by default)
zig build

# Build with custom include path (if blst installed in non-standard location)
zig build -Dblst-include=/usr/include

# Disable blst if needed (not recommended)
zig build -Dblst=false
```

**Installing dependencies (Ubuntu/Debian):**
```bash
sudo apt-get update
sudo apt-get install -y libsecp256k1-dev libssl-dev

# Build blst from source (required)
# See "Required Libraries" section below for installation instructions
```

**Installing dependencies (Fedora/RHEL):**
```bash
sudo dnf install libsecp256k1-devel openssl-devel
```

### Windows

```bash
# Standard build (blst is required by default)
zig build

# Build with custom include path (if blst installed in non-standard location)
zig build -Dblst-include="C:/vcpkg/installed/x64-windows/include"

# Disable blst if needed (not recommended)
zig build -Dblst=false
```

**Installing dependencies on Windows:**

1. **Using vcpkg** (recommended):
   ```powershell
   vcpkg install secp256k1 openssl
   # Optional:
   vcpkg install blst
   ```

2. **Using pre-built binaries:**
   - Download OpenSSL from: https://slproweb.com/products/Win32OpenSSL.html
   - Download secp256k1 or build from source
   - Set include paths using `-Dblst-include=...` and `-Dmcl-include=...`

## Platform-Specific Notes

### Include Paths

The build system uses platform-specific defaults:
- **macOS/Linux**: `/usr/local/include` (standard Unix location)
- **Windows**: `C:/Program Files` (users should override with `-Dblst-include=...`)

You can always override defaults:
```bash
zig build -Dblst-include=/custom/path/to/blst/include
zig build -Dmcl-include=/custom/path/to/mcl/include
```

### Library Linking

The build system automatically handles:
- **Math library (`libm`)**: Only linked on Unix systems (not needed on Windows)
- **OpenSSL**: Uses standard names (`ssl`, `crypto`) on all platforms
- **secp256k1**: Uses standard name on all platforms

### Cross-Compilation

Zig supports cross-compilation out of the box:

```bash
# Build for Linux from macOS
zig build -Dtarget=x86_64-linux-gnu

# Build for Windows from macOS/Linux
zig build -Dtarget=x86_64-windows

# Build for macOS from Linux
zig build -Dtarget=x86_64-macos
```

When cross-compiling, you may need to:
1. Install target-specific libraries
2. Specify custom include paths for the target platform
3. Use `zig cc` to compile C dependencies for the target

## Required Libraries

All precompile dependencies are required by default. You can disable them individually with `-Dblst=false` or `-Dmcl=false` if needed, but this will disable the corresponding precompiles.

### BLST (BLS12-381 and KZG)

**Status**: Required by default, enables BLS12-381 precompiles and KZG point evaluation

**Note**: You can disable blst with `-Dblst=false`, but this will disable BLS12-381 and KZG precompiles.

**Installation:**

**macOS** (build from source):
```bash
# Clone the repository
git clone https://github.com/supranational/blst.git
cd blst

# Build the library
./build.sh

# Install (optional, or use custom include path)
# The library will be in ./libblst.a
# Headers will be in ./bindings/
# You can then use: zig build -Dblst=true -Dblst-include=/path/to/blst/bindings
```

**Linux** (build from source):
```bash
# Clone the repository
git clone https://github.com/supranational/blst.git
cd blst

# Build the library
./build.sh

# Install system-wide (optional)
sudo make install
# Or use custom include path: zig build -Dblst=true -Dblst-include=/path/to/blst/bindings
```

**Windows** (build from source or vcpkg):
```bash
# Option 1: Build from source (requires Visual Studio or MinGW)
git clone https://github.com/supranational/blst.git
cd blst
# Follow Windows build instructions in the repository

# Option 2: Use vcpkg (if available)
vcpkg install blst
```

**Usage:**
```bash
# If installed system-wide
zig build -Dblst=true

# If using custom path
zig build -Dblst=true -Dblst-include=/path/to/blst/bindings
```

**Note**: The `blst` library is not available via Homebrew on macOS, so you must build it from source. See the [official repository](https://github.com/supranational/blst) for detailed build instructions.

### MCL (BN254)

**Status**: Required by default, enables BN254 precompiles

**Note**: You can disable mcl with `-Dmcl=false`, but this will disable BN254 precompiles.

**Installation:**

**macOS** (build from source):
```bash
# Clone the repository
git clone https://github.com/herumi/mcl.git
cd mcl

# Build the library
# Follow the build instructions in the repository
# Note: mcl is primarily C++, so C bindings may need to be created
```

**Linux** (build from source):
```bash
# Clone the repository
git clone https://github.com/herumi/mcl.git
cd mcl

# Build the library
# Follow the build instructions in the repository
```

**Windows** (build from source or vcpkg):
```bash
# Option 1: Build from source (requires Visual Studio or MinGW)
git clone https://github.com/herumi/mcl.git
cd mcl
# Follow Windows build instructions in the repository

# Option 2: Use vcpkg (if available)
vcpkg install mcl
```

**Usage:**
```bash
# Standard build (mcl enabled by default)
zig build

# If using custom include path
zig build -Dmcl-include=/path/to/mcl/include

# Disable mcl (not recommended, disables BN254 precompiles)
zig build -Dmcl=false
```

**Note**: The `mcl` library is primarily C++, so C bindings may need to be created or you may need to use mcl's C API if available. See the [official repository](https://github.com/herumi/mcl) for detailed build instructions.

## Troubleshooting

### Library Not Found Errors

If you see errors like:
```
error: unable to find dynamic system library 'blst' using strategy 'paths_first'
error: unable to find dynamic system library 'mcl' using strategy 'paths_first'
```

This means the required libraries are not installed. Here's how to fix it:

**Quick Fix:**
1. **Install blst**: See the "Required Libraries" section above for installation instructions
2. **Install mcl**: See the "Required Libraries" section above for installation instructions
3. **Rebuild**: Run `zig build` again

**If you can't install the libraries right now:**
- You can temporarily disable them: `zig build -Dblst=false -Dmcl=false`
- Note: This will disable BLS12-381, KZG, and BN254 precompiles

**Other common issues:**

1. **Libraries installed but not found**:
   - Check library installation: Verify libraries are installed and accessible
   - Specify include paths: Use `-Dblst-include=...` or `-Dmcl-include=...`
   - Check library paths: Ensure libraries are in system library paths or use `-L` flags
   - On macOS with Homebrew: Libraries are typically in `/opt/homebrew/lib` or `/usr/local/lib`
   - On Linux: Libraries are typically in `/usr/lib` or `/usr/local/lib`

### Windows-Specific Issues

- **MSVC vs MinGW**: Zig uses its own toolchain, but you may need MSVC runtime on Windows
- **Path separators**: Use forward slashes (`/`) or escaped backslashes (`\\`) in paths
- **Library names**: Some libraries may have different names (e.g., `libssl.a` vs `ssl.lib`)

### Linux-Specific Issues

- **Package managers**: Different distributions use different package managers
- **Library versions**: Ensure compatible versions of OpenSSL and secp256k1
- **Development headers**: Install `-dev` or `-devel` packages, not just runtime libraries

## CI/CD Support

The project includes GitHub Actions workflows that test on:
- Ubuntu Latest (Linux)
- macOS Latest

Windows support can be added by adding a Windows runner to the CI matrix.

## Testing Cross-Platform

To test cross-platform compatibility:

```bash
# Test Linux build from macOS
zig build -Dtarget=x86_64-linux-gnu

# Test Windows build from macOS/Linux  
zig build -Dtarget=x86_64-windows

# Run tests for specific target
zig test src/precompile/tests.zig -I src -target x86_64-linux-gnu
```

## Summary

The build system is designed to work cross-platform with minimal configuration:
- ✅ Automatic platform detection
- ✅ Platform-specific defaults
- ✅ Override options for custom installations
- ✅ Cross-compilation support
- ✅ All precompile dependencies are required by default
  - `blst` (BLS12-381 and KZG) - can be disabled with `-Dblst=false`
  - `mcl` (BN254) - can be disabled with `-Dmcl=false`
- ✅ Other required libraries: `secp256k1`, `openssl` (ssl/crypto), `libm` (Unix)

**Important**: All precompile dependencies (`blst` and `mcl`) are now required by default. You must install them before building. See the "Required Libraries" section above for installation instructions.

For most users, after installing the required libraries, `zig build` should work out of the box.

