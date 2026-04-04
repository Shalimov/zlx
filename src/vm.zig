const std = @import("std");
const builtin = @import("builtin");
const OpCode = @import("op_code.zig").OpCode;
const Chunk = @import("chunk.zig").Chunk;
const val = @import("value.zig");
const debug = @import("debug.zig");

pub const InstructionResult = enum { ok, compile_error, runtime_error };

const Stack = struct {
    stack: []val.Value,
    stack_top: [*]val.Value,

    fn deinit(self: *Stack, alloc: std.mem.Allocator) void {
        alloc.free(self.stack);
    }

    fn pop(self: *Stack) val.Value {
        self.stack_top -= 1;

        return @as(val.Value, self.stack_top[0]);
    }

    fn push(self: *Stack, value: val.Value) void {
        self.stack_top[0] = value;
        self.stack_top += 1;
    }

    fn reset(self: *Stack) void {
        self.stack_top = self.stack.ptr;
    }

    inline fn debugPrint(self: Stack) void {
        std.debug.print("        ", .{});

        var slot = self.stack.ptr;
        while (@intFromPtr(slot) < @intFromPtr(self.stack_top)) : (slot += 1) {
            std.debug.print("[", .{});
            val.printValue(slot[0]);
            std.debug.print("]", .{});
        }

        std.debug.print("\n", .{});
    }
};

pub const VirtualMachine = struct {
    const MAX_STACK = 256;

    ip: [*]u8,
    chunk: *Chunk,
    stack: Stack,

    pub fn init(alloc: std.mem.Allocator) !VirtualMachine {
        const stack = try alloc.alloc(val.Value, MAX_STACK);

        return VirtualMachine{
            .chunk = undefined,
            .ip = undefined,
            .stack = .{ .stack = stack, .stack_top = stack.ptr },
        };
    }

    pub fn interpret(self: *VirtualMachine, chunk: *Chunk) InstructionResult {
        self.chunk = chunk;
        self.ip = chunk.code.items.ptr;

        return self.run();
    }

    pub fn deinit(self: *VirtualMachine, alloc: std.mem.Allocator) void {
        self.stack.deinit(alloc);
    }

    fn run(self: *VirtualMachine) InstructionResult {
        while (true) {
            if (comptime builtin.mode == .Debug) {
                self.stack.debugPrint();
                _ = debug.disassembleInstruction(self.chunk, self.ip - self.chunk.code.items.ptr);
            }

            const op_code: OpCode = @enumFromInt(self.advance());

            switch (op_code) {
                .op_constant => {
                    const value = self.chunk.values.items[self.advance()];
                    self.stack.push(value);
                },
                .op_constant_long => {
                    const low_part: u8 = self.advance();
                    var const_index: u16 = self.advance();

                    const_index = (const_index << 8) | low_part;

                    const value = self.chunk.values.items[const_index];
                    self.stack.push(value);
                },
                .op_negate => {
                    self.stack.push(-self.stack.pop());
                },
                inline .op_add, .op_sub, .op_mul, .op_div => |op| {
                    const x2 = self.stack.pop();
                    const x1 = self.stack.pop();

                    self.stack.push(switch (op) {
                        .op_add => x1 + x2,
                        .op_sub => x1 - x2,
                        .op_mul => x1 * x2,
                        .op_div => x1 / x2,
                        else => unreachable,
                    });
                },
                .op_return => {
                    val.printValue(self.stack.pop());
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
