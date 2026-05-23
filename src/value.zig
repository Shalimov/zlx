const std = @import("std");

pub const Value = union(enum) {
    pub const with_nil: @This() = .{ .val_nil = 0 };
    pub const with_true: @This() = .{ .val_bool = true };
    pub const with_false: @This() = .{ .val_bool = false };

    val_number: f64,
    val_bool: bool,
    val_nil: u1,

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
