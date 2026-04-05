const std = @import("std");
const builtin = @import("builtin");
const OpCode = @import("op_code.zig").OpCode;
const Chunk = @import("chunk.zig").Chunk;
const val = @import("value.zig");
const debug = @import("debug.zig");

pub const InstructionResult = enum {
    ok,
};

const InterpretError = (std.mem.Allocator.Error || error{
    CompileError,
    RuntimeError,
});

pub const VirtualMachine = struct {
    ip: [*]u8,
    chunk: *Chunk,
    stack: std.ArrayList(val.Value),

    pub const init: @This() = .{
        .chunk = undefined,
        .ip = undefined,
        .stack = .empty,
    };

    pub fn interpret(self: *VirtualMachine, alloc: std.mem.Allocator, chunk: *Chunk) InterpretError!InstructionResult {
        self.chunk = chunk;
        self.ip = chunk.code.items.ptr;

        return try self.run(alloc);
    }

    pub fn deinit(self: *VirtualMachine, alloc: std.mem.Allocator) void {
        self.stack.deinit(alloc);
    }

    fn run(self: *VirtualMachine, alloc: std.mem.Allocator) InterpretError!InstructionResult {
        while (true) {
            if (builtin.mode == .Debug) {
                std.debug.print("        ", .{});

                for (self.stack.items) |item| {
                    std.debug.print("[", .{});
                    val.printValue(item);
                    std.debug.print("]", .{});
                }

                std.debug.print("\n", .{});
                _ = debug.disassembleInstruction(self.chunk, self.ip - self.chunk.code.items.ptr);
            }

            const op_code: OpCode = @enumFromInt(self.advance());

            switch (op_code) {
                .op_constant => {
                    const value = self.chunk.values.items[self.advance()];
                    try self.stack.append(alloc, value);
                },
                .op_constant_long => {
                    const low_part: u8 = self.advance();
                    var const_index: u16 = self.advance();

                    const_index = (const_index << 8) | low_part;

                    const value = self.chunk.values.items[const_index];
                    try self.stack.append(alloc, value);
                },
                .op_negate => {
                    const top = self.stack.items.len - 1;
                    self.stack.items[top] = -self.stack.items[top];
                },
                inline .op_add, .op_sub, .op_mul, .op_div => |op| {
                    const x2 = self.stack.pop().?;
                    const x1 = self.stack.pop().?;

                    try self.stack.append(alloc, switch (op) {
                        .op_add => x1 + x2,
                        .op_sub => x1 - x2,
                        .op_mul => x1 * x2,
                        .op_div => x1 / x2,
                        else => unreachable,
                    });
                },
                .op_return => {
                    val.printValue(self.stack.pop().?);
                    std.debug.print("\n", .{});

                    return InstructionResult.ok;
                },
            }
        }
    }

    inline fn advance(self: *VirtualMachine) u8 {
        const instruction = self.ip[0];
        self.ip += 1;

        return instruction;
    }
};
