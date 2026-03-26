const std = @import("std");

pub const Value = union(enum) {
    number: f64,

    pub fn print(self: Value) void {
        switch (self) {
            .number => |v| std.debug.print("{d}", .{v}),
        }
    }
};
