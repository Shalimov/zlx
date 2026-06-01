const std = @import("std");
const builtin = @import("builtin");

const Chunk = @import("chunk.zig").Chunk;
const Compiler = @import("compiler.zig").Compiler;
const debug = @import("debug.zig");
const OpCode = @import("op_code.zig").OpCode;
const Value = @import("value.zig").Value;

const ObjectString = @import("object.zig").ObjectString;

pub const InterpretError = (std.mem.Allocator.Error || error{
    CompileError,
    RuntimeError,
});

pub const VirtualMachine = struct {
    const Self = @This();
    pub const init: Self = .{ .chunk = undefined, .ip = undefined, .stack = .empty, .compiler = .init };

    ip: [*]u8,
    chunk: *Chunk,
    stack: std.ArrayList(Value),
    compiler: Compiler,

    pub fn interpret(self: *Self, alloc: std.mem.Allocator, source: []const u8) !void {
        var chunk: Chunk = .init;
        defer chunk.deinit(alloc);

        try self.compiler.compile(alloc, source, &chunk);

        self.chunk = &chunk;
        self.ip = self.chunk.code.items.ptr;

        try self.run(alloc);
    }

    pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
        self.stack.deinit(alloc);
    }

    fn run(self: *Self, alloc: std.mem.Allocator) InterpretError!void {
        while (true) {
            if (builtin.mode == .Debug) {
                std.debug.print("        ", .{});

                for (self.stack.items) |item| {
                    std.debug.print("[", .{});
                    item.print();
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
                    const top_value = self.peek(0);

                    if (top_value != .val_number) {
                        return self.reportRuntimeError("Operand must be a number\n", .{});
                    }

                    const top = self.stack.items.len - 1;
                    self.stack.items[top].val_number = -top_value.val_number;
                },
                .op_equal => {
                    const x2 = self.stack.pop().?;
                    const x1 = self.stack.pop().?;

                    try self.stack.append(alloc, Value{ .val_bool = x1.equals(x2) });
                },
                .op_less => {
                    if (self.peek(0) != .val_number or self.peek(1) != .val_number) {
                        return self.reportRuntimeError("Operands must be numbers\n", .{});
                    }

                    const x2 = self.stack.pop().?;
                    const x1 = self.stack.pop().?;

                    try self.stack.append(alloc, Value{ .val_bool = x1.val_number < x2.val_number });
                },
                .op_greater => {
                    if (self.peek(0) != .val_number or self.peek(1) != .val_number) {
                        return self.reportRuntimeError("Operands must be numbers\n", .{});
                    }

                    const x2 = self.stack.pop().?;
                    const x1 = self.stack.pop().?;

                    try self.stack.append(alloc, Value{ .val_bool = x1.val_number > x2.val_number });
                },
                .op_not => {
                    const top_value = self.stack.pop().?;
                    try self.stack.append(alloc, if (top_value.isFalsy()) .with_true else .with_false);
                },
                .op_nil => {
                    try self.stack.append(alloc, .with_nil);
                },
                .op_true => {
                    try self.stack.append(alloc, .with_true);
                },
                .op_false => {
                    try self.stack.append(alloc, .with_false);
                },
                .op_concat => {
                    const b = self.peek(0);
                    const a = self.peek(1);

                    if (b == .val_obj and a == .val_obj and b.val_obj.type == .string and b.val_obj.type == a.val_obj.type) {
                        const higher_part = self.stack.pop().?.val_obj.as(ObjectString);
                        const lower_part = self.stack.pop().?.val_obj.as(ObjectString);

                        var concat_result = try ObjectString.concat(alloc, lower_part.str, higher_part.str);

                        try self.stack.append(alloc, Value{ .val_obj = concat_result.asObject() });
                    } else {
                        return self.reportRuntimeError("Operands must be strings\n", .{});
                    }
                },
                .op_add => {
                    if (self.peek(0) != .val_number or self.peek(1) != .val_number) {
                        return self.reportRuntimeError("Operands must be numbers\n", .{});
                    }

                    const b = self.stack.pop().?.val_number;
                    const a = self.stack.pop().?.val_number;

                    try self.stack.append(alloc, Value{ .val_number = a + b });
                },
                .op_sub => {
                    if (self.peek(0) != .val_number or self.peek(1) != .val_number) {
                        return self.reportRuntimeError("Operands must be numbers\n", .{});
                    }

                    const b = self.stack.pop().?.val_number;
                    const a = self.stack.pop().?.val_number;

                    try self.stack.append(alloc, Value{ .val_number = a - b });
                },
                .op_mul => {
                    if (self.peek(0) != .val_number or self.peek(1) != .val_number) {
                        return self.reportRuntimeError("Operands must be numbers\n", .{});
                    }

                    const b = self.stack.pop().?.val_number;
                    const a = self.stack.pop().?.val_number;

                    try self.stack.append(alloc, Value{ .val_number = a * b });
                },
                .op_div => {
                    if (self.peek(0) != .val_number or self.peek(1) != .val_number) {
                        return self.reportRuntimeError("Operands must be numbers\n", .{});
                    }

                    const b = self.stack.pop().?.val_number;
                    const a = self.stack.pop().?.val_number;

                    try self.stack.append(alloc, Value{ .val_number = a / b });
                },
                .op_return => {
                    self.stack.pop().?.print();
                    std.debug.print("\n", .{});

                    return;
                },
            }
        }
    }

    inline fn peek(self: *Self, distance: usize) Value {
        return self.stack.items[self.stack.items.len - 1 - distance];
    }

    inline fn advance(self: *Self) u8 {
        const instruction = self.ip[0];
        self.ip += 1;

        return instruction;
    }

    fn reportRuntimeError(self: *Self, comptime message: []const u8, args: anytype) InterpretError!void {
        std.debug.print(message, args);

        const current_ip_offset = self.ip - self.chunk.code.items.ptr - 1;
        const current_line = self.chunk.lines.items[current_ip_offset];
        std.debug.print("[line {d}] in script\n", .{current_line});

        // Reset the stack
        self.stack.clearRetainingCapacity();

        return InterpretError.RuntimeError;
    }
};
