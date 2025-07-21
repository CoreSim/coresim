# CoreSim - Deterministic Simulation Framework

CoreSim is a powerful, easy-to-use deterministic simulation testing framework for Zig. Test any system with automatic operation generation, failure injection, and comprehensive validation - all in just a few lines of code.

## Quick Start

Add simulation testing to any system in seconds:

```zig
const std = @import("std");
const coresim = @import("coresim");

const MyCache = struct {
    data: std.HashMap([]const u8, []const u8, ...),
    
    pub const Operation = enum { put, get, delete };
    
    pub fn init(allocator: std.mem.Allocator) !@This() { /* ... */ }
    pub fn deinit(self: *@This()) void { /* ... */ }
    
    pub fn put(self: *@This(), key: []const u8, value: []const u8) !void { /* ... */ }
    pub fn get(self: *@This(), key: []const u8) ?[]const u8 { /* ... */ }
    pub fn delete(self: *@This(), key: []const u8) bool { /* ... */ }
    
    pub fn checkConsistency(self: *@This()) bool { /* your invariants */ }
};

// Test your system with the TestBuilder API!
const builder = coresim.TestBuilder(MyCache){};
try builder
    .operations(&[_]MyCache.Operation{ .put, .get, .delete })
    .iterations(100)
    .run(allocator);
```

**That's it!** CoreSim will automatically:
- Generate thousands of random operation sequences
- Inject memory allocation failures
- Validate your invariants after each operation
- Provide detailed statistics and shrink failing cases

## Features

- **Flexible Configuration**: Configure all testing parameters explicitly for your use case
- **Property-Based Testing**: Generate randomized test sequences with configurable distributions
- **Failure Injection**: Inject failures with conditional multipliers based on system state
- **Filesystem Simulation**: Abstract filesystem interface with controllable error injection
- **Deterministic Execution**: Seed-controlled PRNG for reproducible test runs
- **Automatic Shrinking**: Reduce failing test cases to minimal reproductions
- **Universal Design**: Works with any system type - not just databases

## Testing Options

CoreSim offers multiple testing approaches - **see the [API Reference](docs/api-reference.md) for complete documentation**:

```zig
// TestBuilder API - explicit configuration for your specific needs
// Fast development testing
const builder = coresim.TestBuilder(MySystem){};
try builder
    .operations(&ops)
    .iterations(25)
    .sequence_length(10, 50)
    .run(allocator);

// Standard CI/CD testing
try coresim.TestBuilder(MySystem){}
    .operations(&ops)
    .iterations(100)
    .allocator_failures(0.001)
    .filesystem_errors(0.005)
    .run(allocator);

// High-stress robustness testing
try coresim.TestBuilder(MySystem){}
    .operations(&ops)
    .iterations(500)
    .sequence_length(100, 500)
    .allocator_failures(0.02)
    .filesystem_errors(0.01)
    .run(allocator);

// Custom configuration with operation weights
const weights = [_]coresim.OpWeight(MySystem.Operation){
    .{ .operation = .get, .weight = 0.7 },    // 70% reads
    .{ .operation = .put, .weight = 0.2 },    // 20% writes
    .{ .operation = .delete, .weight = 0.1 }, // 10% deletes
};
try coresim.TestBuilder(MySystem){}
    .operations(&ops)
    .operation_weights(&weights)
    .random_keys(8, 32)
    .variable_size_values(64, 2048)
    .iterations(1000)
    .run(allocator);
```

**[→ See complete TestBuilder configuration options in the API Reference](docs/api-reference.md)**

## System Requirements

Your system needs:

1. **Operation enum**: Define the operations your system supports
2. **Lifecycle methods**: `init(allocator)` and `deinit(*Self)`
3. **Operation methods**: Functions named to match your operation enum
4. **Optional invariants**: `checkConsistency`, `checkMemory`, `validate` (auto-discovered)

```zig
const MySystem = struct {
    pub const Operation = enum { create, read, update, delete };
    
    pub fn init(allocator: std.mem.Allocator) !@This() { /* ... */ }
    pub fn deinit(self: *@This()) void { /* ... */ }
    
    // Method names must match operation enum values
    pub fn create(self: *@This(), key: []const u8, value: []const u8) !void { /* ... */ }
    pub fn read(self: *@This(), key: []const u8) ?[]const u8 { /* ... */ }
    pub fn update(self: *@This(), key: []const u8, value: []const u8) !void { /* ... */ }
    pub fn delete(self: *@This(), key: []const u8) bool { /* ... */ }
    
    // Optional: auto-discovered invariants
    pub fn checkConsistency(self: *@This()) bool { /* ... */ }
};
```

## Works with Any System

CoreSim tests any system type - networks, data structures, state machines, file systems, etc.

**[→ See complete working examples](examples/) for HTTP servers, caches, queues, and more!**

## Documentation

- **[API Reference](docs/api-reference.md)** - Complete API documentation with all 20+ testing functions
- **[Quick Start Guide](docs/README.md)** - Get up and running in 5 minutes
- **[Examples](examples/README.md)** - Working examples for 6 different system types
- **[Integration Guide](docs/integration-guide.md)** - Step-by-step integration walkthrough  
- **[Architecture Overview](docs/architecture.md)** - Deep dive into CoreSim's design

## Building and Running

```bash
# Build the library and examples
zig build

# Run unit tests
zig build test

# Run example demonstrations
zig build example

# Build your own project with CoreSim
zig build --dep coresim=/path/to/coresim
```


## Requirements

- **Zig 0.14.1 or later**
- No external dependencies

## Why CoreSim?

### For Library Authors
- **Catch edge cases** your unit tests miss
- **Test under failure conditions** (allocation failures, I/O errors)
- **Validate invariants** automatically across thousands of scenarios
- **Get reproducible failures** with deterministic seeds

### For Application Developers  
- **Test complex state interactions** between multiple operations
- **Simulate real-world conditions** with configurable failure rates
- **Find memory leaks and resource issues** early in development
- **Build confidence** in your system's robustness

### For System Designers
- **Validate distributed system properties** (consistency, availability)
- **Test recovery mechanisms** under various failure scenarios
- **Analyze system behavior** with detailed statistics and metrics

## Contributing

CoreSim is designed to be generic and extensible. We welcome contributions for:

- **New system examples** showing CoreSim with different domains
- **Enhanced failure injection** patterns and custom failure types
- **Improved shrinking strategies** for faster minimal case discovery
- **Performance optimizations** for large-scale testing
- **Documentation and tutorials** for specific use cases

## License

This project is extracted from the poro database project and follows similar licensing terms.