// ABOUTME: Comptime reflection utilities for automatically discovering system methods
// ABOUTME: Provides method discovery and type introspection for CoreSim test generation

const std = @import("std");
const property_testing = @import("property_testing.zig");

/// Auto-discover init method using comptime reflection
pub fn discover_init_method(comptime SystemType: type) *const fn (std.mem.Allocator) anyerror!SystemType {
    // Look for common method names
    if (@hasDecl(SystemType, "init")) {
        const init_fn = SystemType.init;
        const InitType = @TypeOf(init_fn);
        const init_info = @typeInfo(InitType).@"fn";

        // Check if the return type is already an error union
        const return_type_info = @typeInfo(init_info.return_type.?);
        if (return_type_info == .error_union and return_type_info.error_union.payload == SystemType) {
            return init_fn;
        } else {
            // Wrap non-error returning init in a wrapper
            return struct {
                fn wrapper(allocator: std.mem.Allocator) anyerror!SystemType {
                    return init_fn(allocator);
                }
            }.wrapper;
        }
    } else if (@hasDecl(SystemType, "create")) {
        const create_fn = SystemType.create;
        const CreateType = @TypeOf(create_fn);
        const create_info = @typeInfo(CreateType).@"fn";

        // Check if the return type is already an error union
        const return_type_info = @typeInfo(create_info.return_type.?);
        if (return_type_info == .error_union and return_type_info.error_union.payload == SystemType) {
            return create_fn;
        } else {
            // Wrap non-error returning create in a wrapper
            return struct {
                fn wrapper(allocator: std.mem.Allocator) anyerror!SystemType {
                    return create_fn(allocator);
                }
            }.wrapper;
        }
    } else {
        @compileError("SystemType must have an 'init' or 'create' method that takes an allocator and returns the system type");
    }
}

/// Auto-discover deinit method using comptime reflection
pub fn discover_deinit_method(comptime SystemType: type) *const fn (*SystemType) void {
    if (@hasDecl(SystemType, "deinit")) {
        return SystemType.deinit;
    } else if (@hasDecl(SystemType, "destroy")) {
        return SystemType.destroy;
    } else {
        @compileError("SystemType must have a 'deinit' or 'destroy' method that takes a pointer to the system");
    }
}

/// Auto-discover execute method using comptime reflection
pub fn discover_execute_method(comptime SystemType: type, comptime OperationType: type) *const fn (*SystemType, property_testing.Operation(OperationType)) anyerror!void {
    if (@hasDecl(SystemType, "execute_operation")) {
        return SystemType.execute_operation;
    } else if (@hasDecl(SystemType, "execute")) {
        return SystemType.execute;
    } else if (@hasDecl(SystemType, "perform_operation")) {
        return SystemType.perform_operation;
    } else {
        @compileError("SystemType must have an 'execute_operation', 'execute', or 'perform_operation' method");
    }
}

/// Auto-discover operation type from system type
pub fn discover_operation_type(comptime SystemType: type) type {
    if (@hasDecl(SystemType, "Operation")) {
        return SystemType.Operation;
    } else if (@hasDecl(SystemType, "OpType")) {
        return SystemType.OpType;
    } else if (@hasDecl(SystemType, "Operations")) {
        return SystemType.Operations;
    } else if (@hasDecl(SystemType, "CoreSimOperations")) {
        return SystemType.CoreSimOperations;
    } else {
        @compileError("SystemType must define 'Operation', 'OpType', 'Operations', or 'CoreSimOperations' enum");
    }
}

/// Check if a type has a method with the given name
pub fn has_method(comptime T: type, comptime method_name: []const u8) bool {
    return @hasDecl(T, method_name);
}

/// Get method signature information
pub fn get_method_info(comptime T: type, comptime method_name: []const u8) std.builtin.Type.Fn {
    if (!@hasDecl(T, method_name)) {
        @compileError("Type " ++ @typeName(T) ++ " does not have method '" ++ method_name ++ "'");
    }

    const method = @field(T, method_name);
    const MethodType = @TypeOf(method);
    return @typeInfo(MethodType).@"fn";
}

/// Validate that a system type follows CoreSim conventions
pub fn validate_system_type(comptime SystemType: type) void {
    // Check for required methods
    if (!@hasDecl(SystemType, "init") and !@hasDecl(SystemType, "create")) {
        @compileError("SystemType must have an 'init' or 'create' method");
    }

    if (!@hasDecl(SystemType, "deinit") and !@hasDecl(SystemType, "destroy")) {
        @compileError("SystemType must have a 'deinit' or 'destroy' method");
    }

    // Check for operation type
    _ = discover_operation_type(SystemType);
}

/// Call a method with appropriate parameters based on its signature
/// This handles the common pattern of calling methods with 1-3 parameters
pub fn call_method_with_operation(comptime SystemType: type, system: *SystemType, comptime method: anytype, operation: property_testing.Operation(discover_operation_type(SystemType))) !void {
    const MethodType = @TypeOf(method);
    const method_info = @typeInfo(MethodType).@"fn";

    switch (method_info.params.len) {
        1 => {
            // Method signature: fn(self: *SystemType) ReturnType
            const result = method(system);
            // Handle both error unions and regular return types
            if (@typeInfo(@TypeOf(result)) == .error_union) {
                _ = try result;
            }
        },
        2 => {
            // Method signature: fn(self: *SystemType, key: []const u8) ReturnType
            if (operation.key) |key| {
                const result = method(system, key);
                if (@typeInfo(@TypeOf(result)) == .error_union) {
                    _ = try result;
                }
            }
        },
        3 => {
            // Method signature: fn(self: *SystemType, key: []const u8, value: []const u8) ReturnType
            if (operation.key) |key| {
                if (operation.value) |value| {
                    _ = try method(system, key, value);
                }
            }
        },
        else => {
            @compileError("Unsupported method signature: expected 1-3 parameters, found " ++ std.fmt.comptimePrint("{}", .{method_info.params.len}));
        },
    }
}

// ============================================================================
// Unit Tests for Reflection Utilities
// ============================================================================

test "discover_init_method with error union return" {
    const TestSystem = struct {
        value: u32,

        pub fn init(allocator: std.mem.Allocator) !@This() {
            _ = allocator;
            return @This(){ .value = 42 };
        }
    };

    const init_fn = discover_init_method(TestSystem);
    const system = try init_fn(std.testing.allocator);
    try std.testing.expect(system.value == 42);
}

test "discover_init_method with create method" {
    const TestSystem = struct {
        value: u32,

        pub fn create(allocator: std.mem.Allocator) !@This() {
            _ = allocator;
            return @This(){ .value = 123 };
        }
    };

    const init_fn = discover_init_method(TestSystem);
    const system = try init_fn(std.testing.allocator);
    try std.testing.expect(system.value == 123);
}

test "discover_deinit_method with deinit" {
    const TestSystem = struct {
        pub fn deinit(_: *@This()) void {}
    };

    const deinit_fn = discover_deinit_method(TestSystem);
    var system = TestSystem{};
    deinit_fn(&system); // Should not crash
}

test "discover_deinit_method with destroy" {
    const TestSystem = struct {
        pub fn destroy(_: *@This()) void {}
    };

    const deinit_fn = discover_deinit_method(TestSystem);
    var system = TestSystem{};
    deinit_fn(&system); // Should not crash
}

test "discover_operation_type with Operation enum" {
    const TestSystem = struct {
        pub const Operation = enum { put, get, delete };
    };

    const OpType = discover_operation_type(TestSystem);
    try std.testing.expect(OpType == TestSystem.Operation);

    const op: OpType = .put;
    try std.testing.expect(op == .put);
}

test "discover_operation_type with OpType enum" {
    const TestSystem = struct {
        pub const OpType = enum { read, write };
    };

    const OpType = discover_operation_type(TestSystem);
    try std.testing.expect(OpType == TestSystem.OpType);
}

test "discover_operation_type with Operations enum" {
    const TestSystem = struct {
        pub const Operations = enum { start, stop, restart };
    };

    const OpType = discover_operation_type(TestSystem);
    try std.testing.expect(OpType == TestSystem.Operations);
}

test "discover_operation_type with CoreSimOperations enum" {
    const TestSystem = struct {
        pub const CoreSimOperations = enum { init_op, cleanup_op };
    };

    const OpType = discover_operation_type(TestSystem);
    try std.testing.expect(OpType == TestSystem.CoreSimOperations);
}

test "has_method utility function" {
    const TestSystem = struct {
        pub fn existing_method(_: *@This()) void {}
        // no non_existing_method
    };

    try std.testing.expect(has_method(TestSystem, "existing_method"));
    try std.testing.expect(!has_method(TestSystem, "non_existing_method"));
}

test "get_method_info utility function" {
    const TestSystem = struct {
        pub fn test_method(_: *@This(), _: []const u8) void {}
    };

    const method_info = get_method_info(TestSystem, "test_method");
    try std.testing.expect(method_info.params.len == 2); // self + key parameter
}

test "validate_system_type with valid system" {
    const ValidSystem = struct {
        pub const Operation = enum { op1, op2 };

        pub fn init(allocator: std.mem.Allocator) !@This() {
            _ = allocator;
            return @This(){};
        }

        pub fn deinit(_: *@This()) void {}
    };

    // Should compile without error
    validate_system_type(ValidSystem);
}

test "call_method_with_operation single parameter" {
    const TestSystem = struct {
        called: bool = false,

        pub const Operation = enum { test_op };

        pub fn single_param_method(self: *@This()) void {
            self.called = true;
        }
    };

    var system = TestSystem{};
    const operation = property_testing.Operation(TestSystem.Operation){
        .operation_type = .test_op,
        .key = null,
        .value = null,
    };

    try call_method_with_operation(TestSystem, &system, TestSystem.single_param_method, operation);
    try std.testing.expect(system.called);
}

test "call_method_with_operation two parameters" {
    const TestSystem = struct {
        last_key: ?[]const u8 = null,

        pub const Operation = enum { test_op };

        pub fn two_param_method(self: *@This(), key: []const u8) void {
            self.last_key = key;
        }
    };

    var system = TestSystem{};
    const key_data = "test_key";
    const operation = property_testing.Operation(TestSystem.Operation){
        .operation_type = .test_op,
        .key = @constCast(key_data),
        .value = null,
    };

    try call_method_with_operation(TestSystem, &system, TestSystem.two_param_method, operation);
    try std.testing.expect(std.mem.eql(u8, system.last_key.?, "test_key"));
}

test "call_method_with_operation three parameters" {
    const TestSystem = struct {
        last_key: ?[]const u8 = null,
        last_value: ?[]const u8 = null,

        pub const Operation = enum { test_op };

        pub fn three_param_method(self: *@This(), key: []const u8, value: []const u8) !void {
            self.last_key = key;
            self.last_value = value;
        }
    };

    var system = TestSystem{};
    const key_data = "test_key";
    const value_data = "test_value";
    const operation = property_testing.Operation(TestSystem.Operation){
        .operation_type = .test_op,
        .key = @constCast(key_data),
        .value = @constCast(value_data),
    };

    try call_method_with_operation(TestSystem, &system, TestSystem.three_param_method, operation);
    try std.testing.expect(std.mem.eql(u8, system.last_key.?, "test_key"));
    try std.testing.expect(std.mem.eql(u8, system.last_value.?, "test_value"));
}
