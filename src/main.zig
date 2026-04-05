const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("op_code.zig").OpCode;
const debug = @import("debug.zig");
const VirtualMachine = @import("vm.zig").VirtualMachine;

const VM_MAX_STACK_SIZE = 1024;
var stack_buffer: [VM_MAX_STACK_SIZE]u8 = undefined;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var FixedBufferAllocator = std.heap.FixedBufferAllocator.init(&stack_buffer);
    const fba = FixedBufferAllocator.allocator();

    var chunk: Chunk = .init();
    defer chunk.deinit(gpa);

    var vm: VirtualMachine = .init;
    defer vm.deinit(fba);

    try chunk.writeConstant(gpa, 120, 123);
    try chunk.writeConstant(gpa, 110, 123);
    try chunk.write(gpa, @intFromEnum(OpCode.op_sub), 123);
    try chunk.writeConstant(gpa, 2, 123);
    try chunk.write(gpa, @intFromEnum(OpCode.op_div), 123);

    try chunk.write(gpa, @intFromEnum(OpCode.op_negate), 123);

    try chunk.write(gpa, @intFromEnum(OpCode.op_return), 123);

    _ = try vm.interpret(fba, &chunk);
}
