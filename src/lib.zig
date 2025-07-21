// ABOUTME: Main library module for CoreSim deterministic simulation framework
// ABOUTME: Exports all public APIs for property testing, failure injection, and filesystem simulation

const std = @import("std");

pub const property_testing = @import("property_testing.zig");
pub const filesystem = @import("filesystem.zig");
pub const failure_injection = @import("failure_injection.zig");

// Core ergonomic API for minimal boilerplate
pub const core = @import("core.zig");

// Separated concerns for cleaner architecture
pub const reflection = @import("reflection.zig"); // Comptime method discovery utilities
pub const auto_test = @import("auto_test.zig"); // Automatic test generation and convenience functions

// Core API exports - TestBuilder only for clean, standardized API
pub const TestBuilder = core.TestBuilder;
pub const OpWeight = core.OpWeight;
pub const CustomFailure = core.CustomFailure;
pub const should_inject_custom_failure = core.should_inject_custom_failure;
pub const should_inject_network_error = core.should_inject_network_error;
pub const set_system_condition = core.set_system_condition;
pub const current_system_condition = core.current_system_condition;
pub const SystemCondition = failure_injection.SystemCondition;
pub const ConditionalMultiplier = failure_injection.ConditionalMultiplier;

test {
    std.testing.refAllDecls(@This());
}
