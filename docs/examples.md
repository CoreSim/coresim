# CoreSim Examples

Practical examples using the modern TestBuilder API.

## Basic Key-Value Store

```zig
const std = @import("std");
const coresim = @import("coresim");

const KVStore = struct {
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
    
    pub fn clear(self: *@This()) void {
        var iterator = self.data.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.data.clearAndFree();
    }
    
    pub fn checkConsistency(self: *@This()) bool {
        var iterator = self.data.iterator();
        while (iterator.next()) |entry| {
            if (entry.key_ptr.len == 0) return false;
        }
        return true;
    }
};

test "KV Store Example" {
    const weights = [_]coresim.OpWeight(KVStore.Operation){
        .{ .operation = .put, .weight = 0.4 },
        .{ .operation = .get, .weight = 0.4 },
        .{ .operation = .delete, .weight = 0.15 },
        .{ .operation = .clear, .weight = 0.05 },
    };
    
    try coresim.TestBuilder(KVStore){}
        .operations(&[_]KVStore.Operation{ .put, .get, .delete, .clear })
        .operation_weights(&weights)
        .allocator_failures(0.01)
        .iterations(100)
        .run(std.testing.allocator);
}
```

## Database with Transactions

```zig
const Database = struct {
    allocator: std.mem.Allocator,
    data: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    transaction_data: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    in_transaction: bool = false,
    
    pub const Operation = enum { begin_tx, commit_tx, rollback_tx, put, get, delete };
    
    pub fn init(allocator: std.mem.Allocator) !@This() {
        return @This(){
            .allocator = allocator,
            .data = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .transaction_data = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }
    
    pub fn deinit(self: *@This()) void {
        self.freeHashMap(&self.data);
        self.freeHashMap(&self.transaction_data);
    }
    
    fn freeHashMap(self: *@This(), map: *std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage)) void {
        var iterator = map.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        map.deinit();
    }
    
    pub fn begin_tx(self: *@This()) !void {
        if (self.in_transaction) return error.TransactionAlreadyActive;
        self.in_transaction = true;
    }
    
    pub fn commit_tx(self: *@This()) !void {
        if (!self.in_transaction) return error.NoActiveTransaction;
        
        // Apply transaction changes
        var iterator = self.transaction_data.iterator();
        while (iterator.next()) |entry| {
            const key = try self.allocator.dupe(u8, entry.key_ptr.*);
            const value = try self.allocator.dupe(u8, entry.value_ptr.*);
            
            if (self.data.fetchRemove(key)) |existing| {
                self.allocator.free(existing.key);
                self.allocator.free(existing.value);
            }
            try self.data.put(key, value);
        }
        
        self.freeHashMap(&self.transaction_data);
        self.transaction_data = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        self.in_transaction = false;
    }
    
    pub fn rollback_tx(self: *@This()) !void {
        if (!self.in_transaction) return error.NoActiveTransaction;
        
        self.freeHashMap(&self.transaction_data);
        self.transaction_data = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        self.in_transaction = false;
    }
    
    pub fn put(self: *@This(), key: []const u8, value: []const u8) !void {
        const target = if (self.in_transaction) &self.transaction_data else &self.data;
        
        if (target.fetchRemove(key)) |existing| {
            self.allocator.free(existing.key);
            self.allocator.free(existing.value);
        }
        try target.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, value));
    }
    
    pub fn get(self: *@This(), key: []const u8) ?[]const u8 {
        if (self.in_transaction) {
            if (self.transaction_data.get(key)) |value| return value;
        }
        return self.data.get(key);
    }
    
    pub fn delete(self: *@This(), key: []const u8) bool {
        const target = if (self.in_transaction) &self.transaction_data else &self.data;
        
        if (target.fetchRemove(key)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value);
            return true;
        }
        return false;
    }
    
    pub fn checkConsistency(self: *@This()) bool {
        return self.data.count() < 10000;
    }
};

test "Database with Transactions" {
    const tx_weights = [_]coresim.OpWeight(Database.Operation){
        .{ .operation = .put, .weight = 0.3 },
        .{ .operation = .get, .weight = 0.3 },
        .{ .operation = .delete, .weight = 0.2 },
        .{ .operation = .begin_tx, .weight = 0.1 },
        .{ .operation = .commit_tx, .weight = 0.05 },
        .{ .operation = .rollback_tx, .weight = 0.05 },
    };
    
    try coresim.TestBuilder(Database){}
        .operations(&[_]Database.Operation{ .begin_tx, .commit_tx, .rollback_tx, .put, .get, .delete })
        .operation_weights(&tx_weights)
        .allocator_failures(0.005)
        .iterations(150)
        .run(std.testing.allocator);
}
```

## Network Service with Failure Injection

```zig
const NetworkService = struct {
    allocator: std.mem.Allocator,
    data: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    connected: bool = true,
    
    pub const Operation = enum { put, get, sync, backup };
    
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
        if (coresim.should_inject_network_error()) {
            self.connected = false;
            return error.NetworkTimeout;
        }
        
        if (!self.connected) return error.NotConnected;
        
        if (self.data.fetchRemove(key)) |existing| {
            self.allocator.free(existing.key);
            self.allocator.free(existing.value);
        }
        try self.data.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, value));
    }
    
    pub fn get(self: *@This(), key: []const u8) ?[]const u8 {
        if (coresim.should_inject_network_error()) {
            return null;
        }
        
        if (!self.connected) return null;
        return self.data.get(key);
    }
    
    pub fn sync(self: *@This()) !void {
        if (coresim.should_inject_network_error()) {
            return error.SyncFailed;
        }
        self.connected = true;
    }
    
    pub fn backup(self: *@This()) !void {
        if (coresim.should_inject_network_error()) {
            return error.BackupFailed;
        }
    }
    
    pub fn checkConsistency(self: *@This()) bool {
        return self.data.count() < 10000;
    }
};

test "Network Service with Failures" {
    try coresim.TestBuilder(NetworkService){}
        .operations(&[_]NetworkService.Operation{ .put, .get, .sync, .backup })
        .network_errors(0.05) // 5% network failure rate
        .iterations(100)
        .run(std.testing.allocator);
}
```

## Custom Failures Example

```zig
const DatabaseWithCustomFailures = struct {
    allocator: std.mem.Allocator,
    data: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    is_corrupted: bool = false,
    disk_full: bool = false,
    
    pub const Operation = enum { insert, select, update, delete, backup };
    
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
    
    pub fn insert(self: *@This(), key: []const u8, value: []const u8) !void {
        if (coresim.should_inject_custom_failure("disk_full")) {
            self.disk_full = true;
            return error.DiskFull;
        }
        
        if (coresim.should_inject_custom_failure("index_corruption")) {
            self.is_corrupted = true;
            return error.IndexCorrupted;
        }
        
        if (self.is_corrupted or self.disk_full) return error.DatabaseError;
        
        if (self.data.fetchRemove(key)) |existing| {
            self.allocator.free(existing.key);
            self.allocator.free(existing.value);
        }
        try self.data.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, value));
    }
    
    pub fn select(self: *@This(), key: []const u8) ?[]const u8 {
        if (coresim.should_inject_custom_failure("cache_miss")) {
            return null;
        }
        
        if (self.is_corrupted) return null;
        return self.data.get(key);
    }
    
    pub fn update(self: *@This(), key: []const u8, value: []const u8) !void {
        try self.insert(key, value);
    }
    
    pub fn delete(self: *@This(), key: []const u8) bool {
        if (coresim.should_inject_custom_failure("permission_denied")) {
            return false;
        }
        
        if (self.is_corrupted) return false;
        
        if (self.data.fetchRemove(key)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value);
            return true;
        }
        return false;
    }
    
    pub fn backup(self: *@This()) !void {
        if (coresim.should_inject_custom_failure("backup_failure")) {
            return error.BackupFailed;
        }
    }
    
    pub fn checkConsistency(self: *@This()) bool {
        return self.data.count() < 10000;
    }
};

test "Database with Custom Failures" {
    const db_failures = [_]coresim.CustomFailure{
        .{ .name = "disk_full", .probability = 0.01 },
        .{ .name = "index_corruption", .probability = 0.005 },
        .{ .name = "cache_miss", .probability = 0.1 },
        .{ .name = "permission_denied", .probability = 0.02 },
        .{ .name = "backup_failure", .probability = 0.02 },
    };
    
    try coresim.TestBuilder(DatabaseWithCustomFailures){}
        .operations(&[_]DatabaseWithCustomFailures.Operation{ .insert, .select, .update, .delete, .backup })
        .custom_failures(&db_failures)
        .iterations(200)
        .run(std.testing.allocator);
}
```

## Conditional Multipliers Example

```zig
const RecoverySystem = struct {
    allocator: std.mem.Allocator,
    data: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    
    pub const Operation = enum { put, get, recover, backup };
    
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
        if (coresim.should_inject_custom_failure("write_error")) {
            return error.WriteFailed;
        }
        
        if (self.data.fetchRemove(key)) |existing| {
            self.allocator.free(existing.key);
            self.allocator.free(existing.value);
        }
        try self.data.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, value));
    }
    
    pub fn get(self: *@This(), key: []const u8) ?[]const u8 {
        return self.data.get(key);
    }
    
    pub fn recover(self: *@This()) !void {
        coresim.set_system_condition(.during_recovery);
        defer coresim.set_system_condition(null);
        
        // During recovery, failures are 10x more likely
        if (coresim.should_inject_custom_failure("recovery_error")) {
            return error.RecoveryFailed;
        }
    }
    
    pub fn backup(self: *@This()) !void {
        if (coresim.should_inject_custom_failure("backup_error")) {
            return error.BackupFailed;
        }
    }
    
    pub fn checkConsistency(self: *@This()) bool {
        return self.data.count() < 10000;
    }
};

test "System with Conditional Multipliers" {
    const failures = [_]coresim.CustomFailure{
        .{ .name = "write_error", .probability = 0.01 },
        .{ .name = "recovery_error", .probability = 0.01 },
        .{ .name = "backup_error", .probability = 0.005 },
    };
    
    const multipliers = [_]coresim.ConditionalMultiplier{
        .{ .condition = .during_recovery, .multiplier = 10.0 }, // 10x failures during recovery
        .{ .condition = .under_memory_pressure, .multiplier = 5.0 },
    };
    
    try coresim.TestBuilder(RecoverySystem){}
        .operations(&[_]RecoverySystem.Operation{ .put, .get, .recover, .backup })
        .custom_failures(&failures)
        .conditional_multipliers(&multipliers)
        .iterations(100)
        .run(std.testing.allocator);
}
```

## Advanced Configuration Example

```zig
test "Advanced Configuration" {
    const weights = [_]coresim.OpWeight(KVStore.Operation){
        .{ .operation = .get, .weight = 0.7 },   // 70% reads
        .{ .operation = .put, .weight = 0.2 },   // 20% writes
        .{ .operation = .delete, .weight = 0.1 }, // 10% deletes
    };
    
    const stats = try coresim.TestBuilder(KVStore){}
        .operations(&[_]KVStore.Operation{ .put, .get, .delete })
        .operation_weights(&weights)
        .allocator_failures(0.01)
        .filesystem_errors(0.005)
        .random_keys(8, 64)
        .variable_size_values(100, 8192)
        .collision_prone_keys(0.3) // 30% collision rate for stress testing
        .detailed_stats(true)
        .named("advanced_kv_test")
        .iterations(500)
        .sequence_length(100, 300)
        .seed(12345) // Reproducible
        .run_with_stats(std.testing.allocator);
    
    defer stats.deinit();
    std.debug.print("Test statistics: {}\n", .{stats});
}
```

## Key Features Demonstrated

### 1. TestBuilder API
All examples use the modern, fluent TestBuilder API for simple configuration.

### 2. Failure Injection
- **Basic**: Allocator and filesystem failures  
- **Network**: Network error injection for distributed systems
- **Custom**: Domain-specific failures with `should_inject_custom_failure()`
- **Conditional**: State-aware failure multipliers

### 3. Operation Control
- **Weights**: Custom probability distributions for realistic workloads
- **Key/Value Generation**: Various strategies for different testing scenarios
- **Sequence Configuration**: Control test length and complexity

### 4. Auto-Discovery
Systems define operations as enums and methods with matching names. CoreSim automatically discovers and uses invariant methods like `checkConsistency`.

### 5. Comprehensive Testing
Each example demonstrates testing different aspects:
- **Memory Management**: Proper allocation/deallocation patterns
- **Error Handling**: Resilience under various failure conditions  
- **State Management**: Complex system states like transactions
- **Performance**: High-throughput scenarios with realistic workloads

These examples show how CoreSim makes property-based testing accessible while providing the power needed for complex, real-world systems.