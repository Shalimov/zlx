const std = @import("std");
const builtin = @import("builtin");

const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("op_code.zig").OpCode;
const Value = @import("value.zig").Value;
const scn = @import("scanner.zig");
const debug = @import("debug.zig");

const ObjectString = @import("object.zig").ObjectString;

const TokenType = scn.TokenType;
const Token = scn.Token;
const Scanner = scn.Scanner;

const Precedence = enum {
    ex_none,
    ex_assignment,
    ex_or, // or
    ex_and, // and
    ex_equality, // == !=
    ex_comparison, // < > <= >=
    ex_term, // + -
    ex_factor, // * /
    ex_unary, // ! -
    ex_call, // . ()
    ex_primary,
};

const rules = rls: {
    const RuleFn = *const fn (self: *Compiler, alloc: std.mem.Allocator) anyerror!void;
    const ParseRule = struct { prefix: ?RuleFn, infix: ?RuleFn, precedence: Precedence };

    var table = [_]ParseRule{.{ .prefix = null, .infix = null, .precedence = .ex_none }} ** @typeInfo(TokenType).@"enum".fields.len;

    table[@intFromEnum(TokenType.token_left_paren)] = .{ .prefix = Compiler.grouping, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_right_paren)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_left_square)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_right_square)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_left_brace)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_right_brace)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_comma)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_dot)] = .{ .prefix = null, .infix = null, .precedence = .ex_call };
    table[@intFromEnum(TokenType.token_minus)] = .{ .prefix = Compiler.unary, .infix = Compiler.binary, .precedence = .ex_term };
    table[@intFromEnum(TokenType.token_plus)] = .{ .prefix = null, .infix = Compiler.binary, .precedence = .ex_term };
    table[@intFromEnum(TokenType.token_plus_plus)] = .{ .prefix = null, .infix = Compiler.binary, .precedence = .ex_term };
    table[@intFromEnum(TokenType.token_semicolon)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_slash)] = .{ .prefix = null, .infix = Compiler.binary, .precedence = .ex_factor };
    table[@intFromEnum(TokenType.token_star)] = .{ .prefix = null, .infix = Compiler.binary, .precedence = .ex_factor };
    table[@intFromEnum(TokenType.token_bang)] = .{ .prefix = Compiler.unary, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_bang_equal)] = .{ .prefix = null, .infix = Compiler.binary, .precedence = .ex_equality };
    table[@intFromEnum(TokenType.token_equal)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_equal_equal)] = .{ .prefix = null, .infix = Compiler.binary, .precedence = .ex_equality };
    table[@intFromEnum(TokenType.token_greater)] = .{ .prefix = null, .infix = Compiler.binary, .precedence = .ex_comparison };
    table[@intFromEnum(TokenType.token_greater_equal)] = .{ .prefix = null, .infix = Compiler.binary, .precedence = .ex_comparison };
    table[@intFromEnum(TokenType.token_less)] = .{ .prefix = null, .infix = Compiler.binary, .precedence = .ex_comparison };
    table[@intFromEnum(TokenType.token_less_equal)] = .{ .prefix = null, .infix = Compiler.binary, .precedence = .ex_comparison };
    table[@intFromEnum(TokenType.token_identifier)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_string)] = .{ .prefix = Compiler.string, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_number)] = .{ .prefix = Compiler.number, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_true)] = .{ .prefix = Compiler.literal, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_false)] = .{ .prefix = Compiler.literal, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_or)] = .{ .prefix = null, .infix = null, .precedence = .ex_or };
    table[@intFromEnum(TokenType.token_and)] = .{ .prefix = null, .infix = null, .precedence = .ex_and };
    table[@intFromEnum(TokenType.token_if)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_else)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_for)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_while)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_fun)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_return)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_class)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_super)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_this)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_var)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_nil)] = .{ .prefix = Compiler.literal, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_print)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_error)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };

    break :rls table;
};

pub const CompilerError = (std.mem.Allocator.Error || error{
    ParseError,
});

pub const Compiler = struct {
    const Self = @This();

    const Parser = struct {
        current: Token,
        previous: Token,
        panic_mode: bool,

        pub const init: @This() = .{ .current = undefined, .previous = undefined, .panic_mode = false };
    };

    pub const init: Self = .{ .compiling_chunk = undefined, .scanner = undefined, .parser = .init };

    compiling_chunk: *Chunk,
    scanner: Scanner,
    parser: Parser,

    pub fn compile(self: *Compiler, alloc: std.mem.Allocator, source: []const u8, chunk: *Chunk) !void {
        self.compiling_chunk = chunk;
        self.scanner.init(source);

        try self.advance();
        try self.expression(alloc);
        try self.endCompilation(alloc);
    }

    // Expressions, Pratt.

    fn expression(self: *Compiler, alloc: std.mem.Allocator) !void {
        try self.parsePrecedence(alloc, .ex_assignment);
    }

    fn number(self: *Compiler, alloc: std.mem.Allocator) !void {
        const const_value: f64 = try std.fmt.parseFloat(f64, self.parser.previous.str);

        var current_chunk = self.currentChunk();
        try current_chunk.writeConstant(alloc, Value{ .val_number = const_value }, self.parser.previous.line);
    }

    fn string(self: *Compiler, alloc: std.mem.Allocator) !void {
        var current_chunk = self.currentChunk();

        var obj_string = try ObjectString.dupe(alloc, self.parser.previous.str);
        try current_chunk.writeConstant(alloc, Value{ .val_obj = obj_string.asObject() }, self.parser.previous.line);
    }

    fn grouping(self: *Compiler, alloc: std.mem.Allocator) !void {
        try self.expression(alloc);
        try self.consume(.token_right_paren, "Expect ')' after expression.");
    }

    fn binary(self: *Compiler, alloc: std.mem.Allocator) !void {
        const op_type = self.parser.previous.token_type;
        const precedence = rules[@intFromEnum(op_type)].precedence;

        try self.parsePrecedence(alloc, @enumFromInt(@intFromEnum(precedence) + 1));

        try switch (op_type) {
            .token_plus => self.emitByte(alloc, @intFromEnum(OpCode.op_add)),
            .token_plus_plus => self.emitByte(alloc, @intFromEnum(OpCode.op_concat)),
            .token_minus => self.emitByte(alloc, @intFromEnum(OpCode.op_sub)),
            .token_star => self.emitByte(alloc, @intFromEnum(OpCode.op_mul)),
            .token_slash => self.emitByte(alloc, @intFromEnum(OpCode.op_div)),
            .token_equal_equal => self.emitByte(alloc, @intFromEnum(OpCode.op_equal)),
            .token_less => self.emitByte(alloc, @intFromEnum(OpCode.op_less)),
            .token_greater => self.emitByte(alloc, @intFromEnum(OpCode.op_greater)),
            .token_bang_equal => self.emitBytes(alloc, @intFromEnum(OpCode.op_equal), @intFromEnum(OpCode.op_not)),
            .token_less_equal => self.emitBytes(alloc, @intFromEnum(OpCode.op_greater), @intFromEnum(OpCode.op_not)),
            .token_greater_equal => self.emitBytes(alloc, @intFromEnum(OpCode.op_less), @intFromEnum(OpCode.op_not)),
            else => unreachable,
        };
    }

    fn unary(self: *Compiler, alloc: std.mem.Allocator) !void {
        const operator_type = self.parser.previous.token_type;

        // Compile the operand.
        try self.parsePrecedence(alloc, .ex_unary);

        try switch (operator_type) {
            .token_bang => self.emitByte(alloc, @intFromEnum(OpCode.op_not)),
            .token_minus => self.emitByte(alloc, @intFromEnum(OpCode.op_negate)),
            else => unreachable,
        };
    }

    fn literal(self: *Compiler, alloc: std.mem.Allocator) !void {
        try switch (self.parser.previous.token_type) {
            .token_nil => self.emitByte(alloc, @intFromEnum(OpCode.op_nil)),
            .token_true => self.emitByte(alloc, @intFromEnum(OpCode.op_true)),
            .token_false => self.emitByte(alloc, @intFromEnum(OpCode.op_false)),
            else => unreachable,
        };
    }

    fn parsePrecedence(self: *Compiler, alloc: std.mem.Allocator, precedence: Precedence) !void {
        try self.advance();

        if (rules[@intFromEnum(self.parser.previous.token_type)].prefix) |prefix_rule| {
            try prefix_rule(self, alloc);
        } else {
            return self.errorAtPrev("Unexpected expression.");
        }

        while (@intFromEnum(precedence) <= @intFromEnum(rules[@intFromEnum(self.parser.current.token_type)].precedence)) {
            try self.advance();

            if (rules[@intFromEnum(self.parser.previous.token_type)].infix) |infix_rule| {
                try infix_rule(self, alloc);
            }
        }
    }

    // Parsing helpers.

    fn advance(self: *Compiler) CompilerError!void {
        self.parser.previous = self.parser.current;

        // We keep looping, reading tokens and reporting the errors, until we hit a non-error one or reach the end.
        // That way, the rest of the parser sees only valid tokens.
        while (self.scanner.scanNext()) |token| {
            self.parser.current = token;

            if (token.token_type != .token_error) break;

            // TODO: Temp reporting
            try self.errorAtCurr(self.parser.current.str);
        }
    }

    fn consume(self: *Compiler, expected_token: TokenType, msg: []const u8) CompilerError!void {
        if (self.parser.current.token_type == expected_token) {
            try self.advance();
            return;
        }

        try self.errorAtCurr(msg);
    }

    fn emitByte(self: *Compiler, alloc: std.mem.Allocator, byte: u8) !void {
        var current_chunk = self.currentChunk();
        try current_chunk.write(alloc, byte, self.parser.current.line);
    }

    fn emitBytes(self: *Compiler, alloc: std.mem.Allocator, byte1: u8, byte2: u8) !void {
        try self.emitByte(alloc, byte1);
        try self.emitByte(alloc, byte2);
    }

    fn emitReturn(self: *Compiler, alloc: std.mem.Allocator) !void {
        try self.emitByte(alloc, @intFromEnum(OpCode.op_return));
    }

    fn endCompilation(self: *Compiler, alloc: std.mem.Allocator) !void {
        try self.emitReturn(alloc);

        if (builtin.mode == .Debug) {
            debug.disassembleChunk(self.currentChunk(), "code");
        }
    }

    fn currentChunk(self: *Compiler) *Chunk {
        return self.compiling_chunk;
    }

    // Error reporting helpers.

    fn errorAtCurr(self: *Compiler, msg: []const u8) !void {
        try self.errorAt(self.parser.current, msg);
    }

    fn errorAtPrev(self: *Compiler, msg: []const u8) !void {
        try self.errorAt(self.parser.previous, msg);
    }

    fn errorAt(self: *Compiler, token: Token, msg: []const u8) !void {
        _ = self;
        std.debug.print("[line {d}] Error", .{token.line});

        if (token.token_type == .token_error) {
            // Nothing.
        } else {
            std.debug.print(" at '{s}'", .{token.str});
        }

        std.debug.print(": {s}\n", .{msg});
        return CompilerError.ParseError;
    }
};
