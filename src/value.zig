const std = @import("std");

const object = @import("object.zig");

const Object = object.Object;
const ObjectString = object.ObjectString;

pub const Value = union(enum) {
    pub const with_nil: @This() = .val_nil;
    pub const with_true: @This() = .{ .val_bool = true };
    pub const with_false: @This() = .{ .val_bool = false };

    val_obj: *Object,
    val_number: f64,
    val_bool: bool,
    val_nil,

    pub fn equals(self: Value, other: Value) bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(other)) {
            return false;
        }

        switch (self) {
            .val_number => |v| return v == other.val_number,
            .val_bool => |v| return v == other.val_bool,
            .val_obj => |v| {
                return if (other == .val_obj) v.equals(other.val_obj) else false;
            },
            .val_nil => return true,
        }
    }

    pub fn isFalsy(self: Value) bool {
        return switch (self) {
            .val_bool => |val| !val,
            .val_nil => true,
            else => false,
        };
    }

    pub fn print(self: Value) void {
        switch (self) {
            .val_number => |val| std.debug.print("{d}", .{val}),
            .val_bool => |val| std.debug.print("{any}", .{val}),
            .val_nil => std.debug.print("nil", .{}),
            .val_obj => |obj| switch (obj.type) {
                .string => {
                    const obj_str = obj.as(ObjectString);
                    std.debug.print("{s}", .{obj_str.str});
                },
            },
        }
    }
};
