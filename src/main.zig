const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("op-code.zig").OpCode;
const debug = @import("debug.zig");

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;

    var first_chunk: *Chunk = try alloc.create(Chunk);
    defer alloc.destroy(first_chunk);

    first_chunk.init();
    defer first_chunk.deinit(alloc);

    var i: usize = 0;

    while (i < 260) : (i += 1) {
        const value = 2.4 + @as(f64, @floatFromInt(i));
        try first_chunk.write_constant(alloc, .{ .value = value }, i);
    }

    try first_chunk.write(alloc, @intFromEnum(OpCode.op_return), 123);

    try debug.disassemble_chunk(first_chunk, "test chunk");
}
