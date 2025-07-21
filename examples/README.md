# CoreSim Simple Examples

This directory contains simple, focused examples showing how to use CoreSim with different types of systems. Each example is designed to be under 10 lines of actual testing code and demonstrates proper invariant checking.

## Running Examples

```bash
# Run all simple examples
zig build example

# Or compile and run manually
zig build
./zig-out/bin/simple_examples
```

## Examples Included

### 1. HTTP Server (`HttpServer`)
- **Operations**: `start`, `stop`, `handle_request`, `get_status`
- **Invariant**: `checkConsistency` - ensures request count stays reasonable
- **Use Case**: Network services, web servers, APIs
- **Test Configuration**: 25 iterations, short sequences for fast feedback

### 2. Message Queue (`MessageQueue`) 
- **Operations**: `push`, `pop`, `peek`, `clear`, `size`
- **Invariant**: `checkMemory` - prevents queue from growing too large
- **Use Case**: Message brokers, task queues, async processing
- **Test Configuration**: 100 iterations with low failure injection
- **Note**: Shows proper memory management with allocator cleanup

### 3. Traffic Light (`TrafficLight`)
- **Operations**: `next`, `reset`, `get_state`
- **Invariant**: `validate` - ensures transition count stays bounded
- **Use Case**: State machines, workflow engines, game states
- **Test Configuration**: 5 iterations with fixed seed for deterministic debugging

### 4. Simple Cache (`SimpleCache`)
- **Operations**: `put`, `get`, `delete`, `stats`, `clear`
- **Invariant**: `checkConsistency` - ensures hit/miss counts stay reasonable
- **Use Case**: Caches, memoization, temporary storage
- **Test Configuration**: 500 iterations with high failure injection for stress testing

### 5. File Manager (`FileManager`)
- **Operations**: `open`, `close`, `read`, `write`, `list`
- **Invariant**: `checkMemory` - limits number of open files
- **Use Case**: File systems, document managers, persistence
- **Test Configuration**: 100 iterations with moderate failure injection

### 6. Counter (`Counter`)
- **Operations**: `increment`, `decrement`, `reset`, `get`
- **Invariant**: `validate` - keeps counter value within reasonable bounds
- **Use Case**: Metrics, statistics, simple state tracking
- **Test Configuration**: 25 iterations with short sequences for fast testing

## Key Patterns Demonstrated

### TestBuilder API Usage
```zig
// Fast development testing - explicit configuration
const builder = coresim.TestBuilder(MySystem){};
try builder
    .operations(&[_]MySystem.Operation{ .op1, .op2 })
    .iterations(25)
    .sequence_length(10, 50)
    .run(allocator);

// Standard testing with failure injection
try coresim.TestBuilder(MySystem){}
    .operations(&[_]MySystem.Operation{ .op1, .op2 })
    .iterations(100)
    .allocator_failures(0.001)
    .filesystem_errors(0.005)
    .run(allocator);

// High-stress testing
try coresim.TestBuilder(MySystem){}
    .operations(&[_]MySystem.Operation{ .op1, .op2 })
    .iterations(500)
    .sequence_length(100, 500)
    .allocator_failures(0.02)
    .filesystem_errors(0.01)
    .run(allocator);

// Debugging with deterministic seed
try coresim.TestBuilder(MySystem){}
    .operations(&[_]MySystem.Operation{ .op1, .op2 })
    .iterations(5)
    .sequence_length(5, 15)
    .seed(12345)
    .run(allocator);
```

### Required System Structure
```zig
const MySystem = struct {
    // Your state here...
    
    // Required: Operation enum
    pub const Operation = enum { op1, op2, op3 };
    
    // Required: Lifecycle methods
    pub fn init(allocator: std.mem.Allocator) !@This() { /* ... */ }
    pub fn deinit(self: *@This()) void { /* ... */ }
    
    // Required: Operation methods (names must match enum)
    pub fn op1(self: *@This(), key: []const u8, value: []const u8) !void { /* ... */ }
    pub fn op2(self: *@This(), key: []const u8) ?[]const u8 { /* ... */ }
    pub fn op3(self: *@This()) !void { /* ... */ }
    
    // IMPORTANT: At least one invariant method (auto-discovered)
    pub fn checkConsistency(self: *@This()) bool { 
        // Verify system is in a valid state
        return /* your consistency checks */;
    }
    
    // Optional: Additional invariants
    pub fn checkMemory(self: *@This()) bool { 
        // Verify memory usage is reasonable
        return /* your memory checks */;
    }
    
    pub fn validate(self: *@This()) bool { 
        // Verify system-specific constraints
        return /* your validation logic */;
    }
};
```

### Why Invariants Matter

**Property-based testing without invariants is just random operation execution.** The real value comes from:

1. **Correctness Validation**: Invariants catch logic errors that unit tests miss
2. **State Consistency**: Ensure your system maintains valid state through complex operation sequences
3. **Resource Management**: Detect memory leaks, handle exhaustion, resource limits
4. **Edge Case Discovery**: Find corner cases that break your assumptions

**Examples of Good Invariants:**
- Hash maps: Key count matches stored entries, no null keys
- Queues: Size matches actual item count, FIFO ordering preserved
- Caches: Hit ratio is reasonable, no duplicate keys
- Counters: Value stays within expected bounds
- File systems: No duplicate handles, proper cleanup

## Configuration Guidelines

### Development Testing
```zig
// Fast feedback loop - low iterations, no failures
.iterations(25)
.sequence_length(10, 50)
```

### CI/CD Testing  
```zig
// Moderate testing - standard failure rates
.iterations(100) 
.allocator_failures(0.001)
.filesystem_errors(0.005)
```

### Stress Testing
```zig
// Robustness testing - high failure rates, long sequences
.iterations(500)
.sequence_length(100, 500)
.allocator_failures(0.02)
.filesystem_errors(0.01)
```

### Debugging
```zig
// Deterministic, minimal testing
.iterations(5)
.sequence_length(5, 15)
.seed(12345)  // Fixed seed for reproducibility
```

## Beyond These Examples

For more complex scenarios, use the full TestBuilder configuration:

```zig
// Realistic workload simulation
const weights = [_]coresim.OpWeight(MySystem.Operation){
    .{ .operation = .read, .weight = 0.7 },   // 70% reads
    .{ .operation = .write, .weight = 0.2 },  // 20% writes
    .{ .operation = .delete, .weight = 0.1 }, // 10% deletes
};

try coresim.TestBuilder(MySystem){}
    .operations(&[_]MySystem.Operation{ .read, .write, .delete })
    .operation_weights(&weights)
    .random_keys(8, 64)
    .variable_size_values(100, 8192)
    .iterations(1000)
    .named("realistic_workload_test")
    .run(allocator);
```

**Remember**: These examples show CoreSim works for any system - not just databases! The key is defining good operations and invariants for your specific domain.

## Advanced Demos

For more complex testing scenarios, see these additional demos:

```bash
# Custom failure types - domain-specific error injection  
zig build failures-demo

# Network error injection - distributed systems testing
zig build network-demo

# Conditional multipliers - dynamic failure scaling
zig build conditional-demo

# Operation weights - realistic workload patterns
zig build weights-demo

# Generator configuration - custom key/value strategies
zig build generator-demo

# Detailed statistics - comprehensive analytics and performance insights
zig build stats-demo
```

### Key Advanced Features

- **Custom Failures**: Define domain-specific failures like "disk_full", "timeout", "replication_lag"
- **Network Errors**: Built-in network error injection for distributed systems
- **Conditional Multipliers**: Scale failure rates based on system state (e.g., 10x failures during recovery)
- **Operation Weights**: Realistic workload patterns (e.g., 80% reads, 20% writes)
- **Conditional Logic**: Set system conditions to trigger different failure behaviors
- **Detailed Statistics**: Comprehensive analytics including per-operation timing, distribution verification, and performance insights

These demos show real-world testing patterns and advanced failure injection scenarios.