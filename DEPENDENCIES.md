# External Dependencies

This project requires several external cryptographic libraries for full EVM precompile support.

## Required Libraries

### 1. OpenSSL (P256Verify) ✅
**Status**: Installed and integrated

OpenSSL is used for secp256r1 (P-256) signature verification.

**Installation** (macOS):
```bash
brew install openssl@3
```

**Installation** (Linux):
```bash
sudo apt-get install libssl-dev  # Debian/Ubuntu
sudo yum install openssl-devel    # RHEL/CentOS
```

### 2. blst (BLS12-381 & KZG) ⚠️
**Status**: Needs installation

blst is a high-performance BLS12-381 signature library used for:
- BLS12-381 precompiles (G1 Add, G1 MSM, G2 Add, G2 MSM, Pairing, MapFpToG1, MapFp2ToG2)
- KZG point evaluation precompile

**Installation**:
```bash
# Clone the repository
git clone https://github.com/supranational/blst.git
cd blst

# Build the library
make

# Install (optional, or use from build directory)
sudo make install
# Or set BLST_DIR environment variable to point to the blst directory
```

**Environment Variable**:
```bash
export BLST_DIR=/path/to/blst
```

### 3. mcl (BN254) ⚠️
**Status**: Needs installation

mcl is a portable pairing-based cryptography library used for:
- BN254 precompiles (Add, Mul, Pairing)

**Installation**:
```bash
# Clone the repository
git clone https://github.com/herumi/mcl.git
cd mcl

# Build the library
make -j4

# Install (optional, or use from build directory)
sudo make install
# Or set MCL_DIR environment variable to point to the mcl directory
```

**Environment Variable**:
```bash
export MCL_DIR=/path/to/mcl
```

### 4. c-kzg (KZG - Alternative) ⚠️
**Status**: Optional alternative to blst for KZG

c-kzg is a C implementation of KZG commitments.

**Installation**:
```bash
# Clone the repository
git clone https://github.com/ethereum/c-kzg.git
cd c-kzg

# Build the library
make

# Install (optional)
sudo make install
# Or set CKZG_DIR environment variable
```

**Environment Variable**:
```bash
export CKZG_DIR=/path/to/c-kzg
```

## Build Configuration

The build system (`build.zig`) will automatically link against these libraries if they are:
1. Installed system-wide (via `make install`)
2. Available via `pkg-config`
3. Set via environment variables (BLST_DIR, MCL_DIR, CKZG_DIR)

## Current Status

- ✅ **OpenSSL**: Fully integrated and working
- ⚠️ **blst**: Bindings created, needs library installation
- ⚠️ **mcl**: Bindings created, needs library installation
- ⚠️ **c-kzg**: Optional, bindings can be added if needed

## Testing

After installing the libraries, run:
```bash
zig build
```

If libraries are not found, the precompiles will use placeholder implementations that return errors for invalid inputs but won't perform actual cryptographic operations.
