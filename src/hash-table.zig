// TODO: Optimizations & Design Considerations:
//
// 1. Resizing on Updates (Avoid Premature Growth):
//    Currently, `insert` calls `respace(alloc, self.count + 1)` upfront. If the key already exists (an update),
//    the count will not actually increase, but we may have already triggered an unnecessary and expensive resize.
//
//    - Reconsideration: Run the search loop first. If the key is found, update it in-place and return.
//      If it is not found, check the load factor. If a resize is needed, resize and then perform a second
//      probe in the newly sized table. Although this requires a second probe during resizes, resizing is
//      rare (amortized O(1)), making the fast path (updates and normal insertions) more efficient and
//      preventing unnecessary table growth.
//
// 2. Tombstone Reuse Metadata:
//    When a tombstone is reused during insertion, `self.tombstone_count` is decremented and `self.count` is
//    incremented. Since the load factor check includes `next_count + self.tombstone_count`, reusing
//    a tombstone keeps this sum constant, meaning a tombstone-reusing insertion will never trigger a resize.
//    By doing the search first, we can leverage this to skip the resize check entirely when reusing a tombstone.
//
// 3. Table Shrinking on Removal:
//    Currently, the table only grows. If many entries are added and then removed, the table remains at
//    its peak size with a high tombstone count. Reconsider adding support for shrinking the table (e.g.,
//    halving the capacity) when the active count drops below a certain threshold (like 12.5% of capacity).
//
// -- Extra --
//
// 4. Power-of-2 Bitwise Masking (Modulo Optimization):
//    Because capacity is a power of two, replace `key.hash % self.capacity` with
//    `key.hash & (self.capacity - 1)` to eliminate expensive division instructions.
//
// 5. Unified Bit-Mask Probe Loop:
//    Replace the split `for` loops with a single loop from `0..self.capacity` using
//    `idx = (start_idx + i) & (self.capacity - 1)` to reduce branch mispredictions.
//
// 6. Memory Safety and Allocation Inversion:
//    In Zig, pass slice `[]?Entry` instead of tracking separate `.capacity` and raw `.entries`
//    pointers to make `entries.len` self-tracking. In `respace`, free the old slice *before* //    allocating the new one if temporary copies aren't required, mitigating transient OOM.
//
// 7. Integer Math Load Factor Check:
//    Avoid `usize` to `f16` runtime casting overhead. Since `loading_factor` is `0.75`,
//    use the integer expression: `if ((next_count + self.tombstone_count) * 4 > self.capacity * 3)`.
//
// 8. Hash Collision Safeguard / Interning Shortcut:
//    Comparing only `entry.key.?.hash == key.hash` risks silent collision corruption.
//    Add `std.mem.eql(u8, ...)` verification. If utilizing a strict string-interned VM,
//    bypass string data comparison entirely via pointer equality: `ptr == key.bytes.ptr`.
//
// 9. Struct Field Alignment and Packing:
//    Reorder fields in `Entry` by alignment size (largest to smallest) to strip compiler padding,
//    shrinking cache-line footprint during linear probing. Remove unnecessary nested optionals.
//
const std = @import("std");

const ObjectString = @import("object.zig").ObjectString;
const Value = @import("value.zig").Value;
const GcAllocator = @import("gc-allocator.zig").GcAllocator;

const HashTable = struct {
    const HashTableError = error{
        RespaceFailure,
        InsertFailure,
    };

    const n_basis: usize = 16;
    const loading_factor: f16 = 0.75;

    const Entry = struct { key: ?ObjectString, value: Value, tombstone: bool };

    capacity: usize,
    count: usize,
    tombstone_count: usize,
    entries: [*]?Entry,

    pub fn init(alloc: std.mem.Allocator) !HashTable {
        return try initWithCap(alloc, n_basis);
    }

    pub fn initWithCap(alloc: std.mem.Allocator, capacity: comptime_int) !HashTable {
        if (capacity <= 0 or (capacity & (capacity - 1) != 0)) {
            @compileError("HashTable capactity must be a power of 2");
        }

        const entries = try alloc.alloc(?Entry, capacity);
        @memset(entries, null);

        return .{
            .capacity = capacity,
            .count = 0,
            .tombstone_count = 0,
            .entries = entries.ptr,
        };
    }

    pub fn insert(self: *HashTable, alloc: std.mem.Allocator, key: ObjectString, value: Value) HashTableError!void {
        try self.respace(alloc, self.count + 1);

        const start_idx = key.hash % self.capacity;

        var first_tombstone_index: usize = self.capacity;
        var target_index = start_idx;
        var next_count = self.count;

        for (start_idx..self.capacity) |idx| {
            const entry = self.entries[idx];

            if (entry == null) {
                next_count += 1;
                target_index = idx;
                break;
            } else if (first_tombstone_index == self.capacity and entry.?.tombstone) {
                first_tombstone_index = idx;
            } else if (!entry.?.tombstone and entry.?.key.?.hash == key.hash) {
                first_tombstone_index = self.capacity;
                target_index = idx;
                break;
            }
        } else {
            for (0..start_idx) |idx| {
                const entry = self.entries[idx];

                if (entry == null) {
                    next_count += 1;
                    target_index = idx;
                    break;
                } else if (first_tombstone_index == self.capacity and entry.?.tombstone) {
                    first_tombstone_index = idx;
                } else if (!entry.?.tombstone and entry.?.key.?.hash == key.hash) {
                    first_tombstone_index = self.capacity;
                    target_index = idx;
                    break;
                }
            }
        }

        if (first_tombstone_index != self.capacity) {
            target_index = first_tombstone_index;
            self.tombstone_count -= 1;
        }

        self.entries[target_index] = .{ .key = key, .value = value, .tombstone = false };
        self.count = next_count;
    }

    pub fn get(self: *HashTable, key: ObjectString) ?Value {
        if (self.getEntry(key)) |entry| {
            return if (entry.tombstone) null else entry.value;
        }

        return null;
    }

    pub fn remove(self: *HashTable, key: ObjectString) void {
        if (self.getEntry(key)) |*entry| {
            entry.*.tombstone = true;
            entry.*.key = null;
            entry.*.value = Value.with_nil;

            self.count -= 1;
            self.tombstone_count += 1;
        }
    }

    fn getEntry(self: *HashTable, key: ObjectString) ?*Entry {
        const start_idx = key.hash % self.capacity;

        for (start_idx..self.capacity) |idx| {
            if (self.entries[idx]) |*solid_entry| {
                if (!solid_entry.tombstone and solid_entry.key.?.hash == key.hash) {
                    return solid_entry;
                }
            } else break;
        } else {
            for (0..start_idx) |idx| {
                if (self.entries[idx]) |*solid_entry| {
                    if (!solid_entry.tombstone and solid_entry.key.?.hash == key.hash) {
                        return solid_entry;
                    }
                } else break;
            }
        }

        return null;
    }

    fn respace(self: *HashTable, alloc: std.mem.Allocator, next_count: usize) HashTableError!void {
        if (@as(f16, @as(f16, @floatFromInt(next_count + self.tombstone_count)) / @as(f16, @floatFromInt(self.capacity))) <= loading_factor) {
            return;
        }

        var new_count: usize = 0;
        const new_capacity = self.capacity << 1;
        const new_entries = alloc.alloc(?Entry, new_capacity) catch return HashTableError.RespaceFailure;

        @memset(new_entries, null);

        for (self.entries[0..self.capacity]) |entry| {
            if (entry != null and !entry.?.tombstone) {
                const start_idx = entry.?.key.?.hash % new_capacity;

                for (start_idx..new_capacity) |jdx| {
                    if (new_entries[jdx] == null) {
                        new_entries[jdx] = entry;
                        new_count += 1;
                        break;
                    }
                } else {
                    for (0..start_idx) |jdx| {
                        if (new_entries[jdx] == null) {
                            new_entries[jdx] = entry;
                            new_count += 1;
                            break;
                        }
                    }
                }
            }
        }

        const old_entries = self.entries;
        const old_capacity = self.capacity;

        self.entries = new_entries.ptr;
        self.count = new_count;
        self.tombstone_count = 0;
        self.capacity = new_capacity;

        alloc.free(old_entries[0..old_capacity]);
    }

    // Hint: If the capacity is not correctly tracked or updated after a resize,
    // does the slice size passed to free match the size of the allocated memory?
    pub fn deinit(self: *HashTable, alloc: std.mem.Allocator) void {
        alloc.free(self.entries[0..self.capacity]);
        self.capacity = 0;
        self.count = 0;
        self.tombstone_count = 0;
    }
};

inline fn makeString(alloc: std.mem.Allocator, bytes: []const u8) !ObjectString {
    const obj_str = try ObjectString.concat(alloc, bytes, "");
    return obj_str.*;
}

test "initializes with default capacity and zero count" {
    // Arrange
    const testing = std.testing;
    var gc = GcAllocator.init(testing.allocator);
    const alloc = gc.allocator();
    defer gc.freeObjects();

    // Act
    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    // Assert
    try testing.expectEqual(@as(usize, 0), table.count);
    try testing.expectEqual(@as(usize, 0), table.tombstone_count);
    try testing.expectEqual(@as(usize, 16), table.capacity);
}

test "inserts new key and retrieves it" {
    // Arrange
    const testing = std.testing;
    var gc = GcAllocator.init(testing.allocator);
    const alloc = gc.allocator();
    defer gc.freeObjects();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    const key = try makeString(alloc, "username");
    const value = Value{ .val_number = 123.45 };

    // Act
    try table.insert(alloc, key, value);

    // Assert
    const retrieved = table.get(key);
    try testing.expect(retrieved != null);
    try testing.expectEqual(value, retrieved.?);
    try testing.expectEqual(@as(usize, 1), table.count);
}

test "updates value of existing key without changing count" {
    // Arrange
    const testing = std.testing;
    var gc = GcAllocator.init(testing.allocator);
    const alloc = gc.allocator();
    defer gc.freeObjects();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    const key = try makeString(alloc, "theme");
    const original_value = Value{ .val_bool = true };
    const updated_value = Value{ .val_bool = false };

    try table.insert(alloc, key, original_value);

    // Act
    try table.insert(alloc, key, updated_value);

    // Assert
    const retrieved = table.get(key);
    try testing.expect(retrieved != null);
    try testing.expectEqual(updated_value, retrieved.?);
    try testing.expectEqual(@as(usize, 1), table.count);
}

test "returns null for non-existent key" {
    // Arrange
    const testing = std.testing;
    var gc = GcAllocator.init(testing.allocator);
    const alloc = gc.allocator();
    defer gc.freeObjects();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    const key = try makeString(alloc, "nonexistent");

    // Act
    const retrieved = table.get(key);

    // Assert
    try testing.expectEqual(null, retrieved);
}

test "makes key unretrievable and decrements count" {
    // Arrange
    const testing = std.testing;
    var gc = GcAllocator.init(testing.allocator);
    const alloc = gc.allocator();
    defer gc.freeObjects();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    const key = try makeString(alloc, "temporary");
    const value = Value{ .val_nil = {} };
    try table.insert(alloc, key, value);

    // Act
    table.remove(key);

    // Assert
    const retrieved = table.get(key);
    try testing.expectEqual(null, retrieved);
    try testing.expectEqual(@as(usize, 0), table.count);
    try testing.expectEqual(@as(usize, 1), table.tombstone_count);
}

test "preserves lookup chain of colliding keys past tombstones" {
    // Arrange
    const testing = std.testing;
    var gc = GcAllocator.init(testing.allocator);
    const alloc = gc.allocator();
    defer gc.freeObjects();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    // Dynamically find two keys that hash to the exact same bucket.
    var key1: ?ObjectString = null;
    var key2: ?ObjectString = null;
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

    const val1 = Value{ .val_number = 1.0 };
    const val2 = Value{ .val_number = 2.0 };

    try table.insert(alloc, key1.?, val1);
    try table.insert(alloc, key2.?, val2); // Collides and probes to next slot

    // Act
    table.remove(key1.?); // Marks slot as tombstone

    // Assert
    // We should still find key2.? past the tombstone of key1.?
    const retrieved2 = table.get(key2.?);
    try testing.expect(retrieved2 != null);
    try testing.expectEqual(val2, retrieved2.?);
}

test "resizes table and preserves all elements when load factor is exceeded" {
    // Arrange
    const testing = std.testing;
    var gc = GcAllocator.init(testing.allocator);
    const alloc = gc.allocator();
    defer gc.freeObjects();

    var table = try HashTable.init(alloc);
    defer table.deinit(alloc);

    // Initial capacity is 16. With load factor 0.75, inserting 13 elements should trigger resize.
    const num_elements = 13;
    var keys = try alloc.alloc(ObjectString, num_elements);
    defer alloc.free(keys);

    var buf: [16]u8 = undefined;
    for (0..num_elements) |i| {
        const name = try std.fmt.bufPrint(&buf, "item_{d}", .{i});
        keys[i] = try makeString(alloc, name);
    }

    // Act
    for (0..num_elements) |i| {
        try table.insert(alloc, keys[i], Value{ .val_number = @floatFromInt(i) });
    }

    // Assert
    try testing.expect(table.capacity > 16);
    try testing.expectEqual(@as(usize, num_elements), table.count);

    // All inserted elements must still be retrievable and correct.
    for (0..num_elements) |i| {
        const retrieved = table.get(keys[i]);
        try testing.expect(retrieved != null);
        try testing.expectEqual(Value{ .val_number = @floatFromInt(i) }, retrieved.?);
    }
}
