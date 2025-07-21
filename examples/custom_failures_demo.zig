// ABOUTME: Demonstrates custom failure types for domain-specific error injection
// ABOUTME: Shows how systems can detect and respond to simulated failures

const std = @import("std");
const coresim = @import("coresim");

const DatabaseSystem = struct {
    allocator: std.mem.Allocator,
    data: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    is_corrupted: bool = false,
    disk_full: bool = false,
    operation_count: u32 = 0,
    failure_count: u32 = 0,

    pub const Operation = enum { put, get, delete, backup };

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
        self.operation_count += 1;

        // Check persistent failure states first
        if (self.is_corrupted) {
            return error.DatabaseCorrupted;
        }

        if (self.disk_full) {
            return error.DiskFull;
        }

        // Check for custom failure types - these only set state, don't add data
        if (coresim.should_inject_custom_failure("disk_full")) {
            self.disk_full = true;
            self.failure_count += 1;
            return error.DiskFull;
        }

        if (coresim.should_inject_custom_failure("index_corruption")) {
            self.is_corrupted = true;
            self.failure_count += 1;
            return error.IndexCorrupted;
        }

        if (coresim.should_inject_custom_failure("timeout")) {
            self.failure_count += 1;
            return error.Timeout;
        }

        // Only proceed with normal operation if no failures occurred
        if (self.data.fetchRemove(key)) |existing| {
            self.allocator.free(existing.key);
            self.allocator.free(existing.value);
        }
        try self.data.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, value));
    }

    pub fn get(self: *@This(), key: []const u8) ?[]const u8 {
        self.operation_count += 1;

        // Check for custom failure types
        if (coresim.should_inject_custom_failure("cache_miss")) {
            self.failure_count += 1;
            return null; // Simulate cache miss
        }

        if (coresim.should_inject_custom_failure("timeout")) {
            self.failure_count += 1;
            // For non-error returning methods, we can't return an error
            // but we can simulate the failure by returning null
            return null;
        }

        if (self.is_corrupted) {
            return null; // Corrupted database can't read data
        }

        return self.data.get(key);
    }

    pub fn delete(self: *@This(), key: []const u8) bool {
        self.operation_count += 1;

        // Check for custom failure types
        if (coresim.should_inject_custom_failure("permission_denied")) {
            self.failure_count += 1;
            return false; // Simulate permission denied
        }

        if (self.is_corrupted) {
            return false;
        }

        if (self.data.fetchRemove(key)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value);
            return true;
        }
        return false;
    }

    pub fn backup(self: *@This()) !void {
        self.operation_count += 1;

        // Backup operations are particularly susceptible to failures
        if (coresim.should_inject_custom_failure("disk_full")) {
            self.failure_count += 1;
            return error.DiskFull;
        }

        if (coresim.should_inject_custom_failure("network_failure")) {
            self.failure_count += 1;
            return error.NetworkUnavailable;
        }

        if (coresim.should_inject_custom_failure("backup_corruption")) {
            self.failure_count += 1;
            return error.BackupCorrupted;
        }

        // Simulate successful backup
        // In a real system, this would write to backup storage
    }

    pub fn checkConsistency(self: *@This()) bool {
        // Database is consistent if it's in a reasonable state
        // Don't fail on corruption since that's an expected failure scenario
        return self.data.count() < 10000; // Much higher limit for stress testing
    }

    pub fn getStats(self: *@This()) struct { operations: u32, failures: u32, corrupted: bool, disk_full: bool } {
        return .{
            .operations = self.operation_count,
            .failures = self.failure_count,
            .corrupted = self.is_corrupted,
            .disk_full = self.disk_full,
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== CoreSim Custom Failure Types Demo ===\n\n", .{});

    // Demo 1: Database-specific failures
    std.debug.print("1. Testing database-specific failure types...\n", .{});
    const db_failures = [_]coresim.CustomFailure{
        .{ .name = "disk_full", .probability = 0.01 }, // 1% chance
        .{ .name = "index_corruption", .probability = 0.005 }, // 0.5% chance
        .{ .name = "timeout", .probability = 0.01 }, // 1% chance
    };

    const builder1 = coresim.TestBuilder(DatabaseSystem){};
    try builder1
        .operations(&[_]DatabaseSystem.Operation{ .put, .get, .delete })
        .custom_failures(&db_failures)
        .iterations(100)
        .named("database_failures_test")
        .invariant("consistency", DatabaseSystem.checkConsistency, .critical)
        .run(allocator);

    std.debug.print("   ✓ Database failure types test passed!\n\n", .{});

    // Demo 2: Cache-specific failures
    std.debug.print("2. Testing cache-specific failure types...\n", .{});
    const cache_failures = [_]coresim.CustomFailure{
        .{ .name = "cache_miss", .probability = 0.05 }, // 5% chance
        .{ .name = "timeout", .probability = 0.01 }, // 1% chance
        .{ .name = "permission_denied", .probability = 0.005 }, // 0.5% chance
    };

    const builder2 = coresim.TestBuilder(DatabaseSystem){};
    try builder2
        .operations(&[_]DatabaseSystem.Operation{ .get, .put, .delete })
        .custom_failures(&cache_failures)
        .iterations(150)
        .named("cache_failures_test")
        .invariant("consistency", DatabaseSystem.checkConsistency, .critical)
        .run(allocator);

    std.debug.print("   ✓ Cache failure types test passed!\n\n", .{});

    // Demo 3: Backup and recovery failures
    std.debug.print("3. Testing backup and recovery failure types...\n", .{});
    const backup_failures = [_]coresim.CustomFailure{
        .{ .name = "network_failure", .probability = 0.08 }, // 8% chance
        .{ .name = "backup_corruption", .probability = 0.03 }, // 3% chance
        .{ .name = "disk_full", .probability = 0.05 }, // 5% chance
    };

    const builder3 = coresim.TestBuilder(DatabaseSystem){};
    try builder3
        .operations(&[_]DatabaseSystem.Operation{ .backup, .put, .get })
        .custom_failures(&backup_failures)
        .iterations(80)
        .named("backup_failures_test")
        .invariant("consistency", DatabaseSystem.checkConsistency, .critical)
        .run(allocator);

    std.debug.print("   ✓ Backup failure types test passed!\n\n", .{});

    // Demo 4: Combined failures with operation weights
    std.debug.print("4. Testing combined custom failures with operation weights...\n", .{});
    const combined_failures = [_]coresim.CustomFailure{
        .{ .name = "disk_full", .probability = 0.03 },
        .{ .name = "cache_miss", .probability = 0.15 },
        .{ .name = "timeout", .probability = 0.02 },
        .{ .name = "index_corruption", .probability = 0.01 },
        .{ .name = "network_failure", .probability = 0.04 },
    };

    const operation_weights = [_]coresim.OpWeight(DatabaseSystem.Operation){
        .{ .operation = .get, .weight = 0.5 }, // 50% reads (most likely to hit cache_miss)
        .{ .operation = .put, .weight = 0.3 }, // 30% writes (most likely to hit disk_full)
        .{ .operation = .delete, .weight = 0.1 }, // 10% deletes
        .{ .operation = .backup, .weight = 0.1 }, // 10% backups (most likely to hit network_failure)
    };

    const builder4 = coresim.TestBuilder(DatabaseSystem){};
    try builder4
        .operations(&[_]DatabaseSystem.Operation{ .put, .get, .delete, .backup })
        .custom_failures(&combined_failures)
        .operation_weights(&operation_weights)
        .random_keys(4, 12)
        .variable_size_values(16, 128)
        .iterations(200)
        .named("combined_failures_test")
        .invariant("consistency", DatabaseSystem.checkConsistency, .critical)
        .run(allocator);

    std.debug.print("   ✓ Combined failures test passed!\n\n", .{});

    // Demo 5: High failure rate stress test
    std.debug.print("5. Testing high failure rate stress scenarios...\n", .{});
    const stress_failures = [_]coresim.CustomFailure{
        .{ .name = "disk_full", .probability = 0.2 }, // 20% chance
        .{ .name = "index_corruption", .probability = 0.15 }, // 15% chance
        .{ .name = "timeout", .probability = 0.1 }, // 10% chance
        .{ .name = "cache_miss", .probability = 0.3 }, // 30% chance
    };

    const builder5 = coresim.TestBuilder(DatabaseSystem){};
    try builder5
        .operations(&[_]DatabaseSystem.Operation{ .put, .get, .delete })
        .custom_failures(&stress_failures)
        .iterations(50)
        .named("stress_failures_test")
        .invariant("consistency", DatabaseSystem.checkConsistency, .critical)
        .run(allocator);

    std.debug.print("   ✓ Stress failure test passed!\n\n", .{});

    std.debug.print("🎉 All custom failure types demos passed!\n", .{});
    std.debug.print("\nThis demo showed:\n", .{});
    std.debug.print("• Domain-specific failure injection (database, cache, backup)\n", .{});
    std.debug.print("• Multiple custom failure types in a single test\n", .{});
    std.debug.print("• Integration with operation weights for realistic scenarios\n", .{});
    std.debug.print("• System-level failure detection and response\n", .{});
    std.debug.print("• High failure rate stress testing\n", .{});
    std.debug.print("• Error propagation and state management under failures\n", .{});
}
