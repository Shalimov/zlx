const std = @import("std");

pub const Value = union(enum) {
    pub const with_nil: @This() = .{ .val_nil = 0 };
    pub const with_true: @This() = .{ .val_bool = true };
    pub const with_false: @This() = .{ .val_bool = false };

    val_number: f64,
    val_bool: bool,
    val_nil: u1,

    pub fn equals(self: Value, val: Value) bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(val)) {
            return false;
        }

        return switch (self) {
            .val_number => |v| v == val.val_number,
            .val_bool => |v| v == val.val_bool,
            .val_nil => true,
        };
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
        }
    }
};
