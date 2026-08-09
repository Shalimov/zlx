const std = @import("std");

const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("op_code.zig").OpCode;
const Value = @import("value.zig").Value;

fn printSimpleInstruction(name: []const u8, offset: usize) usize {
    std.debug.print("{s}\n", .{name});
    return offset + 1;
}

fn printConstInstruction(name: []const u8, chunk: *const Chunk, offset: usize, modifier_wide: bool) usize {
    var step: usize = 2;
    var constant_index: u16 = chunk.code.items[offset + 1];

    if (modifier_wide) {
        constant_index = (@as(u16, chunk.code.items[offset + 2]) << 8) + constant_index;
        step = 3;

        std.debug.print("{0s: <12}(wide) {1d: >4} '", .{ name, constant_index });
    } else {
        std.debug.print("{0s: <18} {1d: >4} '", .{ name, constant_index });
    }

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
    var actual_offset = offset;

    std.debug.print("{d:0>4} ", .{actual_offset});

    if (actual_offset > 0 and chunk.lines.items[actual_offset] == chunk.lines.items[actual_offset - 1]) {
        std.debug.print("   | ", .{});
    } else {
        std.debug.print("{d: >4} ", .{chunk.lines.items[actual_offset]});
    }

    const instruction: OpCode = @enumFromInt(chunk.code.items[actual_offset]);
    var wide = false;
    var result_offset: usize = undefined;

    modifier: switch (instruction) {
        .op_wide => {
            wide = true;
            actual_offset += 1;
            continue :modifier @enumFromInt(chunk.code.items[actual_offset]);
        },
        inline .op_constant,
        .op_define_global,
        .op_get_global,
        .op_set_global,
        => |op| {
            result_offset = printConstInstruction(@tagName(op), chunk, actual_offset, wide);
            wide = false;
        },
        inline .op_not, .op_negate, .op_nil, .op_true, .op_false, .op_equal, .op_less, .op_greater, .op_concat, .op_add, .op_sub, .op_mul, .op_div, .op_print, .op_pop, .op_return => |op| {
            result_offset = printSimpleInstruction(@tagName(op), actual_offset);
        },
    }

    return result_offset;
}
