# fuzz/Makefile — AFL++ build and campaign orchestration for ZEVM
#
# Prerequisites:
#   - AFL++ installed:
#       macOS:          make deps   (brew install afl++)
#       Ubuntu/Debian:  sudo apt install afl++
#       Fedora/RHEL:    sudo dnf install afl++
#       From source:    https://github.com/AFLplusplus/AFLplusplus
#   - Zig 0.15+ in PATH
#   - ZEVM crypto dependencies installed (run: make install-deps from project root)
#
# Quick start:
#   make lib        # build the Zig fuzz harness library
#   make harness    # compile C shim + link with Zig library
#   make seeds      # generate seeds from spec test fixtures (optional)
#   make fuzz-tx    # start fuzzing full transaction pipeline

ZEVM_ROOT := $(abspath $(CURDIR)/..)

# Detect macOS vs Linux for library flags
UNAME_S := $(shell uname -s)

# afl-clang-lto requires a patched LLVM — not available in the macOS Homebrew bottle.
# Fall back to afl-clang-fast (PCguard instrumentation, nearly as effective).
# Override: AFL_CC=afl-clang-lto make harness
ifeq ($(UNAME_S),Darwin)
  AFL_CC  ?= afl-clang-fast
  AFL_CXX ?= afl-clang-fast++
else
  AFL_CC  ?= afl-clang-lto
  AFL_CXX ?= afl-clang-lto++
endif

ifeq ($(UNAME_S),Darwin)
  LIBCXX     := -lc++
  BREW_LIB   := $(shell brew --prefix 2>/dev/null)/lib
  EXTRA_LIBS := -L$(BREW_LIB)
  # Use absolute paths to static archives to avoid picking up dylibs.
  # The Zig-built libzevm-fuzz.a embeds a relative rpath 'lib/' for mcl/blst;
  # specifying the .a directly overrides the dynamic linker's preference.
  STATIC_MCL  := $(BREW_LIB)/libmcl.a
  STATIC_BLST := $(BREW_LIB)/libblst.a
else
  LIBCXX      := -lstdc++
  # /usr/local/lib is not always in the default linker path on Linux
  EXTRA_LIBS  := -L/usr/local/lib
  STATIC_MCL  := /usr/local/lib/libmcl.a
  STATIC_BLST := /usr/local/lib/libblst.a
endif

# AFL++ env flags:
#   AFL_SKIP_CPUFREQ=1              suppress CPU frequency scaling warning
#   AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1  suppress core_pattern warning on Linux
AFL_ENV := AFL_SKIP_CPUFREQ=1 AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1

# Zig output directory
ZIG_OUT := $(ZEVM_ROOT)/zig-out

# AFL++ findings output
FINDINGS_DIR := $(CURDIR)/findings

.PHONY: all deps deps-linux lib harness seeds fuzz-tx fuzz-bytecode fuzz-precompile convert clean help

all: harness

# ── Install AFL++ ────────────────────────────────────────────────────────────
deps:
ifeq ($(UNAME_S),Darwin)
	@echo "==> Installing AFL++ via Homebrew (macOS)"
	brew install afl++
else
	@echo "==> On Linux, install AFL++ via your package manager:"
	@echo "    Ubuntu/Debian: sudo apt install afl++"
	@echo "    Fedora/RHEL:   sudo dnf install afl++"
	@echo "    Or build from source: https://github.com/AFLplusplus/AFLplusplus"
	@exit 1
endif

# ── Build Zig static library ─────────────────────────────────────────────────
lib:
	@echo "==> Building Zig fuzz harness library (ReleaseSafe)"
	cd $(ZEVM_ROOT) && zig build fuzz-lib -Doptimize=ReleaseSafe
	@echo "    Library: $(ZIG_OUT)/lib/libzevm-fuzz.a"

# ── Compile AFL++ instrumented harness binary ────────────────────────────────
harness: lib $(CURDIR)/afl_shim.c
	@echo "==> Linking AFL++ harness binary"
	$(AFL_CC) -O2 \
		-o $(ZEVM_ROOT)/zevm-fuzz \
		$(CURDIR)/afl_shim.c \
		-L$(ZIG_OUT)/lib -lzevm-fuzz \
		-lsecp256k1 -lssl -lcrypto \
		$(STATIC_BLST) $(STATIC_MCL) \
		$(EXTRA_LIBS) \
		$(LIBCXX) -lm -lc
	@echo "    Harness: $(ZEVM_ROOT)/zevm-fuzz"

# ── Build tool binaries ──────────────────────────────────────────────────────
tools:
	cd $(ZEVM_ROOT) && zig build fuzz2spec gen-seeds

# ── Generate seed corpus from spec test fixtures ─────────────────────────────
seeds: tools
	@echo "==> Generating transaction seeds from spec test fixtures"
	@if [ -d "$(ZEVM_ROOT)/spec-tests/fixtures/state_tests" ]; then \
		$(ZIG_OUT)/bin/gen-seeds \
			$(ZEVM_ROOT)/spec-tests/fixtures/state_tests \
			$(CURDIR)/seeds/transaction && \
		echo "    Seeds written to fuzz/seeds/transaction/"; \
	else \
		echo "    WARNING: spec-tests/fixtures/state_tests not found, skipping"; \
		echo "    Run: git submodule update --init spec-tests (or clone manually)"; \
	fi
	@echo "==> Creating minimal hand-crafted seeds"
	cd $(ZEVM_ROOT) && zig run fuzz/seeds/create_bytecode_seeds.zig

# ── Run AFL++ fuzzing campaigns ──────────────────────────────────────────────

# Full transaction pipeline fuzzer
fuzz-tx: harness
	@mkdir -p $(FINDINGS_DIR)/transaction
	@echo "==> Starting transaction fuzzer (Ctrl-C to stop)"
	@echo "    Seeds:    fuzz/seeds/transaction/"
	@echo "    Findings: fuzz/findings/transaction/"
	$(AFL_ENV) \
	afl-fuzz \
		-i $(CURDIR)/seeds/transaction \
		-o $(FINDINGS_DIR)/transaction \
		-x $(CURDIR)/dictionaries/evm_opcodes.dict \
		-x $(CURDIR)/dictionaries/evm_values.dict \
		-t 5000 \
		-- $(ZEVM_ROOT)/zevm-fuzz transaction

# Bytecode-focused fuzzer (faster iteration, opcode dictionary)
fuzz-bytecode: harness
	@mkdir -p $(FINDINGS_DIR)/bytecode
	@[ -f $(CURDIR)/seeds/bytecode/push_stop.bin ] || (cd $(ZEVM_ROOT) && zig run fuzz/seeds/create_bytecode_seeds.zig)
	@echo "==> Starting bytecode fuzzer (Ctrl-C to stop)"
	$(AFL_ENV) \
	afl-fuzz \
		-i $(CURDIR)/seeds/bytecode \
		-o $(FINDINGS_DIR)/bytecode \
		-x $(CURDIR)/dictionaries/evm_opcodes.dict \
		-t 5000 \
		-- $(ZEVM_ROOT)/zevm-fuzz bytecode

# Precompile fuzzer (targets C library bindings)
fuzz-precompile: harness
	@mkdir -p $(FINDINGS_DIR)/precompile
	@[ -f $(CURDIR)/seeds/precompile/sha256_empty.bin ] || (cd $(ZEVM_ROOT) && zig run fuzz/seeds/create_bytecode_seeds.zig)
	@echo "==> Starting precompile fuzzer (Ctrl-C to stop)"
	$(AFL_ENV) \
	afl-fuzz \
		-i $(CURDIR)/seeds/precompile \
		-o $(FINDINGS_DIR)/precompile \
		-t 10000 \
		-- $(ZEVM_ROOT)/zevm-fuzz precompile

# Multi-core transaction fuzzer (requires AFL++ parallel mode)
# Usage: make fuzz-tx-parallel CORES=4
CORES ?= $(shell nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 2)
fuzz-tx-parallel: harness
	@mkdir -p $(FINDINGS_DIR)/transaction
	@echo "==> Starting parallel transaction fuzzer on $(CORES) cores"
	AFL_SKIP_CPUFREQ=1 \
	afl-fuzz -M main \
		-i $(CURDIR)/seeds/transaction \
		-o $(FINDINGS_DIR)/transaction \
		-x $(CURDIR)/dictionaries/evm_opcodes.dict \
		-t 5000 \
		-- $(ZEVM_ROOT)/zevm-fuzz transaction &
	@for i in $(shell seq 2 $(CORES)); do \
		AFL_SKIP_CPUFREQ=1 \
		afl-fuzz -S worker$$i \
			-i $(CURDIR)/seeds/transaction \
			-o $(FINDINGS_DIR)/transaction \
			-t 5000 \
			-- $(ZEVM_ROOT)/zevm-fuzz transaction & \
	done
	@wait

# ── Convert findings to spec test format ────────────────────────────────────
convert: tools
	@echo "==> Converting crash findings to spec test JSON"
	@mkdir -p $(ZEVM_ROOT)/spec-tests/fuzz
	@CRASHES=0; \
	for crash_dir in $(FINDINGS_DIR)/*/crashes; do \
		harness=$$(basename $$(dirname $$crash_dir)); \
		for f in $$crash_dir/id:*; do \
			[ -f "$$f" ] || continue; \
			name="fuzz_$${harness}_$$(basename $$f)"; \
			out="$(ZEVM_ROOT)/spec-tests/fuzz/$${name}.json"; \
			echo "  Converting $$f -> $$out"; \
			$(ZIG_OUT)/bin/fuzz2spec "$$f" "$$harness" > "$$out" && CRASHES=$$((CRASHES+1)); \
		done; \
	done; \
	echo "==> Converted $$CRASHES crash files"

# ── Show AFL++ stats ──────────────────────────────────────────────────────────
stats:
	@for d in $(FINDINGS_DIR)/*/; do \
		[ -f "$$d/fuzzer_stats" ] && echo "=== $$(basename $$d) ===" && cat "$$d/fuzzer_stats"; \
	done

# ── Cleanup ──────────────────────────────────────────────────────────────────
clean:
	rm -f $(ZEVM_ROOT)/zevm-fuzz
	rm -rf $(FINDINGS_DIR)

help:
	@echo "ZEVM AFL++ fuzzing targets:"
	@echo "  make deps           Install AFL++ (macOS via Homebrew)"
	@echo "  make lib            Build Zig fuzz harness library"
	@echo "  make harness        Compile AFL++ instrumented binary"
	@echo "  make seeds          Generate seed corpus from spec tests"
	@echo "  make fuzz-tx        Fuzz full transaction pipeline"
	@echo "  make fuzz-bytecode  Fuzz bytecode interpreter"
	@echo "  make fuzz-precompile Fuzz precompile inputs"
	@echo "  make convert        Convert crash findings to spec test JSON"
	@echo "  make stats          Show AFL++ campaign statistics"
	@echo "  make clean          Remove harness and findings"
