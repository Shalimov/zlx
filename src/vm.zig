const std = @import("std");
const builtin = @import("builtin");

const Chunk = @import("chunk.zig").Chunk;
const Compiler = @import("compiler.zig").Compiler;
const debug = @import("debug.zig");
const OpCode = @import("op_code.zig").OpCode;
const Value = @import("value.zig").Value;
const GcAllocator = @import("gc-allocator.zig").GcAllocator;

const ObjectString = @import("object.zig").ObjectString;

pub const InterpretError = error{
    CompileError,
    RuntimeError,
};

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

    fn run(self: *Self, alloc: std.mem.Allocator) !void {
        // Wide is completly artifical instruction
        // It works rather as a modifer to instruct how many bytes to read after the main instruction
        // Hence we should skip rendering of the wide in debug mode to show correctly which instruction is main
        // The main instruction itself will render a label (wide) if it's "extended version" and requires read more from the stack to restore an argument
        var modifier_wide = false;

        while (true) {
            if (builtin.mode == .Debug and !modifier_wide) {
                std.debug.print("        ", .{});

                for (self.stack.items) |item| {
                    std.debug.print("[", .{});
                    item.print();
                    std.debug.print("]", .{});
                }

                if (self.stack.items.len > 0) {
                    std.debug.print("\n", .{});
                } else {
                    std.debug.print("\r", .{});
                }

                _ = debug.disassembleInstruction(self.chunk, self.ip - self.chunk.code.items.ptr);
            }

            const op_code: OpCode = @enumFromInt(self.advance());

            switch (op_code) {
                .op_negate => {
                    const top_value = self.peek(0);

                    if (top_value != .val_number) {
                        return self.reportRuntimeError("Operand must be a number\n", .{});
                    }

                    // Trip over a dollar to pick a dime ;)
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
                .op_print => {
                    self.stack.pop().?.print();
                    std.debug.print("\n", .{});
                },
                .op_constant => {
                    defer modifier_wide = false;
                    const value = self.getConstantValue(modifier_wide);

                    try self.stack.append(alloc, value);
                },
                .op_define_global => {
                    defer modifier_wide = false;
                    const gc = GcAllocator.as(alloc);
                    const key = self.getConstantValue(modifier_wide);

                    const key_str = key.val_obj.as(ObjectString);
                    _ = try gc.globals.insert(alloc, key_str, self.peek(0));

                    _ = self.stack.pop();
                },
                .op_get_global => {
                    defer modifier_wide = false;
                    const gc = GcAllocator.as(alloc);
                    const val = self.getConstantValue(modifier_wide);

                    const key_str = val.val_obj.as(ObjectString);

                    const value = gc.globals.findValue(key_str);

                    if (value == null) {
                        return self.reportRuntimeError("Variable '{s}' is undefined.", .{key_str.str});
                    }

                    try self.stack.append(alloc, value.?);
                },
                .op_set_global => {
                    defer modifier_wide = false;
                    const gc = GcAllocator.as(alloc);
                    const val = self.getConstantValue(modifier_wide);

                    const key_str = val.val_obj.as(ObjectString);

                    const is_new_insert = try gc.globals.insert(alloc, key_str, self.peek(0));

                    if (is_new_insert) {
                        // if there were no values it crops up after insert
                        // while for interpreation of scripts is fine to keep, it's not good for REPL
                        gc.globals.remove(key_str);
                        return self.reportRuntimeError("Forbidden to set undefined variable '{s}'.", .{key_str.str});
                    }

                    // Unique operation in sense (no push, no pop)
                },
                .op_wide => {
                    // Incorporate modifier into the operation loop
                    modifier_wide = true;
                },
                .op_pop => {
                    _ = self.stack.pop();
                },
                .op_return => {
                    // End of an interpretation loop
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

    fn getConstantValue(self: *Self, modifier_wide: bool) Value {
        var const_index: u16 = self.advance();

        if (modifier_wide) {
            const high_part: u16 = self.advance();

            const_index = (high_part << 8) | const_index;
        }

        return self.chunk.values.items[const_index];
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
