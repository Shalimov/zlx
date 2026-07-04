const std = @import("std");

const GcAllocator = @import("gc-allocator.zig").GcAllocator;

pub const ObjectType = enum(u4) {
    string,
};

pub const Object = struct {
    type: ObjectType,
    next: ?*Object = null,

    pub fn as(self: *Object, comptime T: type) *T {
        return @fieldParentPtr("object", self);
    }

    pub fn equals(self: *Object, other: *Object) bool {
        if (self.type != other.type) return false;

        return switch (self.type) {
            .string => {
                const self_obj_str = self.as(ObjectString);
                const other_obj_str = other.as(ObjectString);

                return self_obj_str.str.len == other_obj_str.str.len and
                    std.mem.eql(u8, self_obj_str.str, other_obj_str.str);
            },
        };
    }
};

pub const ObjectString = struct {
    object: Object,
    str: []u8,

    pub fn concat(alloc: std.mem.Allocator, a: []const u8, b: []const u8) !*ObjectString {
        const gc_alloc = GcAllocator.as(alloc);
        const obj_str = try gc_alloc.createObjectString(a.len + b.len);

        @memcpy(obj_str.str[0..a.len], a);
        @memcpy(obj_str.str[a.len..], b);

        return obj_str;
    }

    pub fn dupe(alloc: std.mem.Allocator, slice: []const u8) !*ObjectString {
        const gc_alloc = GcAllocator.as(alloc);
        const obj_str = try gc_alloc.createObjectString(slice.len - 2);

        @memcpy(obj_str.str, slice[1 .. slice.len - 1]);

        return obj_str;
    }

    pub fn asObject(self: *ObjectString) *Object {
        return &self.object;
    }

    pub fn deinit(self: *ObjectString, alloc: std.mem.Allocator) void {
        const gc_alloc = GcAllocator.as(alloc);

        gc_alloc.destroyObject(self);
    }
};
