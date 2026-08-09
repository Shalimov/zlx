const std = @import("std");
const Value = @import("value.zig").Value;
const OpCode = @import("op_code.zig").OpCode;

const MAX_U8: u8 = std.math.maxInt(u8);
const MAX_U16: u16 = std.math.maxInt(u16);

const ChunkError = (std.mem.Allocator.Error || error{
    ConstantOverflow,
});

pub const Chunk = struct {
    code: std.ArrayList(u8),
    lines: std.ArrayList(usize),
    values: std.ArrayList(Value),

    pub const init: @This() = .{
        .code = .empty,
        .lines = .empty,
        .values = .empty,
    };

    pub fn deinit(self: *Chunk, alloc: std.mem.Allocator) void {
        self.code.deinit(alloc);
        self.lines.deinit(alloc);
        self.values.deinit(alloc);
    }

    pub fn write(self: *Chunk, alloc: std.mem.Allocator, byte: u8, line: usize) ChunkError!void {
        try self.code.append(alloc, byte);
        try self.lines.append(alloc, line);
    }

    pub fn writeConstantAs(self: *Chunk, alloc: std.mem.Allocator, comptime as: OpCode, value: Value, line: usize) !void {
        comptime var op_short: OpCode = undefined;
        comptime var op_long: OpCode = undefined;

        comptime {
            switch (as) {
                .op_constant => {
                    op_short = .op_constant;
                    op_long = .op_constant_long;
                },
                .op_define_global => {
                    op_short = .op_define_global;
                    op_long = .op_define_global_long;
                },
                .op_get_global => {
                    op_short = .op_get_global;
                    op_long = .op_get_global_long;
                },
                .op_set_global => {
                    op_short = .op_set_global;
                    op_long = .op_set_global_long;
                },
                else => @compileError("Only op_constant, op_define_global, op_get_global, op_set_global are supported, long versions are inferred automatically"),
            }
        }

        try self.values.append(alloc, value);

        const current_const_index = self.values.items.len - 1;

        if (current_const_index <= MAX_U8) {
            try self.write(alloc, @intFromEnum(op_short), line);
            try self.write(alloc, @intCast(current_const_index), line);
        } else if (current_const_index <= MAX_U16) {
            const index_u16: u16 = @intCast(current_const_index);
            const low_part: u8 = @truncate(index_u16 & 0x00_FF);
            const high_part: u8 = @truncate((index_u16 >> 8) & 0x00_FF);

            try self.write(alloc, @intFromEnum(op_long), line);
            try self.write(alloc, low_part, line);
            try self.write(alloc, high_part, line);
        } else {
            return ChunkError.ConstantOverflow;
        }
    }
};
