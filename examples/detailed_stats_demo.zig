// ABOUTME: Demo showcasing detailed statistics collection and analytics
// ABOUTME: Shows timing analysis, operation distribution verification, and failure trends

const std = @import("std");
const coresim = @import("coresim");

// Example analytics-focused database system for detailed statistics demonstration
const AnalyticsDatabase = struct {
    allocator: std.mem.Allocator,
    data: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    operation_count: u32 = 0,
    total_data_size: usize = 0,

    pub const Operation = enum { put, get, delete, stats, clear };

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

    pub fn put(self: *@This(), key: []const u8, value: []const u8) !void {
        // Simulate variable workload - operations take different time based on data size
        if (value.len > 1000) {
            std.time.sleep(std.time.ns_per_us); // Simulate slower large writes
        }

        // Check for custom failures
        if (coresim.should_inject_custom_failure("replication_lag")) {
            std.time.sleep(std.time.ns_per_us * 100); // Simulate lag
            return error.ReplicationLag;
        }

        if (coresim.should_inject_custom_failure("disk_full")) {
            return error.DiskFull;
        }

        // Clean up existing entry if it exists
        if (self.data.fetchRemove(key)) |existing| {
            self.total_data_size -= existing.key.len + existing.value.len;
            self.allocator.free(existing.key);
            self.allocator.free(existing.value);
        }

        const owned_key = try self.allocator.dupe(u8, key);
        const owned_value = try self.allocator.dupe(u8, value);
        try self.data.put(owned_key, owned_value);

        self.operation_count += 1;
        self.total_data_size += key.len + value.len;
    }

    pub fn get(self: *@This(), key: []const u8) ?[]const u8 {
        // Check for cache miss simulation
        if (coresim.should_inject_custom_failure("cache_miss")) {
            std.time.sleep(std.time.ns_per_us * 10); // Simulate cache miss penalty
            return null;
        }

        self.operation_count += 1;
        return self.data.get(key);
    }

    pub fn delete(self: *@This(), key: []const u8) bool {
        if (self.data.fetchRemove(key)) |entry| {
            self.total_data_size -= entry.key.len + entry.value.len;
            self.allocator.free(entry.key);
            self.allocator.free(entry.value);
            self.operation_count += 1;
            return true;
        }
        self.operation_count += 1;
        return false;
    }

    pub fn stats(self: *@This()) void {
        // Simulate stats collection overhead
        std.time.sleep(std.time.ns_per_us * 5);
        self.operation_count += 1;
    }

    pub fn clear(self: *@This()) !void {
        // Check for operation under memory pressure
        coresim.set_system_condition(.under_memory_pressure);
        defer coresim.set_system_condition(null);

        if (coresim.should_inject_custom_failure("operation_timeout")) {
            return error.OperationTimeout;
        }

        var iterator = self.data.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.data.clearAndFree();
        self.total_data_size = 0;
        self.operation_count += 1;
    }

    pub fn checkConsistency(self: *@This()) bool {
        // Verify total data size calculation is correct
        var calculated_size: usize = 0;
        var iterator = self.data.iterator();
        while (iterator.next()) |entry| {
            calculated_size += entry.key_ptr.len + entry.value_ptr.len;
        }
        return calculated_size == self.total_data_size;
    }

    pub fn checkMemory(self: *@This()) bool {
        // Ensure we don't use excessive memory (10MB limit for demo)
        return self.total_data_size < 10 * 1024 * 1024;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== CoreSim Detailed Statistics Demo ===\n\n", .{});

    // Demo 1: Basic detailed statistics
    std.debug.print("Demo 1: Basic detailed statistics collection\n", .{});
    std.debug.print("-------------------------------------------\n", .{});
    const builder1 = coresim.TestBuilder(AnalyticsDatabase){};
    var basic_stats = try builder1
        .operations(&[_]AnalyticsDatabase.Operation{ .put, .get, .delete, .stats })
        .named("basic_analytics_test")
        .iterations(50)
        .sequence_length(20, 50)
        .detailed_stats(true)
        .invariant("consistency", AnalyticsDatabase.checkConsistency, .critical)
        .invariant("memory", AnalyticsDatabase.checkMemory, .critical)
        .run_with_stats(allocator);
    defer basic_stats.deinit();

    std.debug.print("{}\n\n", .{basic_stats});

    // Demo 2: Workload pattern analysis with operation weights
    std.debug.print("Demo 2: Workload pattern analysis (70% reads, 20% writes, 10% other)\n", .{});
    std.debug.print("----------------------------------------------------------------------\n", .{});
    const workload_weights = [_]coresim.OpWeight(AnalyticsDatabase.Operation){
        .{ .operation = .get, .weight = 0.7 }, // 70% reads
        .{ .operation = .put, .weight = 0.2 }, // 20% writes
        .{ .operation = .delete, .weight = 0.05 }, // 5% deletes
        .{ .operation = .stats, .weight = 0.05 }, // 5% stats
    };

    const builder2 = coresim.TestBuilder(AnalyticsDatabase){};
    var workload_stats = try builder2
        .operations(&[_]AnalyticsDatabase.Operation{ .put, .get, .delete, .stats })
        .named("workload_pattern_analysis")
        .iterations(100)
        .sequence_length(50, 100)
        .operation_weights(&workload_weights)
        .detailed_stats(true)
        .invariant("consistency", AnalyticsDatabase.checkConsistency, .critical)
        .invariant("memory", AnalyticsDatabase.checkMemory, .critical)
        .run_with_stats(allocator);
    defer workload_stats.deinit();

    std.debug.print("{}\n\n", .{workload_stats});

    // Demo 3: Performance analysis under different failure conditions
    std.debug.print("Demo 3: Performance impact of failures and conditional multipliers\n", .{});
    std.debug.print("-------------------------------------------------------------------\n", .{});
    const performance_failures = [_]coresim.CustomFailure{
        .{ .name = "replication_lag", .probability = 0.02 },
        .{ .name = "cache_miss", .probability = 0.05 },
        .{ .name = "disk_full", .probability = 0.01 },
        .{ .name = "operation_timeout", .probability = 0.005 },
    };

    const performance_multipliers = [_]coresim.ConditionalMultiplier{
        .{ .condition = .under_memory_pressure, .multiplier = 8.0 },
    };

    const builder3 = coresim.TestBuilder(AnalyticsDatabase){};
    var performance_stats = try builder3
        .operations(&[_]AnalyticsDatabase.Operation{ .put, .get, .delete, .clear })
        .named("performance_under_stress")
        .iterations(75)
        .sequence_length(30, 80)
        .custom_failures(&performance_failures)
        .conditional_multipliers(&performance_multipliers)
        .detailed_stats(true)
        .variable_size_values(100, 2000) // Variable payload sizes
        .invariant("consistency", AnalyticsDatabase.checkConsistency, .critical)
        .invariant("memory", AnalyticsDatabase.checkMemory, .critical)
        .run_with_stats(allocator);
    defer performance_stats.deinit();

    std.debug.print("{}\n\n", .{performance_stats});

    // Demo 4: Mixed workload with comprehensive failure injection
    std.debug.print("Demo 4: Comprehensive testing with all failure types and detailed analytics\n", .{});
    std.debug.print("--------------------------------------------------------------------------\n", .{});
    const comprehensive_failures = [_]coresim.CustomFailure{
        .{ .name = "network_partition", .probability = 0.01 },
        .{ .name = "data_corruption", .probability = 0.005 },
        .{ .name = "backup_failure", .probability = 0.008 },
    };

    const comprehensive_weights = [_]coresim.OpWeight(AnalyticsDatabase.Operation){
        .{ .operation = .get, .weight = 0.5 }, // 50% reads
        .{ .operation = .put, .weight = 0.3 }, // 30% writes
        .{ .operation = .delete, .weight = 0.1 }, // 10% deletes
        .{ .operation = .stats, .weight = 0.05 }, // 5% stats
        .{ .operation = .clear, .weight = 0.05 }, // 5% clears
    };

    const builder4 = coresim.TestBuilder(AnalyticsDatabase){};
    var comprehensive_stats = try builder4
        .operations(&[_]AnalyticsDatabase.Operation{ .put, .get, .delete, .stats, .clear })
        .named("comprehensive_analytics_test")
        .iterations(150)
        .sequence_length(40, 120)
        .operation_weights(&comprehensive_weights)
        .allocator_failures(0.008)
        .network_errors(0.012)
        .custom_failures(&comprehensive_failures)
        .detailed_stats(true)
        .random_keys(8, 32)
        .variable_size_values(64, 1024)
        .seed(98765)
        .invariant("consistency", AnalyticsDatabase.checkConsistency, .critical)
        .invariant("memory", AnalyticsDatabase.checkMemory, .critical)
        .run_with_stats(allocator);
    defer comprehensive_stats.deinit();

    std.debug.print("{}\n\n", .{comprehensive_stats});

    std.debug.print("=== Demo Complete ===\n", .{});
    std.debug.print("The detailed statistics show:\n", .{});
    std.debug.print("• Per-operation timing analysis (min/max/avg execution times)\n", .{});
    std.debug.print("• Operation distribution verification (actual vs intended percentages)\n", .{});
    std.debug.print("• Comprehensive failure injection statistics\n", .{});
    std.debug.print("• Memory allocation tracking\n", .{});
    std.debug.print("• Performance impact analysis under various conditions\n\n", .{});
    std.debug.print("This data helps identify:\n", .{});
    std.debug.print("• Performance bottlenecks in specific operations\n", .{});
    std.debug.print("• Whether workload patterns match expectations\n", .{});
    std.debug.print("• Impact of failures on system performance\n", .{});
    std.debug.print("• Resource usage patterns and optimization opportunities\n", .{});
}
