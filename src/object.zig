const std = @import("std");

const getHash = @import("fnv-hash.zig").getHash;
const GcAllocator = @import("gc-allocator.zig").GcAllocator;
const Chunk = @import("chunk.zig").Chunk;

pub const ObjectType = enum(u4) {
    string,
    function,
};

pub const Object = struct {
    next: ?*Object = null,
    type: ObjectType,

    pub fn as(self: *Object, comptime T: type) *T {
        return @fieldParentPtr("object", self);
    }

    pub fn equals(self: *Object, other: *Object) bool {
        if (self.type != other.type) return false;

        switch (self.type) {
            .string => {
                const self_obj_str = self.as(ObjectString);
                const other_obj_str = other.as(ObjectString);

                return self_obj_str.str.len == other_obj_str.str.len and std.mem.eql(u8, self_obj_str.str, other_obj_str.str);
            },
            .function => {
                return self == other;
            },
        }
    }
};

pub const ObjectString = struct {
    hash: u64,
    object: Object,
    str: []u8,

    pub fn concat(alloc: std.mem.Allocator, a: []const u8, b: []const u8) !*ObjectString {
        const gc_alloc = GcAllocator.from(alloc);

        return gc_alloc.concatFromSlices(a, b);
    }

    pub fn dupe(alloc: std.mem.Allocator, slice: []const u8) !*ObjectString {
        const gc_alloc = GcAllocator.from(alloc);

        return gc_alloc.dupeFromSlice(slice);
    }

    pub fn asObject(self: *ObjectString) *Object {
        return &self.object;
    }
};

pub const ObjectFunction = struct {
    object: Object,
    arity: usize = 0,
    body: Chunk = .init,
    name: ?*ObjectString = null,

    pub fn asObject(self: *ObjectFunction) *Object {
        return &self.object;
    }
};
