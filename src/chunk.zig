const std = @import("std");
const Value = @import("value.zig").Value;
const OpCode = @import("op_code.zig").OpCode;

const MAX_U8: u8 = std.math.maxInt(u8);
const MAX_U16: u16 = std.math.maxInt(u16);

pub const ChunkError = error{ConstantOverflow};

pub const Chunk = struct {
    code: std.ArrayList(u8),
    lines: std.ArrayList(usize),
    values: std.ArrayList(Value),

    pub fn init() Chunk {
        return .{
            .code = .empty,
            .lines = .empty,
            .values = .empty,
        };
    }

    pub fn deinit(self: *Chunk, alloc: std.mem.Allocator) void {
        self.code.deinit(alloc);
        self.lines.deinit(alloc);
        self.values.deinit(alloc);
    }

    pub fn write(self: *Chunk, alloc: std.mem.Allocator, byte: u8, line: usize) !void {
        try self.code.append(alloc, byte);
        try self.lines.append(alloc, line);
    }

    pub fn writeConstant(self: *Chunk, alloc: std.mem.Allocator, value: Value, line: usize) !void {
        try self.values.append(alloc, value);

        const current_const_index = self.values.items.len - 1;

        if (current_const_index <= MAX_U8) {
            try self.write(alloc, @intFromEnum(OpCode.op_constant), line);
            try self.write(alloc, @intCast(current_const_index), line);
        } else if (current_const_index <= MAX_U16) {
            const index_u16: u16 = @intCast(current_const_index);
            const low_part: u8 = @truncate(index_u16 & 0x00FF);
            const high_part: u8 = @truncate((index_u16 >> 8) & 0x00FF);

            try self.write(alloc, @intFromEnum(OpCode.op_constant_long), line);
            try self.write(alloc, low_part, line);
            try self.write(alloc, high_part, line);
        } else {
            return ChunkError.ConstantOverflow;
        }
    }
};
