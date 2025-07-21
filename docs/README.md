# CoreSim Documentation

Welcome to CoreSim, a generalized deterministic simulation testing framework for Zig. This documentation will help you understand, integrate, and effectively use CoreSim in your projects.

## Quick Start

### 30-Second Start

Add CoreSim to any system in three steps:

1. **Define your operations**: `pub const Operation = enum { op1, op2, op3 };`
2. **Add lifecycle methods**: `pub fn init(allocator) !@This()` and `pub fn deinit(*@This())`  
3. **Test**: `try coresim.TestBuilder(MySystem){}.operations(&ops).iterations(100).run(allocator);`

### 5-Minute Deep Dive

1. **[Integration Guide](integration-guide.md)** - Step-by-step guide to adding CoreSim to your project
2. **[Examples](../examples/README.md)** - Working examples for different system types  
3. **[Architecture](architecture.md)** - Understanding CoreSim's design and components

## What is CoreSim?

CoreSim is a deterministic simulation testing framework that makes property-based testing accessible to any Zig project. Originally extracted from the poro database project, it's now generalized to test any system type - from network services to data structures to state machines.

### Key Features

- **Flexible Configuration**: Configure all testing parameters explicitly for your use case
- **Deterministic Testing**: All test runs are reproducible using seeds
- **Property-Based Testing**: Generate large numbers of test sequences automatically
- **Failure Injection**: Inject allocator, filesystem, network, and custom domain-specific failures
- **Conditional Multipliers**: Scale failure rates based on system conditions (e.g., 10x failures during recovery)
- **Automatic Shrinking**: Reduce failing test cases to minimal reproductions
- **Filesystem Simulation**: Test filesystem operations with controllable errors
- **Universal Design**: Works with any system type - not just databases

### When to Use CoreSim

CoreSim is valuable for testing any system with stateful operations:

- **Network Services**: HTTP servers, REST APIs, WebSocket handlers
- **Data Structures**: Queues, caches, maps, trees, graphs  
- **State Machines**: Game logic, workflow engines, protocol handlers
- **File Systems**: Document managers, configuration systems
- **Databases**: Any storage system with CRUD operations
- **Distributed Systems**: Consensus algorithms, replication, clustering

## Documentation Structure

### Getting Started
- **[Integration Guide](integration-guide.md)** - Complete guide to integrating CoreSim into your project
- **[Examples](examples.md)** - Practical examples for different types of systems

### Understanding CoreSim
- **[Architecture](architecture.md)** - Design principles and component architecture
- **[Core Concepts](#core-concepts)** - Key concepts and terminology

### Reference
- **[API Reference](api-reference.md)** - Complete documentation of all testing functions and configurations
- **[Configuration Options](#configuration-options)** - Complete configuration reference
- **[Best Practices](#best-practices)** - Guidelines for effective use

## Core Concepts

### Property-Based Testing

Unlike traditional unit tests that check specific scenarios, property-based testing generates many random test cases and verifies that certain properties (invariants) always hold.

```zig
// Instead of testing specific operations:
try store.put("key1", "value1");
try testing.expect(std.mem.eql(u8, store.get("key1").?, "value1"));

// Property testing generates hundreds of random sequences:
// put("abc", "xyz"), get("def"), delete("abc"), put("ghi", "jkl"), ...
// And verifies invariants hold after each operation
```

### Invariants

Invariants are properties that should always be true about your system:

```zig
// Example invariants:
fn checkDataConsistency(system: *MySystem) bool {
    // All stored data should be retrievable
    // No corrupted entries should exist
    // Memory usage should be bounded
}
```

### Failure Injection

CoreSim can inject various types of failures to test system resilience:

- **Allocator Failures**: Simulate out-of-memory conditions
- **Filesystem Errors**: Disk full, I/O errors, permission denied
- **Network Failures**: Timeouts, connection drops, partitions
- **Custom Failures**: Application-specific error conditions

### Deterministic Execution

All randomness in CoreSim is controlled by seeds, making test failures reproducible:

```zig
// Same seed = same test sequence
var test_config = MyTest{ .seed = 12345, /* ... */ };
```

## Quick Example

Here's a complete working example:

```zig
const std = @import("std");
const coresim = @import("coresim");

// Define your system
const MyCache = struct {
    allocator: std.mem.Allocator,
    data: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    
    // Required: Operation enum
    pub const Operation = enum { put, get, delete, clear };
    
    // Required: Lifecycle methods
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
    
    // Required: Operation methods (names match enum)
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
    
    // Optional: Invariant checking (auto-discovered)
    pub fn checkConsistency(self: *@This()) bool {
        var iterator = self.data.iterator();
        while (iterator.next()) |entry| {
            if (entry.key_ptr.len == 0) return false; // No empty keys
        }
        return true;
    }
};

// Test with TestBuilder API!
pub fn testMyCache(allocator: std.mem.Allocator) !void {
    const builder = coresim.TestBuilder(MyCache){};
    try builder
        .operations(&[_]MyCache.Operation{ .put, .get, .delete, .clear })
        .iterations(100)
        .allocator_failures(0.001)
        .run(allocator);
}
```

That's it! CoreSim will automatically:
- Generate thousands of random operation sequences
- Inject allocation failures to test error handling  
- Validate your `checkConsistency` invariant after each operation
- Provide detailed statistics and shrink any failures to minimal cases

## Common Patterns

### Basic Testing Pattern

1. **Define Operations**: Create an enum of operations your system supports
2. **Implement System**: Create a struct representing your system state
3. **Create Interface Functions**: Implement init, deinit, and execute functions
4. **Define Invariants**: Specify properties that should always hold
5. **Configure Test**: Set up operation distributions and failure injection
6. **Run Test**: Execute the property test with desired iterations

### Error Handling Pattern

```zig
fn executeOperation(system: *MySystem, operation: MyOp) !void {
    switch (operation.operation_type) {
        .put => {
            // Handle allocation failures gracefully
            system.put(operation.key.?, operation.value.?) catch |err| switch (err) {
                error.OutOfMemory => return, // Expected failure
                else => return err, // Unexpected failure
            };
        },
        // ... other operations
    }
}
```

### Filesystem Testing Pattern

```zig
// Use simulated filesystem for testing
var sim_fs = coresim.filesystem.SimulatedFilesystem.init(allocator);
defer sim_fs.deinit();

// Configure error conditions
try sim_fs.set_error_condition(.write, "*.log", .DiskFull);

// Your system uses the filesystem interface
var system = MySystem.init(allocator, sim_fs.interface());
```

## Best Practices

### 1. Start Simple
- Begin with basic operations and simple invariants
- Add complexity gradually as tests stabilize
- Use small sequence lengths during development

### 2. Meaningful Invariants
- Focus on critical system properties
- Make invariants deterministic and timing-independent
- Use different severity levels appropriately

### 3. Realistic Failure Rates
- Base failure probabilities on real-world observations
- Use higher rates during development for faster feedback
- Consider conditional multipliers for system states

### 4. Test Organization
- Group related tests by system component
- Use descriptive test names
- Document expected behaviors and edge cases

### 5. Debugging
- Always use deterministic seeds for reproducibility
- Keep debug logs for investigation
- Use shrinking to find minimal failure cases

## Getting Help

### Common Issues

1. **Memory Leaks**: Ensure all allocations in operations are properly managed
2. **Flaky Invariants**: Make invariants independent of timing and external state
3. **Slow Shrinking**: Reduce shrinking attempts or improve shrinking strategies
4. **Low Test Coverage**: Adjust operation distributions and failure rates

### Debugging Tips

1. **Use Small Sequences**: Start with sequence lengths of 10-50 for debugging
2. **Fixed Seeds**: Use specific seeds to reproduce issues consistently
3. **Verbose Logging**: Add debug output to understand test execution
4. **Incremental Development**: Test individual operations before complex sequences

### Resources

- **[Examples](examples.md)**: Working code for various system types
- **[Architecture](architecture.md)**: Deep dive into CoreSim's design
- **[Integration Guide](integration-guide.md)**: Complete integration walkthrough

## Contributing

CoreSim is designed to be extensible. Common contribution areas:

- **New Generation Strategies**: Additional ways to generate keys and values
- **Enhanced Shrinking**: More sophisticated shrinking algorithms
- **Additional Failure Types**: New categories of failures to inject
- **Performance Optimizations**: Improvements to test execution speed
- **Documentation**: Examples for additional system types

---

*This documentation covers CoreSim version 0.1.0. For the latest updates and examples, check the project repository.*