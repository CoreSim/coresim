// ABOUTME: Demonstrates advanced generator configuration with TestBuilder API
// ABOUTME: Shows different key/value generation strategies and their use cases

const std = @import("std");
const coresim = @import("coresim");

const TestStore = struct {
    allocator: std.mem.Allocator,
    data: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

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
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== CoreSim Generator Configuration Demo ===\n\n", .{});

    // Demo 1: Random keys with custom length range
    std.debug.print("1. Testing with custom random keys (8-32 chars)...\n", .{});
    const builder1 = coresim.TestBuilder(TestStore){};
    try builder1
        .operations(&[_]TestStore.Operation{ .put, .get, .delete })
        .random_keys(8, 32) // Keys: 8-32 characters
        .variable_size_values(16, 512) // Values: 16-512 bytes
        .iterations(50)
        .named("random_keys_test")
        .run(allocator);
    std.debug.print("   ✓ Random keys test passed!\n\n", .{});

    // Demo 2: Collision-prone keys for hash map stress testing
    std.debug.print("2. Testing with collision-prone keys (30% collision rate)...\n", .{});
    const builder2 = coresim.TestBuilder(TestStore){};
    try builder2
        .operations(&[_]TestStore.Operation{ .put, .get, .delete })
        .collision_prone_keys(0.3) // 30% collision-prone keys
        .random_binary_values() // Random binary data
        .iterations(75)
        .named("collision_stress_test")
        .run(allocator);
    std.debug.print("   ✓ Collision stress test passed!\n\n", .{});

    // Demo 3: Sequential keys for deterministic testing
    std.debug.print("3. Testing with sequential keys...\n", .{});
    const builder3 = coresim.TestBuilder(TestStore){};
    try builder3
        .operations(&[_]TestStore.Operation{ .put, .get, .clear })
        .sequential_keys("item_") // Keys: item_00000001, item_00000002...
        .fixed_size_values(128) // Values: exactly 128 bytes
        .sequence_length(25, 100) // Sequences: 25-100 operations
        .seed(12345) // Deterministic
        .iterations(30)
        .named("sequential_test")
        .run(allocator);
    std.debug.print("   ✓ Sequential keys test passed!\n\n", .{});

    // Demo 4: Full custom configuration
    std.debug.print("4. Testing with full custom configuration...\n", .{});
    const builder4 = coresim.TestBuilder(TestStore){};
    try builder4
        .operations(&[_]TestStore.Operation{ .put, .get, .delete, .clear })
        .key_strategy(.{ .uniform_random = .{ .min_length = 12, .max_length = 24 } })
        .value_strategy(.{ .variable_size = .{ .min = 64, .max = 1024 } })
        .sequence_length(150, 300)
        .allocator_failures(0.01) // 1% allocation failures
        .iterations(40)
        .named("full_custom_test")
        .run(allocator);
    std.debug.print("   ✓ Full custom configuration test passed!\n\n", .{});

    std.debug.print("🎉 All generator configuration demos passed!\n", .{});
    std.debug.print("\nThis demo showed:\n", .{});
    std.debug.print("• Custom key length ranges (8-32 chars)\n", .{});
    std.debug.print("• Collision-prone key generation for hash map stress testing\n", .{});
    std.debug.print("• Sequential key patterns for deterministic testing\n", .{});
    std.debug.print("• Fixed-size, variable-size, and binary value generation\n", .{});
    std.debug.print("• Custom sequence lengths and failure injection\n", .{});
    std.debug.print("• Full control over all generation parameters\n", .{});
}
