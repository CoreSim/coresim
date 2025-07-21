// ABOUTME: Property-based testing framework for deterministic simulation testing
// ABOUTME: Provides operation generation, failure injection, and automatic shrinking

const std = @import("std");
const failure_injection = @import("failure_injection.zig");
const filesystem = @import("filesystem.zig");

pub const PropertyTestingError = error{
    TestFailed,
    InvariantViolation,
    ShrinkingFailed,
    StatisticsError,
    GenerationError,
};

// Core types
pub const Range = struct {
    min: usize,
    max: usize,

    pub fn sample(self: Range, prng: *std.Random.DefaultPrng) usize {
        if (self.min == self.max) return self.min;
        return self.min + prng.random().uintLessThan(usize, self.max - self.min + 1);
    }

    pub fn validate(self: Range) bool {
        return self.min <= self.max;
    }
};

/// Duration in nanoseconds
pub const Duration = u64;

// Generic operation interface
pub fn Operation(comptime OperationType: type) type {
    return struct {
        operation_type: OperationType,
        key: ?[]u8 = null,
        value: ?[]u8 = null,
        context: ?*anyopaque = null, // For operation-specific data

        const Self = @This();

        pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
            if (self.key) |key| allocator.free(key);
            if (self.value) |value| allocator.free(value);
        }
    };
}

// Generic operation distribution
pub fn OperationDistribution(comptime OperationType: type) type {
    return struct {
        weights: std.EnumMap(OperationType, f64),

        const Self = @This();

        pub fn init() Self {
            return Self{
                .weights = std.EnumMap(OperationType, f64).init(.{}),
            };
        }

        pub fn set_weight(self: *Self, op_type: OperationType, weight: f64) void {
            self.weights.put(op_type, weight);
        }

        pub fn normalize(self: *Self) void {
            var total: f64 = 0;
            var iterator = self.weights.iterator();
            while (iterator.next()) |entry| {
                total += entry.value.*;
            }

            if (total > 0) {
                iterator = self.weights.iterator();
                while (iterator.next()) |entry| {
                    entry.value.* /= total;
                }
            }
        }

        pub fn sample(self: Self, prng: *std.Random.DefaultPrng) OperationType {
            const rand = prng.random().float(f64);
            var cumulative: f64 = 0;

            var weights_copy = self.weights;
            var iterator = weights_copy.iterator();
            while (iterator.next()) |entry| {
                cumulative += entry.value.*;
                if (rand < cumulative) return entry.key;
            }

            // Fallback to first operation type
            iterator = weights_copy.iterator();
            return iterator.next().?.key;
        }
    };
}

pub const KeyGenerationStrategy = union(enum) {
    uniform_random: struct { min_length: usize, max_length: usize },
    collision_prone: struct { hash_collision_rate: f64 },
    sequential: struct { prefix: []const u8 },

    pub fn generate_key(self: KeyGenerationStrategy, allocator: std.mem.Allocator, prng: *std.Random.DefaultPrng, existing_keys: [][]const u8) ![]u8 {
        switch (self) {
            .uniform_random => |config| {
                const length = config.min_length + prng.random().uintLessThan(usize, config.max_length - config.min_length + 1);
                const key = try allocator.alloc(u8, length);
                for (key) |*byte| {
                    byte.* = 'a' + prng.random().uintLessThan(u8, 26);
                }
                return key;
            },
            .collision_prone => |config| {
                // Generate keys likely to collide
                if (existing_keys.len > 0 and prng.random().float(f64) < config.hash_collision_rate) {
                    // Modify an existing key slightly to create collision potential
                    const base_key = existing_keys[prng.random().uintLessThan(usize, existing_keys.len)];
                    var key = try allocator.dupe(u8, base_key);
                    if (key.len > 0) {
                        key[0] = key[0] ^ 1; // Flip one bit
                    }
                    return key;
                }
                // Fall back to random
                const length = 8 + prng.random().uintLessThan(usize, 16);
                const key = try allocator.alloc(u8, length);
                for (key) |*byte| {
                    byte.* = 'a' + prng.random().uintLessThan(u8, 26);
                }
                return key;
            },
            .sequential => |config| {
                var buf: [16]u8 = undefined; // Buffer for the number
                const number = prng.random().int(u32);
                const suffix = std.fmt.bufPrint(&buf, "{d:0>8}", .{number}) catch std.fmt.bufPrint(&buf, "{d}", .{number}) catch unreachable;

                const total_len = config.prefix.len + suffix.len;
                var key = try allocator.alloc(u8, total_len);
                @memcpy(key[0..config.prefix.len], config.prefix);
                @memcpy(key[config.prefix.len..], suffix);
                return key;
            },
        }
    }
};

pub const ValueGenerationStrategy = union(enum) {
    fixed_size: usize,
    variable_size: Range,
    random_binary: void,

    pub fn generate_value(self: ValueGenerationStrategy, allocator: std.mem.Allocator, prng: *std.Random.DefaultPrng) ![]u8 {
        const size = switch (self) {
            .fixed_size => |s| s,
            .variable_size => |r| r.sample(prng),
            .random_binary => 64 + prng.random().uintLessThan(usize, 960), // 64-1024 bytes
        };

        const value = try allocator.alloc(u8, size);
        switch (self) {
            .random_binary => {
                prng.random().bytes(value);
            },
            else => {
                for (value) |*byte| {
                    byte.* = 'A' + prng.random().uintLessThan(u8, 26);
                }
            },
        }
        return value;
    }
};

// Generic property generators
pub fn PropertyGenerators(comptime OperationType: type) type {
    return struct {
        operation_distribution: OperationDistribution(OperationType),
        key_generators: KeyGenerationStrategy = .{ .uniform_random = .{ .min_length = 4, .max_length = 16 } },
        value_generators: ValueGenerationStrategy = .{ .variable_size = .{ .min = 8, .max = 256 } },
        sequence_length: Range = .{ .min = 100, .max = 1000 },
    };
}

// Test statistics
pub const FailureStats = struct {
    allocator_failures_injected: u64 = 0,
    filesystem_errors_injected: u64 = 0,
    network_errors_injected: u64 = 0,
    custom_failures_injected: std.StringHashMap(u64),
    allocator: std.mem.Allocator,
    total_operations: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) FailureStats {
        return FailureStats{
            .custom_failures_injected = std.StringHashMap(u64).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FailureStats) void {
        // Free all owned keys before deinitializing the map
        var iterator = self.custom_failures_injected.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.custom_failures_injected.deinit();
    }

    pub fn record_custom_failure(self: *FailureStats, failure_type: []const u8) !void {
        // Check if we already have this failure type
        if (self.custom_failures_injected.getPtr(failure_type)) |count_ptr| {
            count_ptr.* += 1;
        } else {
            // Create an owned copy of the failure type string
            const owned_key = try self.allocator.dupe(u8, failure_type);
            try self.custom_failures_injected.put(owned_key, 1);
        }
    }

    pub fn format(self: FailureStats, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Failure Stats:\n", .{});
        try writer.print("  Allocator failures: {}/{} ({d:.2}%)\n", .{ self.allocator_failures_injected, self.total_operations, if (self.total_operations > 0) @as(f64, @floatFromInt(self.allocator_failures_injected)) / @as(f64, @floatFromInt(self.total_operations)) * 100.0 else 0.0 });
        try writer.print("  Filesystem errors: {}/{} ({d:.2}%)\n", .{ self.filesystem_errors_injected, self.total_operations, if (self.total_operations > 0) @as(f64, @floatFromInt(self.filesystem_errors_injected)) / @as(f64, @floatFromInt(self.total_operations)) * 100.0 else 0.0 });
        try writer.print("  Network errors: {}/{} ({d:.2}%)\n", .{ self.network_errors_injected, self.total_operations, if (self.total_operations > 0) @as(f64, @floatFromInt(self.network_errors_injected)) / @as(f64, @floatFromInt(self.total_operations)) * 100.0 else 0.0 });

        var iterator = self.custom_failures_injected.iterator();
        while (iterator.next()) |entry| {
            const rate = if (self.total_operations > 0) @as(f64, @floatFromInt(entry.value_ptr.*)) / @as(f64, @floatFromInt(self.total_operations)) * 100.0 else 0.0;
            try writer.print("  {s} failures: {}/{} ({d:.2}%)\n", .{ entry.key_ptr.*, entry.value_ptr.*, self.total_operations, rate });
        }
    }
};

pub const OperationTiming = struct {
    total_calls: u64 = 0,
    total_time: Duration = 0,
    min_time: Duration = std.math.maxInt(Duration),
    max_time: Duration = 0,

    pub fn record_call(self: *OperationTiming, time: Duration) void {
        self.total_calls += 1;
        self.total_time += time;
        self.min_time = @min(self.min_time, time);
        self.max_time = @max(self.max_time, time);
    }

    pub fn average_time(self: OperationTiming) Duration {
        if (self.total_calls == 0) return 0;
        return self.total_time / self.total_calls;
    }
};

pub const OperationAnalytics = struct {
    actual_counts: std.StringHashMap(u64),
    intended_weights: std.StringHashMap(f64),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) OperationAnalytics {
        return OperationAnalytics{
            .actual_counts = std.StringHashMap(u64).init(allocator),
            .intended_weights = std.StringHashMap(f64).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *OperationAnalytics) void {
        // Free all owned keys in actual_counts
        var actual_iter = self.actual_counts.iterator();
        while (actual_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }

        // Free all owned keys in intended_weights
        var weight_iter = self.intended_weights.iterator();
        while (weight_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }

        self.actual_counts.deinit();
        self.intended_weights.deinit();
    }

    pub fn record_operation(self: *OperationAnalytics, operation_name: []const u8) !void {
        if (self.actual_counts.getPtr(operation_name)) |count_ptr| {
            count_ptr.* += 1;
        } else {
            const owned_key = try self.allocator.dupe(u8, operation_name);
            try self.actual_counts.put(owned_key, 1);
        }
    }

    pub fn set_intended_weight(self: *OperationAnalytics, operation_name: []const u8, weight: f64) !void {
        if (self.intended_weights.contains(operation_name)) {
            // Update existing entry (key already owned)
            try self.intended_weights.put(operation_name, weight);
        } else {
            // Create new entry with owned key
            const owned_key = try self.allocator.dupe(u8, operation_name);
            try self.intended_weights.put(owned_key, weight);
        }
    }

    pub fn get_actual_distribution(self: OperationAnalytics, allocator: std.mem.Allocator) !std.StringHashMap(f64) {
        var result = std.StringHashMap(f64).init(allocator);

        var total_ops: u64 = 0;
        var iter = self.actual_counts.iterator();
        while (iter.next()) |entry| {
            total_ops += entry.value_ptr.*;
        }

        if (total_ops > 0) {
            iter = self.actual_counts.iterator();
            while (iter.next()) |entry| {
                const percentage = @as(f64, @floatFromInt(entry.value_ptr.*)) / @as(f64, @floatFromInt(total_ops));
                try result.put(entry.key_ptr.*, percentage);
            }
        }

        return result;
    }
};

pub const TestStatistics = struct {
    total_operations_generated: u64 = 0,
    unique_sequences_tested: u32 = 0,
    failures_injected: FailureStats,
    invariant_violations: u64 = 0,
    shrinking_iterations: u32 = 0,
    test_execution_time: Duration = 0,

    // Detailed statistics (only collected when enabled)
    detailed_stats_enabled: bool = false,
    operation_timings: std.StringHashMap(OperationTiming),
    operation_distribution: OperationAnalytics,
    failure_rates_over_time: std.ArrayList(f64),
    memory_allocations: u64 = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TestStatistics {
        return TestStatistics{
            .failures_injected = FailureStats.init(allocator),
            .operation_timings = std.StringHashMap(OperationTiming).init(allocator),
            .operation_distribution = OperationAnalytics.init(allocator),
            .failure_rates_over_time = std.ArrayList(f64).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn initWithDetailedStats(allocator: std.mem.Allocator, enable_detailed: bool) TestStatistics {
        var stats = TestStatistics.init(allocator);
        stats.detailed_stats_enabled = enable_detailed;
        return stats;
    }

    pub fn deinit(self: *TestStatistics) void {
        self.failures_injected.deinit();

        // Free all keys in operation_timings
        var timing_iter = self.operation_timings.iterator();
        while (timing_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.operation_timings.deinit();

        self.operation_distribution.deinit();
        self.failure_rates_over_time.deinit();
    }

    pub fn clone(self: TestStatistics, allocator: std.mem.Allocator) !TestStatistics {
        var cloned = TestStatistics.initWithDetailedStats(allocator, self.detailed_stats_enabled);

        // Copy basic fields
        cloned.total_operations_generated = self.total_operations_generated;
        cloned.unique_sequences_tested = self.unique_sequences_tested;
        cloned.invariant_violations = self.invariant_violations;
        cloned.shrinking_iterations = self.shrinking_iterations;
        cloned.test_execution_time = self.test_execution_time;
        cloned.memory_allocations = self.memory_allocations;

        // Deep copy failure stats
        cloned.failures_injected.allocator_failures_injected = self.failures_injected.allocator_failures_injected;
        cloned.failures_injected.filesystem_errors_injected = self.failures_injected.filesystem_errors_injected;
        cloned.failures_injected.network_errors_injected = self.failures_injected.network_errors_injected;
        cloned.failures_injected.total_operations = self.failures_injected.total_operations;

        // Deep copy custom failures map
        var custom_iter = self.failures_injected.custom_failures_injected.iterator();
        while (custom_iter.next()) |entry| {
            const owned_key = try allocator.dupe(u8, entry.key_ptr.*);
            try cloned.failures_injected.custom_failures_injected.put(owned_key, entry.value_ptr.*);
        }

        // Deep copy operation timings if detailed stats enabled
        if (self.detailed_stats_enabled) {
            var timing_iter = self.operation_timings.iterator();
            while (timing_iter.next()) |entry| {
                const owned_key = try allocator.dupe(u8, entry.key_ptr.*);
                try cloned.operation_timings.put(owned_key, entry.value_ptr.*);
            }

            // Deep copy operation distribution
            var dist_iter = self.operation_distribution.actual_counts.iterator();
            while (dist_iter.next()) |entry| {
                const owned_key = try allocator.dupe(u8, entry.key_ptr.*);
                try cloned.operation_distribution.actual_counts.put(owned_key, entry.value_ptr.*);
            }

            var weight_iter = self.operation_distribution.intended_weights.iterator();
            while (weight_iter.next()) |entry| {
                const owned_key = try allocator.dupe(u8, entry.key_ptr.*);
                try cloned.operation_distribution.intended_weights.put(owned_key, entry.value_ptr.*);
            }

            // Copy failure rates array
            try cloned.failure_rates_over_time.appendSlice(self.failure_rates_over_time.items);
        }

        return cloned;
    }

    pub fn record_operation_timing(self: *TestStatistics, operation_name: []const u8, execution_time: Duration) !void {
        if (!self.detailed_stats_enabled) return;

        // Check if we already have an entry for this operation
        if (self.operation_timings.getPtr(operation_name)) |timing_ptr| {
            timing_ptr.record_call(execution_time);
        } else {
            // Create new entry with owned key
            const owned_key = try self.failures_injected.allocator.dupe(u8, operation_name);
            var timing = OperationTiming{};
            timing.record_call(execution_time);
            try self.operation_timings.put(owned_key, timing);
        }
    }

    pub fn record_operation_call(self: *TestStatistics, operation_name: []const u8) !void {
        if (!self.detailed_stats_enabled) return;
        try self.operation_distribution.record_operation(operation_name);
    }

    pub fn set_intended_operation_weight(self: *TestStatistics, operation_name: []const u8, weight: f64) !void {
        if (!self.detailed_stats_enabled) return;
        try self.operation_distribution.set_intended_weight(operation_name, weight);
    }

    pub fn record_failure_rate(self: *TestStatistics, rate: f64) !void {
        if (!self.detailed_stats_enabled) return;
        try self.failure_rates_over_time.append(rate);
    }

    pub fn format(self: TestStatistics, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("=== Property Test Statistics ===\n", .{});
        try writer.print("Total operations: {}\n", .{self.total_operations_generated});
        try writer.print("Sequences tested: {}\n", .{self.unique_sequences_tested});
        try writer.print("Invariant violations: {}\n", .{self.invariant_violations});
        try writer.print("Shrinking iterations: {}\n", .{self.shrinking_iterations});
        try writer.print("Execution time: {d:.2}ms\n", .{@as(f64, @floatFromInt(self.test_execution_time)) / 1_000_000.0});
        try writer.print("{}\n", .{self.failures_injected});

        if (self.detailed_stats_enabled) {
            try writer.print("\n=== Detailed Analytics ===\n", .{});

            // Operation timing statistics
            if (self.operation_timings.count() > 0) {
                try writer.print("Operation Timings:\n", .{});
                var timing_iter = self.operation_timings.iterator();
                while (timing_iter.next()) |entry| {
                    const timing = entry.value_ptr.*;
                    const avg_ns = timing.average_time();
                    const avg_us = @as(f64, @floatFromInt(avg_ns)) / 1000.0;
                    const min_us = @as(f64, @floatFromInt(timing.min_time)) / 1000.0;
                    const max_us = @as(f64, @floatFromInt(timing.max_time)) / 1000.0;
                    try writer.print("  {s}: {} calls, avg: {d:.1}μs, min: {d:.1}μs, max: {d:.1}μs\n", .{ entry.key_ptr.*, timing.total_calls, avg_us, min_us, max_us });
                }
            }

            // Operation distribution analysis
            if (self.operation_distribution.actual_counts.count() > 0) {
                try writer.print("Operation Distribution:\n", .{});
                var total_ops: u64 = 0;
                var dist_iter = self.operation_distribution.actual_counts.iterator();
                while (dist_iter.next()) |entry| {
                    total_ops += entry.value_ptr.*;
                }

                dist_iter = self.operation_distribution.actual_counts.iterator();
                while (dist_iter.next()) |entry| {
                    const actual_percent = @as(f64, @floatFromInt(entry.value_ptr.*)) / @as(f64, @floatFromInt(total_ops)) * 100.0;
                    const intended_weight = self.operation_distribution.intended_weights.get(entry.key_ptr.*);

                    if (intended_weight) |weight| {
                        const intended_percent = weight * 100.0;
                        const diff = actual_percent - intended_percent;
                        try writer.print("  {s}: {d:.1}% actual vs {d:.1}% intended (diff: {d:.1}%)\n", .{ entry.key_ptr.*, actual_percent, intended_percent, diff });
                    } else {
                        try writer.print("  {s}: {d:.1}% actual (no intended weight set)\n", .{ entry.key_ptr.*, actual_percent });
                    }
                }
            }

            // Failure rate trends
            if (self.failure_rates_over_time.items.len > 0) {
                var total_rate: f64 = 0;
                for (self.failure_rates_over_time.items) |rate| {
                    total_rate += rate;
                }
                const avg_rate = total_rate / @as(f64, @floatFromInt(self.failure_rates_over_time.items.len));
                try writer.print("Failure Rate Trend: {d:.2}% average over {} samples\n", .{ avg_rate * 100.0, self.failure_rates_over_time.items.len });
            }

            // Memory allocations
            if (self.memory_allocations > 0) {
                try writer.print("Memory Allocations: {} total\n", .{self.memory_allocations});
            }
        }
    }
};

// Invariant checking
pub const InvariantSeverity = enum {
    critical,
    important,
    advisory,
};

pub fn InvariantChecker(comptime SystemType: type) type {
    return struct {
        name: []const u8,
        check_fn: *const fn (system: *SystemType) bool,
        severity: InvariantSeverity,

        const Self = @This();

        pub fn check(self: Self, system: *SystemType) bool {
            return self.check_fn(system);
        }
    };
}

// Shrinking
pub const ShrinkStrategy = enum {
    remove_operations,
    simplify_values,
    reduce_key_diversity,
};

pub const ShrinkingConfig = struct {
    max_shrink_attempts: u32 = 100,
    shrink_strategies: []const ShrinkStrategy = &[_]ShrinkStrategy{ .remove_operations, .simplify_values },
    preserve_failure_conditions: bool = true,
};

// Generic property test
pub fn PropertyTest(comptime OperationType: type, comptime SystemType: type) type {
    const OperationT = Operation(OperationType);
    const GeneratorsT = PropertyGenerators(OperationType);
    const InvariantT = InvariantChecker(SystemType);

    return struct {
        name: []const u8,
        generators: GeneratorsT,
        failure_config: failure_injection.FailureInjectionConfig,
        invariants: []const InvariantT,
        shrinking: ShrinkingConfig,
        seed: u64,

        allocator: std.mem.Allocator,
        prng: std.Random.DefaultPrng,
        stats: TestStatistics,
        current_condition: ?failure_injection.SystemCondition = null,

        // System interface functions
        system_init_fn: *const fn (allocator: std.mem.Allocator) anyerror!SystemType,
        system_deinit_fn: *const fn (system: *SystemType) void,
        execute_operation_fn: *const fn (system: *SystemType, operation: OperationT) anyerror!void,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, config: Self) Self {
            return Self{
                .name = config.name,
                .generators = config.generators,
                .failure_config = config.failure_config,
                .invariants = config.invariants,
                .shrinking = config.shrinking,
                .seed = config.seed,
                .allocator = allocator,
                .prng = std.Random.DefaultPrng.init(config.seed),
                .stats = TestStatistics.init(allocator),
                .system_init_fn = config.system_init_fn,
                .system_deinit_fn = config.system_deinit_fn,
                .execute_operation_fn = config.execute_operation_fn,
            };
        }

        pub fn deinit(self: *Self) void {
            self.stats.deinit();
        }

        pub fn run(self: *Self, iterations: u32) !void {
            const start_time = std.time.nanoTimestamp();
            defer {
                const end_time = std.time.nanoTimestamp();
                self.stats.test_execution_time = @intCast(end_time - start_time);
            }

            std.debug.print("Running property test: {s} (seed: {}, iterations: {})\n", .{ self.name, self.seed, iterations });

            for (0..iterations) |i| {
                const sequence = try self.generate_operation_sequence();
                defer self.free_operation_sequence(sequence);

                const result = self.execute_sequence(sequence) catch |err| switch (err) {
                    PropertyTestingError.InvariantViolation => {
                        std.debug.print("Invariant violation detected in iteration {}, attempting to shrink...\n", .{i});
                        const shrunk = try self.shrink_sequence(sequence);
                        defer self.free_operation_sequence(shrunk);

                        std.debug.print("Shrunk from {} to {} operations\n", .{ sequence.len, shrunk.len });
                        self.print_minimal_reproduction(shrunk);
                        return PropertyTestingError.TestFailed;
                    },
                    else => return err,
                };

                if (!result) {
                    return PropertyTestingError.TestFailed;
                }

                self.stats.unique_sequences_tested += 1;

                if ((i + 1) % 100 == 0) {
                    std.debug.print("Completed {} iterations...\n", .{i + 1});
                }
            }

            std.debug.print("Property test completed successfully!\n", .{});
            std.debug.print("{}\n", .{self.stats});
        }

        fn generate_operation_sequence(self: *Self) ![]OperationT {
            const sequence_length = self.generators.sequence_length.sample(&self.prng);
            const sequence = try self.allocator.alloc(OperationT, sequence_length);
            var generated_keys = std.ArrayList([]const u8).init(self.allocator);
            defer {
                for (generated_keys.items) |key| {
                    self.allocator.free(key);
                }
                generated_keys.deinit();
            }

            for (sequence) |*op| {
                const op_type = self.generators.operation_distribution.sample(&self.prng);

                op.* = OperationT{
                    .operation_type = op_type,
                };

                // Generate key for operations that need it
                op.key = try self.generators.key_generators.generate_key(self.allocator, &self.prng, generated_keys.items);
                try generated_keys.append(try self.allocator.dupe(u8, op.key.?));

                // Generate value for operations that need it
                op.value = try self.generators.value_generators.generate_value(self.allocator, &self.prng);

                self.stats.total_operations_generated += 1;
            }

            return sequence;
        }

        fn execute_sequence(self: *Self, sequence: []OperationT) !bool {
            var system = try self.system_init_fn(self.allocator);
            defer self.system_deinit_fn(&system);

            for (sequence) |op| {
                self.stats.failures_injected.total_operations += 1;

                // Check for allocator failure injection
                if (self.should_inject_allocator_failure()) {
                    self.stats.failures_injected.allocator_failures_injected += 1;
                    continue;
                }

                // Execute operation with timing if detailed stats enabled
                const op_name = @tagName(op.operation_type);
                if (self.stats.detailed_stats_enabled) {
                    const start_time = std.time.nanoTimestamp();
                    self.execute_operation_fn(&system, op) catch {
                        // Operation failure might be expected due to failure injection
                    };
                    const end_time = std.time.nanoTimestamp();
                    const execution_time: Duration = @intCast(end_time - start_time);

                    // Record timing and operation call
                    self.stats.record_operation_timing(op_name, execution_time) catch |err| {
                        // Statistics recording failed - log warning but continue test execution
                        std.debug.print("Warning: Failed to record operation timing for '{s}': {}\n", .{ op_name, err });
                    };
                    self.stats.record_operation_call(op_name) catch |err| {
                        // Statistics recording failed - log warning but continue test execution
                        std.debug.print("Warning: Failed to record operation call for '{s}': {}\n", .{ op_name, err });
                    };
                } else {
                    self.execute_operation_fn(&system, op) catch {
                        // Operation failure is expected during testing due to failure injection
                        // These errors are intentionally not logged to avoid noise in test output
                    };
                }

                // Check invariants
                for (self.invariants) |invariant| {
                    if (!invariant.check(&system)) {
                        std.debug.print("Invariant violation: {s}\n", .{invariant.name});
                        self.stats.invariant_violations += 1;
                        if (invariant.severity == .critical) {
                            return PropertyTestingError.InvariantViolation;
                        }
                    }
                }
            }

            return true;
        }

        fn should_inject_allocator_failure(self: *Self) bool {
            const base_prob = self.failure_config.allocator_failure_probability;
            const effective_prob = self.failure_config.get_effective_probability(base_prob, self.current_condition);
            return self.prng.random().float(f64) < effective_prob;
        }

        fn shrink_sequence(self: *Self, original_sequence: []OperationT) ![]OperationT {
            var current_sequence = try self.clone_sequence(original_sequence);

            for (0..self.shrinking.max_shrink_attempts) |_| {
                var shrunk = false;

                if (current_sequence.len > 1) {
                    const remove_index = self.prng.random().uintLessThan(usize, current_sequence.len);
                    var new_sequence = try self.allocator.alloc(OperationT, current_sequence.len - 1);

                    @memcpy(new_sequence[0..remove_index], current_sequence[0..remove_index]);
                    if (remove_index < current_sequence.len - 1) {
                        @memcpy(new_sequence[remove_index..], current_sequence[remove_index + 1 ..]);
                    }

                    const still_fails = self.execute_sequence(new_sequence) catch true;
                    if (!still_fails) {
                        self.free_operation_sequence(current_sequence);
                        current_sequence = new_sequence;
                        shrunk = true;
                        self.stats.shrinking_iterations += 1;
                    } else {
                        self.free_operation_sequence(new_sequence);
                    }
                }

                if (!shrunk) {
                    break;
                }
            }

            return current_sequence;
        }

        fn clone_sequence(self: *Self, sequence: []OperationT) ![]OperationT {
            var cloned = try self.allocator.alloc(OperationT, sequence.len);
            for (sequence, 0..) |op, i| {
                cloned[i] = OperationT{
                    .operation_type = op.operation_type,
                    .key = if (op.key) |key| try self.allocator.dupe(u8, key) else null,
                    .value = if (op.value) |value| try self.allocator.dupe(u8, value) else null,
                    .context = op.context,
                };
            }
            return cloned;
        }

        fn free_operation_sequence(self: *Self, sequence: []OperationT) void {
            for (sequence) |op| {
                op.deinit(self.allocator);
            }
            self.allocator.free(sequence);
        }

        fn print_minimal_reproduction(self: *Self, sequence: []OperationT) void {
            std.debug.print("=== Minimal Reproduction Case ===\n", .{});
            std.debug.print("Seed: {}\n", .{self.seed});
            std.debug.print("Operations ({}):\n", .{sequence.len});
            for (sequence, 0..) |op, i| {
                if (op.key) |key| {
                    if (op.value) |value| {
                        std.debug.print("  {}: {} '{}' = '{}'\n", .{ i, op.operation_type, std.fmt.fmtSliceHexLower(key), std.fmt.fmtSliceHexLower(value) });
                    } else {
                        std.debug.print("  {}: {} '{}'\n", .{ i, op.operation_type, std.fmt.fmtSliceHexLower(key) });
                    }
                } else {
                    std.debug.print("  {}: {}\n", .{ i, op.operation_type });
                }
            }
            std.debug.print("=================================\n", .{});
        }
    };
}

test "Range sampling" {
    var prng = std.Random.DefaultPrng.init(42);
    const range = Range{ .min = 10, .max = 20 };

    for (0..100) |_| {
        const sample = range.sample(&prng);
        try std.testing.expect(sample >= 10 and sample <= 20);
    }
}

test "Key generation strategies" {
    var prng = std.Random.DefaultPrng.init(42);
    const allocator = std.testing.allocator;

    // Test uniform random
    const uniform = KeyGenerationStrategy{ .uniform_random = .{ .min_length = 5, .max_length = 10 } };
    const key1 = try uniform.generate_key(allocator, &prng, &[_][]const u8{});
    defer allocator.free(key1);
    try std.testing.expect(key1.len >= 5 and key1.len <= 10);

    // Test collision prone
    const collision = KeyGenerationStrategy{ .collision_prone = .{ .hash_collision_rate = 0.5 } };
    var keys = [_][]const u8{"existing"};
    const key2 = try collision.generate_key(allocator, &prng, keys[0..]);
    defer allocator.free(key2);
    try std.testing.expect(key2.len > 0);
}

test "Range validation" {
    const valid_range = Range{ .min = 5, .max = 10 };
    const invalid_range = Range{ .min = 10, .max = 5 };
    const equal_range = Range{ .min = 5, .max = 5 };

    try std.testing.expect(valid_range.validate());
    try std.testing.expect(!invalid_range.validate());
    try std.testing.expect(equal_range.validate());
}

test "Range sampling edge cases" {
    var prng = std.Random.DefaultPrng.init(12345);

    // Test single value range
    const single_value = Range{ .min = 42, .max = 42 };
    try std.testing.expect(single_value.sample(&prng) == 42);

    // Test small range
    const small_range = Range{ .min = 0, .max = 1 };
    for (0..20) |_| {
        const sample = small_range.sample(&prng);
        try std.testing.expect(sample >= 0 and sample <= 1);
    }
}

test "Operation creation and cleanup" {
    const TestOp = enum { put, get, delete };
    const allocator = std.testing.allocator;

    var operation = Operation(TestOp){
        .operation_type = .put,
        .key = try allocator.dupe(u8, "test_key"),
        .value = try allocator.dupe(u8, "test_value"),
    };

    try std.testing.expect(std.mem.eql(u8, operation.key.?, "test_key"));
    try std.testing.expect(std.mem.eql(u8, operation.value.?, "test_value"));

    // Cleanup should not leak memory
    operation.deinit(allocator);
}

test "OperationDistribution basic functionality" {
    const TestOp = enum { frequent, rare, medium };

    var dist = OperationDistribution(TestOp).init();
    dist.set_weight(.frequent, 0.7);
    dist.set_weight(.rare, 0.1);
    dist.set_weight(.medium, 0.2);

    var prng = std.Random.DefaultPrng.init(42);

    // Test sampling produces valid operations
    for (0..100) |_| {
        const op = dist.sample(&prng);
        const is_valid = (op == .frequent or op == .rare or op == .medium);
        try std.testing.expect(is_valid);
    }
}

test "OperationDistribution normalization" {
    const TestOp = enum { op1, op2 };

    var dist = OperationDistribution(TestOp).init();
    dist.set_weight(.op1, 200.0); // Large unnormalized weights
    dist.set_weight(.op2, 800.0);

    dist.normalize();

    // After normalization, weights should sum to 1.0
    const weight1 = dist.weights.get(.op1).?;
    const weight2 = dist.weights.get(.op2).?;
    const sum = weight1 + weight2;

    try std.testing.expect(@abs(sum - 1.0) < 0.0001); // Float precision tolerance
    try std.testing.expect(@abs(weight1 - 0.2) < 0.0001); // Should be 200/1000 = 0.2
    try std.testing.expect(@abs(weight2 - 0.8) < 0.0001); // Should be 800/1000 = 0.8
}

test "ValueGenerationStrategy fixed size" {
    var prng = std.Random.DefaultPrng.init(42);
    const allocator = std.testing.allocator;

    const strategy = ValueGenerationStrategy{ .fixed_size = 100 };
    const value = try strategy.generate_value(allocator, &prng);
    defer allocator.free(value);

    try std.testing.expect(value.len == 100);
}

test "ValueGenerationStrategy variable size" {
    var prng = std.Random.DefaultPrng.init(42);
    const allocator = std.testing.allocator;

    const strategy = ValueGenerationStrategy{ .variable_size = .{ .min = 50, .max = 150 } };
    const value = try strategy.generate_value(allocator, &prng);
    defer allocator.free(value);

    try std.testing.expect(value.len >= 50 and value.len <= 150);
}

test "InvariantSeverity enum completeness" {
    const severities = [_]InvariantSeverity{ .critical, .important, .advisory };

    for (severities) |severity| {
        // Test that all severities are valid and accessible
        const is_valid = (severity == .critical or severity == .important or severity == .advisory);
        try std.testing.expect(is_valid);
    }
}

test "TestStatistics initialization and basic operations" {
    var stats = TestStatistics.init(std.testing.allocator);
    defer stats.deinit();

    try std.testing.expect(stats.total_operations_generated == 0);
    try std.testing.expect(stats.invariant_violations == 0);
    try std.testing.expect(stats.test_execution_time == 0);

    stats.total_operations_generated = 100;
    stats.invariant_violations = 2;
    stats.test_execution_time = 1000000;

    try std.testing.expect(stats.total_operations_generated == 100);
    try std.testing.expect(stats.invariant_violations == 2);
    try std.testing.expect(stats.test_execution_time == 1000000);
}

test "TestStatistics with detailed stats" {
    var stats = TestStatistics.initWithDetailedStats(std.testing.allocator, true);
    defer stats.deinit();

    try std.testing.expect(stats.detailed_stats_enabled);
    // Detailed stats should initialize properly without crashing
}

test "FailureStats basic functionality" {
    var stats = FailureStats.init(std.testing.allocator);
    defer stats.deinit();

    try std.testing.expect(stats.allocator_failures_injected == 0);
    try std.testing.expect(stats.filesystem_errors_injected == 0);
    try std.testing.expect(stats.network_errors_injected == 0);

    stats.allocator_failures_injected = 10;
    stats.filesystem_errors_injected = 5;
    stats.network_errors_injected = 8;

    try std.testing.expect(stats.allocator_failures_injected == 10);
    try std.testing.expect(stats.filesystem_errors_injected == 5);
    try std.testing.expect(stats.network_errors_injected == 8);
}

test "FailureStats custom failure recording" {
    var stats = FailureStats.init(std.testing.allocator);
    defer stats.deinit();

    try stats.record_custom_failure("disk_full");
    try stats.record_custom_failure("disk_full");
    try stats.record_custom_failure("network_timeout");

    try std.testing.expect(stats.custom_failures_injected.get("disk_full").? == 2);
    try std.testing.expect(stats.custom_failures_injected.get("network_timeout").? == 1);
    try std.testing.expect(stats.custom_failures_injected.get("unknown") == null);
}

test "InvariantChecker basic functionality" {
    const TestSystem = struct {
        value: u32 = 0,

        pub fn checkPositive(self: *@This()) bool {
            return self.value > 0;
        }

        pub fn checkRange(self: *@This()) bool {
            return self.value < 100;
        }
    };

    var system = TestSystem{ .value = 50 };

    const checker1 = InvariantChecker(TestSystem){
        .name = "positive",
        .check_fn = TestSystem.checkPositive,
        .severity = .important,
    };

    const checker2 = InvariantChecker(TestSystem){
        .name = "range",
        .check_fn = TestSystem.checkRange,
        .severity = .critical,
    };

    try std.testing.expect(checker1.check(&system));
    try std.testing.expect(checker2.check(&system));

    system.value = 0;
    try std.testing.expect(!checker1.check(&system)); // Not positive anymore
    try std.testing.expect(checker2.check(&system)); // Still in range
}

test "PropertyTestingError enum completeness" {
    const errors = [_]PropertyTestingError{
        PropertyTestingError.TestFailed,
        PropertyTestingError.InvariantViolation,
        PropertyTestingError.ShrinkingFailed,
        PropertyTestingError.StatisticsError,
        PropertyTestingError.GenerationError,
    };

    for (errors) |_| {
        // Test that all error types are accessible
    }
}

test "Duration type alias" {
    const duration: Duration = 1000000; // 1 million nanoseconds
    try std.testing.expect(duration == 1000000);
    try std.testing.expect(@TypeOf(duration) == u64);
}
