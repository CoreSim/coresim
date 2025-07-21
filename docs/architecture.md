# CoreSim Architecture

CoreSim is designed as a layered framework that makes property-based testing accessible to any Zig project. This document describes the architectural design and how the layers work together.

## Design Principles

### 1. **Progressive Complexity**
- Simple one-liner API for immediate adoption
- Powerful low-level API for advanced use cases
- Smooth transition path from basic to sophisticated testing

### 2. **Deterministic by Design**
- All randomness is controlled through seeded PRNGs
- Test runs are fully reproducible given the same seed
- Failure injection follows predictable probability distributions

### 3. **Universal Applicability**
- Works with any system type through compile-time generics
- Convention-over-configuration for minimal setup
- Extensible for domain-specific needs

### 4. **Auto-Discovery**
- Automatically finds operation methods and invariants
- Minimal boilerplate through naming conventions
- Clear error messages when conventions aren't followed

## Layered Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Core API (core.zig)                      │
│                                                             │
│  quickTestOps() ┌─► TestBuilder ─► preset() ─► run()       │
│  basicTestOps() │                                           │
│  stressTestOps()└─► Auto-discovery of methods & invariants │
│  debugTestOps()    Convention-over-configuration            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 Foundation Layer                           │
├─────────────────────────────────────────────────────────────┤
│  Property Testing  │  Failure Injection  │  Filesystem Sim  │
│                    │                      │                  │
│  • Operation Gen   │  • Probability-based │  • VTable Interface│
│  • Sequence Gen    │  • Conditional Mult. │  • Error Injection │
│  • Invariant Check │  • Statistics Track  │  • Pattern Match  │
│  • Auto Shrinking  │  • Custom Failures   │  • Real/Simulated │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Your System                              │
│                                                             │
│  • Operation enum: .put, .get, .delete                     │
│  • Lifecycle methods: init(), deinit()                     │
│  • Operation methods: put(), get(), delete()               │
│  • Optional invariants: checkConsistency()                 │
└─────────────────────────────────────────────────────────────┘
```

## API Layers

### 1. Core API Layer (`core.zig`)

The primary interface that most users interact with. Provides:

**One-liner Functions:**
- `quickTestOps()` - Fast testing with no failures
- `basicTestOps()` - Standard testing with low failure rates
- `stressTestOps()` - High failure injection for robustness testing
- `debugTestOps()` - Minimal, deterministic testing for debugging

**Builder API:**
```zig
TestBuilder(SystemType)
    .operations(&ops)
    .preset(.stress)      // or .quick, .basic, .debug
    .iterations(1000)
    .allocator_failures(0.02)
    .run(allocator)
```

**Auto-Discovery Features:**
- Finds operation methods by matching enum names to method names
- Discovers invariant methods (`checkConsistency`, `checkMemory`, `validate`)
- Validates system structure at compile time

### 2. Foundation Layer

The foundation layer provides the core testing primitives that the Core API builds upon. These modules work together to deliver comprehensive deterministic testing capabilities.

#### Property Testing Module (`property_testing.zig`)

The core framework for generating and executing test sequences:

```zig
// Key types and their relationships
PropertyTest(OperationType, SystemType)
├── PropertyGenerators(OperationType)
│   ├── OperationDistribution(OperationType)
│   ├── KeyGenerationStrategy
│   └── ValueGenerationStrategy
├── FailureInjectionConfig
├── InvariantChecker(SystemType)[]
├── ShrinkingConfig
└── TestStatistics
```

**Key Components:**

1. **Operation Generation Pipeline**
   ```
   OperationDistribution → KeyGenerator → ValueGenerator → Operation
   ```

2. **Test Execution Pipeline**
   ```
   GenerateSequence → ExecuteWithFailures → CheckInvariants → RecordStats
   ```

3. **Failure Handling Pipeline**
   ```
   InvariantViolation → ShrinkSequence → FindMinimalReproduction
   ```

#### Failure Injection Module (`failure_injection.zig`)

Provides sophisticated failure injection with conditional probability adjustments:

```zig
// Core components
FailureInjectionConfig
├── Base Probabilities (allocator, filesystem, network)
├── Custom Failure Types (StringHashMap)
└── ConditionalMultiplier[] (system state aware)

FailureInjector
├── Config Reference
├── PRNG Reference
└── Current System Condition

FailureTracker
├── Failure Counts by Type
├── Operation Counts
└── Rate Calculations
```

**Failure Decision Flow:**
```
Operation Request → Check System Condition → Apply Multipliers → Roll Dice → Inject/Proceed
```

#### Filesystem Module (`filesystem.zig`)

Provides filesystem abstraction with vtable-based dependency injection:

```zig
// Interface hierarchy
FilesystemInterface (vtable)
├── RealFilesystem (production)
└── SimulatedFilesystem (testing)
    ├── RealFilesystem (delegate)
    ├── ErrorConditions (pattern matching)
    └── OperationCounts (statistics)
```

**Operation Flow:**
```
FilesystemInterface.operation() → VTable Dispatch → Real/Simulated Implementation
                                                  ↓
                                    (Simulated) Pattern Match → Error/Delegate
```

**Foundation Layer Integration:**

The three foundation modules work together seamlessly:

1. **Property Testing** coordinates overall test execution and calls both failure injection and filesystem simulation
2. **Failure Injection** is consulted before each operation to determine if a failure should be injected
3. **Filesystem Module** provides a clean abstraction that systems can use, with error injection handled transparently
4. All modules share the same PRNG state for deterministic behavior across the entire test execution

## Generic Type System

CoreSim heavily uses Zig's compile-time generics to provide type safety while remaining flexible.

### Type Parameters

1. **OperationType**: User-defined enum for system operations
   ```zig
   const MyOps = enum { read, write, delete, compact };
   ```

2. **SystemType**: User-defined struct representing the system under test
   ```zig
   const MySystem = struct {
       // System state and methods
   };
   ```

### Generic Instantiation

```zig
// Framework types are instantiated with user types
const MyPropertyTest = PropertyTest(MyOps, MySystem);
const MyOperation = Operation(MyOps);
const MyInvariant = InvariantChecker(MySystem);
```

## Interface Design

### System Interface

Users must provide three interface functions:

```zig
// System lifecycle
system_init_fn: *const fn (allocator: std.mem.Allocator) anyerror!SystemType
system_deinit_fn: *const fn (system: *SystemType) void

// Operation execution
execute_operation_fn: *const fn (system: *SystemType, operation: Operation(OperationType)) anyerror!void
```

### Invariant Interface

```zig
InvariantChecker(SystemType) = struct {
    name: []const u8,
    check_fn: *const fn (system: *SystemType) bool,
    severity: InvariantSeverity,
}
```

### Filesystem Interface

```zig
FilesystemInterface = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    // VTable contains function pointers for all filesystem operations
}
```

## Data Flow

### Test Execution Flow

```
1. Initialize PropertyTest with configuration
2. For each iteration:
   a. Generate operation sequence
   b. Initialize system
   c. For each operation:
      - Check failure injection
      - Execute operation (if not failed)
      - Check invariants
   d. Record statistics
   e. Cleanup system
3. Report final statistics
```

### Shrinking Flow

```
1. Detect invariant violation
2. Clone failing sequence
3. While shrink attempts remain:
   a. Apply shrinking strategy
   b. Test shrunk sequence
   c. If still fails, adopt shrunk version
   d. If passes, discard shrunk version
4. Report minimal reproduction
```

### Failure Injection Flow

```
1. Operation requested
2. Look up base failure probability
3. Check current system condition
4. Apply conditional multipliers
5. Generate random number
6. Compare against effective probability
7. Inject failure or proceed
8. Record statistics
```

## Memory Management

### Allocation Strategy

- **User Responsibility**: Systems manage their own memory
- **Framework Responsibility**: Operations, sequences, and internal state
- **Clear Ownership**: All allocations have clear ownership boundaries

### Memory Safety

```zig
// Example of safe memory handling
fn generate_operation_sequence(self: *PropertyTest) ![]Operation {
    const sequence = try self.allocator.alloc(Operation, length);
    // Framework owns this allocation

    for (sequence) |*op| {
        op.key = try generateKey(); // Framework allocates
        op.value = try generateValue(); // Framework allocates
    }
    return sequence; // Caller must free via free_operation_sequence()
}
```

## Extensibility Points

### 1. Custom Generation Strategies

```zig
// Add new key generation strategies
pub const KeyGenerationStrategy = union(enum) {
    uniform_random: struct { min_length: usize, max_length: usize },
    collision_prone: struct { hash_collision_rate: f64 },
    sequential: struct { prefix: []const u8 },
    // Add your custom strategy here
    custom_pattern: YourCustomConfig,
};
```

### 2. Custom Failure Types

```zig
// Register application-specific failures
try failure_config.set_custom_probability(allocator, "cache_miss", 0.1);
try failure_config.set_custom_probability(allocator, "network_partition", 0.01);
```

### 3. Custom Shrinking Strategies

```zig
pub const ShrinkStrategy = enum {
    remove_operations,
    simplify_values,
    reduce_key_diversity,
    // Add your custom shrinking approach
    custom_domain_shrink,
};
```

### 4. Custom System Conditions

```zig
pub const SystemCondition = enum {
    during_recovery,
    under_memory_pressure,
    high_operation_rate,
    // Add your system-specific conditions
    during_replication,
    cache_warming,
};
```

## Performance Considerations

### 1. **Operation Generation**
- Pre-allocate sequences where possible
- Reuse key/value generation buffers
- Cache expensive computations

### 2. **Failure Injection**
- Fast random number generation
- Efficient condition lookup
- Minimal overhead in non-failure paths

### 3. **Memory Usage**
- Bounded sequence lengths
- Configurable shrinking limits
- Efficient cleanup in failure paths

### 4. **Parallelization Opportunities**
- Independent test iterations can run in parallel
- Shrinking attempts can be parallelized
- Statistics aggregation can be done concurrently

## Configuration Philosophy

CoreSim follows a "configuration over convention" approach where users configure all aspects of testing rather than relying on hidden defaults.

### Configuration Benefits

1. **Reproducibility**: All behavior is determined by explicit configuration
2. **Debuggability**: No hidden magic or implicit behavior
3. **Flexibility**: Every aspect can be customized for specific needs
4. **Clarity**: Test setup clearly shows what is being tested

### Configuration Validation

```zig
// Example configuration validation
pub fn validate(config: PropertyTest) !void {
    if (config.generators.sequence_length.min > config.generators.sequence_length.max) {
        return error.InvalidSequenceLength;
    }

    if (config.failure_config.allocator_failure_probability > 1.0) {
        return error.InvalidProbability;
    }

    // Additional validation...
}
```

## Error Handling Strategy

### 1. **Graceful Degradation**
- Failures during generation are reported but don't crash
- Invariant violations trigger shrinking, not immediate failure
- Filesystem errors are isolated and recoverable

### 2. **Clear Error Reporting**
- Detailed failure context
- Minimal reproduction cases
- Statistical summaries

### 3. **Fail-Fast for Configuration Errors**
- Invalid configurations detected at setup time
- Clear error messages for common mistakes
- Validation happens before expensive test execution

This architectural design enables CoreSim to be both powerful and flexible while maintaining the deterministic guarantees essential for effective simulation testing.
