const std = @import("std");

const ObjectString = @import("object.zig").ObjectString;
const Value = @import("value.zig").Value;
const GcAllocator = @import("gc-allocator.zig").GcAllocator;
const getHash = @import("fnv-hash.zig").getHash;

const Alignment = std.mem.Alignment;

var tombstone: ObjectString = .{
    .hash = 0,
    .object = .{ .type = .string },
    .str = &[_]u8{},
};

const tombstone_ref: *ObjectString = &tombstone;
const n_basis: usize = 16;
const united_memory_region_alignment = Alignment.max(Alignment.of(?*ObjectString), Alignment.of(Value));

pub const HashTable = struct {
    const HashTableError = error{RespaceFailure};

    const Entry = struct { key: ?*ObjectString, value: Value };

    capacity: usize,
    count: usize,
    tombstone_count: usize,
    keys: [*]?*ObjectString,
    values: [*]Value,

    pub fn init(alloc: std.mem.Allocator) !HashTable {
        return try initWithCap(alloc, n_basis);
    }

    pub fn initWithCap(alloc: std.mem.Allocator, capacity: comptime_int) HashTableError!HashTable {
        if (capacity <= 0 or (capacity & (capacity - 1) != 0)) {
            // Capacity of a power of 2
            // NOTE: ALIGNMENT TRICK IS MOST IMPORTANT
            // Facilitates to do multiple useful tricks
            // To slightly improve performance of some operations like:
            // Modulo, Multiplication and even index checks (dedupe for loops in get and insert (see prev commits));
            @compileError("HashTable capactity must be a power of 2");
        }

        const allocated = try allocUnitedMemoryRegion(alloc, capacity);

        return .{ .capacity = capacity, .count = 0, .tombstone_count = 0, .keys = allocated.keys, .values = allocated.values };
    }

    pub fn insert(self: *HashTable, alloc: std.mem.Allocator, key: *ObjectString, value: Value) HashTableError!void {
        var trailing_capacity = self.capacity - 1;
        var start_idx = key.hash & trailing_capacity;
        var first_tombstone_index: usize = self.capacity;
        var target_index = start_idx;
        var next_count = self.count;

        // Note that comparison here k == key, where both are *ObjectString
        // Is based on an assumption that all strings are internalized
        for (0..self.capacity) |idx| {
            const curr_idx = (start_idx + idx) & trailing_capacity;
            const curr_key = self.keys[curr_idx];

            if (curr_key) |k| {
                if (k == tombstone_ref and first_tombstone_index == self.capacity) {
                    first_tombstone_index = curr_idx;
                } else if (k != tombstone_ref and k == key) {
                    first_tombstone_index = self.capacity;
                    target_index = curr_idx;
                    break;
                }
            } else {
                next_count += 1;
                target_index = curr_idx;
                break;
            }
        }

        if (next_count > self.count and try self.respace(alloc, next_count)) {
            // Potentially can be changed after respacing
            trailing_capacity = self.capacity - 1;
            start_idx = key.hash & trailing_capacity;

            for (0..self.capacity) |idx| {
                const curr_idx = (start_idx + idx) & trailing_capacity;
                const curr_key = self.keys[curr_idx];

                if (curr_key == null) {
                    target_index = curr_idx;
                    break;
                }
            }
        } else if (first_tombstone_index != self.capacity) {
            target_index = first_tombstone_index;
            self.tombstone_count -= 1;
        }

        self.keys[target_index] = key;
        self.values[target_index] = value;
        self.count = next_count;
    }

    pub fn findValue(self: *HashTable, key: *ObjectString) ?Value {
        if (self.findIndex(key.hash, key.str)) |value_idx| {
            return self.values[@as(usize, value_idx)];
        }

        return null;
    }

    pub fn findKey(self: *HashTable, hash: u64, str: []const u8) ?*ObjectString {
        if (self.findIndex(hash, str)) |key_id| {
            return self.keys[@as(usize, key_id)];
        }

        return null;
    }

    pub fn remove(self: *HashTable, key: *ObjectString) void {
        if (self.findIndex(key.hash, key.str)) |value_idx| {
            self.keys[value_idx] = tombstone_ref;
            self.values[value_idx] = Value.with_nil;

            self.count -= 1;
            self.tombstone_count += 1;
        }
    }

    pub fn deinit(self: *HashTable, alloc: std.mem.Allocator) void {
        freeUnitedMemoryRegion(alloc, self.capacity, self.keys);

        self.capacity = 0;
        self.count = 0;
        self.tombstone_count = 0;
    }

    fn findIndex(self: *HashTable, hash: u64, key_str: []const u8) ?usize {
        const trailing_capacity = self.capacity - 1;
        const start_idx = hash & trailing_capacity;

        for (0..self.capacity) |idx| {
            const curr_idx = (start_idx + idx) & trailing_capacity;

            if (self.keys[curr_idx]) |curr_key| {
                if (curr_key != tombstone_ref and
                    key_str.len == curr_key.str.len and
                    hash == curr_key.hash and
                    std.mem.eql(u8, key_str, curr_key.str))
                {
                    return curr_idx;
                }
            } else {
                break;
            }
        }

        return null;
    }

    fn respace(self: *HashTable, alloc: std.mem.Allocator, next_count: usize) HashTableError!bool {
        // Approx ~0.75 of space
        const above_loading_factor = (next_count + self.tombstone_count) * 4 <= self.capacity * 3;

        if (above_loading_factor) {
            return false;
        }

        var new_count: usize = 0;
        const new_capacity = self.capacity << 1;
        const allocated = try allocUnitedMemoryRegion(alloc, new_capacity);

        const keys_ptr = allocated.keys;
        const values_ptr = allocated.values;

        const new_trailing_capacity = new_capacity - 1;

        for (self.keys[0..self.capacity], 0..) |key, k_idx| {
            if (key) |existing_key| {
                if (existing_key == tombstone_ref) continue;

                const start_idx = existing_key.hash & new_trailing_capacity;

                for (0..new_capacity) |idx| {
                    const corrected_idx = (start_idx + idx) & new_trailing_capacity;

                    if (keys_ptr[corrected_idx] == null) {
                        keys_ptr[corrected_idx] = key;
                        values_ptr[corrected_idx] = self.values[k_idx];
                        new_count += 1;

                        break;
                    }
                }
            }
        }

        freeUnitedMemoryRegion(alloc, self.capacity, self.keys);

        self.keys = keys_ptr;
        self.values = values_ptr;
        self.count = new_count;
        self.tombstone_count = 0;
        self.capacity = new_capacity;

        return true;
    }

    fn allocUnitedMemoryRegion(alloc: std.mem.Allocator, capacity: usize) HashTableError!struct { keys: [*]?*ObjectString, values: [*]Value } {
        const keys_size = capacity * @sizeOf(?*ObjectString);
        const values_size = capacity * @sizeOf(Value);
        const padded_keys_size = Alignment.of(Value).forward(keys_size);

        const keys_values_region = alloc.alignedAlloc(
            u8,
            united_memory_region_alignment,
            padded_keys_size + values_size,
        ) catch return HashTableError.RespaceFailure;

        const keys_ptr: [*]?*ObjectString = @ptrCast(@alignCast(keys_values_region.ptr));
        @memset(keys_ptr[0..capacity], null);

        const values_ptr: [*]Value = @ptrCast(@alignCast(keys_values_region.ptr + padded_keys_size));

        return .{ .keys = keys_ptr, .values = values_ptr };
    }

    fn freeUnitedMemoryRegion(alloc: std.mem.Allocator, capacity: usize, keys: [*]?*ObjectString) void {
        const keys_size = capacity * @sizeOf(?*ObjectString);
        const values_size = capacity * @sizeOf(Value);
        const padded_keys_size = Alignment.of(Value).forward(keys_size);
        const key_value_region_size = padded_keys_size + values_size;

        const key_value_region_ptr: [*]align(united_memory_region_alignment.toByteUnits()) u8 = @ptrCast(@alignCast(keys));

        alloc.free(key_value_region_ptr[0..key_value_region_size]);
    }
};

inline fn makeString(alloc: std.mem.Allocator, bytes: []const u8) !*ObjectString {
    return try ObjectString.concat(alloc, bytes, "");
}

fn findCollidingKeys(alloc: std.mem.Allocator, table: *HashTable) ![2]*ObjectString {
    var key1: ?*ObjectString = null;
    var key2: ?*ObjectString = null;
    var i: usize = 0;
    var buf: [16]u8 = undefined;

    while (key1 == null or key2 == null) : (i += 1) {
        const name = try std.fmt.bufPrint(&buf, "k_{d}", .{i});
        const k = try makeString(alloc, name);
        const idx = k.hash % table.capacity;
        if (idx == 0) {
            if (key1 == null) {
                key1 = k;
            } else if (key2 == null) {
                key2 = k;
            }
        }
    }
    return .{ key1.?, key2.? };
}

test "init starts with zero count" {
    const testing = std.testing;
    var gc = try GcAllocator.prepare(testing.allocator);
    const alloc = gc.allocator();
    defer gc.deinit();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    try testing.expectEqual(@as(usize, 0), table.count);
}

test "initWithCap creates an empty table with the requested capacity" {
    const testing = std.testing;
    var gc = try GcAllocator.prepare(testing.allocator);
    const alloc = gc.allocator();
    defer gc.deinit();

    var table = try HashTable.initWithCap(alloc, 2);
    defer table.deinit(alloc);

    try testing.expectEqual(@as(usize, 0), table.count);
    try testing.expectEqual(@as(usize, 2), table.capacity);
}

test "insert stores value for a new key" {
    const testing = std.testing;
    var gc = try GcAllocator.prepare(testing.allocator);
    const alloc = gc.allocator();
    defer gc.deinit();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    const key = try makeString(alloc, "username");
    const value = Value{ .val_number = 123.45 };

    try table.insert(alloc, key, value);

    const retrieved = table.findValue(key);
    try testing.expect(retrieved != null);
    try testing.expectEqual(value, retrieved.?);
}

test "insert increments count for a new key" {
    const testing = std.testing;
    var gc = try GcAllocator.prepare(testing.allocator);
    const alloc = gc.allocator();
    defer gc.deinit();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    const key = try makeString(alloc, "username");

    try table.insert(alloc, key, Value{ .val_number = 1.0 });

    try testing.expectEqual(@as(usize, 1), table.count);
}

test "insert updates value for an existing key" {
    const testing = std.testing;
    var gc = try GcAllocator.prepare(testing.allocator);
    const alloc = gc.allocator();
    defer gc.deinit();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    const key = try makeString(alloc, "theme");
    const original = Value{ .val_bool = true };
    const updated = Value{ .val_bool = false };

    try table.insert(alloc, key, original);
    try table.insert(alloc, key, updated);

    const retrieved = table.findValue(key);
    try testing.expect(retrieved != null);
    try testing.expectEqual(updated, retrieved.?);
}

test "insert does not change count when updating an existing key" {
    const testing = std.testing;
    var gc = try GcAllocator.prepare(testing.allocator);
    const alloc = gc.allocator();
    defer gc.deinit();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    const key = try makeString(alloc, "theme");

    try table.insert(alloc, key, Value{ .val_bool = true });
    try table.insert(alloc, key, Value{ .val_bool = false });

    try testing.expectEqual(@as(usize, 1), table.count);
}

test "find value returns null for a missing key" {
    const testing = std.testing;
    var gc = try GcAllocator.prepare(testing.allocator);
    const alloc = gc.allocator();
    defer gc.deinit();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    const key = try makeString(alloc, "nonexistent");

    const retrieved = table.findValue(key);

    try testing.expectEqual(null, retrieved);
}

test "find value retrieves value by content using a different object string" {
    const testing = std.testing;
    var gc = try GcAllocator.prepare(testing.allocator);
    const alloc = gc.allocator();
    defer gc.deinit();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    const key1 = try makeString(alloc, "shared_content");
    const key2 = try makeString(alloc, "shared_content");
    const value = Value{ .val_number = 99.0 };

    try table.insert(alloc, key1, value);

    const retrieved = table.findValue(key2);
    try testing.expect(retrieved != null);
    try testing.expectEqual(value, retrieved.?);
}

test "remove makes a key unretrievable" {
    const testing = std.testing;
    var gc = try GcAllocator.prepare(testing.allocator);
    const alloc = gc.allocator();
    defer gc.deinit();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    const key = try makeString(alloc, "temporary");
    try table.insert(alloc, key, Value{ .val_nil = {} });

    table.remove(key);

    try testing.expectEqual(null, table.findValue(key));
}

test "remove decrements count" {
    const testing = std.testing;
    var gc = try GcAllocator.prepare(testing.allocator);
    const alloc = gc.allocator();
    defer gc.deinit();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    const key = try makeString(alloc, "temporary");
    try table.insert(alloc, key, Value{ .val_nil = {} });

    table.remove(key);

    try testing.expectEqual(@as(usize, 0), table.count);
}

test "remove on a missing key is a no-op" {
    const testing = std.testing;
    var gc = try GcAllocator.prepare(testing.allocator);
    const alloc = gc.allocator();
    defer gc.deinit();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    const key = try makeString(alloc, "ghost");

    table.remove(key);

    try testing.expectEqual(@as(usize, 0), table.count);
}

test "remove on an already removed key is idempotent" {
    const testing = std.testing;
    var gc = try GcAllocator.prepare(testing.allocator);
    const alloc = gc.allocator();
    defer gc.deinit();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    const key = try makeString(alloc, "once");
    try table.insert(alloc, key, Value{ .val_number = 1.0 });

    table.remove(key);
    table.remove(key);

    try testing.expectEqual(@as(usize, 0), table.count);
    try testing.expectEqual(null, table.findValue(key));
}

test "insert restores a removed key" {
    const testing = std.testing;
    var gc = try GcAllocator.prepare(testing.allocator);
    const alloc = gc.allocator();
    defer gc.deinit();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    const key = try makeString(alloc, "reusable");
    const new_value = Value{ .val_number = 2.0 };

    try table.insert(alloc, key, Value{ .val_number = 1.0 });
    table.remove(key);
    try table.insert(alloc, key, new_value);

    const retrieved = table.findValue(key);
    try testing.expect(retrieved != null);
    try testing.expectEqual(new_value, retrieved.?);
}

test "insert restores count after reinserting a removed key" {
    const testing = std.testing;
    var gc = try GcAllocator.prepare(testing.allocator);
    const alloc = gc.allocator();
    defer gc.deinit();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    const key = try makeString(alloc, "reusable");

    try table.insert(alloc, key, Value{ .val_number = 1.0 });
    table.remove(key);
    try table.insert(alloc, key, Value{ .val_number = 2.0 });

    try testing.expectEqual(@as(usize, 1), table.count);
}

test "insert grows capacity when load factor is exceeded" {
    const testing = std.testing;
    var gc = try GcAllocator.prepare(testing.allocator);
    const alloc = gc.allocator();
    defer gc.deinit();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    const num_elements = 13;
    var buf: [16]u8 = undefined;
    for (0..num_elements) |i| {
        const name = try std.fmt.bufPrint(&buf, "item_{d}", .{i});
        const key = try makeString(alloc, name);
        try table.insert(alloc, key, Value{ .val_number = @floatFromInt(i) });
    }

    try testing.expect(table.capacity > 16);
}

test "insert preserves all entries after many insertions" {
    const testing = std.testing;
    var gc = try GcAllocator.prepare(testing.allocator);
    const alloc = gc.allocator();
    defer gc.deinit();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    const num_elements = 13;
    var keys = try alloc.alloc(*ObjectString, num_elements);
    defer alloc.free(keys);

    var buf: [16]u8 = undefined;
    for (0..num_elements) |i| {
        const name = try std.fmt.bufPrint(&buf, "item_{d}", .{i});
        keys[i] = try makeString(alloc, name);
        try table.insert(alloc, keys[i], Value{ .val_number = @floatFromInt(i) });
    }

    for (0..num_elements) |i| {
        const retrieved = table.findValue(keys[i]);
        try testing.expect(retrieved != null);
        try testing.expectEqual(Value{ .val_number = @floatFromInt(i) }, retrieved.?);
    }
}

test "insert at minimum capacity preserves all entries" {
    const testing = std.testing;
    var gc = try GcAllocator.prepare(testing.allocator);
    const alloc = gc.allocator();
    defer gc.deinit();

    var table = try HashTable.initWithCap(alloc, 2);
    defer table.deinit(alloc);

    const key1 = try makeString(alloc, "a");
    const key2 = try makeString(alloc, "b");

    try table.insert(alloc, key1, Value{ .val_number = 1.0 });
    try table.insert(alloc, key2, Value{ .val_number = 2.0 });

    const r1 = table.findValue(key1);
    const r2 = table.findValue(key2);
    try testing.expect(r1 != null);
    try testing.expect(r2 != null);
    try testing.expectEqual(Value{ .val_number = 1.0 }, r1.?);
    try testing.expectEqual(Value{ .val_number = 2.0 }, r2.?);
}

test "lookup finds colliding keys past a tombstone" {
    const testing = std.testing;
    var gc = try GcAllocator.prepare(testing.allocator);
    const alloc = gc.allocator();
    defer gc.deinit();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    const keys = try findCollidingKeys(alloc, &table);
    const val1 = Value{ .val_number = 1.0 };
    const val2 = Value{ .val_number = 2.0 };

    try table.insert(alloc, keys[0], val1);
    try table.insert(alloc, keys[1], val2);

    table.remove(keys[0]);

    const retrieved = table.findValue(keys[1]);
    try testing.expect(retrieved != null);
    try testing.expectEqual(val2, retrieved.?);
}

test "find key returns the interned key for matching content" {
    const testing = std.testing;
    var gc = try GcAllocator.prepare(testing.allocator);
    const alloc = gc.allocator();
    defer gc.deinit();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    const interned = try makeString(alloc, "shared");
    try table.insert(alloc, interned, Value{ .val_number = 1.0 });

    var probe_buf: [6]u8 = "shared".*;
    const probe = probe_buf[0..];

    const found = table.findKey(getHash(probe), probe);

    try testing.expect(found != null);
    try testing.expect(interned == found.?);
}

test "find key returns null for non-matching content" {
    const testing = std.testing;
    var gc = try GcAllocator.prepare(testing.allocator);
    const alloc = gc.allocator();
    defer gc.deinit();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    const interned = try makeString(alloc, "present");
    try table.insert(alloc, interned, Value{ .val_number = 1.0 });

    var probe_buf: [6]u8 = "absent".*;
    const probe = probe_buf[0..];

    try testing.expect(table.findKey(getHash(probe), probe) == null);
}

test "find key returns null for an empty table" {
    const testing = std.testing;
    var gc = try GcAllocator.prepare(testing.allocator);
    const alloc = gc.allocator();
    defer gc.deinit();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    var probe_buf: [6]u8 = "shared".*;
    const probe = probe_buf[0..];

    try testing.expect(table.findKey(getHash(probe), probe) == null);
}
