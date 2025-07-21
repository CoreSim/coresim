// ABOUTME: Simple 10-line examples showing CoreSim with diverse systems
// ABOUTME: Demonstrates easy adoption patterns for any type of system

const std = @import("std");
const coresim = @import("coresim");

// ============================================================================
// Example 1: HTTP-like Server
// ============================================================================

const HttpServer = struct {
    allocator: std.mem.Allocator,
    is_running: bool = false,
    request_count: u32 = 0,

    pub const Operation = enum { start, stop, handle_request, get_status };

    pub fn init(allocator: std.mem.Allocator) !@This() {
        return @This(){ .allocator = allocator };
    }

    pub fn deinit(self: *@This()) void {
        _ = self;
    }

    pub fn start(self: *@This()) !void {
        self.is_running = true;
    }
    pub fn stop(self: *@This()) void {
        self.is_running = false;
    }
    pub fn handle_request(self: *@This(), _: []const u8, _: []const u8) !void {
        if (self.is_running) self.request_count += 1;
    }
    pub fn get_status(self: *@This(), _: []const u8) ?[]const u8 {
        return if (self.is_running) "running" else "stopped";
    }

    pub fn checkConsistency(self: *@This()) bool {
        return self.request_count < 10000; // Sanity check
    }
};

pub fn testHttpServer(allocator: std.mem.Allocator) !void {
    const builder = coresim.TestBuilder(HttpServer){};
    try builder
        .operations(&[_]HttpServer.Operation{ .start, .handle_request, .get_status, .stop })
        .iterations(25)
        .sequence_length(10, 50)
        .invariant("consistency", HttpServer.checkConsistency, .critical)
        .run(allocator);
}

// ============================================================================
// Example 2: Queue System
// ============================================================================

const MessageQueue = struct {
    allocator: std.mem.Allocator,
    messages: std.ArrayList([]const u8),

    pub const Operation = enum { push, pop, peek, clear, size };

    pub fn init(allocator: std.mem.Allocator) !@This() {
        return @This(){
            .allocator = allocator,
            .messages = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        for (self.messages.items) |msg| self.allocator.free(msg);
        self.messages.deinit();
    }

    pub fn push(self: *@This(), _: []const u8, value: []const u8) !void {
        const owned = try self.allocator.dupe(u8, value);
        try self.messages.append(owned);
    }

    pub fn pop(self: *@This(), _: []const u8) bool {
        if (self.messages.items.len > 0) {
            const msg = self.messages.orderedRemove(0);
            self.allocator.free(msg);
            return true; // Successfully popped
        }
        return false; // Queue was empty
    }

    pub fn peek(self: *@This(), _: []const u8) ?[]const u8 {
        return if (self.messages.items.len > 0) self.messages.items[0] else null;
    }

    pub fn clear(self: *@This()) !void {
        for (self.messages.items) |msg| self.allocator.free(msg);
        self.messages.clearAndFree();
    }

    pub fn size(self: *@This(), _: []const u8) ?[]const u8 {
        // Return simple size indication based on actual queue state
        return if (self.messages.items.len == 0) "empty" else "has_items";
    }

    pub fn checkMemory(self: *@This()) bool {
        return self.messages.items.len < 1000;
    }
};

pub fn testMessageQueue(allocator: std.mem.Allocator) !void {
    const builder = coresim.TestBuilder(MessageQueue){};
    try builder
        .operations(&[_]MessageQueue.Operation{ .push, .pop, .peek, .clear })
        .iterations(100)
        .allocator_failures(0.001)
        .filesystem_errors(0.005)
        .invariant("memory", MessageQueue.checkMemory, .critical)
        .run(allocator);
}

// ============================================================================
// Example 3: State Machine
// ============================================================================

const TrafficLight = struct {
    state: enum { red, yellow, green } = .red,
    transition_count: u32 = 0,

    pub const Operation = enum { next, reset, get_state };

    pub fn init(allocator: std.mem.Allocator) !@This() {
        _ = allocator;
        return @This(){};
    }
    pub fn deinit(self: *@This()) void {
        _ = self;
    }

    pub fn next(self: *@This()) !void {
        self.state = switch (self.state) {
            .red => .green,
            .green => .yellow,
            .yellow => .red,
        };
        self.transition_count += 1;
    }

    pub fn reset(self: *@This()) void {
        self.state = .red;
        self.transition_count = 0;
    }

    pub fn get_state(self: *@This(), _: []const u8) ?[]const u8 {
        return switch (self.state) {
            .red => "red",
            .yellow => "yellow",
            .green => "green",
        };
    }

    pub fn validate(self: *@This()) bool {
        return self.transition_count < 10000;
    }
};

pub fn testTrafficLight(allocator: std.mem.Allocator) !void {
    const builder = coresim.TestBuilder(TrafficLight){};
    try builder
        .operations(&[_]TrafficLight.Operation{ .next, .get_state, .reset })
        .iterations(5)
        .sequence_length(5, 15)
        .seed(12345)
        .invariant("validation", TrafficLight.validate, .important)
        .run(allocator);
}

// ============================================================================
// Example 4: Cache System
// ============================================================================

const SimpleCache = struct {
    allocator: std.mem.Allocator,
    data: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    hit_count: u32 = 0,
    miss_count: u32 = 0,

    pub const Operation = enum { put, get, delete, stats, clear };

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
        if (self.data.get(key)) |value| {
            self.hit_count += 1;
            return value;
        }
        self.miss_count += 1;
        return null;
    }

    pub fn delete(self: *@This(), key: []const u8) bool {
        if (self.data.fetchRemove(key)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value);
            return true;
        }
        return false;
    }

    pub fn stats(self: *@This(), _: []const u8) ?[]const u8 {
        // Return simple stats based on actual cache state
        const total_requests = self.hit_count + self.miss_count;
        if (total_requests == 0) return "no_requests";
        return if (self.hit_count > self.miss_count) "mostly_hits" else "mostly_misses";
    }

    pub fn clear(self: *@This()) !void {
        var iterator = self.data.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.data.clearAndFree();
    }

    pub fn checkConsistency(self: *@This()) bool {
        return (self.hit_count + self.miss_count) < 100000;
    }
};

pub fn testSimpleCache(allocator: std.mem.Allocator) !void {
    const builder = coresim.TestBuilder(SimpleCache){};
    try builder
        .operations(&[_]SimpleCache.Operation{ .put, .get, .delete, .clear })
        .iterations(500)
        .sequence_length(100, 500)
        .allocator_failures(0.02)
        .filesystem_errors(0.01)
        .invariant("consistency", SimpleCache.checkConsistency, .critical)
        .run(allocator);
}

// ============================================================================
// Example 5: File Manager
// ============================================================================

const FileManager = struct {
    allocator: std.mem.Allocator,
    open_files: std.ArrayList([]const u8),

    pub const Operation = enum { open, close, read, write, list };

    pub fn init(allocator: std.mem.Allocator) !@This() {
        return @This(){
            .allocator = allocator,
            .open_files = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        for (self.open_files.items) |filename| self.allocator.free(filename);
        self.open_files.deinit();
    }

    pub fn open(self: *@This(), filename: []const u8, _: []const u8) !void {
        const owned = try self.allocator.dupe(u8, filename);
        try self.open_files.append(owned);
    }

    pub fn close(self: *@This(), filename: []const u8) bool {
        for (self.open_files.items, 0..) |file, i| {
            if (std.mem.eql(u8, file, filename)) {
                self.allocator.free(self.open_files.orderedRemove(i));
                return true;
            }
        }
        return false;
    }

    pub fn read(self: *@This(), filename: []const u8) ?[]const u8 {
        _ = self;
        _ = filename;
        return "file_data";
    }
    pub fn write(self: *@This(), filename: []const u8, data: []const u8) !void {
        _ = self;
        _ = filename;
        _ = data;
    }
    pub fn list(self: *@This(), _: []const u8) ?[]const u8 {
        _ = self;
        return "file_list";
    }

    pub fn checkMemory(self: *@This()) bool {
        return self.open_files.items.len < 100;
    }
};

pub fn testFileManager(allocator: std.mem.Allocator) !void {
    const builder = coresim.TestBuilder(FileManager){};
    try builder
        .operations(&[_]FileManager.Operation{ .open, .read, .write, .close })
        .iterations(100)
        .allocator_failures(0.001)
        .filesystem_errors(0.005)
        .invariant("memory", FileManager.checkMemory, .critical)
        .run(allocator);
}

// ============================================================================
// Example 6: Counter System (Minimal)
// ============================================================================

const Counter = struct {
    value: i32 = 0,

    pub const Operation = enum { increment, decrement, reset, get };

    pub fn init(allocator: std.mem.Allocator) !@This() {
        _ = allocator;
        return @This(){};
    }
    pub fn deinit(self: *@This()) void {
        _ = self;
    }

    pub fn increment(self: *@This()) !void {
        self.value += 1;
    }
    pub fn decrement(self: *@This()) !void {
        self.value -= 1;
    }
    pub fn reset(self: *@This()) void {
        self.value = 0;
    }
    pub fn get(self: *@This(), _: []const u8) ?[]const u8 {
        // Return simple value indication based on actual counter state
        if (self.value == 0) return "zero";
        return if (self.value > 0) "positive" else "negative";
    }

    pub fn validate(self: *@This()) bool {
        return self.value > -1000 and self.value < 1000;
    }
};

pub fn testCounter(allocator: std.mem.Allocator) !void {
    const builder = coresim.TestBuilder(Counter){};
    try builder
        .operations(&[_]Counter.Operation{ .increment, .decrement, .get, .reset })
        .iterations(25)
        .sequence_length(10, 50)
        .invariant("validation", Counter.validate, .important)
        .run(allocator);
}

// ============================================================================
// Run All Examples
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== CoreSim Simple Examples ===\n\n", .{});

    std.debug.print("1. Testing HTTP Server...\n", .{});
    try testHttpServer(allocator);
    std.debug.print("   ✓ HTTP Server test passed!\n\n", .{});

    std.debug.print("2. Testing Message Queue...\n", .{});
    try testMessageQueue(allocator);
    std.debug.print("   ✓ Message Queue test passed!\n\n", .{});

    std.debug.print("3. Testing Traffic Light State Machine...\n", .{});
    try testTrafficLight(allocator);
    std.debug.print("   ✓ Traffic Light test passed!\n\n", .{});

    std.debug.print("4. Testing Simple Cache...\n", .{});
    try testSimpleCache(allocator);
    std.debug.print("   ✓ Simple Cache test passed!\n\n", .{});

    std.debug.print("5. Testing File Manager...\n", .{});
    try testFileManager(allocator);
    std.debug.print("   ✓ File Manager test passed!\n\n", .{});

    std.debug.print("6. Testing Counter...\n", .{});
    try testCounter(allocator);
    std.debug.print("   ✓ Counter test passed!\n\n", .{});

    std.debug.print("🎉 All simple examples passed!\n", .{});
    std.debug.print("\nThese examples show CoreSim testing:\n", .{});
    std.debug.print("• Network services (HTTP server)\n", .{});
    std.debug.print("• Data structures (queue, cache)\n", .{});
    std.debug.print("• State machines (traffic light)\n", .{});
    std.debug.print("• File systems (file manager)\n", .{});
    std.debug.print("• Simple counters\n", .{});
    std.debug.print("\nEach example is ~10 lines and shows different testing approaches!\n", .{});
}
