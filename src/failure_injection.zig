// ABOUTME: Generic failure injection system for deterministic simulation testing
// ABOUTME: Provides configurable probability-based failure injection with conditional multipliers

const std = @import("std");

/// Duration in nanoseconds
pub const Duration = u64;

// System conditions that can affect failure rates
pub const SystemCondition = enum {
    during_recovery,
    under_memory_pressure,
    high_operation_rate,
    after_restart,
    during_flush,
    hash_table_resize,
    normal_operation,
};

pub const ConditionalMultiplier = struct {
    condition: SystemCondition,
    multiplier: f64,
    duration: Duration = std.math.maxInt(Duration), // forever by default

    pub fn isActive(self: ConditionalMultiplier, elapsed: Duration) bool {
        return elapsed < self.duration;
    }
};

pub const FailureInjectionConfig = struct {
    allocator_failure_probability: f64 = 0.0,
    filesystem_error_probability: f64 = 0.0,
    network_error_probability: f64 = 0.0,
    custom_failure_probabilities: std.StringHashMap(f64),
    conditional_multipliers: []const ConditionalMultiplier = &[_]ConditionalMultiplier{},

    pub fn init(allocator: std.mem.Allocator) FailureInjectionConfig {
        return FailureInjectionConfig{
            .custom_failure_probabilities = std.StringHashMap(f64).init(allocator),
        };
    }

    pub fn get_effective_probability(self: FailureInjectionConfig, base_probability: f64, current_condition: ?SystemCondition) f64 {
        var effective = base_probability;

        if (current_condition) |condition| {
            for (self.conditional_multipliers) |multiplier| {
                if (multiplier.condition == condition) {
                    effective *= multiplier.multiplier;
                    break;
                }
            }
        }

        return @min(effective, 1.0);
    }

    pub fn get_custom_probability(self: FailureInjectionConfig, failure_type: []const u8, current_condition: ?SystemCondition) f64 {
        const base_prob = self.custom_failure_probabilities.get(failure_type) orelse 0.0;
        return self.get_effective_probability(base_prob, current_condition);
    }

    pub fn set_custom_probability(self: *FailureInjectionConfig, allocator: std.mem.Allocator, failure_type: []const u8, probability: f64) !void {
        if (self.custom_failure_probabilities.capacity() == 0) {
            self.custom_failure_probabilities = std.StringHashMap(f64).init(allocator);
        }
        try self.custom_failure_probabilities.put(failure_type, probability);
    }

    pub fn deinit(self: *FailureInjectionConfig) void {
        self.custom_failure_probabilities.deinit();
    }
};

// Generic failure injector
pub const FailureInjector = struct {
    config: FailureInjectionConfig,
    prng: *std.Random.DefaultPrng,
    current_condition: ?SystemCondition = null,

    pub fn init(config: FailureInjectionConfig, prng: *std.Random.DefaultPrng) FailureInjector {
        return FailureInjector{
            .config = config,
            .prng = prng,
        };
    }

    pub fn set_condition(self: *FailureInjector, condition: ?SystemCondition) void {
        self.current_condition = condition;
    }

    pub fn should_inject_allocator_failure(self: *FailureInjector) bool {
        const effective_prob = self.config.get_effective_probability(
            self.config.allocator_failure_probability,
            self.current_condition,
        );
        return self.prng.random().float(f64) < effective_prob;
    }

    pub fn should_inject_filesystem_error(self: *FailureInjector) bool {
        const effective_prob = self.config.get_effective_probability(
            self.config.filesystem_error_probability,
            self.current_condition,
        );
        return self.prng.random().float(f64) < effective_prob;
    }

    pub fn should_inject_network_error(self: *FailureInjector) bool {
        const effective_prob = self.config.get_effective_probability(
            self.config.network_error_probability,
            self.current_condition,
        );
        return self.prng.random().float(f64) < effective_prob;
    }

    pub fn should_inject_custom_failure(self: *FailureInjector, failure_type: []const u8) bool {
        const effective_prob = self.config.get_custom_probability(failure_type, self.current_condition);
        return self.prng.random().float(f64) < effective_prob;
    }
};

// Failure tracking for statistics
pub const FailureTracker = struct {
    allocator_failures: u64 = 0,
    filesystem_errors: u64 = 0,
    network_errors: u64 = 0,
    custom_failures: std.StringHashMap(u64),
    total_operations: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) FailureTracker {
        return FailureTracker{
            .custom_failures = std.StringHashMap(u64).init(allocator),
        };
    }

    pub fn deinit(self: *FailureTracker) void {
        self.custom_failures.deinit();
    }

    pub fn record_allocator_failure(self: *FailureTracker) void {
        self.allocator_failures += 1;
    }

    pub fn record_filesystem_error(self: *FailureTracker) void {
        self.filesystem_errors += 1;
    }

    pub fn record_network_error(self: *FailureTracker) void {
        self.network_errors += 1;
    }

    pub fn record_custom_failure(self: *FailureTracker, failure_type: []const u8) !void {
        const current = self.custom_failures.get(failure_type) orelse 0;
        try self.custom_failures.put(failure_type, current + 1);
    }

    pub fn record_operation(self: *FailureTracker) void {
        self.total_operations += 1;
    }

    pub fn get_allocator_failure_rate(self: FailureTracker) f64 {
        if (self.total_operations == 0) return 0.0;
        return @as(f64, @floatFromInt(self.allocator_failures)) / @as(f64, @floatFromInt(self.total_operations));
    }

    pub fn get_filesystem_error_rate(self: FailureTracker) f64 {
        if (self.total_operations == 0) return 0.0;
        return @as(f64, @floatFromInt(self.filesystem_errors)) / @as(f64, @floatFromInt(self.total_operations));
    }

    pub fn get_network_error_rate(self: FailureTracker) f64 {
        if (self.total_operations == 0) return 0.0;
        return @as(f64, @floatFromInt(self.network_errors)) / @as(f64, @floatFromInt(self.total_operations));
    }

    pub fn get_custom_failure_rate(self: FailureTracker, failure_type: []const u8) f64 {
        if (self.total_operations == 0) return 0.0;
        const failures = self.custom_failures.get(failure_type) orelse 0;
        return @as(f64, @floatFromInt(failures)) / @as(f64, @floatFromInt(self.total_operations));
    }

    pub fn format(self: FailureTracker, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Failure Statistics:\n", .{});
        try writer.print("  Total operations: {}\n", .{self.total_operations});
        try writer.print("  Allocator failures: {} ({d:.2}%)\n", .{ self.allocator_failures, self.get_allocator_failure_rate() * 100.0 });
        try writer.print("  Filesystem errors: {} ({d:.2}%)\n", .{ self.filesystem_errors, self.get_filesystem_error_rate() * 100.0 });
        try writer.print("  Network errors: {} ({d:.2}%)\n", .{ self.network_errors, self.get_network_error_rate() * 100.0 });

        var iterator = self.custom_failures.iterator();
        while (iterator.next()) |entry| {
            const rate = self.get_custom_failure_rate(entry.key_ptr.*);
            try writer.print("  {} failures: {} ({d:.2}%)\n", .{ entry.key_ptr.*, entry.value_ptr.*, rate * 100.0 });
        }
    }
};

// Utility for building common failure injection configurations
pub const FailureConfigBuilder = struct {
    config: FailureInjectionConfig,
    allocator: std.mem.Allocator,
    multipliers: std.ArrayList(ConditionalMultiplier),

    pub fn init(allocator: std.mem.Allocator) FailureConfigBuilder {
        return FailureConfigBuilder{
            .config = FailureInjectionConfig{},
            .allocator = allocator,
            .multipliers = std.ArrayList(ConditionalMultiplier).init(allocator),
        };
    }

    pub fn deinit(self: *FailureConfigBuilder) void {
        self.config.deinit();
        self.multipliers.deinit();
    }

    pub fn allocator_failures(self: *FailureConfigBuilder, probability: f64) *FailureConfigBuilder {
        self.config.allocator_failure_probability = probability;
        return self;
    }

    pub fn filesystem_errors(self: *FailureConfigBuilder, probability: f64) *FailureConfigBuilder {
        self.config.filesystem_error_probability = probability;
        return self;
    }

    pub fn network_errors(self: *FailureConfigBuilder, probability: f64) *FailureConfigBuilder {
        self.config.network_error_probability = probability;
        return self;
    }

    pub fn custom_failure(self: *FailureConfigBuilder, failure_type: []const u8, probability: f64) !*FailureConfigBuilder {
        try self.config.set_custom_probability(self.allocator, failure_type, probability);
        return self;
    }

    pub fn conditional_multiplier(self: *FailureConfigBuilder, condition: SystemCondition, multiplier: f64) !*FailureConfigBuilder {
        try self.multipliers.append(ConditionalMultiplier{
            .condition = condition,
            .multiplier = multiplier,
        });
        return self;
    }

    pub fn build(self: *FailureConfigBuilder) !FailureInjectionConfig {
        self.config.conditional_multipliers = try self.multipliers.toOwnedSlice();
        return self.config;
    }
};

test "Basic failure injection" {
    var prng = std.Random.DefaultPrng.init(42);

    var config = FailureInjectionConfig.init(std.testing.allocator);
    defer config.deinit();
    config.allocator_failure_probability = 0.1;
    config.filesystem_error_probability = 0.05;

    var injector = FailureInjector.init(config, &prng);

    var allocator_failures: u32 = 0;
    var filesystem_errors: u32 = 0;
    const total_tests = 1000;

    for (0..total_tests) |_| {
        if (injector.should_inject_allocator_failure()) {
            allocator_failures += 1;
        }
        if (injector.should_inject_filesystem_error()) {
            filesystem_errors += 1;
        }
    }

    // Rates should be approximately the configured probabilities (within 20% tolerance)
    const allocator_rate = @as(f64, @floatFromInt(allocator_failures)) / total_tests;
    const filesystem_rate = @as(f64, @floatFromInt(filesystem_errors)) / total_tests;

    try std.testing.expect(@abs(allocator_rate - 0.1) < 0.02);
    try std.testing.expect(@abs(filesystem_rate - 0.05) < 0.02);
}

test "Conditional multipliers" {
    var prng = std.Random.DefaultPrng.init(42);

    const multipliers = [_]ConditionalMultiplier{
        .{ .condition = .during_recovery, .multiplier = 10.0 },
    };

    var config = FailureInjectionConfig.init(std.testing.allocator);
    defer config.deinit();
    config.allocator_failure_probability = 0.01;
    config.conditional_multipliers = &multipliers;

    var injector = FailureInjector.init(config, &prng);

    // Test normal conditions
    var normal_failures: u32 = 0;
    for (0..1000) |_| {
        if (injector.should_inject_allocator_failure()) {
            normal_failures += 1;
        }
    }

    // Test during recovery (should have ~10x more failures)
    injector.set_condition(.during_recovery);
    var recovery_failures: u32 = 0;
    for (0..1000) |_| {
        if (injector.should_inject_allocator_failure()) {
            recovery_failures += 1;
        }
    }

    // Recovery should have significantly more failures than normal
    try std.testing.expect(recovery_failures > normal_failures * 5);
}

test "Failure tracker" {
    var tracker = FailureTracker.init(std.testing.allocator);
    defer tracker.deinit();

    // Record some failures
    for (0..10) |_| {
        tracker.record_operation();
    }

    tracker.record_allocator_failure();
    tracker.record_allocator_failure();
    tracker.record_filesystem_error();

    try std.testing.expect(tracker.get_allocator_failure_rate() == 0.2); // 2/10
    try std.testing.expect(tracker.get_filesystem_error_rate() == 0.1); // 1/10
}
