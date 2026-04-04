const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("op_code.zig").OpCode;
const debug = @import("debug.zig");
const VirtualMachine = @import("vm.zig").VirtualMachine;

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;

    var first_chunk: Chunk = .init();
    defer first_chunk.deinit(alloc);

    var vm: VirtualMachine = try VirtualMachine.init(alloc);
    defer vm.deinit(alloc);

    try first_chunk.writeConstant(alloc, 120, 123);
    try first_chunk.writeConstant(alloc, 110, 123);
    try first_chunk.write(alloc, @intFromEnum(OpCode.op_sub), 123);
    try first_chunk.writeConstant(alloc, 2, 123);
    try first_chunk.write(alloc, @intFromEnum(OpCode.op_div), 123);

    try first_chunk.write(alloc, @intFromEnum(OpCode.op_negate), 123);
    try first_chunk.write(alloc, @intFromEnum(OpCode.op_return), 123);

    _ = vm.interpret(&first_chunk);
}
