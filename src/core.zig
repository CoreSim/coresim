// ABOUTME: Core ergonomic API for CoreSim with minimal boilerplate
// ABOUTME: Provides convention-over-configuration approach for easy testing

const std = @import("std");
const property_testing = @import("property_testing.zig");
const failure_injection = @import("failure_injection.zig");
const reflection = @import("reflection.zig");

// Thread-local storage for current failure configuration (used during test execution)
threadlocal var current_failure_config: ?*failure_injection.FailureInjectionConfig = null;
threadlocal var current_prng: ?*std.Random.DefaultPrng = null;
threadlocal var current_failure_stats: ?*property_testing.FailureStats = null;
threadlocal var current_condition: ?failure_injection.SystemCondition = null;

/// Check if a custom failure should be injected during test execution
/// This function can be called by system methods to determine if they should simulate specific failures
pub fn should_inject_custom_failure(failure_type: []const u8) bool {
    if (current_failure_config) |config| {
        if (current_prng) |prng| {
            const base_prob = config.custom_failure_probabilities.get(failure_type) orelse 0.0;
            const effective_prob = config.get_effective_probability(base_prob, current_condition);
            const should_inject = prng.random().float(f64) < effective_prob;

            if (should_inject) {
                if (current_failure_stats) |stats| {
                    stats.record_custom_failure(failure_type) catch |err| {
                        // Statistics recording failed - log warning but continue test execution
                        std.debug.print("Warning: Failed to record custom failure '{s}': {}\n", .{ failure_type, err });
                    };
                }
            }

            return should_inject;
        }
    }
    return false;
}

/// Check if a network error should be injected during test execution
/// This function can be called by system methods to simulate network failures
pub fn should_inject_network_error() bool {
    if (current_failure_config) |config| {
        if (current_prng) |prng| {
            const base_prob = config.network_error_probability;
            const effective_prob = config.get_effective_probability(base_prob, current_condition);
            const should_inject = prng.random().float(f64) < effective_prob;

            if (should_inject) {
                if (current_failure_stats) |stats| {
                    stats.network_errors_injected += 1;
                }
            }

            return should_inject;
        }
    }
    return false;
}

/// Update current system condition to influence failure rates through conditional multipliers
/// This function can be called by system methods to indicate current operational state
pub fn set_system_condition(condition: ?failure_injection.SystemCondition) void {
    current_condition = condition;
}

/// Return current system condition (mainly for debugging/testing)
pub fn current_system_condition() ?failure_injection.SystemCondition {
    return current_condition;
}

/// Operation weight configuration for custom probability distributions
pub fn OpWeight(comptime OperationType: type) type {
    return struct {
        operation: OperationType,
        weight: f64,
    };
}

/// Custom failure configuration for domain-specific error injection
pub const CustomFailure = struct {
    name: []const u8,
    probability: f64,
};

/// Ergonomic test builder that requires minimal setup
pub fn TestBuilder(comptime SystemType: type) type {
    // Auto-discover the operation type using the reflection module
    const OperationType = reflection.discover_operation_type(SystemType);

    return struct {
        config: TestConfig = .{},
        operation_list: []const OperationType = &.{},

        const Self = @This();
        const PropertyTest = property_testing.PropertyTest(OperationType, SystemType);
        const Operation = property_testing.Operation(OperationType);

        /// Simple test configuration with smart defaults
        const TestConfig = struct {
            name: []const u8 = "auto_test",
            iterations: u32 = 100,
            sequence_length: struct { min: usize = 50, max: usize = 200 } = .{},
            allocator_failures: f64 = 0.001,
            filesystem_errors: f64 = 0.005,
            network_errors: f64 = 0.001,
            seed: u64 = 42,
            key_strategy: ?property_testing.KeyGenerationStrategy = null,
            value_strategy: ?property_testing.ValueGenerationStrategy = null,
            operation_weights: []const OpWeight(OperationType) = &.{},
            individual_weights: std.EnumMap(OperationType, f64) = std.EnumMap(OperationType, f64).init(.{}),
            custom_failures: []const CustomFailure = &.{},
            conditional_multipliers: []const failure_injection.ConditionalMultiplier = &.{},
            custom_invariants: []const property_testing.InvariantChecker(SystemType) = &.{},
            detailed_stats_enabled: bool = false,
        };

        /// Specify which operations to test
        pub fn operations(self: Self, ops: []const OperationType) Self {
            return .{
                .config = self.config,
                .operation_list = ops,
            };
        }

        /// Helper to update config immutably
        fn with_config(self: Self, new_config: TestConfig) Self {
            return .{
                .config = new_config,
                .operation_list = self.operation_list,
            };
        }

        /// Set test name
        pub fn named(self: Self, name: []const u8) Self {
            var config = self.config;
            config.name = name;
            return self.with_config(config);
        }

        /// Set number of iterations
        pub fn iterations(self: Self, count: u32) Self {
            var config = self.config;
            config.iterations = count;
            return self.with_config(config);
        }

        /// Set allocator failure rate
        pub fn allocator_failures(self: Self, rate: f64) Self {
            var config = self.config;
            config.allocator_failures = rate;
            return self.with_config(config);
        }

        /// Set filesystem error rate
        pub fn filesystem_errors(self: Self, rate: f64) Self {
            var config = self.config;
            config.filesystem_errors = rate;
            return self.with_config(config);
        }

        /// Set network error rate
        pub fn network_errors(self: Self, rate: f64) Self {
            var config = self.config;
            config.network_errors = rate;
            return self.with_config(config);
        }

        /// Set random seed
        pub fn seed(self: Self, s: u64) Self {
            var config = self.config;
            config.seed = s;
            return self.with_config(config);
        }

        /// Set sequence length range
        pub fn sequence_length(self: Self, min: usize, max: usize) Self {
            var config = self.config;
            config.sequence_length = .{ .min = min, .max = max };
            return self.with_config(config);
        }

        /// Configure key generation strategy
        pub fn key_strategy(self: Self, strategy: property_testing.KeyGenerationStrategy) Self {
            var config = self.config;
            config.key_strategy = strategy;
            return self.with_config(config);
        }

        /// Configure value generation strategy
        pub fn value_strategy(self: Self, strategy: property_testing.ValueGenerationStrategy) Self {
            var config = self.config;
            config.value_strategy = strategy;
            return self.with_config(config);
        }

        // Convenience methods for common key strategies

        /// Generate random keys with specified length range
        pub fn random_keys(self: Self, min_length: usize, max_length: usize) Self {
            return self.key_strategy(.{ .uniform_random = .{ .min_length = min_length, .max_length = max_length } });
        }

        /// Generate collision-prone keys for stress testing hash maps
        pub fn collision_prone_keys(self: Self, collision_rate: f64) Self {
            return self.key_strategy(.{ .collision_prone = .{ .hash_collision_rate = collision_rate } });
        }

        /// Generate sequential keys with specified prefix
        pub fn sequential_keys(self: Self, prefix: []const u8) Self {
            return self.key_strategy(.{ .sequential = .{ .prefix = prefix } });
        }

        // Convenience methods for common value strategies

        /// Generate values of exact size
        pub fn fixed_size_values(self: Self, size: usize) Self {
            return self.value_strategy(.{ .fixed_size = size });
        }

        /// Generate values within size range
        pub fn variable_size_values(self: Self, min_size: usize, max_size: usize) Self {
            return self.value_strategy(.{ .variable_size = .{ .min = min_size, .max = max_size } });
        }

        /// Generate random binary values
        pub fn random_binary_values(self: Self) Self {
            return self.value_strategy(.{ .random_binary = {} });
        }

        /// Set custom operation weights for probability distribution
        pub fn operation_weights(self: Self, weights: []const OpWeight(OperationType)) Self {
            var config = self.config;
            config.operation_weights = weights;
            return self.with_config(config);
        }

        /// Set custom failure types and their probabilities
        pub fn custom_failures(self: Self, failures: []const CustomFailure) Self {
            var config = self.config;
            config.custom_failures = failures;
            return self.with_config(config);
        }

        /// Configure conditional multipliers for state-aware failure injection
        pub fn conditional_multipliers(self: Self, multipliers: []const failure_injection.ConditionalMultiplier) Self {
            var config = self.config;
            config.conditional_multipliers = multipliers;
            return self.with_config(config);
        }

        /// Add a single conditional multiplier (convenience method)
        pub fn conditional_multiplier(self: Self, condition: failure_injection.SystemCondition, multiplier: f64) Self {
            // For single multiplier, we need to create a slice with one element
            // This is a limitation - users should prefer conditional_multipliers for multiple
            const single_multiplier = [_]failure_injection.ConditionalMultiplier{.{ .condition = condition, .multiplier = multiplier }};
            return self.conditional_multipliers(&single_multiplier);
        }

        /// Enable detailed statistics collection for performance analysis
        pub fn detailed_stats(self: Self, enabled: bool) Self {
            var config = self.config;
            config.detailed_stats_enabled = enabled;
            return self.with_config(config);
        }

        /// Set weight for individual operation (convenience method)
        pub fn operation_weight(self: Self, operation: OperationType, weight: f64) Self {
            var config = self.config;
            config.individual_weights.put(operation, weight);
            return self.with_config(config);
        }

        /// Add custom invariants (replaces any previously set custom invariants)
        pub fn invariants(self: Self, invariant_list: []const property_testing.InvariantChecker(SystemType)) Self {
            var config = self.config;
            config.custom_invariants = invariant_list;
            return self.with_config(config);
        }

        /// Convenience method to add a single custom invariant
        /// Note: For multiple invariants, build an array and use .invariants() instead
        pub fn invariant(self: Self, name: []const u8, check_fn: *const fn (*SystemType) bool, severity: property_testing.InvariantSeverity) Self {
            // Create a single invariant array - this allocates at comptime
            const single_invariant = [_]property_testing.InvariantChecker(SystemType){.{ .name = name, .check_fn = check_fn, .severity = severity }};
            return self.invariants(&single_invariant);
        }

        /// Run the test with specified allocator
        pub fn run(self: Self, allocator: std.mem.Allocator) !void {
            var stats = try self.run_with_stats(allocator);
            defer stats.deinit();
        }

        /// Run the test and return detailed statistics
        pub fn run_with_stats(self: Self, allocator: std.mem.Allocator) !property_testing.TestStatistics {
            var failure_config = try self.setup_failure_injection(allocator);
            defer failure_config.deinit();

            var prng = std.Random.DefaultPrng.init(self.config.seed);
            self.setup_global_failure_context(&failure_config, &prng);
            defer self.cleanup_global_failure_context();

            const op_dist = self.setup_operation_distribution();

            // Create invariants list with only explicit custom invariants
            var invariants_list = std.ArrayList(property_testing.InvariantChecker(SystemType)).init(allocator);
            defer invariants_list.deinit();

            // Add custom invariants from config
            for (self.config.custom_invariants) |custom_invariant| {
                try invariants_list.append(custom_invariant);
            }

            // Create property test configuration
            const test_config = PropertyTest{
                .name = self.config.name,
                .generators = .{
                    .operation_distribution = op_dist,
                    .key_generators = self.config.key_strategy orelse .{ .uniform_random = .{ .min_length = 4, .max_length = 16 } },
                    .value_generators = self.config.value_strategy orelse .{ .variable_size = .{ .min = 8, .max = 256 } },
                    .sequence_length = .{ .min = self.config.sequence_length.min, .max = self.config.sequence_length.max },
                },
                .failure_config = failure_config,
                .invariants = invariants_list.items,
                .shrinking = .{},
                .seed = self.config.seed,
                .allocator = allocator,
                .prng = undefined,
                .stats = property_testing.TestStatistics.initWithDetailedStats(allocator, self.config.detailed_stats_enabled),
                .system_init_fn = SystemType.init,
                .system_deinit_fn = SystemType.deinit,
                .execute_operation_fn = executeOperation,
            };

            var test_instance = PropertyTest.init(allocator, test_config);
            defer test_instance.deinit();

            current_failure_stats = &test_instance.stats.failures_injected;
            try self.setup_detailed_statistics(&test_instance.stats);

            try test_instance.run(self.config.iterations);

            // Create a deep copy of the statistics before the test instance is deallocated
            return try test_instance.stats.clone(allocator);
        }

        /// Set up failure injection configuration with custom failures and multipliers
        fn setup_failure_injection(self: Self, allocator: std.mem.Allocator) !failure_injection.FailureInjectionConfig {
            var failure_config = failure_injection.FailureInjectionConfig.init(allocator);
            failure_config.allocator_failure_probability = self.config.allocator_failures;
            failure_config.filesystem_error_probability = self.config.filesystem_errors;
            failure_config.network_error_probability = self.config.network_errors;

            // Set up custom failure types
            const failure_list = self.config.custom_failures;
            for (failure_list) |custom_failure| {
                try failure_config.set_custom_probability(allocator, custom_failure.name, custom_failure.probability);
            }

            // Set up conditional multipliers
            failure_config.conditional_multipliers = self.config.conditional_multipliers;

            return failure_config;
        }

        /// Set up global failure context for use by system methods
        fn setup_global_failure_context(_: Self, failure_config: *failure_injection.FailureInjectionConfig, prng: *std.Random.DefaultPrng) void {
            current_failure_config = failure_config;
            current_prng = prng;
        }

        /// Clean up global failure context
        fn cleanup_global_failure_context(_: Self) void {
            current_failure_config = null;
            current_prng = null;
            current_failure_stats = null;
            current_condition = null;
        }

        /// Create and configure operation distribution based on weights
        fn setup_operation_distribution(self: Self) property_testing.OperationDistribution(OperationType) {
            var op_dist = property_testing.OperationDistribution(OperationType).init();

            // Check if bulk custom weights are provided
            const custom_weights = self.config.operation_weights;
            if (custom_weights.len > 0) {
                // Use bulk custom weights
                for (custom_weights) |weight_config| {
                    op_dist.set_weight(weight_config.operation, weight_config.weight);
                }
            } else if (self.config.individual_weights.count() > 0) {
                // Use individual weights
                var individual_weights = self.config.individual_weights;
                var weight_iter = individual_weights.iterator();
                while (weight_iter.next()) |entry| {
                    op_dist.set_weight(entry.key, entry.value.*);
                }
                // Set default weight for operations not explicitly configured
                const default_weight = 1.0;
                for (self.operation_list) |op| {
                    if (!individual_weights.contains(op)) {
                        op_dist.set_weight(op, default_weight);
                    }
                }
            } else {
                // Use equal weights by default
                const weight = 1.0 / @as(f64, @floatFromInt(self.operation_list.len));
                for (self.operation_list) |op| {
                    op_dist.set_weight(op, weight);
                }
            }
            op_dist.normalize();

            return op_dist;
        }

        /// Set up detailed statistics with intended operation weights
        fn setup_detailed_statistics(self: Self, stats: *property_testing.TestStatistics) !void {
            if (!self.config.detailed_stats_enabled) return;

            const weights = self.config.operation_weights;
            if (weights.len > 0) {
                for (weights) |weight_config| {
                    const op_name = @tagName(weight_config.operation);
                    try stats.set_intended_operation_weight(op_name, weight_config.weight);
                }
            } else {
                // Set equal weights for all operations
                const equal_weight = 1.0 / @as(f64, @floatFromInt(self.operation_list.len));
                for (self.operation_list) |op| {
                    const op_name = @tagName(op);
                    try stats.set_intended_operation_weight(op_name, equal_weight);
                }
            }
        }

        /// Auto-generated operation executor that maps operations to methods
        fn executeOperation(system: *SystemType, operation: Operation) !void {
            switch (operation.operation_type) {
                inline else => |op| {
                    const method_name = @tagName(op);

                    // Compile-time validation that the method exists
                    if (!@hasDecl(SystemType, method_name)) {
                        @compileError("SystemType must have method '" ++ method_name ++ "' for operation " ++ @typeName(OperationType) ++ "." ++ method_name);
                    }

                    const method = @field(SystemType, method_name);
                    try reflection.call_method_with_operation(SystemType, system, method, operation);
                },
            }
        }
    };
}

test "Simple API basic usage" {
    // Example system following conventions
    const SimpleKV = struct {
        allocator: std.mem.Allocator,
        data: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

        // Required: Operation enum
        pub const Operation = enum { put, get, delete };

        // Required: Standard lifecycle methods
        pub fn init(allocator: std.mem.Allocator) !@This() {
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

        // Operation methods (names match enum values)
        pub fn put(self: *@This(), key: []const u8, value: []const u8) !void {
            const owned_key = try self.allocator.dupe(u8, key);
            const owned_value = try self.allocator.dupe(u8, value);
            try self.data.put(owned_key, owned_value);
        }

        pub fn get(self: *@This(), key: []const u8) ?[]const u8 {
            return self.data.get(key);
        }

        pub fn delete(self: *@This(), key: []const u8) bool {
            if (self.data.fetchRemove(key)) |entry| {
                self.allocator.free(entry.key);
                self.allocator.free(entry.value);
                return true;
            }
            return false;
        }

        // Invariant checking method for explicit use
        pub fn checkConsistency(self: *@This()) bool {
            var iterator = self.data.iterator();
            while (iterator.next()) |entry| {
                if (entry.key_ptr.len == 0) return false;
            }
            return true;
        }
    };

    // Test the simple API with explicit invariant
    const builder = TestBuilder(SimpleKV){};
    try builder
        .operations(&[_]SimpleKV.Operation{ .put, .get, .delete })
        .named("simple_test")
        .iterations(5)
        .invariant("consistency", SimpleKV.checkConsistency, .critical)
        .run(std.testing.allocator);
}

test "One-liner test" {
    const SimpleKV = struct {
        allocator: std.mem.Allocator,

        pub const Operation = enum { put, get };

        pub fn init(allocator: std.mem.Allocator) !@This() {
            return @This(){ .allocator = allocator };
        }

        pub fn deinit(_: *@This()) void {}

        pub fn put(_: *@This(), _: []const u8, _: []const u8) !void {}

        pub fn get(_: *@This(), _: []const u8) ?[]const u8 {
            return null;
        }
    };

    // TestBuilder test!
    const builder = TestBuilder(SimpleKV){};
    try builder
        .operations(&[_]SimpleKV.Operation{ .put, .get })
        .iterations(3)
        .run(std.testing.allocator);
}

test "Custom invariants functionality" {
    const TestSystem = struct {
        counter: u32 = 0,

        pub const Operation = enum { increment, decrement, reset };

        pub fn init(allocator: std.mem.Allocator) !@This() {
            _ = allocator;
            return @This(){};
        }

        pub fn deinit(self: *@This()) void {
            _ = self;
        }

        pub fn increment(self: *@This(), _: []const u8, _: []const u8) !void {
            self.counter += 1;
        }

        pub fn decrement(self: *@This(), _: []const u8, _: []const u8) !void {
            if (self.counter > 0) self.counter -= 1;
        }

        pub fn reset(self: *@This(), _: []const u8, _: []const u8) !void {
            self.counter = 0;
        }

        // Invariant checking method
        pub fn checkConsistency(self: *@This()) bool {
            return self.counter < 1000; // Basic sanity check
        }

        // Custom invariant function
        pub fn checkCounterRange(self: *@This()) bool {
            // Custom invariant: counter shouldn't exceed 50
            return self.counter <= 50;
        }
    };

    const ops = [_]TestSystem.Operation{ .increment, .decrement, .reset };

    // Test with multiple explicit invariants
    const builder = TestBuilder(TestSystem){};
    try builder
        .operations(&ops)
        .named("explicit_invariants_test")
        .iterations(5)
        .sequence_length(10, 20)
        .invariant("consistency", TestSystem.checkConsistency, .critical)
        .invariant("counter_range", TestSystem.checkCounterRange, .important)
        .run(std.testing.allocator);
}

test "TestBuilder builder pattern immutability" {
    const TestSystem = struct {
        pub const Operation = enum { op1, op2 };

        pub fn init(allocator: std.mem.Allocator) !@This() {
            _ = allocator;
            return @This(){};
        }

        pub fn deinit(_: *@This()) void {}
        pub fn op1(_: *@This(), _: []const u8, _: []const u8) !void {}
        pub fn op2(_: *@This(), _: []const u8) ?[]const u8 {
            return null;
        }
    };

    const ops = [_]TestSystem.Operation{ .op1, .op2 };

    // Test that builder pattern preserves immutability
    const builder1 = TestBuilder(TestSystem){};
    const builder2 = builder1.operations(&ops);
    const builder3 = builder2.iterations(10);
    const builder4 = builder3.seed(12345);

    // Original builders should be unchanged
    try std.testing.expect(builder1.config.iterations == 100); // default
    try std.testing.expect(builder2.config.iterations == 100); // still default
    try std.testing.expect(builder3.config.iterations == 10); // changed
    try std.testing.expect(builder4.config.iterations == 10); // preserved
    try std.testing.expect(builder4.config.seed == 12345);
}

test "TestBuilder operation weights configuration" {
    const TestSystem = struct {
        pub const Operation = enum { frequent, rare, medium };

        pub fn init(allocator: std.mem.Allocator) !@This() {
            _ = allocator;
            return @This(){};
        }

        pub fn deinit(_: *@This()) void {}
        pub fn frequent(_: *@This(), _: []const u8, _: []const u8) !void {}
        pub fn rare(_: *@This(), _: []const u8, _: []const u8) !void {}
        pub fn medium(_: *@This(), _: []const u8, _: []const u8) !void {}
    };

    const ops = [_]TestSystem.Operation{ .frequent, .rare, .medium };
    const weights = [_]OpWeight(TestSystem.Operation){
        .{ .operation = .frequent, .weight = 0.7 },
        .{ .operation = .rare, .weight = 0.1 },
        .{ .operation = .medium, .weight = 0.2 },
    };

    const builder = TestBuilder(TestSystem){};
    try builder
        .operations(&ops)
        .operation_weights(&weights)
        .iterations(5)
        .run(std.testing.allocator);
}

test "TestBuilder custom failures configuration" {
    const TestSystem = struct {
        pub const Operation = enum { put, get };

        pub fn init(allocator: std.mem.Allocator) !@This() {
            _ = allocator;
            return @This(){};
        }

        pub fn deinit(_: *@This()) void {}

        pub fn put(_: *@This(), _: []const u8, _: []const u8) !void {
            // Test injection of custom failures
            if (should_inject_custom_failure("disk_full")) {
                return error.DiskFull;
            }
            if (should_inject_custom_failure("permission_denied")) {
                return error.PermissionDenied;
            }
        }

        pub fn get(_: *@This(), _: []const u8) ?[]const u8 {
            return null;
        }
    };

    const ops = [_]TestSystem.Operation{ .put, .get };
    const failures = [_]CustomFailure{
        .{ .name = "disk_full", .probability = 0.1 },
        .{ .name = "permission_denied", .probability = 0.05 },
    };

    const builder = TestBuilder(TestSystem){};
    try builder
        .operations(&ops)
        .custom_failures(&failures)
        .iterations(10)
        .run(std.testing.allocator);
}

test "TestBuilder failure injection configuration" {
    const TestSystem = struct {
        pub const Operation = enum { allocate, write, network_call };

        pub fn init(allocator: std.mem.Allocator) !@This() {
            _ = allocator;
            return @This(){};
        }

        pub fn deinit(_: *@This()) void {}

        pub fn allocate(_: *@This(), _: []const u8, _: []const u8) !void {
            // These would fail if failure injection is active
        }

        pub fn write(_: *@This(), _: []const u8, _: []const u8) !void {}

        pub fn network_call(_: *@This(), _: []const u8, _: []const u8) !void {
            if (should_inject_network_error()) {
                return error.NetworkTimeout;
            }
        }
    };

    const ops = [_]TestSystem.Operation{ .allocate, .write, .network_call };

    // Test various failure injection configurations
    const builder = TestBuilder(TestSystem){};
    try builder
        .operations(&ops)
        .allocator_failures(0.01) // 1% allocator failures
        .filesystem_errors(0.005) // 0.5% filesystem errors
        .network_errors(0.02) // 2% network errors
        .iterations(5)
        .run(std.testing.allocator);
}

test "TestBuilder sequence length configuration" {
    const TestSystem = struct {
        operations_count: u32 = 0,

        pub const Operation = enum { op1, op2 };

        pub fn init(allocator: std.mem.Allocator) !@This() {
            _ = allocator;
            return @This(){};
        }

        pub fn deinit(_: *@This()) void {}

        pub fn op1(self: *@This(), _: []const u8, _: []const u8) !void {
            self.operations_count += 1;
        }

        pub fn op2(self: *@This(), _: []const u8, _: []const u8) !void {
            self.operations_count += 1;
        }

        pub fn checkOperationsInRange(self: *@This()) bool {
            // Should be within configured range
            return self.operations_count >= 5 and self.operations_count <= 15;
        }
    };

    const ops = [_]TestSystem.Operation{ .op1, .op2 };

    const builder = TestBuilder(TestSystem){};
    try builder
        .operations(&ops)
        .sequence_length(5, 15) // Between 5 and 15 operations per test
        .iterations(3)
        .invariant("ops_in_range", TestSystem.checkOperationsInRange, .important)
        .run(std.testing.allocator);
}

test "should_inject_custom_failure function" {
    // Test with no active configuration
    try std.testing.expect(!should_inject_custom_failure("test_failure"));

    // Test with active configuration
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = failure_injection.FailureInjectionConfig.init(allocator);
    defer config.deinit();

    try config.set_custom_probability(allocator, "test_failure", 1.0); // 100% probability

    var prng = std.Random.DefaultPrng.init(12345);

    current_failure_config = &config;
    current_prng = &prng;
    defer {
        current_failure_config = null;
        current_prng = null;
    }

    // Should inject at 100% probability
    try std.testing.expect(should_inject_custom_failure("test_failure"));

    // Non-configured failure should not inject
    try std.testing.expect(!should_inject_custom_failure("unknown_failure"));
}

test "should_inject_network_error function" {
    // Test with no active configuration
    try std.testing.expect(!should_inject_network_error());

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = failure_injection.FailureInjectionConfig.init(allocator);
    defer config.deinit();

    config.network_error_probability = 1.0; // 100% probability

    var prng = std.Random.DefaultPrng.init(12345);

    current_failure_config = &config;
    current_prng = &prng;
    defer {
        current_failure_config = null;
        current_prng = null;
    }

    // Should inject at 100% probability
    try std.testing.expect(should_inject_network_error());
}

test "system condition management" {
    // Test initial state
    try std.testing.expect(current_system_condition() == null);

    // Test setting condition
    set_system_condition(.during_flush);
    try std.testing.expect(current_system_condition() == .during_flush);

    // Test changing condition
    set_system_condition(.during_recovery);
    try std.testing.expect(current_system_condition() == .during_recovery);

    // Test clearing condition
    set_system_condition(null);
    try std.testing.expect(current_system_condition() == null);
}

test "OpWeight type functionality" {
    const TestOp = enum { op1, op2, op3 };

    const weight1 = OpWeight(TestOp){ .operation = .op1, .weight = 0.5 };
    const weight2 = OpWeight(TestOp){ .operation = .op2, .weight = 0.3 };
    const weight3 = OpWeight(TestOp){ .operation = .op3, .weight = 0.2 };

    try std.testing.expect(weight1.operation == .op1);
    try std.testing.expect(weight1.weight == 0.5);
    try std.testing.expect(weight2.weight == 0.3);
    try std.testing.expect(weight3.weight == 0.2);
}

test "CustomFailure type functionality" {
    const failure1 = CustomFailure{ .name = "disk_full", .probability = 0.1 };
    const failure2 = CustomFailure{ .name = "network_timeout", .probability = 0.05 };

    try std.testing.expect(std.mem.eql(u8, failure1.name, "disk_full"));
    try std.testing.expect(failure1.probability == 0.1);
    try std.testing.expect(std.mem.eql(u8, failure2.name, "network_timeout"));
    try std.testing.expect(failure2.probability == 0.05);
}
