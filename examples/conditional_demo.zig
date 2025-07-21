// ABOUTME: Demo showing conditional multipliers and system condition support
// ABOUTME: Demonstrates how failure rates change based on current system state

const std = @import("std");
const coresim = @import("coresim");

const Database = struct {
    pub const Operation = enum {
        put,
        get,
        flush,
        checkpoint,
    };
    data: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,
    is_checkpointing: bool = false,

    pub fn init(allocator: std.mem.Allocator) !Database {
        return Database{
            .data = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Database) void {
        var iterator = self.data.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.data.deinit();
    }

    pub fn put(self: *Database, key: []const u8, value: []const u8) !void {
        // Simulate network failures during checkpointing (when system is under stress)
        if (self.is_checkpointing and coresim.should_inject_network_error()) {
            return error.NetworkTimeout;
        }

        // Custom failures also affected by system conditions
        if (coresim.should_inject_custom_failure("replication_lag")) {
            return error.ReplicationLag;
        }

        const owned_key = try self.allocator.dupe(u8, key);
        const owned_value = try self.allocator.dupe(u8, value);
        try self.data.put(owned_key, owned_value);
    }

    pub fn get(self: *Database, key: []const u8, value: []const u8) !void {
        _ = value;
        if (coresim.should_inject_custom_failure("cache_miss")) {
            return error.CacheMiss;
        }
        _ = self.data.get(key) orelse return error.NotFound;
    }

    pub fn flush(self: *Database, key: []const u8, value: []const u8) !void {
        _ = self;
        _ = key;
        _ = value;

        // Set system condition during flush operations
        coresim.set_system_condition(.during_flush);
        defer coresim.set_system_condition(null);

        if (coresim.should_inject_custom_failure("disk_full")) {
            return error.DiskFull;
        }
    }

    pub fn checkpoint(self: *Database, key: []const u8, value: []const u8) !void {
        _ = key;
        _ = value;

        // Set high-stress system condition during checkpointing
        self.is_checkpointing = true;
        coresim.set_system_condition(.during_recovery);
        defer {
            coresim.set_system_condition(null);
            self.is_checkpointing = false;
        }

        if (coresim.should_inject_custom_failure("checkpoint_failed")) {
            return error.CheckpointFailed;
        }
    }

    pub fn checkConsistency(self: *Database) bool {
        return self.data.count() < 10000; // Arbitrary limit for demo
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== CoreSim Conditional Multipliers Demo ===\n\n", .{});

    // Test 1: Basic failure rates without conditions
    std.debug.print("1. Testing baseline failure rates (no conditional multipliers)...\n", .{});
    const builder1 = coresim.TestBuilder(Database){};
    try builder1
        .operations(&[_]Database.Operation{ .put, .get, .flush })
        .network_errors(0.01) // 1% base rate
        .custom_failures(&[_]coresim.CustomFailure{
            .{ .name = "replication_lag", .probability = 0.005 }, // 0.5% base rate
            .{ .name = "cache_miss", .probability = 0.02 }, // 2% base rate
            .{ .name = "disk_full", .probability = 0.001 }, // 0.1% base rate
        })
        .iterations(100)
        .seed(42)
        .named("baseline_test")
        .run(allocator);

    std.debug.print("   ✓ Baseline test completed!\n\n", .{});

    // Test 2: Same test but WITH conditional multipliers configured
    std.debug.print("2. Testing with conditional multipliers (10x failures during recovery, 5x during flush)...\n", .{});
    const builder2a = coresim.TestBuilder(Database){};
    try builder2a
        .operations(&[_]Database.Operation{ .put, .get, .flush })
        .network_errors(0.01) // 1% base rate
        .custom_failures(&[_]coresim.CustomFailure{
            .{ .name = "replication_lag", .probability = 0.005 }, // 0.5% base rate
            .{ .name = "cache_miss", .probability = 0.02 }, // 2% base rate
            .{ .name = "disk_full", .probability = 0.001 }, // 0.1% base rate
        })
        .conditional_multipliers(&[_]coresim.ConditionalMultiplier{
            .{ .condition = .during_recovery, .multiplier = 10.0 }, // 10x failures during recovery
            .{ .condition = .during_flush, .multiplier = 5.0 }, // 5x failures during flush
        })
        .iterations(100)
        .seed(42)
        .named("conditional_multipliers_test")
        .run(allocator);

    std.debug.print("   ✓ Conditional multipliers test completed!\n\n", .{});

    // Test 3: Same test but with checkpoint operations that trigger conditions AND conditional multipliers
    std.debug.print("3. Testing checkpoint operations (during_recovery condition) WITH multipliers...\n", .{});
    const builder3 = coresim.TestBuilder(Database){};
    try builder3
        .operations(&[_]Database.Operation{ .put, .get, .flush, .checkpoint })
        .operation_weights(&[_]coresim.OpWeight(Database.Operation){
            .{ .operation = .put, .weight = 0.4 },
            .{ .operation = .get, .weight = 0.4 },
            .{ .operation = .flush, .weight = 0.15 },
            .{ .operation = .checkpoint, .weight = 0.05 }, // 5% checkpoints trigger high-stress condition
        })
        .network_errors(0.01)
        .custom_failures(&[_]coresim.CustomFailure{
            .{ .name = "replication_lag", .probability = 0.005 },
            .{ .name = "cache_miss", .probability = 0.02 },
            .{ .name = "disk_full", .probability = 0.001 },
            .{ .name = "checkpoint_failed", .probability = 0.01 },
        })
        .conditional_multipliers(&[_]coresim.ConditionalMultiplier{
            .{ .condition = .during_recovery, .multiplier = 10.0 }, // 10x failures during checkpoint (recovery)
            .{ .condition = .during_flush, .multiplier = 5.0 }, // 5x failures during flush
        })
        .iterations(100)
        .seed(42)
        .named("checkpoint_test")
        .run(allocator);

    std.debug.print("   ✓ Checkpoint test completed!\n\n", .{});

    // Test 4: Single conditional multiplier using convenience method
    std.debug.print("4. Testing single conditional multiplier (convenience API)...\n", .{});
    const builder4 = coresim.TestBuilder(Database){};
    try builder4
        .operations(&[_]Database.Operation{ .put, .get, .flush })
        .operation_weights(&[_]coresim.OpWeight(Database.Operation){
            .{ .operation = .put, .weight = 0.4 },
            .{ .operation = .get, .weight = 0.4 },
            .{ .operation = .flush, .weight = 0.2 }, // More flush operations to trigger during_flush condition
        })
        .custom_failures(&[_]coresim.CustomFailure{
            .{ .name = "disk_full", .probability = 0.005 }, // Should be 5x higher during flush
            .{ .name = "cache_miss", .probability = 0.02 },
        })
        .conditional_multiplier(.during_flush, 5.0) // Convenience method for single multiplier
        .iterations(150)
        .seed(42)
        .named("convenience_api_test")
        .run(allocator);

    std.debug.print("   ✓ Convenience API test completed!\n\n", .{});

    std.debug.print("Note: The flush() and checkpoint() operations automatically set system conditions\n", .{});
    std.debug.print("(.during_flush and .during_recovery), which activate the conditional multipliers.\n", .{});

    std.debug.print("\n🎉 All conditional multipliers demos completed!\n\n", .{});
    std.debug.print("This demo showed:\n", .{});
    std.debug.print("• Configuring conditional multipliers via TestBuilder API\n", .{});
    std.debug.print("• Multiple multipliers vs single multiplier convenience method\n", .{});
    std.debug.print("• How system conditions trigger multiplier effects automatically\n", .{});
    std.debug.print("• Integration with existing custom failures and network errors\n", .{});
    std.debug.print("• Realistic failure rate scaling during system stress periods\n", .{});
}
