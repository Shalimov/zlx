const std = @import("std");

const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("op_code.zig").OpCode;
const Value = @import("value.zig").Value;

fn printSimpleInstruction(name: []const u8, offset: usize) usize {
    std.debug.print("{s}\n", .{name});
    return offset + 1;
}

fn printConstInstruction(name: []const u8, chunk: *const Chunk, offset: usize) usize {
    const op: OpCode = @enumFromInt(chunk.code.items[offset]);
    var step: usize = 2;
    var constant_index: u16 = chunk.code.items[offset + 1];

    if (op == OpCode.op_constant_long) {
        constant_index = (@as(u16, chunk.code.items[offset + 2]) << 8) + constant_index;
        step = 3;
    }

    std.debug.print("{0s: <16} {1d: >4} '", .{ name, constant_index });
    chunk.values.items[@as(usize, constant_index)].print();
    std.debug.print("'\n", .{});

    return offset + step;
}

pub fn disassembleChunk(chunk: *const Chunk, name: []const u8) void {
    std.debug.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunk.code.items.len) {
        offset = disassembleInstruction(chunk, offset);
    }
}

pub fn disassembleInstruction(chunk: *const Chunk, offset: usize) usize {
    std.debug.print("{d:0>4} ", .{offset});

    if (offset > 0 and chunk.lines.items[offset] == chunk.lines.items[offset - 1]) {
        std.debug.print("   | ", .{});
    } else {
        std.debug.print("{d: >4} ", .{chunk.lines.items[offset]});
    }

    const instruction: OpCode = @enumFromInt(chunk.code.items[offset]);

    return switch (instruction) {
        inline .op_constant, .op_constant_long, .op_define_global, .op_define_global_long, .op_get_global, .op_get_global_long, .op_set_global, .op_set_global_long => |op| printConstInstruction(@tagName(op), chunk, offset),
        inline .op_not, .op_negate, .op_nil, .op_true, .op_false, .op_equal, .op_less, .op_greater, .op_concat, .op_add, .op_sub, .op_mul, .op_div, .op_print, .op_pop, .op_return => |op| printSimpleInstruction(@tagName(op), offset),
    };
}
