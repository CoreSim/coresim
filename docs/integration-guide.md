# CoreSim Integration Guide

This guide shows you how to integrate CoreSim into your Zig project using the modern TestBuilder API.

## Adding CoreSim as a Dependency

### Git Submodule
```bash
git submodule add https://github.com/yourusername/coresim.git deps/coresim

# In build.zig
const coresim_dep = b.dependency("coresim", .{ .target = target, .optimize = optimize });
test_module.addImport("coresim", coresim_dep.module("coresim"));
```

### Local Path
```zig
// build.zig.zon
.dependencies = .{ .coresim = .{ .path = "../coresim" } },

// build.zig  
const coresim_dep = b.dependency("coresim", .{});
exe.root_module.addImport("coresim", coresim_dep.module("coresim"));
```

## Quick Start - 3 Simple Steps

### 1. Define Your System
```zig
const MyCache = struct {
    allocator: std.mem.Allocator,
    data: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    
    pub const Operation = enum { put, get, delete };
    
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
    
    // Optional: Auto-discovered invariants
    pub fn checkConsistency(self: *@This()) bool {
        var iterator = self.data.iterator();
        while (iterator.next()) |entry| {
            if (entry.key_ptr.len == 0) return false;
        }
        return true;
    }
};
```

### 2. Import CoreSim
```zig
const coresim = @import("coresim");
```

### 3. Test Your System
```zig
test "My Cache Property Test" {
    try coresim.TestBuilder(MyCache){}
        .operations(&[_]MyCache.Operation{ .put, .get, .delete })
        .iterations(100)
        .run(std.testing.allocator);
}
```

**That's it!** CoreSim automatically generates operation sequences, injects failures, validates invariants, and provides detailed feedback.

## System Requirements

Your system needs exactly 4 things:

1. **Operation Enum**: `pub const Operation = enum { create, read, update, delete };`
2. **Lifecycle Methods**: `init(allocator)` and `deinit(self)`
3. **Operation Methods**: Method names must match enum values
4. **Optional Invariants**: `checkConsistency`, `checkMemory`, `validate` (auto-discovered)

## Testing Configurations

### Development (Fast Feedback)
```zig
try coresim.TestBuilder(MySystem){}
    .operations(&ops)
    .iterations(25)
    .sequence_length(10, 50)
    .run(allocator);
```

### CI/CD (Standard Testing)
```zig
try coresim.TestBuilder(MySystem){}
    .operations(&ops)
    .iterations(100)
    .allocator_failures(0.001)
    .filesystem_errors(0.005)
    .run(allocator);
```

### Stress Testing
```zig
try coresim.TestBuilder(MySystem){}
    .operations(&ops)
    .iterations(500)
    .sequence_length(100, 500)
    .allocator_failures(0.02)
    .run(allocator);
```

### Debugging (Reproducible)
```zig
try coresim.TestBuilder(MySystem){}
    .operations(&ops)
    .iterations(5)
    .seed(12345)
    .run(allocator);
```

## Failure Injection

### Basic Failures
```zig
try coresim.TestBuilder(MySystem){}
    .operations(&ops)
    .allocator_failures(0.01)    // 1% allocation failures
    .filesystem_errors(0.005)    // 0.5% filesystem errors
    .network_errors(0.02)        // 2% network failures
    .run(allocator);
```

### Custom Failures
```zig
const custom_failures = [_]coresim.CustomFailure{
    .{ .name = "disk_full", .probability = 0.02 },
    .{ .name = "timeout", .probability = 0.01 },
    .{ .name = "cache_miss", .probability = 0.1 },
};

try coresim.TestBuilder(MySystem){}
    .operations(&ops)
    .custom_failures(&custom_failures)
    .run(allocator);
```

Use in your system methods:
```zig
pub fn put(self: *MySystem, key: []const u8, value: []const u8) !void {
    if (coresim.should_inject_custom_failure("disk_full")) {
        return error.DiskFull;
    }
    // Normal operation
    try self.data.put(key, value);
}
```

### Conditional Multipliers
```zig
const multipliers = [_]coresim.ConditionalMultiplier{
    .{ .condition = .during_recovery, .multiplier = 10.0 },
    .{ .condition = .under_memory_pressure, .multiplier = 5.0 },
};

try coresim.TestBuilder(MySystem){}
    .operations(&ops)
    .conditional_multipliers(&multipliers)
    .run(allocator);
```

Set conditions in your system:
```zig
pub fn recover(self: *MySystem) !void {
    coresim.set_system_condition(.during_recovery);
    defer coresim.set_system_condition(null);
    try self.performRecovery();
}
```

## Custom Workloads

### Operation Weights
```zig
const weights = [_]coresim.OpWeight(MySystem.Operation){
    .{ .operation = .read, .weight = 0.7 },   // 70% reads
    .{ .operation = .write, .weight = 0.2 },  // 20% writes  
    .{ .operation = .delete, .weight = 0.1 }, // 10% deletes
};

try coresim.TestBuilder(MySystem){}
    .operations(&ops)
    .operation_weights(&weights)
    .run(allocator);
```

### Key/Value Generation
```zig
try coresim.TestBuilder(MySystem){}
    .operations(&ops)
    .random_keys(8, 64)              // Variable key lengths
    .variable_size_values(100, 8192) // Realistic record sizes
    .collision_prone_keys(0.3)       // 30% collision rate
    .sequential_keys("user_")        // Sequential: user_00000001, etc.
    .run(allocator);
```

## Advanced Features

### Detailed Statistics
```zig
const stats = try coresim.TestBuilder(MySystem){}
    .operations(&ops)
    .detailed_stats(true)
    .run_with_stats(allocator);

defer stats.deinit();
std.debug.print("Test completed: {}\n", .{stats});
```

### Multiple Test Phases
```zig
fn run_comprehensive_tests(allocator: std.mem.Allocator) !void {
    // Phase 1: Basic functionality
    try coresim.TestBuilder(MySystem){}
        .operations(&basic_ops)
        .iterations(100)
        .named("basic_functionality")
        .run(allocator);
    
    // Phase 2: Stress testing
    try coresim.TestBuilder(MySystem){}
        .operations(&all_ops)
        .iterations(500)
        .allocator_failures(0.02)
        .named("stress_test")
        .run(allocator);
}
```

## Complete Example: Database with Custom Failures

```zig
const Database = struct {
    allocator: std.mem.Allocator,
    data: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    is_corrupted: bool = false,
    
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
            return error.DiskFull;
        }
        if (coresim.should_inject_custom_failure("index_corruption")) {
            self.is_corrupted = true;
            return error.IndexCorrupted;
        }
        if (self.is_corrupted) return error.DatabaseCorrupted;
        
        if (self.data.fetchRemove(key)) |existing| {
            self.allocator.free(existing.key);
            self.allocator.free(existing.value);
        }
        try self.data.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, value));
    }
    
    pub fn select(self: *@This(), key: []const u8) ?[]const u8 {
        if (self.is_corrupted) return null;
        return self.data.get(key);
    }
    
    pub fn update(self: *@This(), key: []const u8, value: []const u8) !void {
        try self.insert(key, value);
    }
    
    pub fn delete(self: *@This(), key: []const u8) bool {
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
        .{ .name = "backup_failure", .probability = 0.02 },
    };
    
    try coresim.TestBuilder(Database){}
        .operations(&[_]Database.Operation{ .insert, .select, .update, .delete, .backup })
        .custom_failures(&db_failures)
        .iterations(200)
        .run(std.testing.allocator);
}
```

## Best Practices

1. **Start Simple**: Begin with basic operations, add complexity gradually
2. **Meaningful Invariants**: Define invariants that capture critical properties
3. **Realistic Failure Rates**: Use probabilities based on real-world observations
4. **Deterministic Seeds**: Use `.seed()` for reproducible test runs
5. **Test Different Scenarios**: Use multiple configurations for comprehensive coverage

## Common Issues

### Memory Leaks
```zig
// ❌ Wrong: Memory leak
pub fn put(self: *MySystem, key: []const u8, value: []const u8) !void {
    try self.data.put(key, value); // key/value not owned!
}

// ✅ Correct: Own the memory
pub fn put(self: *MySystem, key: []const u8, value: []const u8) !void {
    try self.data.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, value));
}
```

### Flaky Invariants  
```zig
// ❌ Wrong: Non-deterministic
pub fn checkConsistency(self: *MySystem) bool {
    return std.time.milliTimestamp() % 2 == 0; // Flaky!
}

// ✅ Correct: Deterministic
pub fn checkConsistency(self: *MySystem) bool {
    return self.data.count() < self.max_capacity;
}
```

## Why Choose CoreSim?

- **3-Line Setup**: Comprehensive testing with minimal code
- **Auto-Discovery**: Automatically finds methods and invariants
- **Deterministic**: Reproducible failures with seed control
- **Comprehensive**: Tests functionality, error handling, and edge cases
- **Universal**: Works with any system type
- **Production-Ready**: Used for testing real systems with complex state

The modern CoreSim TestBuilder API makes property-based testing accessible to any Zig project with minimal setup and maximum power.