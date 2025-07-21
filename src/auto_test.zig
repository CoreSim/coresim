// ABOUTME: Auto-discovery and annotation-based testing utilities
// ABOUTME: Provides convenience functions for automatic test generation

const std = @import("std");
const core = @import("core.zig");
const reflection = @import("reflection.zig");
const property_testing = @import("property_testing.zig");
const failure_injection = @import("failure_injection.zig");

/// Convenient macro-like function to create and run a simple test
pub fn quick_test(comptime OperationType: type, comptime SystemType: type, allocator: std.mem.Allocator) !void {
    // Set up minimal failure injection config
    var failure_config = failure_injection.FailureInjectionConfig.init(allocator);
    defer failure_config.deinit();
    failure_config.allocator_failure_probability = 0.001;
    failure_config.filesystem_error_probability = 0.005;

    // Set up equal operation distribution
    var op_dist = property_testing.OperationDistribution(OperationType).init();
    const operation_count = @typeInfo(OperationType).Enum.fields.len;
    const equal_weight = 1.0 / @as(f64, @floatFromInt(operation_count));

    inline for (@typeInfo(OperationType).Enum.fields) |field| {
        const operation = @field(OperationType, field.name);
        op_dist.set_weight(operation, equal_weight);
    }
    op_dist.normalize();

    // Auto-discover system methods
    const system_init_fn = comptime reflection.discover_init_method(SystemType);
    const system_deinit_fn = comptime reflection.discover_deinit_method(SystemType);
    const execute_operation_fn = comptime reflection.discover_execute_method(SystemType, OperationType);

    // Create and run property test
    const test_config = property_testing.PropertyTest(OperationType, SystemType){
        .name = "quick_test",
        .generators = .{
            .operation_distribution = op_dist,
            .key_generators = .{ .uniform_random = .{ .min_length = 4, .max_length = 16 } },
            .value_generators = .{ .variable_size = .{ .min = 8, .max = 256 } },
            .sequence_length = .{ .min = 50, .max = 200 },
        },
        .failure_config = failure_config,
        .invariants = &.{},
        .shrinking = .{},
        .seed = 42,
        .allocator = allocator,
        .prng = undefined,
        .stats = property_testing.TestStatistics.init(allocator),
        .system_init_fn = system_init_fn,
        .system_deinit_fn = system_deinit_fn,
        .execute_operation_fn = execute_operation_fn,
    };

    var test_instance = property_testing.PropertyTest(OperationType, SystemType).init(allocator, test_config);
    defer test_instance.deinit();

    try test_instance.run(100);
}

/// Create a test with minimal configuration for common CRUD operations
pub fn crud_test(comptime SystemType: type, allocator: std.mem.Allocator) !void {
    const CrudOp = enum { create, read, update, delete };

    // Set up weighted operation distribution for CRUD
    var failure_config = failure_injection.FailureInjectionConfig.init(allocator);
    defer failure_config.deinit();
    failure_config.allocator_failure_probability = 0.001;

    var op_dist = property_testing.OperationDistribution(CrudOp).init();
    op_dist.set_weight(.create, 0.3);
    op_dist.set_weight(.read, 0.4);
    op_dist.set_weight(.update, 0.2);
    op_dist.set_weight(.delete, 0.1);
    op_dist.normalize();

    // Auto-discover system methods
    const system_init_fn = comptime reflection.discover_init_method(SystemType);
    const system_deinit_fn = comptime reflection.discover_deinit_method(SystemType);
    const execute_operation_fn = comptime reflection.discover_execute_method(SystemType, CrudOp);

    // Create and run property test
    const test_config = property_testing.PropertyTest(CrudOp, SystemType){
        .name = "crud_operations_test",
        .generators = .{
            .operation_distribution = op_dist,
            .key_generators = .{ .uniform_random = .{ .min_length = 4, .max_length = 16 } },
            .value_generators = .{ .variable_size = .{ .min = 8, .max = 256 } },
            .sequence_length = .{ .min = 50, .max = 200 },
        },
        .failure_config = failure_config,
        .invariants = &.{},
        .shrinking = .{},
        .seed = 42,
        .allocator = allocator,
        .prng = undefined,
        .stats = property_testing.TestStatistics.init(allocator),
        .system_init_fn = system_init_fn,
        .system_deinit_fn = system_deinit_fn,
        .execute_operation_fn = execute_operation_fn,
    };

    var test_instance = property_testing.PropertyTest(CrudOp, SystemType).init(allocator, test_config);
    defer test_instance.deinit();

    try test_instance.run(100);
}

/// Simple test function that works with minimal setup
pub fn test_system(comptime SystemType: type, allocator: std.mem.Allocator) !void {
    // Try to auto-discover operation type
    const OperationType = reflection.discover_operation_type(SystemType);
    try quick_test(OperationType, SystemType, allocator);
}

/// Attribute-based testing - automatically generate tests based on system annotations
pub fn auto_test(comptime SystemType: type, allocator: std.mem.Allocator) !void {
    // Look for test annotations in the system type
    if (@hasDecl(SystemType, "CoreSimOperations")) {
        const OperationType = SystemType.CoreSimOperations;
        try quick_test(OperationType, SystemType, allocator);
    } else {
        @compileError("SystemType must define 'CoreSimOperations' enum for auto-testing");
    }
}

/// Run a comprehensive test suite for a system type
pub fn full_test_suite(comptime SystemType: type, allocator: std.mem.Allocator) !void {
    reflection.validate_system_type(SystemType);

    const OperationType = reflection.discover_operation_type(SystemType);

    // Run basic functionality test
    try quick_test(OperationType, SystemType, allocator);

    // Run CRUD test if applicable
    try crud_test(SystemType, allocator);

    // Run specialized tests based on system characteristics
    try stress_test(SystemType, allocator);
    try memory_pressure_test(SystemType, allocator);

    // Run network partition test if system appears to be distributed
    if (has_network_operations(SystemType)) {
        try network_partition_test(SystemType, allocator);
    }
}

/// High-stress testing with long sequences and many iterations
pub fn stress_test(comptime SystemType: type, allocator: std.mem.Allocator) !void {
    const OperationType = reflection.discover_operation_type(SystemType);

    // Discover all operations from the OperationType enum
    const operation_list = comptime blk: {
        const op_fields = @typeInfo(OperationType).@"enum".fields;
        var ops: [op_fields.len]OperationType = undefined;
        for (op_fields, 0..) |field, i| {
            ops[i] = @enumFromInt(field.value);
        }
        break :blk ops;
    };

    const builder = core.TestBuilder(SystemType){};
    try builder
        .operations(&operation_list)
        .named("stress_test")
        .iterations(500)
        .sequence_length(200, 1000)
        .allocator_failures(0.01)
        .filesystem_errors(0.005)
        .run(allocator);
}

/// Memory pressure testing with high allocation failure rates
pub fn memory_pressure_test(comptime SystemType: type, allocator: std.mem.Allocator) !void {
    const OperationType = reflection.discover_operation_type(SystemType);

    // Discover all operations from the OperationType enum
    const operation_list = comptime blk: {
        const op_fields = @typeInfo(OperationType).@"enum".fields;
        var ops: [op_fields.len]OperationType = undefined;
        for (op_fields, 0..) |field, i| {
            ops[i] = @enumFromInt(field.value);
        }
        break :blk ops;
    };

    const builder = core.TestBuilder(SystemType){};
    try builder
        .operations(&operation_list)
        .named("memory_pressure_test")
        .iterations(100)
        .sequence_length(50, 200)
        .allocator_failures(0.05) // High allocation failure rate
        .filesystem_errors(0.001)
        .run(allocator);
}

/// Network partition testing for distributed systems
pub fn network_partition_test(comptime SystemType: type, allocator: std.mem.Allocator) !void {
    const OperationType = reflection.discover_operation_type(SystemType);

    // Discover all operations from the OperationType enum
    const operation_list = comptime blk: {
        const op_fields = @typeInfo(OperationType).@"enum".fields;
        var ops: [op_fields.len]OperationType = undefined;
        for (op_fields, 0..) |field, i| {
            ops[i] = @enumFromInt(field.value);
        }
        break :blk ops;
    };

    const builder = core.TestBuilder(SystemType){};
    try builder
        .operations(&operation_list)
        .named("network_partition_test")
        .iterations(150)
        .sequence_length(30, 100)
        .network_errors(0.10) // High network failure rate
        .allocator_failures(0.001)
        .run(allocator);
}

/// Check if system has network-related operations (heuristic)
fn has_network_operations(comptime SystemType: type) bool {
    const OperationType = reflection.discover_operation_type(SystemType);

    inline for (@typeInfo(OperationType).@"enum".fields) |field| {
        const name = field.name;
        // Look for common network operation patterns
        if (std.mem.indexOf(u8, name, "send") != null or
            std.mem.indexOf(u8, name, "receive") != null or
            std.mem.indexOf(u8, name, "connect") != null or
            std.mem.indexOf(u8, name, "sync") != null or
            std.mem.indexOf(u8, name, "replicate") != null or
            std.mem.indexOf(u8, name, "broadcast") != null)
        {
            return true;
        }
    }
    return false;
}
