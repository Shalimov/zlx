const std = @import("std");

pub const Value = union(enum) {
    value: f64,

    pub fn print(self: Value) void {
        switch (self) {
            .value => |v| std.debug.print("{d}", .{v}),
        }
    }
};
