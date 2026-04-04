const std = @import("std");

const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("op_code.zig").OpCode;
const val = @import("value.zig");

fn printSimpleInstruction(name: []const u8, offset: usize) usize {
    std.debug.print("{s}\n", .{name});
    return offset + 1;
}

fn printConstInstruction(chunk: *const Chunk, offset: usize) usize {
    const op: OpCode = @enumFromInt(chunk.code.items[offset]);
    const op_name = if (op == OpCode.op_constant) "OP_CONSTANT" else "OP_CONSTANT_LONG";
    var step: usize = 2;
    var constant_index: u16 = chunk.code.items[offset + 1];

    if (op == OpCode.op_constant_long) {
        constant_index = (@as(u16, chunk.code.items[offset + 2]) << 8) + constant_index;
        step = 3;
    }

    std.debug.print("{0s: <16} {1d: >4} '", .{ op_name, constant_index });
    val.printValue(chunk.values.items[@as(usize, constant_index)]);
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

    switch (instruction) {
        .op_constant, .op_constant_long => return printConstInstruction(chunk, offset),
        .op_negate => return printSimpleInstruction("OP_NEGATE", offset),
        .op_add => return printSimpleInstruction("OP_ADD", offset),
        .op_sub => return printSimpleInstruction("OP_SUB", offset),
        .op_mul => return printSimpleInstruction("OP_MUL", offset),
        .op_div => return printSimpleInstruction("OP_DIV", offset),
        .op_return => return printSimpleInstruction("OP_RETURN", offset),
    }
}
