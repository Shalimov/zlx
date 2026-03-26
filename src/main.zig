const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("op_code.zig").OpCode;
const debug = @import("debug.zig");

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;

    var first_chunk: Chunk = .init();
    defer first_chunk.deinit(alloc);

    var i: usize = 0;

    while (i < 260) : (i += 1) {
        const value = 2.4 + @as(f64, @floatFromInt(i));
        try first_chunk.writeConstant(alloc, .{ .number = value }, i);
    }

    try first_chunk.write(alloc, @intFromEnum(OpCode.op_return), 123);

    debug.disassembleChunk(&first_chunk, "test chunk");
}
