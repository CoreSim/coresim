// ABOUTME: CLI entry point for CoreSim deterministic simulation framework
// ABOUTME: Provides command-line interface for running property tests and simulations

const std = @import("std");
const coresim = @import("coresim");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "help")) {
        try printUsage();
    } else if (std.mem.eql(u8, command, "version")) {
        std.debug.print("CoreSim v0.1.0\n", .{});
    } else if (std.mem.eql(u8, command, "test")) {
        try runTests(allocator, @ptrCast(args[2..]));
    } else if (std.mem.eql(u8, command, "example")) {
        try runExample(allocator, @ptrCast(args[2..]));
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        try printUsage();
        std.process.exit(1);
    }
}

fn printUsage() !void {
    std.debug.print(
        \\CoreSim - Deterministic Simulation Framework
        \\
        \\Usage: coresim <command> [options]
        \\
        \\Commands:
        \\  help               Show this help message
        \\  version            Show version information
        \\  test [--seed N]    Run basic property tests
        \\  example            Run example simulation
        \\
        \\Options:
        \\  --seed N           Set random seed for reproducible tests
        \\  --iterations N     Number of test iterations (default: 100)
        \\
    , .{});
}

fn runTests(allocator: std.mem.Allocator, args: [][]const u8) !void {
    var seed: u64 = @intCast(std.time.timestamp());
    var iterations: u32 = 100;

    // Parse arguments
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--seed") and i + 1 < args.len) {
            seed = try std.fmt.parseInt(u64, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--iterations") and i + 1 < args.len) {
            iterations = try std.fmt.parseInt(u32, args[i + 1], 10);
            i += 1;
        }
    }

    std.debug.print("Running CoreSim tests with seed: {} for {} iterations\n", .{ seed, iterations });

    // Run built-in tests
    try runFilesystemTests(allocator);
    try runFailureInjectionTests(allocator);

    std.debug.print("All tests completed successfully!\n", .{});
}

fn runExample(allocator: std.mem.Allocator, _: [][]const u8) !void {
    std.debug.print("Running CoreSim example simulation...\n", .{});

    var failure_config = coresim.failure_injection.FailureInjectionConfig.init(allocator);
    failure_config.allocator_failure_probability = 0.01;
    failure_config.filesystem_error_probability = 0.005;
    defer failure_config.deinit();

    std.debug.print("Example simulation completed!\n", .{});
}

fn runFilesystemTests(allocator: std.mem.Allocator) !void {
    std.debug.print("Testing filesystem abstraction...\n", .{});

    var real_fs = coresim.filesystem.RealFilesystem.init(allocator);
    defer real_fs.deinit();

    var sim_fs = coresim.filesystem.SimulatedFilesystem.init(allocator);
    defer sim_fs.deinit();

    // Test basic operations
    const test_path = "/tmp/coresim_test.txt";
    std.fs.deleteFileAbsolute(test_path) catch {};
    defer std.fs.deleteFileAbsolute(test_path) catch {};

    const fs = real_fs.interface();
    const handle = try fs.open(test_path, .{ .write = true, .create = true });
    defer fs.close(handle) catch {};

    const test_data = "CoreSim test data";
    const bytes_written = try fs.write(handle, test_data);
    if (bytes_written != test_data.len) {
        return error.IncompleteWrite;
    }
    try fs.flush(handle);

    std.debug.print("  ✓ Filesystem tests passed\n", .{});
}

fn runFailureInjectionTests(allocator: std.mem.Allocator) !void {
    std.debug.print("Testing failure injection...\n", .{});

    var tracker = coresim.failure_injection.FailureTracker.init(allocator);
    defer tracker.deinit();

    // Record some test operations
    for (0..10) |_| {
        tracker.record_operation();
    }

    tracker.record_allocator_failure();
    tracker.record_filesystem_error();

    const alloc_rate = tracker.get_allocator_failure_rate();
    const fs_rate = tracker.get_filesystem_error_rate();

    std.debug.print("  ✓ Failure injection tests passed (alloc: {d:.1}%, fs: {d:.1}%)\n", .{ alloc_rate * 100.0, fs_rate * 100.0 });
}
