// ABOUTME: Build configuration for CoreSim deterministic simulation framework
// ABOUTME: Manages library compilation and test execution for the framework

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Core library module
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Core library
    const coresim = b.addStaticLibrary(.{
        .name = "coresim",
        .root_module = lib_mod,
    });
    b.installArtifact(coresim);

    // CoreSim is a library - no CLI executable needed

    // Tests
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // Add example executables
    const simple_examples_mod = b.createModule(.{
        .root_source_file = b.path("examples/simple_examples.zig"),
        .target = target,
        .optimize = optimize,
    });
    simple_examples_mod.addImport("coresim", lib_mod);

    const simple_examples = b.addExecutable(.{
        .name = "simple_examples",
        .root_module = simple_examples_mod,
    });

    const run_simple_examples = b.addRunArtifact(simple_examples);
    const example_step = b.step("example", "Run simple examples");
    example_step.dependOn(&run_simple_examples.step);

    // Generator demo executable
    const generator_demo_mod = b.createModule(.{
        .root_source_file = b.path("examples/generator_demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    generator_demo_mod.addImport("coresim", lib_mod);

    const generator_demo = b.addExecutable(.{
        .name = "generator_demo",
        .root_module = generator_demo_mod,
    });

    const run_generator_demo = b.addRunArtifact(generator_demo);
    const generator_demo_step = b.step("generator-demo", "Run generator configuration demo");
    generator_demo_step.dependOn(&run_generator_demo.step);

    // Operation weights demo executable
    const operation_weights_demo_mod = b.createModule(.{
        .root_source_file = b.path("examples/operation_weights_demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    operation_weights_demo_mod.addImport("coresim", lib_mod);

    const operation_weights_demo = b.addExecutable(.{
        .name = "operation_weights_demo",
        .root_module = operation_weights_demo_mod,
    });

    const run_operation_weights_demo = b.addRunArtifact(operation_weights_demo);
    const operation_weights_demo_step = b.step("weights-demo", "Run operation weights demo");
    operation_weights_demo_step.dependOn(&run_operation_weights_demo.step);

    // Custom failures demo
    const custom_failures_demo_mod = b.createModule(.{
        .root_source_file = b.path("examples/custom_failures_demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    custom_failures_demo_mod.addImport("coresim", lib_mod);

    const custom_failures_demo = b.addExecutable(.{
        .name = "custom_failures_demo",
        .root_module = custom_failures_demo_mod,
    });

    const run_custom_failures_demo = b.addRunArtifact(custom_failures_demo);
    const custom_failures_demo_step = b.step("failures-demo", "Run custom failures demo");
    custom_failures_demo_step.dependOn(&run_custom_failures_demo.step);

    // Network failures demo
    const network_failures_demo_mod = b.createModule(.{
        .root_source_file = b.path("examples/network_failures_demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    network_failures_demo_mod.addImport("coresim", lib_mod);

    const network_failures_demo = b.addExecutable(.{
        .name = "network_failures_demo",
        .root_module = network_failures_demo_mod,
    });

    const run_network_failures_demo = b.addRunArtifact(network_failures_demo);
    const network_failures_demo_step = b.step("network-demo", "Run network failures demo");
    network_failures_demo_step.dependOn(&run_network_failures_demo.step);

    // Conditional demo executable
    const conditional_demo_mod = b.createModule(.{
        .root_source_file = b.path("examples/conditional_demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    conditional_demo_mod.addImport("coresim", lib_mod);

    const conditional_demo = b.addExecutable(.{
        .name = "conditional_demo",
        .root_module = conditional_demo_mod,
    });

    const run_conditional_demo = b.addRunArtifact(conditional_demo);
    const conditional_demo_step = b.step("conditional-demo", "Run conditional multipliers demo");
    conditional_demo_step.dependOn(&run_conditional_demo.step);

    // Detailed statistics demo
    const detailed_stats_demo_mod = b.createModule(.{
        .root_source_file = b.path("examples/detailed_stats_demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    detailed_stats_demo_mod.addImport("coresim", lib_mod);

    const detailed_stats_demo = b.addExecutable(.{
        .name = "detailed_stats_demo",
        .root_module = detailed_stats_demo_mod,
    });

    const run_detailed_stats_demo = b.addRunArtifact(detailed_stats_demo);
    const detailed_stats_demo_step = b.step("stats-demo", "Run detailed statistics demo");
    detailed_stats_demo_step.dependOn(&run_detailed_stats_demo.step);

    // CoreSim is a library - no CLI to run
}
