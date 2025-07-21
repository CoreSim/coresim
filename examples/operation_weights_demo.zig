// ABOUTME: Demonstrates operation weights feature for custom probability distributions
// ABOUTME: Shows realistic workload patterns with weighted operation frequency

const std = @import("std");
const coresim = @import("coresim");

const TestStore = struct {
    allocator: std.mem.Allocator,
    data: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    read_count: u32 = 0,
    write_count: u32 = 0,
    delete_count: u32 = 0,

    pub const Operation = enum { put, get, delete, clear };

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
        if (self.data.fetchRemove(key)) |existing| {
            self.allocator.free(existing.key);
            self.allocator.free(existing.value);
        }
        try self.data.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, value));
        self.write_count += 1;
    }

    pub fn get(self: *@This(), key: []const u8) ?[]const u8 {
        self.read_count += 1;
        return self.data.get(key);
    }

    pub fn delete(self: *@This(), key: []const u8) bool {
        self.delete_count += 1;
        if (self.data.fetchRemove(key)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value);
            return true;
        }
        return false;
    }

    pub fn clear(self: *@This()) !void {
        var iterator = self.data.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.data.clearAndFree();
    }

    pub fn checkConsistency(self: *@This()) bool {
        return self.data.count() < 10000; // Reasonable limit
    }

    pub fn getOperationCounts(self: *@This()) struct { reads: u32, writes: u32, deletes: u32 } {
        return .{ .reads = self.read_count, .writes = self.write_count, .deletes = self.delete_count };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== CoreSim Operation Weights Demo ===\n\n", .{});

    // Demo 1: Equal weights (default behavior)
    std.debug.print("1. Testing with equal weights (default)...\n", .{});
    var test_system1 = try TestStore.init(allocator);
    defer test_system1.deinit();

    const builder1 = coresim.TestBuilder(TestStore){};
    try builder1
        .operations(&[_]TestStore.Operation{ .put, .get, .delete })
        .iterations(50)
        .named("equal_weights_test")
        .invariant("consistency", TestStore.checkConsistency, .critical)
        .run(allocator);

    const counts1 = test_system1.getOperationCounts();
    std.debug.print("   Operation counts - Reads: {}, Writes: {}, Deletes: {}\n", .{ counts1.reads, counts1.writes, counts1.deletes });
    std.debug.print("   ✓ Equal weights test passed!\n\n", .{});

    // Demo 2: Read-heavy workload (80% reads, 15% writes, 5% deletes)
    std.debug.print("2. Testing read-heavy workload (80% reads, 15% writes, 5% deletes)...\n", .{});
    const read_heavy_weights = [_]coresim.OpWeight(TestStore.Operation){
        .{ .operation = .get, .weight = 0.8 }, // 80% reads
        .{ .operation = .put, .weight = 0.15 }, // 15% writes
        .{ .operation = .delete, .weight = 0.05 }, // 5% deletes
    };

    const builder2 = coresim.TestBuilder(TestStore){};
    try builder2
        .operations(&[_]TestStore.Operation{ .put, .get, .delete })
        .operation_weights(&read_heavy_weights)
        .iterations(100)
        .named("read_heavy_test")
        .invariant("consistency", TestStore.checkConsistency, .critical)
        .run(allocator);

    std.debug.print("   ✓ Read-heavy workload test passed!\n\n", .{});

    // Demo 3: Write-heavy workload (20% reads, 70% writes, 10% deletes)
    std.debug.print("3. Testing write-heavy workload (20% reads, 70% writes, 10% deletes)...\n", .{});
    const write_heavy_weights = [_]coresim.OpWeight(TestStore.Operation){
        .{ .operation = .get, .weight = 0.2 }, // 20% reads
        .{ .operation = .put, .weight = 0.7 }, // 70% writes
        .{ .operation = .delete, .weight = 0.1 }, // 10% deletes
    };

    const builder3 = coresim.TestBuilder(TestStore){};
    try builder3
        .operations(&[_]TestStore.Operation{ .put, .get, .delete })
        .operation_weights(&write_heavy_weights)
        .iterations(100)
        .named("write_heavy_test")
        .invariant("consistency", TestStore.checkConsistency, .critical)
        .run(allocator);

    std.debug.print("   ✓ Write-heavy workload test passed!\n\n", .{});

    // Demo 4: Cleanup-focused workload (30% reads, 20% writes, 50% deletes)
    std.debug.print("4. Testing cleanup-focused workload (30% reads, 20% writes, 50% deletes)...\n", .{});
    const cleanup_weights = [_]coresim.OpWeight(TestStore.Operation){
        .{ .operation = .get, .weight = 0.3 }, // 30% reads
        .{ .operation = .put, .weight = 0.2 }, // 20% writes
        .{ .operation = .delete, .weight = 0.5 }, // 50% deletes
    };

    const builder4 = coresim.TestBuilder(TestStore){};
    try builder4
        .operations(&[_]TestStore.Operation{ .put, .get, .delete })
        .operation_weights(&cleanup_weights)
        .iterations(75)
        .named("cleanup_focused_test")
        .invariant("consistency", TestStore.checkConsistency, .critical)
        .run(allocator);

    std.debug.print("   ✓ Cleanup-focused workload test passed!\n\n", .{});

    // Demo 5: Combined with other features
    std.debug.print("5. Testing combined features (weights + custom keys + failure injection)...\n", .{});
    const balanced_weights = [_]coresim.OpWeight(TestStore.Operation){
        .{ .operation = .get, .weight = 0.5 }, // 50% reads
        .{ .operation = .put, .weight = 0.4 }, // 40% writes
        .{ .operation = .delete, .weight = 0.1 }, // 10% deletes
    };

    const builder5 = coresim.TestBuilder(TestStore){};
    try builder5
        .operations(&[_]TestStore.Operation{ .put, .get, .delete })
        .operation_weights(&balanced_weights)
        .random_keys(6, 20) // Custom key lengths
        .variable_size_values(32, 512) // Custom value sizes
        .allocator_failures(0.01) // 1% allocation failures
        .sequence_length(100, 300) // Custom sequence lengths
        .iterations(80)
        .named("combined_features_test")
        .invariant("consistency", TestStore.checkConsistency, .critical)
        .run(allocator);

    std.debug.print("   ✓ Combined features test passed!\n\n", .{});

    std.debug.print("🎉 All operation weights demos passed!\n", .{});
    std.debug.print("\nThis demo showed:\n", .{});
    std.debug.print("• Equal weight distribution (default behavior)\n", .{});
    std.debug.print("• Read-heavy workloads for caching scenarios\n", .{});
    std.debug.print("• Write-heavy workloads for data ingestion\n", .{});
    std.debug.print("• Cleanup-focused workloads for maintenance testing\n", .{});
    std.debug.print("• Combination with other advanced features\n", .{});
    std.debug.print("• Realistic workload pattern simulation\n", .{});
}
