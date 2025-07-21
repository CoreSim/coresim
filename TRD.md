# CoreSim Technical Requirements Document (TRD)

## Overview

This document outlines advanced CoreSim features that are available in the underlying framework but not yet exposed through the TestBuilder API. These features represent opportunities for enhancing the user-facing API while maintaining the framework's simplicity for common use cases.

## Current State

The TestBuilder API currently exposes:
- Basic failure injection (allocator, filesystem)
- Key generation strategies (random, collision-prone, sequential)
- Value generation strategies (fixed, variable, binary)
- Sequence length configuration
- Standard test presets

## Unexposed Features Requiring Implementation

### 1. Advanced Failure Injection

#### 1.1 Network Error Injection

**Current State**: ✅ **IMPLEMENTED** - Framework supports `network_error_probability`, `should_inject_network_error()`, and TestBuilder exposes it via `network_errors()` method.

**Proposed API**:
```zig
try coresim.TestBuilder(MySystem)
    .operations(&ops)
    .network_errors(0.01)  // 1% network failure rate
    .run(allocator);
```

**Implementation Requirements**:
- Add `network_errors: f64` field to `TestConfig`
- Add `network_errors(rate: f64)` method to TestBuilder
- Update `run()` method to set `failure_config.network_error_probability`

**Use Cases**:
- Testing distributed systems under network partitions
- HTTP client/server resilience testing
- Database replication failure scenarios

#### 1.2 Custom Failure Types

**Current State**: Framework supports arbitrary custom failure types via `custom_failure_probabilities` HashMap but no TestBuilder exposure.

**Proposed API**:
```zig
try coresim.TestBuilder(MySystem)
    .operations(&ops)
    .custom_failure("disk_corruption", 0.001)
    .custom_failure("cache_miss", 0.1)
    .custom_failure("timeout", 0.02)
    .run(allocator);
```

**Implementation Requirements**:
- Add `custom_failures: std.StringHashMap(f64)` to `TestConfig`
- Add `custom_failure(name: []const u8, rate: f64)` method
- Update `run()` method to populate `failure_config.custom_failure_probabilities`
- Provide system access to `should_inject_custom_failure()` in operation methods

**Use Cases**:
- Database testing: transaction rollback, corruption detection
- Cache testing: cache miss simulation, eviction failures
- File system testing: specific error conditions per component

#### 1.3 Conditional Multipliers

**Current State**: Framework supports `ConditionalMultiplier` for state-aware failure injection but requires direct PropertyTest usage.

**Proposed API**:
```zig
try coresim.TestBuilder(MySystem)
    .operations(&ops)
    .conditional_multiplier(.during_recovery, 10.0)  // 10x failures during recovery
    .conditional_multiplier(.under_memory_pressure, 5.0)
    .run(allocator);
```

**Implementation Requirements**:
- Add `SystemCondition` enum exposure to core API
- Add `conditional_multipliers: []ConditionalMultiplier` to `TestConfig`
- Add `conditional_multiplier(condition: SystemCondition, multiplier: f64)` method
- Provide system interface to set current conditions during operation execution

**Use Cases**:
- Testing recovery scenarios with higher failure rates
- Memory pressure simulation
- High-load condition testing

### 2. Operation Distribution Control

#### 2.1 Weighted Operation Distribution

**Current State**: Framework supports `OperationDistribution` with custom weights but TestBuilder uses equal weights.

**Proposed API**:
```zig
const weights = [_]OpWeight{
    .{ .operation = .put, .weight = 0.5 },    // 50% puts
    .{ .operation = .get, .weight = 0.3 },    // 30% gets  
    .{ .operation = .delete, .weight = 0.2 }, // 20% deletes
};

try coresim.TestBuilder(MySystem)
    .operations(&ops)
    .operation_weights(&weights)
    .run(allocator);
```

**Implementation Requirements**:
- Define `OpWeight` struct: `{ operation: OperationType, weight: f64 }`
- Add `operation_weights: ?[]const OpWeight` to `TestConfig`
- Add `operation_weights(weights: []const OpWeight)` method
- Update operation distribution logic in `run()` method
- Add memory management for weights slice

**Use Cases**:
- Read-heavy workload simulation (80% gets, 20% puts)
- Write-heavy testing (70% puts, 30% gets)
- Realistic workload patterns
- Stress testing specific operations

### 3. Advanced Shrinking Configuration

#### 3.1 Shrinking Strategy Control

**Current State**: Framework supports multiple shrinking strategies but TestBuilder uses defaults.

**Proposed API**:
```zig
try coresim.TestBuilder(MySystem)
    .operations(&ops)
    .shrinking_strategies(&[_]ShrinkStrategy{ 
        .remove_operations, 
        .simplify_values, 
        .reduce_key_diversity 
    })
    .max_shrink_attempts(500)
    .run(allocator);
```

**Implementation Requirements**:
- Expose `ShrinkStrategy` enum in core API
- Add `shrink_strategies: ?[]const ShrinkStrategy` to `TestConfig`
- Add `max_shrink_attempts: ?u32` to `TestConfig`
- Add corresponding TestBuilder methods
- Update PropertyTest configuration to use custom shrinking settings

**Use Cases**:
- Performance-sensitive testing (limit shrink attempts)
- Complex systems requiring specific shrinking approaches
- Debug mode with exhaustive shrinking

#### 3.2 Failure Condition Preservation

**Current State**: Framework supports preserving specific failure conditions during shrinking.

**Proposed API**:
```zig
try coresim.TestBuilder(MySystem)
    .operations(&ops)
    .preserveFailureConditions(true)  // Keep original failure conditions
    .run(allocator);
```

**Implementation Requirements**:
- Add `preserve_failure_conditions: bool` to `TestConfig`
- Add `preserveFailureConditions(preserve: bool)` method
- Update shrinking configuration

**Use Cases**:
- Debugging specific failure scenarios
- Reproducing exact failure conditions
- Analyzing failure interactions

### 4. Advanced Filesystem Simulation

#### 4.1 Path-Specific Error Injection

**Current State**: Framework supports `SimulatedFilesystem` with path pattern matching but no TestBuilder integration.

**Proposed API**:
```zig
try coresim.TestBuilder(MySystem)
    .operations(&ops)
    .filesystem_error_pattern(.write, "*.wal", .DiskFull, 0.1)
    .filesystem_error_pattern(.read, "/tmp/*", .PermissionDenied, 0.05)
    .simulated_filesystem(true)
    .run(allocator);
```

**Implementation Requirements**:
- Define `FilesystemOperation` enum (read, write, open, close, flush, sync)
- Define `FilesystemError` enum (DiskFull, PermissionDenied, CorruptedData, etc.)
- Add filesystem simulation configuration to `TestConfig`
- Integrate `SimulatedFilesystem` into TestBuilder
- Provide filesystem interface to systems under test

**Use Cases**:
- Database WAL file error simulation
- Backup/recovery scenario testing
- Permission-based access testing
- Storage device failure simulation

#### 4.2 Operation-Specific Filesystem Errors

**Current State**: Framework supports per-operation error configuration.

**Proposed API**:
```zig
try coresim.TestBuilder(MySystem)
    .operations(&ops)
    .write_errors(0.02)      // 2% write failures
    .flush_errors(0.01)      // 1% flush failures
    .open_errors(0.005)      // 0.5% open failures
    .run(allocator);
```

**Implementation Requirements**:
- Add per-operation error rate configuration
- Map to `SimulatedFilesystem` error conditions
- Provide granular filesystem error control

**Use Cases**:
- Write-heavy system testing
- Sync/flush reliability testing
- File handle exhaustion scenarios

### 5. Enhanced Statistics and Tracking

#### 5.1 Detailed Failure Statistics

**Current State**: Framework provides `FailureTracker` with comprehensive statistics but TestBuilder only shows basic counts.

**Proposed API**:
```zig
const stats = try coresim.TestBuilder(MySystem)
    .operations(&ops)
    .detailed_stats(true)
    .run(allocator);

// Access detailed statistics
std.debug.print("Custom failure rates: {}\n", .{stats.custom_failure_rates});
std.debug.print("Operation distribution: {}\n", .{stats.operation_distribution});
```

**Implementation Requirements**:
- Define comprehensive `TestStatistics` struct
- Add optional detailed statistics collection
- Return statistics from `run()` method
- Include per-failure-type rates, operation patterns, timing data

**Use Cases**:
- Performance analysis
- Failure pattern analysis
- Test coverage verification
- Benchmarking and optimization

#### 5.2 Real-time Statistics Callback

**Current State**: Framework tracks statistics internally but no user access during test execution.

**Proposed API**:
```zig
try coresim.TestBuilder(MySystem)
    .operations(&ops)
    .stats_callback(struct {
        fn callback(stats: TestStatistics) void {
            if (stats.failure_rate > 0.1) {
                std.debug.print("High failure rate detected: {d:.2}%\n", .{stats.failure_rate * 100});
            }
        }
    }.callback)
    .run(allocator);
```

**Implementation Requirements**:
- Add callback function pointer to `TestConfig`
- Call callback at regular intervals during test execution
- Provide current statistics snapshot

**Use Cases**:
- Real-time monitoring
- Early test termination based on conditions
- Progress reporting for long-running tests

### 6. System Integration Enhancements

#### 6.1 Multiple Invariant Severities

**Current State**: Framework supports critical/important/advisory severities but TestBuilder doesn't expose granularity.

**Proposed API**:
```zig
try coresim.TestBuilder(MySystem)
    .operations(&ops)
    .invariant_severity("checkConsistency", .critical)
    .invariant_severity("checkPerformance", .advisory)
    .run(allocator);
```

**Implementation Requirements**:
- Expose `InvariantSeverity` enum
- Add invariant severity configuration
- Allow different behavior based on severity (stop vs warn)

**Use Cases**:
- Non-blocking performance checks
- Critical vs advisory invariants
- Graduated response to invariant violations

#### 6.2 Operation Context Support

**Current State**: Framework supports operation context data but TestBuilder doesn't utilize it.

**Proposed API**:
```zig
try coresim.TestBuilder(MySystem)
    .operations(&ops)
    .operation_context(true)  // Enable context passing
    .run(allocator);

// System methods receive context:
pub fn put(self: *@This(), key: []const u8, value: []const u8, context: OperationContext) !void {
    // Access timing, failure info, test metadata
}
```

**Implementation Requirements**:
- Define `OperationContext` struct with timing, failure info, metadata
- Add context support to operation method signatures
- Update automatic method dispatch to pass context

**Use Cases**:
- Timing-aware operations
- Context-sensitive behavior
- Advanced debugging and analysis

### 7. Domain-Specific Testing Patterns

#### 7.1 Database Testing Presets

**Proposed API**:
```zig
try coresim.TestBuilder(DatabaseSystem)
    .operations(&[_]DbOp{ .begin_tx, .commit, .rollback, .read, .write })
    .databasePreset(.acid_compliance)  // ACID-focused testing
    .run(allocator);

try coresim.TestBuilder(DatabaseSystem)
    .operations(&ops)
    .databasePreset(.crash_recovery)   // Crash recovery scenarios
    .run(allocator);
```

**Implementation Requirements**:
- Define database-specific presets
- Include transaction-aware failure injection
- Add consistency checking patterns

#### 7.2 Network Service Testing Presets

**Proposed API**:
```zig
try coresim.TestBuilder(HttpServer)
    .operations(&[_]HttpOp{ .connect, .request, .response, .disconnect })
    .networkPreset(.partition_tolerance)  // Network partition testing
    .run(allocator);
```

**Implementation Requirements**:
- Define network-specific presets
- Include connection-aware failure patterns
- Add protocol-specific validation

### 8. Performance and Scalability Enhancements

#### 8.1 Parallel Test Execution

**Proposed API**:
```zig
try coresim.TestBuilder(MySystem)
    .operations(&ops)
    .parallel_execution(4)  // 4 parallel test threads
    .run(allocator);
```

**Implementation Requirements**:
- Add thread pool support
- Ensure thread-safe system initialization
- Aggregate statistics from parallel executions

#### 8.2 Streaming Test Execution

**Proposed API**:
```zig
var test_stream = try coresim.TestBuilder(MySystem)
    .operations(&ops)
    .streamingMode(true)
    .run(allocator);

while (try test_stream.next()) |result| {
    // Process individual test results
}
```

**Implementation Requirements**:
- Add streaming iterator interface
- Support incremental result processing
- Enable early termination

## Implementation Priority

### High Priority (Most Valuable)
1. **Operation Distribution Control** - Common need for realistic workloads
2. **Network Error Injection** - Essential for distributed systems
3. **Custom Failure Types** - Enables domain-specific testing
4. **Detailed Statistics** - Valuable for analysis and debugging

### Medium Priority (Useful for Advanced Cases)
1. **Advanced Shrinking Configuration** - Improves debugging experience
2. **Conditional Multipliers** - Powerful for complex scenarios
3. **Filesystem Path-Specific Errors** - Useful for storage systems
4. **Multiple Invariant Severities** - Better error handling

### Low Priority (Specialized Use Cases)
1. **Real-time Statistics Callbacks** - Niche monitoring needs
2. **Operation Context Support** - Advanced debugging scenarios
3. **Domain-Specific Presets** - Nice-to-have convenience
4. **Parallel/Streaming Execution** - Performance optimization

## Design Principles

### 1. Maintain API Simplicity
- Advanced features should be opt-in
- Common cases should remain simple
- Complex configuration should be ergonomic

### 2. Backward Compatibility
- All existing TestBuilder APIs must continue working
- New features should not break existing code
- Default behavior should remain unchanged

### 3. Performance Considerations
- Advanced features should not impact basic use cases
- Memory allocation should be minimized
- Optional features should have zero cost when unused

### 4. Documentation Requirements
- All new features must be documented with examples
- Integration patterns should be clearly explained
- Performance implications should be noted

### 5. Testing Requirements
- New features must include comprehensive unit tests
- Integration tests should verify end-to-end functionality
- Examples should be provided for each feature

## Success Metrics

1. **API Coverage**: Percentage of underlying framework features exposed
2. **Ease of Use**: Time to implement common advanced scenarios
3. **Performance**: Overhead of advanced features on basic use cases
4. **Adoption**: Usage of advanced features in real projects
5. **Documentation Quality**: User success rate with advanced features

This TRD serves as a roadmap for evolving CoreSim's TestBuilder API to expose the full power of the underlying framework while maintaining its ease of use for common scenarios.