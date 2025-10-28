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

    // Run tests
    const run_tests = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // Example executable
    const example_exe = b.addExecutable(.{
        .name = "zevm-example",
        .root_module = b.addModule("zevm-example", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "examples/simple_evm.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });

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

    // Benchmark executable
    const bench_exe = b.addExecutable(.{
        .name = "zevm-bench",
        .root_module = b.addModule("zevm-bench", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "benchmarks/main.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });

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

    // Example executables
    const simple_contract_exe = b.addExecutable(.{
        .name = "simple_contract",
        .root_module = b.addModule("simple_contract", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "examples/simple_contract.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });
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
}
