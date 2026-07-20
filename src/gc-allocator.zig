const std = @import("std");

const objects = @import("object.zig");
const HashTable = @import("hash-table.zig").HashTable;
const getHash = @import("fnv-hash.zig").getHash;

const Object = objects.Object;
const ObjectString = objects.ObjectString;

pub const GcAllocator = struct {
    internalized_strings: HashTable,
    inner_allocator: std.mem.Allocator,
    object_pool: ?*Object,

    pub fn prepare(inner_alloc: std.mem.Allocator) !GcAllocator {
        return .{ .internalized_strings = try .init(inner_alloc), .inner_allocator = inner_alloc, .object_pool = null };
    }

    pub fn allocator(self: *GcAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    pub fn concatFromSlices(self: *GcAllocator, a: []const u8, b: []const u8) !*ObjectString {
        const concat_str = try self.inner_allocator.alloc(u8, a.len + b.len);

        @memcpy(concat_str[0..a.len], a);
        @memcpy(concat_str[a.len..], b);

        const hash = getHash(concat_str);

        if (self.internalized_strings.findKey(hash, concat_str)) |internalized| {
            self.inner_allocator.free(concat_str);

            return internalized;
        }

        const obj_string = try self.createObjectString();

        obj_string.hash = hash;
        obj_string.str = concat_str;

        try self.internalized_strings.insert(self.inner_allocator, obj_string, .val_nil);

        return obj_string;
    }

    pub fn dupeFromSlice(self: *GcAllocator, a: []const u8) !*ObjectString {
        const dupe_str = try self.inner_allocator.alloc(u8, a.len);
        @memcpy(dupe_str[0..a.len], a);

        const hash = getHash(dupe_str);

        if (self.internalized_strings.findKey(hash, dupe_str)) |internalized| {
            self.inner_allocator.free(dupe_str);

            return internalized;
        }

        const obj_string = try self.createObjectString();
        obj_string.hash = hash;
        obj_string.str = dupe_str;

        try self.internalized_strings.insert(self.inner_allocator, obj_string, .val_nil);

        return obj_string;
    }

    pub fn destroyObject(self: *GcAllocator, obj: *Object) void {
        self.removeFromObjectPool(obj);
        self.destroyObjectInternal(obj);
    }

    pub fn freeObjects(self: *GcAllocator) void {
        var curr: ?*Object = self.object_pool;

        if (curr == null) {
            return;
        }

        while (curr) |safe_curr| {
            const next = safe_curr.next;
            self.destroyObjectInternal(safe_curr);
            curr = next;
        }
    }

    pub fn as(target_alloc: std.mem.Allocator) *GcAllocator {
        return @ptrCast(@alignCast(target_alloc.ptr));
    }

    pub fn deinit(self: *GcAllocator) void {
        self.internalized_strings.deinit(self.inner_allocator);
        self.freeObjects();
    }

    fn createObjectString(self: *GcAllocator) !*ObjectString {
        const obj_str = try self.inner_allocator.create(ObjectString);

        obj_str.* = .{ .hash = 0, .object = .{ .type = .string }, .str = undefined };

        self.addObjectToPool(&obj_str.object);

        return obj_str;
    }

    fn addObjectToPool(self: *GcAllocator, obj: *Object) void {
        const pool_head = self.object_pool;

        obj.next = pool_head;
        self.object_pool = obj;
    }

    fn removeFromObjectPool(self: *GcAllocator, obj: *Object) void {
        var curr: ?*Object = self.object_pool;
        var prev: ?*Object = null;

        if (curr == null) {
            return;
        }

        while (curr) |safe_curr| {
            if (safe_curr == obj) {
                break;
            }

            prev = safe_curr;
            curr = safe_curr.next;
        }

        if (prev) |p| {
            p.next = curr.?.next;
        } else {
            self.object_pool = curr.?.next;
        }
    }

    fn destroyObjectInternal(self: *GcAllocator, obj: *Object) void {
        switch (obj.type) {
            .string => {
                const obj_str = obj.as(ObjectString);

                self.inner_allocator.free(obj_str.str);
                self.inner_allocator.destroy(obj_str);
            },
        }
    }

    // Allocator specifics

    fn alloc(ctx: *anyopaque, n: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *GcAllocator = @ptrCast(@alignCast(ctx));

        return self.inner_allocator.rawAlloc(n, alignment, ra);
    }

    fn resize(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *GcAllocator = @ptrCast(@alignCast(ctx));

        return self.inner_allocator.rawResize(buf, alignment, new_len, ret_addr);
    }

    fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) ?[*]u8 {
        const self: *GcAllocator = @ptrCast(@alignCast(context));

        return self.inner_allocator.rawRemap(memory, alignment, new_len, return_address);
    }

    fn free(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *GcAllocator = @ptrCast(@alignCast(ctx));

        return self.inner_allocator.rawFree(buf, alignment, ret_addr);
    }
};
