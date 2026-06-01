const std = @import("std");

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
        const obj_str = try alloc.create(ObjectString);
        const resulted_str = try alloc.alloc(u8, a.len + b.len);

        @memcpy(resulted_str[0..a.len], a);
        @memcpy(resulted_str[a.len..], b);

        obj_str.* = .{ .object = .{ .type = .string }, .str = resulted_str };

        return obj_str;
    }

    pub fn dupe(alloc: std.mem.Allocator, slice: []const u8) !*ObjectString {
        const obj_str = try alloc.create(ObjectString);
        const resulted_str = try alloc.dupe(u8, slice[1 .. slice.len - 1]);

        obj_str.* = .{ .object = .{ .type = .string }, .str = resulted_str };

        return obj_str;
    }

    pub fn asObject(self: *ObjectString) *Object {
        return &self.object;
    }

    pub fn deinit(self: *ObjectString, alloc: std.mem.Allocator) void {
        alloc.free(self.str);
        alloc.destroy(self);
    }
};
