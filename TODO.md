# CoreSim - Non-Idiomatic Zig Code TODO

This document lists non-idiomatic Zig patterns found in the codebase that should be addressed to improve code quality and follow Zig conventions.

## High Priority Issues

### 1. Naming Convention Violations (snake_case required)

#### Function Names (camelCase → snake_case)
- `core.zig:16` - `shouldInjectCustomFailure` → `should_inject_custom_failure`
- `core.zig:39` - `shouldInjectNetworkError` → `should_inject_network_error`
- `core.zig:60` - `setSystemCondition` → `set_system_condition`
- `core.zig:65` - `getSystemCondition` → `get_system_condition`
- `failure_injection.zig:43` - `getEffectiveProbability` → `get_effective_probability`
- `failure_injection.zig:58` - `getCustomProbability` → `get_custom_probability`
- `failure_injection.zig:63` - `setCustomProbability` → `set_custom_probability`
- `failure_injection.zig:212` - `recordCustomFailure` → `record_custom_failure`
- `property_testing.zig:245` - `recordCall` → `record_call`
- `property_testing.zig:252` - `averageTime` → `average_time`
- `property_testing.zig:288` - `recordOperation` → `record_operation`
- `property_testing.zig:297` - `setIntendedWeight` → `set_intended_weight`
- `property_testing.zig:425` - `recordOperationTiming` → `record_operation_timing`
- `property_testing.zig:440` - `recordOperationCall` → `record_operation_call`
- `property_testing.zig:445` - `setIntendedOperationWeight` → `set_intended_operation_weight`
- `property_testing.zig:450` - `recordFailureRate` → `record_failure_rate`

#### Method Names in Multiple Files
- ✅ **COMPLETED**: All `with*` methods in `core.zig` builder pattern updated to snake_case
- ✅ **COMPLETED**: `easy.zig` removed - consolidated into single TestBuilder implementation

### 2. Complex Type Patterns to Simplify

#### Type-Erased Storage (core.zig:77-119)
- `OpWeightStorage` adds unnecessary complexity
- Consider using simpler generic approaches instead of type erasure
- `CustomFailureStorage` has similar issues

#### Large Function Decomposition
- `core.zig:317-448` - `TestBuilder.runWithStats()` is too large (130+ lines)
- Break into smaller, focused functions:
  - Setup failure injection
  - Setup operation distribution  
  - Setup invariants
  - Execute test run

## Medium Priority Issues

### 3. Memory Management Improvements

#### Defer Usage
- `property_testing.zig:651-656` - Manual cleanup should use defer consistently
- Better lifetime management in test generation functions

#### Error Handling Patterns
- `core.zig:25-28` - Errors caught but ignored without logging
- `property_testing.zig:702-707` - Silent error handling in statistics recording
- Consider adding proper error logging or bubbling

### 4. Code Organization

#### Mixed Abstraction Levels
- ✅ **COMPLETED**: `easy.zig` removed - abstraction levels now cleanly separated
- Concerns properly separated between core.zig (TestBuilder) and reflection.zig

#### Generic Function Complexity
- Some comptime generic functions could be simplified
- Overuse of reflection where simpler approaches would work

## Low Priority Issues

### 5. Naming Consistency

#### Struct Field Naming
- Some structs use camelCase fields, should standardize on snake_case
- Enum variant naming should be consistent across the codebase

#### Function Prefix Patterns
- Avoid `get_*` and `set_*` prefixes where more descriptive names work better
- Use action verbs for function names where appropriate

## Implementation Notes

### Naming Convention Migration
1. Start with public API functions first
2. Update tests to match new function names
3. Ensure all examples and documentation are updated
4. Consider adding deprecated aliases during transition

### Type Simplification
1. Evaluate if type erasure is actually needed
2. Consider compile-time solutions over runtime type erasure
3. Benchmark performance impact of changes

### Function Decomposition Strategy
1. Extract setup functions from large test runners
2. Use clear parameter passing instead of large struct configs
3. Maintain backward compatibility during refactoring

## Files Requiring Updates
- `src/core.zig` - ✅ **COMPLETED**: Builder API updated to snake_case, single TestBuilder implementation
- ~~`src/easy.zig`~~ - ✅ **COMPLETED**: File removed, functionality consolidated into core.zig
- `src/failure_injection.zig` - Method renaming (still needed)
- `src/property_testing.zig` - Extensive naming updates (still needed)
- `examples/*.zig` - ✅ **COMPLETED**: Updated to use new function names
- Tests - ✅ **COMPLETED**: All test calls updated to new naming

## Completion Criteria
- [ ] All public functions use snake_case naming
- [ ] No functions longer than 50 lines
- [ ] Consistent error handling patterns
- [ ] Simplified type patterns where possible
- [ ] All tests pass with new naming
- [ ] Documentation updated to reflect changes