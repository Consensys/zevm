const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main library
    const lib = b.addLibrary(.{
        .name = "zevm",
        .root_module = b.addModule("zevm", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/main.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add crypto dependencies
    lib.linkSystemLibrary("c");
    lib.linkSystemLibrary("m");
    // Link secp256k1 for ECRECOVER precompile
    lib.linkSystemLibrary("secp256k1");
    // Link OpenSSL for P256Verify precompile
    lib.linkSystemLibrary("ssl");
    lib.linkSystemLibrary("crypto");

    // Optional: Link blst for BLS12-381 and KZG (if installed)
    // Uncomment when blst is installed:
    // lib.linkSystemLibrary("blst");

    // Optional: Link mcl for BN254 (if installed)
    // Uncomment when mcl is installed:
    // lib.linkSystemLibrary("mcl");

    // Install the library
    b.installArtifact(lib);

    // Create modules for each component
    const primitives_module = b.addModule("primitives", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/primitives/main.zig" } },
        .target = target,
        .optimize = optimize,
    });

    const bytecode_module = b.addModule("bytecode", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/bytecode/main.zig" } },
        .target = target,
        .optimize = optimize,
    });

    const state_module = b.addModule("state", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/state/main.zig" } },
        .target = target,
        .optimize = optimize,
    });

    const database_module = b.addModule("database", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/database/main.zig" } },
        .target = target,
        .optimize = optimize,
    });

    const context_module = b.addModule("context", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/context/main.zig" } },
        .target = target,
        .optimize = optimize,
    });

    const interpreter_module = b.addModule("interpreter", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/interpreter/main.zig" } },
        .target = target,
        .optimize = optimize,
    });

    const precompile_module = b.addModule("precompile", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/precompile/main.zig" } },
        .target = target,
        .optimize = optimize,
    });

    const handler_module = b.addModule("handler", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/handler/main.zig" } },
        .target = target,
        .optimize = optimize,
    });

    const inspector_module = b.addModule("inspector", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/inspector/main.zig" } },
        .target = target,
        .optimize = optimize,
    });

    // Add module dependencies
    bytecode_module.addImport("primitives", primitives_module);
    state_module.addImport("primitives", primitives_module);
    state_module.addImport("bytecode", bytecode_module);
    database_module.addImport("primitives", primitives_module);
    database_module.addImport("state", state_module);
    database_module.addImport("bytecode", bytecode_module);
    context_module.addImport("primitives", primitives_module);
    context_module.addImport("state", state_module);
    context_module.addImport("database", database_module);
    interpreter_module.addImport("primitives", primitives_module);
    interpreter_module.addImport("bytecode", bytecode_module);
    interpreter_module.addImport("context", context_module);
    precompile_module.addImport("primitives", primitives_module);
    handler_module.addImport("primitives", primitives_module);
    handler_module.addImport("bytecode", bytecode_module);
    handler_module.addImport("state", state_module);
    handler_module.addImport("database", database_module);
    handler_module.addImport("interpreter", interpreter_module);
    handler_module.addImport("context", context_module);
    handler_module.addImport("precompile", precompile_module);
    inspector_module.addImport("primitives", primitives_module);
    inspector_module.addImport("interpreter", interpreter_module);

    // Add modules to main library
    lib.root_module.addImport("primitives", primitives_module);
    lib.root_module.addImport("bytecode", bytecode_module);
    lib.root_module.addImport("state", state_module);
    lib.root_module.addImport("database", database_module);
    lib.root_module.addImport("context", context_module);
    lib.root_module.addImport("interpreter", interpreter_module);
    lib.root_module.addImport("precompile", precompile_module);
    lib.root_module.addImport("handler", handler_module);
    lib.root_module.addImport("inspector", inspector_module);

    // Test executable
    const test_exe = b.addExecutable(.{
        .name = "zevm-test",
        .root_module = b.addModule("zevm-test", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/test.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });

    test_exe.linkSystemLibrary("c");
    test_exe.linkSystemLibrary("m");
    test_exe.linkSystemLibrary("secp256k1");
    test_exe.linkSystemLibrary("ssl");
    test_exe.linkSystemLibrary("crypto");
    test_exe.root_module.addImport("primitives", primitives_module);
    test_exe.root_module.addImport("bytecode", bytecode_module);
    test_exe.root_module.addImport("state", state_module);
    test_exe.root_module.addImport("database", database_module);
    test_exe.root_module.addImport("context", context_module);
    test_exe.root_module.addImport("interpreter", interpreter_module);
    test_exe.root_module.addImport("precompile", precompile_module);
    test_exe.root_module.addImport("handler", handler_module);
    test_exe.root_module.addImport("inspector", inspector_module);

    b.installArtifact(test_exe);

    // Benchmark executable
    const bench_exe = b.addExecutable(.{
        .name = "zevm-bench",
        .root_module = b.addModule("zevm-bench", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "examples/benchmark.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });

    bench_exe.linkSystemLibrary("c");
    bench_exe.linkSystemLibrary("m");
    bench_exe.linkSystemLibrary("secp256k1");
    bench_exe.linkSystemLibrary("ssl");
    bench_exe.linkSystemLibrary("crypto");
    bench_exe.root_module.addImport("primitives", primitives_module);
    bench_exe.root_module.addImport("bytecode", bytecode_module);
    bench_exe.root_module.addImport("state", state_module);
    bench_exe.root_module.addImport("database", database_module);
    bench_exe.root_module.addImport("context", context_module);
    bench_exe.root_module.addImport("interpreter", interpreter_module);
    bench_exe.root_module.addImport("precompile", precompile_module);
    bench_exe.root_module.addImport("handler", handler_module);
    bench_exe.root_module.addImport("inspector", inspector_module);

    b.installArtifact(bench_exe);

    // Run tests
    const run_tests = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // Note: Precompile unit tests (73 tests) are in src/precompile/tests.zig
    // They are automatically run when running: zig test src/precompile/tests.zig -I src
    // The CI should run both: ./zig-out/bin/zevm-test AND zig test src/precompile/tests.zig -I src

    // Example executable
    const example_exe = b.addExecutable(.{
        .name = "zevm-example",
        .root_module = b.addModule("zevm-example", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "examples/simple_evm.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });

    example_exe.linkSystemLibrary("c");
    example_exe.linkSystemLibrary("m");
    example_exe.linkSystemLibrary("secp256k1");
    example_exe.linkSystemLibrary("ssl");
    example_exe.linkSystemLibrary("crypto");
    example_exe.root_module.addImport("zevm", lib.root_module);
    example_exe.root_module.addImport("primitives", primitives_module);
    example_exe.root_module.addImport("bytecode", bytecode_module);
    example_exe.root_module.addImport("state", state_module);
    example_exe.root_module.addImport("database", database_module);
    example_exe.root_module.addImport("context", context_module);
    example_exe.root_module.addImport("interpreter", interpreter_module);
    example_exe.root_module.addImport("precompile", precompile_module);
    example_exe.root_module.addImport("handler", handler_module);
    example_exe.root_module.addImport("inspector", inspector_module);

    b.installArtifact(example_exe);

    // Example executables
    const simple_contract_exe = b.addExecutable(.{
        .name = "simple_contract",
        .root_module = b.addModule("simple_contract", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "examples/simple_contract.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });
    simple_contract_exe.linkSystemLibrary("c");
    simple_contract_exe.linkSystemLibrary("m");
    simple_contract_exe.linkSystemLibrary("secp256k1");
    simple_contract_exe.linkSystemLibrary("ssl");
    simple_contract_exe.linkSystemLibrary("crypto");
    simple_contract_exe.root_module.addImport("primitives", primitives_module);
    simple_contract_exe.root_module.addImport("bytecode", bytecode_module);
    simple_contract_exe.root_module.addImport("state", state_module);
    simple_contract_exe.root_module.addImport("database", database_module);
    simple_contract_exe.root_module.addImport("context", context_module);
    simple_contract_exe.root_module.addImport("interpreter", interpreter_module);
    simple_contract_exe.root_module.addImport("precompile", precompile_module);
    simple_contract_exe.root_module.addImport("handler", handler_module);
    simple_contract_exe.root_module.addImport("inspector", inspector_module);
    b.installArtifact(simple_contract_exe);

    const gas_inspector_exe = b.addExecutable(.{
        .name = "gas_inspector_example",
        .root_module = b.addModule("gas_inspector_example", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "examples/gas_inspector_example.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });
    gas_inspector_exe.linkSystemLibrary("c");
    gas_inspector_exe.linkSystemLibrary("m");
    gas_inspector_exe.linkSystemLibrary("secp256k1");
    gas_inspector_exe.linkSystemLibrary("ssl");
    gas_inspector_exe.linkSystemLibrary("crypto");
    gas_inspector_exe.root_module.addImport("primitives", primitives_module);
    gas_inspector_exe.root_module.addImport("bytecode", bytecode_module);
    gas_inspector_exe.root_module.addImport("state", state_module);
    gas_inspector_exe.root_module.addImport("database", database_module);
    gas_inspector_exe.root_module.addImport("context", context_module);
    gas_inspector_exe.root_module.addImport("interpreter", interpreter_module);
    gas_inspector_exe.root_module.addImport("precompile", precompile_module);
    gas_inspector_exe.root_module.addImport("handler", handler_module);
    gas_inspector_exe.root_module.addImport("inspector", inspector_module);
    b.installArtifact(gas_inspector_exe);

    const precompile_exe = b.addExecutable(.{
        .name = "precompile_example",
        .root_module = b.addModule("precompile_example", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "examples/precompile_example.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });
    precompile_exe.linkSystemLibrary("c");
    precompile_exe.linkSystemLibrary("m");
    precompile_exe.linkSystemLibrary("secp256k1");
    precompile_exe.linkSystemLibrary("ssl");
    precompile_exe.linkSystemLibrary("crypto");
    precompile_exe.root_module.addImport("primitives", primitives_module);
    precompile_exe.root_module.addImport("bytecode", bytecode_module);
    precompile_exe.root_module.addImport("state", state_module);
    precompile_exe.root_module.addImport("database", database_module);
    precompile_exe.root_module.addImport("context", context_module);
    precompile_exe.root_module.addImport("interpreter", interpreter_module);
    precompile_exe.root_module.addImport("precompile", precompile_module);
    precompile_exe.root_module.addImport("handler", handler_module);
    precompile_exe.root_module.addImport("inspector", inspector_module);
    b.installArtifact(precompile_exe);

    // Contract deployment example
    const contract_deployment_exe = b.addExecutable(.{
        .name = "contract_deployment",
        .root_module = b.addModule("contract_deployment", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "examples/contract_deployment.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });
    contract_deployment_exe.linkSystemLibrary("c");
    contract_deployment_exe.linkSystemLibrary("m");
    contract_deployment_exe.linkSystemLibrary("secp256k1");
    contract_deployment_exe.linkSystemLibrary("ssl");
    contract_deployment_exe.linkSystemLibrary("crypto");
    contract_deployment_exe.root_module.addImport("primitives", primitives_module);
    contract_deployment_exe.root_module.addImport("bytecode", bytecode_module);
    contract_deployment_exe.root_module.addImport("state", state_module);
    contract_deployment_exe.root_module.addImport("database", database_module);
    contract_deployment_exe.root_module.addImport("context", context_module);
    contract_deployment_exe.root_module.addImport("interpreter", interpreter_module);
    contract_deployment_exe.root_module.addImport("precompile", precompile_module);
    contract_deployment_exe.root_module.addImport("handler", handler_module);
    contract_deployment_exe.root_module.addImport("inspector", inspector_module);
    b.installArtifact(contract_deployment_exe);

    // Uniswap reserves example
    const uniswap_reserves_exe = b.addExecutable(.{
        .name = "uniswap_reserves",
        .root_module = b.addModule("uniswap_reserves", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "examples/uniswap_reserves.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });
    uniswap_reserves_exe.linkSystemLibrary("c");
    uniswap_reserves_exe.linkSystemLibrary("m");
    uniswap_reserves_exe.linkSystemLibrary("secp256k1");
    uniswap_reserves_exe.linkSystemLibrary("ssl");
    uniswap_reserves_exe.linkSystemLibrary("crypto");
    uniswap_reserves_exe.root_module.addImport("primitives", primitives_module);
    uniswap_reserves_exe.root_module.addImport("bytecode", bytecode_module);
    uniswap_reserves_exe.root_module.addImport("state", state_module);
    uniswap_reserves_exe.root_module.addImport("database", database_module);
    uniswap_reserves_exe.root_module.addImport("context", context_module);
    uniswap_reserves_exe.root_module.addImport("interpreter", interpreter_module);
    uniswap_reserves_exe.root_module.addImport("precompile", precompile_module);
    uniswap_reserves_exe.root_module.addImport("handler", handler_module);
    uniswap_reserves_exe.root_module.addImport("inspector", inspector_module);
    b.installArtifact(uniswap_reserves_exe);

    // Custom opcodes example
    const custom_opcodes_exe = b.addExecutable(.{
        .name = "custom_opcodes",
        .root_module = b.addModule("custom_opcodes", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "examples/custom_opcodes.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });
    custom_opcodes_exe.linkSystemLibrary("c");
    custom_opcodes_exe.linkSystemLibrary("m");
    custom_opcodes_exe.linkSystemLibrary("secp256k1");
    custom_opcodes_exe.linkSystemLibrary("ssl");
    custom_opcodes_exe.linkSystemLibrary("crypto");
    custom_opcodes_exe.root_module.addImport("primitives", primitives_module);
    custom_opcodes_exe.root_module.addImport("bytecode", bytecode_module);
    custom_opcodes_exe.root_module.addImport("state", state_module);
    custom_opcodes_exe.root_module.addImport("database", database_module);
    custom_opcodes_exe.root_module.addImport("context", context_module);
    custom_opcodes_exe.root_module.addImport("interpreter", interpreter_module);
    custom_opcodes_exe.root_module.addImport("precompile", precompile_module);
    custom_opcodes_exe.root_module.addImport("handler", handler_module);
    custom_opcodes_exe.root_module.addImport("inspector", inspector_module);
    b.installArtifact(custom_opcodes_exe);

    // Database components example
    const database_components_exe = b.addExecutable(.{
        .name = "database_components",
        .root_module = b.addModule("database_components", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "examples/database_components.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });
    database_components_exe.linkSystemLibrary("c");
    database_components_exe.linkSystemLibrary("m");
    database_components_exe.linkSystemLibrary("secp256k1");
    database_components_exe.linkSystemLibrary("ssl");
    database_components_exe.linkSystemLibrary("crypto");
    database_components_exe.root_module.addImport("primitives", primitives_module);
    database_components_exe.root_module.addImport("bytecode", bytecode_module);
    database_components_exe.root_module.addImport("state", state_module);
    database_components_exe.root_module.addImport("database", database_module);
    database_components_exe.root_module.addImport("context", context_module);
    database_components_exe.root_module.addImport("interpreter", interpreter_module);
    database_components_exe.root_module.addImport("precompile", precompile_module);
    database_components_exe.root_module.addImport("handler", handler_module);
    database_components_exe.root_module.addImport("inspector", inspector_module);
    b.installArtifact(database_components_exe);

    // Cheatcode inspector example
    const cheatcode_inspector_exe = b.addExecutable(.{
        .name = "cheatcode_inspector",
        .root_module = b.addModule("cheatcode_inspector", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "examples/cheatcode_inspector.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });
    cheatcode_inspector_exe.linkSystemLibrary("c");
    cheatcode_inspector_exe.linkSystemLibrary("m");
    cheatcode_inspector_exe.linkSystemLibrary("secp256k1");
    cheatcode_inspector_exe.linkSystemLibrary("ssl");
    cheatcode_inspector_exe.linkSystemLibrary("crypto");
    cheatcode_inspector_exe.root_module.addImport("primitives", primitives_module);
    cheatcode_inspector_exe.root_module.addImport("bytecode", bytecode_module);
    cheatcode_inspector_exe.root_module.addImport("state", state_module);
    cheatcode_inspector_exe.root_module.addImport("database", database_module);
    cheatcode_inspector_exe.root_module.addImport("context", context_module);
    cheatcode_inspector_exe.root_module.addImport("interpreter", interpreter_module);
    cheatcode_inspector_exe.root_module.addImport("precompile", precompile_module);
    cheatcode_inspector_exe.root_module.addImport("handler", handler_module);
    cheatcode_inspector_exe.root_module.addImport("inspector", inspector_module);
    b.installArtifact(cheatcode_inspector_exe);
}
