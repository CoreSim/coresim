// ABOUTME: Demonstrates network failure injection for distributed systems testing
// ABOUTME: Shows how to simulate network errors in HTTP clients, message queues, and database replicas

const std = @import("std");
const coresim = @import("coresim");

const DistributedSystem = struct {
    allocator: std.mem.Allocator,
    data: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    operation_count: u32 = 0,
    network_failure_count: u32 = 0,
    connected: bool = true,
    last_sync_timestamp: u64 = 0,

    pub const Operation = enum { put, get, delete, sync, backup, replicate };

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

        // Network failure can occur during distributed writes
        if (coresim.should_inject_network_error()) {
            self.network_failure_count += 1;
            self.connected = false;
            return error.NetworkTimeout;
        }

        // Custom failures for database-specific scenarios
        if (coresim.should_inject_custom_failure("consensus_failure")) {
            self.network_failure_count += 1;
            return error.ConsensusTimeout;
        }

        if (!self.connected) {
            return error.NotConnected;
        }

        // Normal operation
        if (self.data.fetchRemove(key)) |existing| {
            self.allocator.free(existing.key);
            self.allocator.free(existing.value);
        }
        try self.data.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, value));
    }

    pub fn get(self: *@This(), key: []const u8) ?[]const u8 {
        self.operation_count += 1;

        // Network failures for distributed reads
        if (coresim.should_inject_network_error()) {
            self.network_failure_count += 1;
            return null; // Connection lost during read
        }

        if (!self.connected) {
            return null; // Cannot read when disconnected
        }

        return self.data.get(key);
    }

    pub fn delete(self: *@This(), key: []const u8) bool {
        self.operation_count += 1;

        // Network failures during distributed deletes
        if (coresim.should_inject_network_error()) {
            self.network_failure_count += 1;
            self.connected = false;
            return false; // Delete failed due to network
        }

        if (!self.connected) {
            return false;
        }

        if (self.data.fetchRemove(key)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value);
            return true;
        }
        return false;
    }

    pub fn sync(self: *@This()) !void {
        self.operation_count += 1;

        // Sync operations are very susceptible to network failures
        if (coresim.should_inject_network_error()) {
            self.network_failure_count += 1;
            return error.SyncNetworkFailure;
        }

        if (coresim.should_inject_custom_failure("partition")) {
            self.network_failure_count += 1;
            self.connected = false;
            return error.NetworkPartition;
        }

        // Successful sync restores connection
        self.connected = true;
        self.last_sync_timestamp = @intCast(std.time.timestamp());
    }

    pub fn backup(self: *@This()) !void {
        self.operation_count += 1;

        // Backup operations require stable network connections
        if (coresim.should_inject_network_error()) {
            self.network_failure_count += 1;
            return error.BackupTransferFailed;
        }

        if (coresim.should_inject_custom_failure("backup_server_down")) {
            self.network_failure_count += 1;
            return error.BackupServerUnavailable;
        }

        // Simulate backup operation (normally would transfer data over network)
    }

    pub fn replicate(self: *@This()) !void {
        self.operation_count += 1;

        // Replication requires network communication with other nodes
        if (coresim.should_inject_network_error()) {
            self.network_failure_count += 1;
            return error.ReplicationFailed;
        }

        if (coresim.should_inject_custom_failure("quorum_unreachable")) {
            self.network_failure_count += 1;
            return error.InsufficientReplicas;
        }

        if (!self.connected) {
            return error.NotConnected;
        }

        // Simulate replication to other nodes
    }

    pub fn checkConsistency(self: *@This()) bool {
        // System is consistent if it has reasonable data and state
        return self.data.count() < 10000 and self.operation_count > 0;
    }

    pub fn getStats(self: *@This()) struct { operations: u32, network_failures: u32, connected: bool } {
        return .{
            .operations = self.operation_count,
            .network_failures = self.network_failure_count,
            .connected = self.connected,
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== CoreSim Network Failure Injection Demo ===\n\n", .{});

    // Demo 1: Basic network failures
    std.debug.print("1. Testing basic network error injection...\n", .{});
    const builder1 = coresim.TestBuilder(DistributedSystem){};
    try builder1
        .operations(&[_]DistributedSystem.Operation{ .put, .get, .delete })
        .network_errors(0.02) // 2% network failure rate
        .iterations(100)
        .named("basic_network_test")
        .run(allocator);

    std.debug.print("   ✓ Basic network failure test passed!\n\n", .{});

    // Demo 2: Distributed operations with higher network failure rates
    std.debug.print("2. Testing distributed operations with network failures...\n", .{});
    const builder2 = coresim.TestBuilder(DistributedSystem){};
    try builder2
        .operations(&[_]DistributedSystem.Operation{ .sync, .replicate, .backup })
        .network_errors(0.05) // 5% network failure rate for distributed ops
        .iterations(80)
        .named("distributed_ops_test")
        .run(allocator);

    std.debug.print("   ✓ Distributed operations network test passed!\n\n", .{});

    // Demo 3: Combined network and custom failures
    std.debug.print("3. Testing combined network and custom failures...\n", .{});
    const custom_failures = [_]coresim.CustomFailure{
        .{ .name = "consensus_failure", .probability = 0.01 }, // 1% consensus failures
        .{ .name = "partition", .probability = 0.02 }, // 2% network partitions
        .{ .name = "backup_server_down", .probability = 0.015 }, // 1.5% backup server failures
        .{ .name = "quorum_unreachable", .probability = 0.025 }, // 2.5% quorum failures
    };

    const builder3 = coresim.TestBuilder(DistributedSystem){};
    try builder3
        .operations(&[_]DistributedSystem.Operation{ .put, .get, .sync, .replicate, .backup })
        .network_errors(0.03) // 3% general network failures
        .custom_failures(&custom_failures)
        .iterations(150)
        .named("combined_failures_test")
        .run(allocator);

    std.debug.print("   ✓ Combined network and custom failures test passed!\n\n", .{});

    // Demo 4: Realistic distributed workload with operation weights
    std.debug.print("4. Testing realistic distributed workload...\n", .{});
    const distributed_weights = [_]coresim.OpWeight(DistributedSystem.Operation){
        .{ .operation = .get, .weight = 0.4 }, // 40% reads
        .{ .operation = .put, .weight = 0.3 }, // 30% writes
        .{ .operation = .sync, .weight = 0.15 }, // 15% sync operations
        .{ .operation = .replicate, .weight = 0.1 }, // 10% replication
        .{ .operation = .backup, .weight = 0.03 }, // 3% backup
        .{ .operation = .delete, .weight = 0.02 }, // 2% deletes
    };

    const workload_failures = [_]coresim.CustomFailure{
        .{ .name = "partition", .probability = 0.01 },
        .{ .name = "quorum_unreachable", .probability = 0.02 },
    };

    const builder4 = coresim.TestBuilder(DistributedSystem){};
    try builder4
        .operations(&[_]DistributedSystem.Operation{ .put, .get, .delete, .sync, .backup, .replicate })
        .network_errors(0.025) // 2.5% network failure rate
        .custom_failures(&workload_failures)
        .operation_weights(&distributed_weights)
        .random_keys(4, 16)
        .variable_size_values(32, 256)
        .iterations(200)
        .named("realistic_workload_test")
        .run(allocator);

    std.debug.print("   ✓ Realistic distributed workload test passed!\n\n", .{});

    // Demo 5: High network failure stress test
    std.debug.print("5. Testing high network failure stress scenarios...\n", .{});
    const stress_failures = [_]coresim.CustomFailure{
        .{ .name = "consensus_failure", .probability = 0.05 }, // 5% consensus failures
        .{ .name = "partition", .probability = 0.08 }, // 8% partitions
        .{ .name = "backup_server_down", .probability = 0.1 }, // 10% backup failures
    };

    const builder5 = coresim.TestBuilder(DistributedSystem){};
    try builder5
        .operations(&[_]DistributedSystem.Operation{ .put, .get, .sync, .replicate })
        .network_errors(0.1) // 10% network failure rate
        .custom_failures(&stress_failures)
        .iterations(60)
        .named("network_stress_test")
        .run(allocator);

    std.debug.print("   ✓ Network failure stress test passed!\n\n", .{});

    std.debug.print("🎉 All network failure injection demos passed!\n", .{});
    std.debug.print("\nThis demo showed:\n", .{});
    std.debug.print("• Built-in network error injection for any distributed system\n", .{});
    std.debug.print("• Integration with custom failures for domain-specific scenarios\n", .{});
    std.debug.print("• Realistic distributed workloads with operation weights\n", .{});
    std.debug.print("• Network partition and connectivity simulation\n", .{});
    std.debug.print("• High failure rate stress testing for resilience\n", .{});
    std.debug.print("• Automatic failure injection without complex setup\n", .{});
}
