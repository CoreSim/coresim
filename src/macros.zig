// ABOUTME: Macro-like functions to automatically generate testing boilerplate
// ABOUTME: Provides attribute-based system definition and test generation

const std = @import("std");
const core = @import("core.zig");
const property_testing = @import("property_testing.zig");
const reflection = @import("reflection.zig");

/// Generates a complete property test for a system with minimal annotation
pub fn CoreSimTest(comptime config: TestConfig) type {
    return struct {
        pub fn run(allocator: std.mem.Allocator) !void {
            // Discover all operations from the OperationType enum
            const operation_list = comptime blk: {
                const op_fields = @typeInfo(config.OperationType).@"enum".fields;
                var ops: [op_fields.len]config.OperationType = undefined;
                for (op_fields, 0..) |field, i| {
                    ops[i] = @enumFromInt(field.value);
                }
                break :blk ops;
            };

            var builder = core.TestBuilder(config.SystemType){};
            builder = builder
                .operations(&operation_list);
            .named(config.name);
            .iterations(config.iterations);
            .sequence_length(config.sequence_min, config.sequence_max);
            .allocator_failures(config.allocator_failure_rate);
            .filesystem_errors(config.filesystem_error_rate);

            // Apply operation weights if provided
            if (config.operation_weights) |weights| {
                inline for (weights) |weight_config| {
                    builder = builder.operation_weight(weight_config.operation, weight_config.weight);
                }
            }

            // Add invariants if provided
            if (config.invariants) |invariants| {
                inline for (invariants) |invariant| {
                    builder = builder.invariant(invariant.name, invariant.check_fn, invariant.severity);
                }
            }

            try builder.run(allocator);
        }
    };
}

/// Configuration struct for generating tests
pub const TestConfig = struct {
    OperationType: type,
    SystemType: type,
    name: []const u8 = "generated_test",
    iterations: u32 = 100,
    sequence_min: usize = 50,
    sequence_max: usize = 200,
    allocator_failure_rate: f64 = 0.001,
    filesystem_error_rate: f64 = 0.005,
    operation_weights: ?*const anyopaque = null, // Will be cast to appropriate type
    invariants: ?*const anyopaque = null, // Will be cast to appropriate type
};

pub fn OperationWeight(comptime OperationType: type) type {
    return struct {
        operation: OperationType,
        weight: f64,
    };
}

pub fn InvariantConfig(comptime SystemType: type) type {
    return struct {
        name: []const u8,
        check_fn: *const fn (*SystemType) bool,
        severity: property_testing.InvariantSeverity,
    };
}

/// Macro to generate a testable system with minimal boilerplate
pub fn TestableSystem(comptime config: SystemConfig) type {
    return struct {
        base: config.BaseType,
        operation_count: u64 = 0,

        const Self = @This();
        pub const CoreSimOperations = config.OperationType;

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .base = config.BaseType.init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.base.deinit();
        }

        pub fn execute_operation(self: *Self, operation: property_testing.Operation(config.OperationType)) !void {
            self.operation_count += 1;

            // Auto-generate operation dispatch based on the operation enum
            switch (operation.operation_type) {
                inline else => |op| {
                    const method_name = @tagName(op);

                    // Look for method with exact name
                    if (@hasDecl(config.BaseType, method_name)) {
                        const method = @field(config.BaseType, method_name);
                        try self.callMethod(method, operation);
                    } else {
                        // Look for method with "do" prefix
                        const do_method_name = "do" ++ capitalizeFirst(method_name);
                        if (@hasDecl(config.BaseType, do_method_name)) {
                            const method = @field(config.BaseType, do_method_name);
                            try self.callMethod(method, operation);
                        } else {
                            @compileError("No method found for operation '" ++ method_name ++ "'. Expected '" ++ method_name ++ "' or '" ++ do_method_name ++ "'");
                        }
                    }
                },
            }
        }

        fn callMethod(self: *Self, comptime method: anytype, operation: property_testing.Operation(config.OperationType)) !void {
            try reflection.call_method_with_operation(config.BaseType, &self.base, method, operation);
        }

        // Auto-generate common invariants
        pub fn checkOperationCount(self: *Self) bool {
            return self.operation_count < 100000;
        }

        pub fn checkMemorySafety(self: *Self) bool {
            // Basic check - can be overridden
            _ = self;
            return true;
        }

        // Delegate other methods to the base type
        pub usingnamespace if (@hasDecl(config.BaseType, "checkConsistency"))
            struct {
                pub fn checkConsistency(self: *Self) bool {
                    return self.base.checkConsistency();
                }
            }
        else
            struct {};
    };
}

pub const SystemConfig = struct {
    BaseType: type,
    OperationType: type,
};

fn capitalizeFirst(comptime str: []const u8) []const u8 {
    if (str.len == 0) return str;

    var result: [str.len]u8 = undefined;
    result[0] = std.ascii.toUpper(str[0]);
    @memcpy(result[1..], str[1..]);
    return &result;
}

/// Attribute to mark a system as testable with specific configuration
pub fn TestableWith(comptime config: anytype) fn (type) type {
    return struct {
        fn apply(comptime T: type) type {
            return struct {
                system: T,

                const Self = @This();
                pub const CoreSimOperations = config.OperationType;

                pub fn init(allocator: std.mem.Allocator) Self {
                    return Self{
                        .system = T.init(allocator),
                    };
                }

                pub fn deinit(self: *Self) void {
                    self.system.deinit();
                }

                pub fn execute_operation(self: *Self, operation: property_testing.Operation(config.OperationType)) !void {
                    // Use the provided execution mapping
                    try config.executeMap(self, operation);
                }

                // Generate test
                pub fn runPropertyTest(allocator: std.mem.Allocator) !void {
                    // Discover all operations from the OperationType enum
                    const operation_list = comptime blk: {
                        const op_fields = @typeInfo(config.OperationType).@"enum".fields;
                        var ops: [op_fields.len]config.OperationType = undefined;
                        for (op_fields, 0..) |field, i| {
                            ops[i] = @enumFromInt(field.value);
                        }
                        break :blk ops;
                    };

                    const builder = try core.TestBuilder(Self){};
                    builder
                        .operations(&operation_list)
                        .named(config.name orelse "property_test")
                        .iterations(config.iterations orelse 100)
                        .run(allocator);
                }
            };
        }
    }.apply;
}

test "macro basic usage" {
    const MyOp = enum { put, get, remove };

    const BaseKV = struct {
        allocator: std.mem.Allocator,
        data: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

        pub fn init(allocator: std.mem.Allocator) @This() {
            return @This(){
                .allocator = allocator,
                .data = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            };
        }

        pub fn deinit(self: *@This()) void {
            var iterator = self.data.iterator();
            while (iterator.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.*);
            }
            self.data.deinit();
        }

        pub fn put(self: *@This(), key: []const u8, value: []const u8) !void {
            const owned_key = try self.allocator.dupe(u8, key);
            const owned_value = try self.allocator.dupe(u8, value);
            try self.data.put(owned_key, owned_value);
        }

        pub fn get(self: *@This(), key: []const u8) ?[]const u8 {
            return self.data.get(key);
        }

        pub fn remove(self: *@This(), key: []const u8) bool {
            if (self.data.fetchRemove(key)) |entry| {
                self.allocator.free(entry.key);
                self.allocator.free(entry.value);
                return true;
            }
            return false;
        }

        pub fn checkConsistency(self: *@This()) bool {
            _ = self;
            return true; // Simplified for test
        }
    };

    const TestableKV = TestableSystem(.{
        .BaseType = BaseKV,
        .OperationType = MyOp,
    });

    const operation_list = [_]MyOp{ .put, .get, .remove };

    const builder = core.TestBuilder(TestableKV){};
    try builder
        .operations(&operation_list)
        .named("macro_test")
        .iterations(3) // Small number for test
        .sequence_length(5, 10)
        .run(std.testing.allocator);
}
