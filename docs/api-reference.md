# CoreSim API Reference

Complete reference for the CoreSim testing framework with the unified TestBuilder API.

## TestBuilder API

CoreSim provides a single, flexible TestBuilder API for configuring and running property-based tests. Users configure all testing parameters explicitly for their specific use case.

### Basic Usage

```zig
try coresim.TestBuilder(MySystem){}
    .operations(&[_]MySystem.Operation{ .put, .get, .delete })
    .iterations(100)
    .run(allocator);
```

### Full Configuration Example

```zig
const MySystem = struct {
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
        if (coresim.should_inject_custom_failure("disk_full")) {
            return error.DiskFull;
        }
        if (self.data.fetchRemove(key)) |existing| {
            self.allocator.free(existing.key);
            self.allocator.free(existing.value);
        }
        try self.data.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, value));
    }
    
    pub fn get(self: *@This(), key: []const u8) ?[]const u8 {
        if (coresim.should_inject_custom_failure("timeout")) {
            return null;
        }
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
    
    // Auto-discovered invariant
    pub fn checkConsistency(self: *@This()) bool {
        return self.data.count() < 10000; // Reasonable size limit
    }
};

const custom_failures = [_]coresim.CustomFailure{
    .{ .name = "timeout", .probability = 0.01 },
    .{ .name = "disk_full", .probability = 0.005 },
};

const conditional_multipliers = [_]coresim.ConditionalMultiplier{
    .{ .condition = .during_recovery, .multiplier = 10.0 },
    .{ .condition = .during_flush, .multiplier = 5.0 },
};

// Custom invariant function
fn checkDataIntegrity(system: *MySystem) bool {
    // Ensure no keys are longer than 64 characters
    var iterator = system.data.iterator();
    while (iterator.next()) |entry| {
        if (entry.key_ptr.len > 64) return false;
    }
    return true;
}

// The TestBuilder automatically discovers checkConsistency and allows custom invariants
const stats = try coresim.TestBuilder(MySystem){}
    .operations(&[_]MySystem.Operation{ .put, .get, .delete })
    .named("comprehensive_test")
    .iterations(1000)
    .sequence_length(100, 500)
    .allocator_failures(0.01)
    .filesystem_errors(0.005)
    .network_errors(0.02)
    .custom_failures(&custom_failures)
    .conditional_multipliers(&conditional_multipliers)
    .invariant("data_integrity", checkDataIntegrity, .important)  // Custom invariant
    .random_keys(8, 32)
    .variable_size_values(64, 2048)
    .seed(12345)
    .run_with_stats(allocator);

defer stats.deinit();
// CoreSim validated both auto-discovered (checkConsistency) and custom (data_integrity) invariants
std.debug.print("Test completed with invariant checks: {}\n", .{stats});
```

## Configuration Methods

### Core Configuration

| Method | Description | Example |
|--------|-------------|---------|
| `.operations(ops)` | Specify operations to test | `.operations(&[_]Op{ .put, .get })` |
| `.named(name)` | Set test name | `.named("cache_test")` |
| `.iterations(count)` | Set iteration count | `.iterations(500)` |
| `.sequence_length(min, max)` | Set operation sequence length range | `.sequence_length(100, 500)` |
| `.seed(value)` | Set random seed for deterministic testing | `.seed(12345)` |
| `.run(allocator)` | Execute the test | `.run(allocator)` |

### Failure Injection

| Method | Description | Example |
|--------|-------------|---------|
| `.allocator_failures(rate)` | Set allocation failure rate (0.0-1.0) | `.allocator_failures(0.01)` |
| `.filesystem_errors(rate)` | Set filesystem error rate (0.0-1.0) | `.filesystem_errors(0.005)` |
| `.network_errors(rate)` | Set network error rate (0.0-1.0) | `.network_errors(0.02)` |
| `.custom_failures(failures)` | Set domain-specific failure types and rates | `.custom_failures(&custom_failures)` |
| `.conditional_multipliers(multipliers)` | Set conditional failure rate multipliers | `.conditional_multipliers(&multipliers)` |
| `.conditional_multiplier(condition, multiplier)` | Set single conditional multiplier | `.conditional_multiplier(.during_recovery, 10.0)` |
| `.detailed_stats(enabled)` | Enable detailed statistics collection | `.detailed_stats(true)` |

### Key Generation

| Method | Description | Example |
|--------|-------------|---------|
| `.key_strategy(strategy)` | Set key generation strategy | `.key_strategy(.{ .uniform_random = .{ .min_length = 4, .max_length = 16 } })` |
| `.random_keys(min, max)` | Generate random keys with length range | `.random_keys(8, 32)` |
| `.collision_prone_keys(rate)` | Generate collision-prone keys | `.collision_prone_keys(0.3)` |
| `.sequential_keys(prefix)` | Generate sequential keys | `.sequential_keys("user_")` |

### Value Generation

| Method | Description | Example |
|--------|-------------|---------|
| `.value_strategy(strategy)` | Set value generation strategy | `.value_strategy(.{ .fixed_size = 256 })` |
| `.fixed_size_values(size)` | Generate fixed-size values | `.fixed_size_values(512)` |
| `.variable_size_values(min, max)` | Generate variable-size values | `.variable_size_values(16, 1024)` |
| `.random_binary_values()` | Generate random binary data | `.random_binary_values()` |

### Operation Weights

| Method | Description | Example |
|--------|-------------|---------|
| `.operation_weights(weights)` | Set custom operation probability distribution | `.operation_weights(&weights)` |

## Network Error Injection

CoreSim provides built-in network error injection for testing distributed systems and network-dependent operations.

### Basic Usage

```zig
try coresim.TestBuilder(DistributedSystem)
    .operations(&[_]DistributedSystem.Operation{ .put, .get, .sync })
    .network_errors(0.02) // 2% network failure rate
    .run(allocator);
```

### System Integration

Systems detect network failures using the global `should_inject_network_error()` function:

```zig
pub fn syncWithRemote(self: *DistributedSystem) !void {
    // Check for network failures
    if (coresim.should_inject_network_error()) {
        self.connected = false;
        return error.NetworkTimeout;
    }
    
    // Proceed with network operation
    try self.performRemoteSync();
}

pub fn sendRequest(self: *HttpClient, request: Request) !Response {
    if (coresim.should_inject_network_error()) {
        return error.ConnectionFailed;
    }
    
    return self.httpClient.send(request);
}
```

### Common Use Cases

- **HTTP Clients**: Connection timeouts, request failures
- **Database Replication**: Sync failures, partition scenarios
- **Message Queues**: Producer/consumer connectivity issues
- **Distributed Consensus**: Network partitions, quorum failures
- **Backup Operations**: Remote backup transfer failures
- **Service Discovery**: Registry connectivity problems

### Combined with Custom Failures

Network errors work seamlessly with custom failures for comprehensive testing:

```zig
const network_specific_failures = [_]coresim.CustomFailure{
    .{ .name = "consensus_failure", .probability = 0.01 },
    .{ .name = "partition", .probability = 0.015 },
    .{ .name = "quorum_unreachable", .probability = 0.02 },
};

try coresim.TestBuilder(DistributedSystem)
    .operations(&ops)
    .network_errors(0.03)                        // General network failures
    .custom_failures(&network_specific_failures) // Specific distributed system failures
    .run(allocator);
```

## Custom Failure Types

CoreSim supports domain-specific failure injection through custom failure types. This allows you to simulate application-specific error conditions beyond basic allocation and filesystem failures.

### Basic Usage

```zig
const custom_failures = [_]coresim.CustomFailure{
    .{ .name = "disk_full", .probability = 0.02 },      // 2% chance
    .{ .name = "timeout", .probability = 0.01 },        // 1% chance
    .{ .name = "network_error", .probability = 0.005 }, // 0.5% chance
};

try coresim.TestBuilder(DatabaseSystem)
    .operations(&[_]DatabaseSystem.Operation{ .put, .get, .delete })
    .custom_failures(&custom_failures)
    .run(allocator);
```

### System Integration

Systems detect custom failures using the global `should_inject_custom_failure()` function:

```zig
pub fn put(self: *DatabaseSystem, key: []const u8, value: []const u8) !void {
    // Check for domain-specific failures
    if (coresim.should_inject_custom_failure("disk_full")) {
        self.disk_full = true;
        return error.DiskFull;
    }
    
    if (coresim.should_inject_custom_failure("timeout")) {
        return error.Timeout;
    }
    
    // Proceed with normal operation
    try self.data.put(key, value);
}
```

### Common Failure Types

#### Database Systems
- `"disk_full"` - Storage exhaustion
- `"index_corruption"` - Data integrity failures  
- `"timeout"` - Operation timeouts
- `"deadlock"` - Transaction conflicts

#### Cache Systems
- `"cache_miss"` - Forced cache misses
- `"eviction_failure"` - Cache eviction errors
- `"memory_pressure"` - Low memory conditions

#### Network Systems
- `"network_failure"` - Connection failures
- `"packet_loss"` - Data transmission errors
- `"dns_timeout"` - Name resolution failures
- `"consensus_failure"` - Distributed consensus failures
- `"partition"` - Network partition scenarios
- `"quorum_unreachable"` - Insufficient replica connectivity

#### File Systems
- `"permission_denied"` - Access control failures
- `"file_corruption"` - Data integrity errors
- `"backup_failure"` - Backup operation failures

### Combined with Operation Weights

Custom failures work seamlessly with operation weights for realistic testing:

```zig
const failures = [_]coresim.CustomFailure{
    .{ .name = "disk_full", .probability = 0.03 },
    .{ .name = "cache_miss", .probability = 0.1 },
};

const weights = [_]coresim.OpWeight(MySystem.Operation){
    .{ .operation = .get, .weight = 0.7 },  // 70% reads (hit cache_miss)
    .{ .operation = .put, .weight = 0.3 },  // 30% writes (hit disk_full)
};

try coresim.TestBuilder(MySystem)
    .operations(&ops)
    .custom_failures(&failures)
    .operation_weights(&weights)
    .run(allocator);
```

### Error Handling Patterns

#### Error Return Types
```zig
pub fn writeData(self: *System, data: []const u8) !void {
    if (coresim.should_inject_custom_failure("disk_full")) {
        return error.DiskFull;
    }
    // Normal operation
}
```

#### Optional Return Types
```zig
pub fn readCache(self: *System, key: []const u8) ?[]const u8 {
    if (coresim.should_inject_custom_failure("cache_miss")) {
        return null; // Simulate cache miss
    }
    return self.cache.get(key);
}
```

#### State-Based Failures
```zig
pub fn put(self: *DatabaseSystem, key: []const u8, value: []const u8) !void {
    // Check persistent failure states first
    if (self.is_corrupted) {
        return error.DatabaseCorrupted;
    }
    
    // Check for new failure injection
    if (coresim.should_inject_custom_failure("index_corruption")) {
        self.is_corrupted = true; // Set persistent state
        return error.IndexCorrupted;
    }
    
    // Proceed with operation
}
```

## Conditional Multipliers

Conditional multipliers allow you to dynamically scale failure rates based on current system conditions. This enables testing scenarios where failures are more likely during specific operational states.

### Basic Usage

```zig
const multipliers = [_]coresim.ConditionalMultiplier{
    .{ .condition = .during_recovery, .multiplier = 10.0 }, // 10x failures during recovery
    .{ .condition = .during_flush, .multiplier = 5.0 },     // 5x failures during flush
    .{ .condition = .under_memory_pressure, .multiplier = 3.0 }, // 3x failures under memory pressure
};

try coresim.TestBuilder(DatabaseSystem){}
    .operations(&[_]DatabaseSystem.Operation{ .put, .get, .flush, .checkpoint })
    .custom_failures(&[_]coresim.CustomFailure{
        .{ .name = "disk_full", .probability = 0.01 },      // Base 1% rate
        .{ .name = "replication_lag", .probability = 0.005 }, // Base 0.5% rate
    })
    .conditional_multipliers(&multipliers)
    .run(allocator);
```

### Single Multiplier (Convenience API)

```zig
try coresim.TestBuilder(DatabaseSystem){}
    .operations(&ops)
    .custom_failures(&failures)
    .conditional_multiplier(.during_recovery, 10.0) // Single multiplier
    .run(allocator);
```

### System Integration

Systems set conditions using `set_system_condition()` to trigger multiplier effects:

```zig
pub fn checkpoint(self: *DatabaseSystem, key: []const u8, value: []const u8) !void {
    // Set high-stress condition during checkpointing
    coresim.set_system_condition(.during_recovery);
    defer coresim.set_system_condition(null); // Reset when done
    
    // Custom failures will now have 10x higher probability
    if (coresim.should_inject_custom_failure("checkpoint_failed")) {
        return error.CheckpointFailed;
    }
    
    // Perform actual checkpoint...
}

pub fn flush(self: *DatabaseSystem, key: []const u8, value: []const u8) !void {
    coresim.set_system_condition(.during_flush);
    defer coresim.set_system_condition(null);
    
    // Disk failures now 5x more likely during flush
    if (coresim.should_inject_custom_failure("disk_full")) {
        return error.DiskFull; 
    }
    
    // Perform actual flush...
}
```

### Available System Conditions

| Condition | Description | Common Use Cases |
|-----------|-------------|------------------|
| `.during_recovery` | System is recovering from failure | Checkpoint operations, crash recovery, backup restoration |
| `.during_flush` | System is flushing data to persistent storage | Database commits, cache flushes, log syncing |
| `.under_memory_pressure` | System is under memory pressure | Memory allocation failures, cache evictions |
| `.high_operation_rate` | System is processing high volume of operations | Load testing, burst scenarios |
| `.after_restart` | System recently restarted | Initialization failures, warm-up issues |
| `.hash_table_resize` | Hash table is being resized | Memory allocation during resize operations |
| `.normal_operation` | System in normal operational state | Baseline testing conditions |

### Realistic Testing Scenarios

#### Database Recovery Testing
```zig
const recovery_multipliers = [_]coresim.ConditionalMultiplier{
    .{ .condition = .during_recovery, .multiplier = 15.0 }, // 15x failures during recovery
    .{ .condition = .under_memory_pressure, .multiplier = 8.0 }, // 8x failures under memory pressure
};

try coresim.TestBuilder(DatabaseSystem){}
    .operations(&[_]DatabaseSystem.Operation{ .put, .get, .checkpoint, .recover })
    .custom_failures(&[_]coresim.CustomFailure{
        .{ .name = "corruption_detected", .probability = 0.001 },
        .{ .name = "insufficient_space", .probability = 0.002 },
    })
    .conditional_multipliers(&recovery_multipliers)
    .run(allocator);
```

#### High-Load Scenario Testing
```zig
try coresim.TestBuilder(CacheSystem){}
    .operations(&cache_ops)
    .custom_failures(&cache_failures)
    .conditional_multiplier(.high_operation_rate, 5.0) // 5x failures under load
    .operation_weights(&high_load_weights) // Simulate heavy traffic
    .run(allocator);
```

### Integration with Other Failure Types

Conditional multipliers affect ALL failure types configured for the test:

```zig
try coresim.TestBuilder(DistributedSystem){}
    .operations(&ops)
    .network_errors(0.01)           // Base 1% network errors
    .allocator_failures(0.005)      // Base 0.5% allocation failures  
    .custom_failures(&custom_failures) // Domain-specific failures
    .conditional_multiplier(.during_recovery, 10.0) // ALL become 10x more likely during recovery
    .run(allocator);
```

When the system sets condition to `.during_recovery`:
- Network errors: 1% → 10% (10x increase)
- Allocation failures: 0.5% → 5% (10x increase)  
- Custom failures: Each multiplied by 10x

## Detailed Statistics Collection

CoreSim provides comprehensive analytics capabilities through detailed statistics collection. When enabled, the framework collects in-depth performance metrics, timing data, and operational insights.

### Basic Usage

```zig
// Enable detailed statistics collection
const stats = try coresim.TestBuilder(MySystem){}
    .operations(&[_]MySystem.Operation{ .put, .get, .delete })
    .detailed_stats(true)
    .run_with_stats(allocator); // Use run_with_stats() to return statistics

// Access collected data
std.debug.print("{}\n", .{stats});
```

### Features Provided

- **Per-Operation Timing**: Min/max/average execution times for each operation type
- **Operation Distribution Analysis**: Compare actual vs intended operation frequency  
- **Failure Rate Tracking**: Monitor failure injection patterns over time
- **Memory Usage Monitoring**: Track memory allocation patterns
- **Performance Impact Analysis**: Measure impact of failures on execution time

### Analytics Output Example

```
=== Detailed Analytics ===
Operation Timings:
  put: 1247 calls, avg: 23.4μs, min: 8.1μs, max: 156.3μs
  get: 3521 calls, avg: 12.7μs, min: 4.2μs, max: 89.1μs
  delete: 324 calls, avg: 18.9μs, min: 7.3μs, max: 134.2μs

Operation Distribution:
  get: 70.2% actual vs 70.0% intended (diff: +0.2%)
  put: 19.8% actual vs 20.0% intended (diff: -0.2%)
  delete: 10.0% actual vs 10.0% intended (diff: 0.0%)
  
Failure Rate Trend: 2.31% average over 150 samples
Memory Allocations: 45,231 total
```

### Integration with Other Features

Detailed statistics work seamlessly with all CoreSim features:

```zig
const comprehensive_stats = try coresim.TestBuilder(DatabaseSystem){}
    .operations(&ops)
    .operation_weights(&workload_pattern)     // Track distribution accuracy
    .custom_failures(&domain_failures)       // Monitor failure impact
    .conditional_multipliers(&stress_modes)   // Analyze failure rate changes
    .detailed_stats(true)                     // Enable comprehensive analytics
    .run_with_stats(allocator);
```

### Use Cases

- **Performance Optimization**: Identify bottleneck operations and optimization opportunities
- **Workload Validation**: Verify that test patterns match real-world usage
- **Failure Impact Assessment**: Understand how failures affect system performance
- **Resource Usage Analysis**: Monitor memory allocation patterns and detect leaks
- **Regression Detection**: Compare performance metrics across different code versions

## Key Generation Strategies

### Uniform Random Keys
```zig
.random_keys(min_length, max_length)
// or
.key_strategy(.{ .uniform_random = .{ .min_length = 4, .max_length = 16 } })
```
- Generates random alphabetic keys (a-z)
- Configurable length bounds
- Best for general testing

### Collision-Prone Keys  
```zig
.collision_prone_keys(collision_rate)
// or  
.key_strategy(.{ .collision_prone = .{ .hash_collision_rate = 0.3 } })
```
- Generates keys designed to cause hash collisions
- `collision_rate`: probability of creating collision-prone keys (0.0-1.0)
- Excellent for stress-testing hash maps and dictionaries

### Sequential Keys
```zig
.sequential_keys("prefix_")
// or
.key_strategy(.{ .sequential = .{ .prefix = "user_" } })
```
- Generates sequential keys: `prefix_00000001`, `prefix_00000002`, etc.
- Predictable patterns for deterministic testing
- Useful for testing ordering and iteration

## Value Generation Strategies

### Fixed Size Values
```zig
.fixed_size_values(size_in_bytes)
// or
.value_strategy(.{ .fixed_size = 256 })
```
- Generates values of exactly the specified size
- Contains random uppercase letters (A-Z)
- Perfect for testing fixed-size data structures

### Variable Size Values
```zig
.variable_size_values(min_bytes, max_bytes)
// or
.value_strategy(.{ .variable_size = .{ .min = 8, .max = 256 } })
```
- Generates values within the specified size range
- Contains random uppercase letters (A-Z)
- Most common strategy for general testing

### Random Binary Values
```zig
.random_binary_values()
// or
.value_strategy(.{ .random_binary = {} })
```
- Generates truly random binary data (all byte values 0-255)
- Size range: 64-1024 bytes
- Best for testing binary data handling and edge cases

## Operation Weight Distribution

Control the probability distribution of operations to simulate realistic workloads:

```zig
// Define operation weights
const OpWeight = coresim.OpWeight(MySystem.Operation);
const weights = [_]OpWeight{
    .{ .operation = .get, .weight = 0.8 },    // 80% reads
    .{ .operation = .put, .weight = 0.15 },   // 15% writes  
    .{ .operation = .delete, .weight = 0.05 } // 5% deletes
};

// Apply weights to test
try coresim.TestBuilder(MySystem){}
    .operations(&[_]MySystem.Operation{ .get, .put, .delete })
    .operation_weights(&weights)
    .run(allocator);
```

**Common Workload Patterns:**

#### Read-Heavy Workload (Caching scenarios)
```zig
const read_heavy = [_]OpWeight{
    .{ .operation = .get, .weight = 0.8 },    // 80% reads
    .{ .operation = .put, .weight = 0.15 },   // 15% writes
    .{ .operation = .delete, .weight = 0.05 } // 5% deletes
};
```

#### Write-Heavy Workload (Data ingestion)
```zig
const write_heavy = [_]OpWeight{
    .{ .operation = .put, .weight = 0.7 },    // 70% writes
    .{ .operation = .get, .weight = 0.2 },    // 20% reads
    .{ .operation = .delete, .weight = 0.1 }  // 10% deletes
};
```

#### Cleanup-Focused Workload (Maintenance testing)
```zig
const cleanup_focused = [_]OpWeight{
    .{ .operation = .delete, .weight = 0.5 }, // 50% deletes
    .{ .operation = .get, .weight = 0.3 },    // 30% reads
    .{ .operation = .put, .weight = 0.2 }     // 20% writes
};
```

**Notes:**
- Weights don't need to sum to 1.0 (they're automatically normalized)
- Operations not included in weights will have 0% probability
- Only operations listed in `.operations()` are considered

## System Requirements

Your system must implement:

### Required Components

```zig
const MySystem = struct {
    // 1. Operation enum (required)
    pub const Operation = enum { op1, op2, op3 };
    
    // 2. Lifecycle methods (required)
    pub fn init(allocator: std.mem.Allocator) !@This() { /* ... */ }
    pub fn deinit(self: *@This()) void { /* ... */ }
    
    // 3. Operation methods (required - names must match enum)
    pub fn op1(self: *@This()) !void { /* ... */ }
    pub fn op2(self: *@This(), key: []const u8) ?[]const u8 { /* ... */ }
    pub fn op3(self: *@This(), key: []const u8, value: []const u8) !void { /* ... */ }
    
    // 4. Invariants (optional - auto-discovered)
    pub fn checkConsistency(self: *@This()) bool { /* ... */ }
    pub fn checkMemory(self: *@This()) bool { /* ... */ }
    pub fn validate(self: *@This()) bool { /* ... */ }
};
```

### Method Signatures

CoreSim supports these method signatures:

```zig
// 0 arguments (beyond self)
pub fn reset(self: *@This()) !void { /* ... */ }

// 1 argument (key)
pub fn get(self: *@This(), key: []const u8) ?[]const u8 { /* ... */ }

// 2 arguments (key, value)
pub fn put(self: *@This(), key: []const u8, value: []const u8) !void { /* ... */ }
```

### Auto-Discovered Invariants

CoreSim automatically finds and uses these invariant methods:

- `checkConsistency()` - Critical severity
- `checkMemory()` - Critical severity  
- `validate()` - Important severity

## Complete Examples

### Development Testing

```zig
// Fast feedback during development
try coresim.TestBuilder(MyCache){}
    .operations(&[_]MyCache.Operation{ .put, .get })
    .iterations(25)
    .sequence_length(10, 50)
    .run(allocator);
```

### CI/CD Testing

```zig
// Standard testing for continuous integration
try coresim.TestBuilder(MyQueue){}
    .operations(&[_]MyQueue.Operation{ .push, .pop, .clear })
    .iterations(100)
    .allocator_failures(0.001)
    .filesystem_errors(0.005)
    .run(allocator);
```

### Robustness Testing

```zig
// High-stress testing before release
try coresim.TestBuilder(MyServer){}
    .operations(&[_]MyServer.Operation{ .start, .handle_request, .stop })
    .iterations(500)
    .sequence_length(100, 500)
    .allocator_failures(0.02)
    .filesystem_errors(0.01)
    .run(allocator);
```

### Custom Configuration

```zig
// Full control over test parameters
try coresim.TestBuilder(MySystem){}
    .operations(&[_]MySystem.Operation{ .create, .read, .update, .delete })
    .named("crud_test")
    .iterations(2000)
    .allocator_failures(0.015)  // 1.5% allocation failures
    .filesystem_errors(0.008)   // 0.8% filesystem errors
    .seed(54321)                   // Custom seed for reproducibility
    .run(allocator);
```

### Realistic Workload Testing

```zig
// Simulate realistic database workload
const db_workload = [_]coresim.OpWeight(DatabaseSystem.Operation){
    .{ .operation = .select, .weight = 0.6 },  // 60% reads
    .{ .operation = .insert, .weight = 0.25 }, // 25% inserts
    .{ .operation = .update, .weight = 0.1 },  // 10% updates
    .{ .operation = .delete, .weight = 0.05 }, // 5% deletes
};

try coresim.TestBuilder(DatabaseSystem){}
    .operations(&[_]DatabaseSystem.Operation{ .select, .insert, .update, .delete })
    .operation_weights(&db_workload)
    .random_keys(8, 64)                     // Variable key lengths
    .variable_size_values(100, 8192)         // Realistic record sizes
    .allocator_failures(0.005)              // Occasional memory pressure
    .sequence_length(500, 2000)                 // Long transaction sequences
    .iterations(1000)
    .named("realistic_database_workload")
    .run(allocator);
```

### Debugging Specific Issues

```zig
// Minimal, deterministic test for debugging
try coresim.TestBuilder(MySystem){}
    .operations(&[_]MySystem.Operation{ .problematic_op })
    .iterations(5)
    .sequence_length(5, 15)
    .seed(12345)  // Fixed seed for reproducibility
    .run(allocator);
```

## Error Handling

All test functions return `!void` and may throw these errors:

- `error.OutOfMemory` - System ran out of memory
- `error.InvariantViolation` - System invariant was violated
- `error.TestConfigurationError` - Invalid test configuration
- `error.SystemInitializationFailed` - System init() failed
- `error.OperationExecutionFailed` - Operation method failed unexpectedly

## Tips

### Choosing Configuration

1. **Development**: Low iterations (25-50), no failures, short sequences
2. **CI/CD**: Medium iterations (100-500), low failures (0.1-1%), medium sequences
3. **Pre-release**: High iterations (500-2000), moderate failures (1-5%), long sequences
4. **Debugging**: Very low iterations (5-10), no failures, fixed seeds

### Performance Considerations

- Low iterations for fast feedback loops
- High iterations for thorough testing
- Failure injection adds overhead - use sparingly for performance tests
- TestBuilder allows fine-tuning for optimal performance/coverage balance

### Reproducibility

- Always use `.seed()` for deterministic tests
- Use consistent seed values for debugging scenarios
- Document seed values in test names for reference