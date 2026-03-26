const std = @import("std");

const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("op-code.zig").OpCode;

fn print_simple_instruction(name: []const u8, offset: usize) !usize {
    std.debug.print("{s}\n", .{name});

    return offset + 1;
}

fn print_const_instruction(chunk: *const Chunk, offset: usize) !usize {
    const op: OpCode = @enumFromInt(chunk.*.code.items[offset]);
    const op_name = if (op == OpCode.op_constant) "OP_CONSTANT" else "OP_CONSTANT_LONG";
    var step: usize = 2;
    var constant_index: u16 = chunk.*.code.items[offset + 1];

    if (op == OpCode.op_constant_long) {
        constant_index = (@as(u16, chunk.*.code.items[offset + 2]) << 8) + constant_index;
        step = 3;
    }

    std.debug.print("{0s: <16} {1d: >4} '", .{ op_name, constant_index });
    chunk.*.values.items[@as(usize, constant_index)].print();
    std.debug.print("'\n", .{});

    return offset + step;
}

pub fn disassemble_chunk(chunk: *const Chunk, name: []const u8) !void {
    std.debug.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunk.*.code.items.len) {
        offset = try disassemble_instruction(chunk, offset);
    }
}

pub fn disassemble_instruction(chunk: *const Chunk, offset: usize) !usize {
    std.debug.print("{d:0>4} ", .{offset});

    if (offset > 0 and chunk.*.lines.items[offset] == chunk.*.lines.items[offset - 1]) {
        std.debug.print("   | ", .{});
    } else {
        std.debug.print("{d: >4} ", .{chunk.*.lines.items[offset]});
    }

    const instruction: OpCode = @enumFromInt(chunk.*.code.items[offset]);

    switch (instruction) {
        OpCode.op_constant_long, OpCode.op_constant => {
            return print_const_instruction(chunk, offset);
        },
        OpCode.op_return => {
            return print_simple_instruction("OP_RETURN", offset);
        },
    }

    // Should not be reached: invalid opcode value.
    std.debug.print("Unknown opcode {d}\n", .{instruction});
    return offset + 1;
}
