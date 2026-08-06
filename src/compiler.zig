const std = @import("std");
const builtin = @import("builtin");

const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("op_code.zig").OpCode;
const Value = @import("value.zig").Value;
const debug = @import("debug.zig");
const scn = @import("scanner.zig");

const Scanner = scn.Scanner;
const Token = scn.Token;
const TokenType = scn.TokenType;

const ObjectString = @import("object.zig").ObjectString;
const GcAllocator = @import("gc-allocator.zig").GcAllocator;

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
    table[@intFromEnum(TokenType.token_eof)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };

    break :rls table;
};

pub const CompilerError = error{
    ParseError,
};

pub const Compiler = struct {
    const Self = @This();
    const Parser = struct {
        const ErrorToken = Token{
            .line = 0,
            .str = &[_]u8{},
            .token_type = .token_error,
        };

        current: Token,
        previous: Token,
        had_error: bool,
        panic_mode: bool,

        pub const init: @This() = .{ .current = ErrorToken, .previous = ErrorToken, .panic_mode = false, .had_error = false };
    };

    pub const init: Self = .{ .compiling_chunk = undefined, .scanner = undefined, .parser = .init };

    scanner: Scanner,
    parser: Parser,
    compiling_chunk: *Chunk,

    pub fn compile(self: *Compiler, alloc: std.mem.Allocator, source: []const u8, chunk: *Chunk) !void {
        self.compiling_chunk = chunk;
        self.scanner.init(source);

        self.advance();

        while (!self.match(TokenType.token_eof)) {
            try self.declaration(alloc);
        }

        try self.endCompilation(alloc);

        if (self.parser.had_error) {
            return CompilerError.ParseError;
        }
    }

    // Statments

    fn declaration(self: *Compiler, alloc: std.mem.Allocator) !void {
        if (self.match(.token_var)) {
            try self.varDeclaration(alloc);
        } else {
            try self.statement(alloc);
        }

        if (self.parser.panic_mode) {
            self.synchronization();
        }
    }

    fn varDeclaration(self: *Compiler, alloc: std.mem.Allocator) !void {
        const chunk = self.currentChunk();

        self.consume(.token_identifier, "Expect variable name.");
        const var_name = try ObjectString.dupe(alloc, self.parser.previous.str);

        if (self.match(.token_equal)) {
            try self.expression(alloc);
        } else {
            try self.emitOpCode(alloc, .op_nil);
        }

        self.consume(.token_semicolon, "Expect ';' after var declaration.");

        try chunk.writeConstantAs(alloc, .op_define_global, .{ .val_obj = var_name.asObject() }, self.parser.previous.line);
    }

    fn statement(self: *Compiler, alloc: std.mem.Allocator) !void {
        if (self.match(TokenType.token_print)) {
            try self.printStatement(alloc);
        } else {
            try self.expressionStatement(alloc);
        }
    }

    fn printStatement(self: *Compiler, alloc: std.mem.Allocator) !void {
        try self.expression(alloc);

        self.consume(TokenType.token_semicolon, "Expect ';' after expression.");

        try self.emitOpCode(alloc, .op_print);
    }

    fn expressionStatement(self: *Compiler, alloc: std.mem.Allocator) !void {
        try self.expression(alloc);

        self.consume(TokenType.token_semicolon, "Expect ';' after expression.");

        try self.emitOpCode(alloc, .op_pop);
    }

    // Expressions, Pratt.

    fn expression(self: *Compiler, alloc: std.mem.Allocator) !void {
        try self.parsePrecedence(alloc, .ex_assignment);
    }

    fn number(self: *Compiler, alloc: std.mem.Allocator) !void {
        const const_value: f64 = try std.fmt.parseFloat(f64, self.parser.previous.str);

        var current_chunk = self.currentChunk();
        try current_chunk.writeConstantAs(alloc, .op_constant, Value{ .val_number = const_value }, self.parser.previous.line);
    }

    fn string(self: *Compiler, alloc: std.mem.Allocator) !void {
        var current_chunk = self.currentChunk();

        var obj_string = try ObjectString.dupe(alloc, self.parser.previous.str);
        try current_chunk.writeConstantAs(alloc, .op_constant, Value{ .val_obj = obj_string.asObject() }, self.parser.previous.line);
    }

    fn grouping(self: *Compiler, alloc: std.mem.Allocator) !void {
        try self.expression(alloc);

        self.consume(.token_right_paren, "Expect ')' after expression.");
    }

    fn binary(self: *Compiler, alloc: std.mem.Allocator) !void {
        const op_type = self.parser.previous.token_type;
        const precedence = rules[@intFromEnum(op_type)].precedence;

        try self.parsePrecedence(alloc, @enumFromInt(@intFromEnum(precedence) + 1));

        try switch (op_type) {
            .token_plus => self.emitOpCode(alloc, .op_add),
            .token_plus_plus => self.emitOpCode(alloc, .op_concat),
            .token_minus => self.emitOpCode(alloc, .op_sub),
            .token_star => self.emitOpCode(alloc, .op_mul),
            .token_slash => self.emitOpCode(alloc, .op_div),
            .token_equal_equal => self.emitOpCode(alloc, .op_equal),
            .token_less => self.emitOpCode(alloc, .op_less),
            .token_greater => self.emitOpCode(alloc, .op_greater),
            .token_bang_equal => self.emitOpCodes(alloc, .op_equal, .op_not),
            .token_less_equal => self.emitOpCodes(alloc, .op_greater, .op_not),
            .token_greater_equal => self.emitOpCodes(alloc, .op_less, .op_not),
            else => unreachable,
        };
    }

    fn unary(self: *Compiler, alloc: std.mem.Allocator) !void {
        const operator_type = self.parser.previous.token_type;

        // Compile the operand.
        try self.parsePrecedence(alloc, .ex_unary);

        try switch (operator_type) {
            .token_bang => self.emitOpCode(alloc, .op_not),
            .token_minus => self.emitOpCode(alloc, .op_negate),
            else => unreachable,
        };
    }

    fn literal(self: *Compiler, alloc: std.mem.Allocator) !void {
        try switch (self.parser.previous.token_type) {
            .token_nil => self.emitOpCode(alloc, .op_nil),
            .token_true => self.emitOpCode(alloc, .op_true),
            .token_false => self.emitOpCode(alloc, .op_false),
            else => unreachable,
        };
    }

    fn parsePrecedence(self: *Compiler, alloc: std.mem.Allocator, precedence: Precedence) !void {
        self.advance();

        if (rules[@intFromEnum(self.parser.previous.token_type)].prefix) |prefix_rule| {
            try prefix_rule(self, alloc);
        } else {
            self.errorAtPrev("Unexpected expression.");

            return;
        }

        while (@intFromEnum(precedence) <= @intFromEnum(rules[@intFromEnum(self.parser.current.token_type)].precedence)) {
            self.advance();

            if (rules[@intFromEnum(self.parser.previous.token_type)].infix) |infix_rule| {
                try infix_rule(self, alloc);
            }
        }
    }

    // Synchronisation

    fn synchronization(self: *Compiler) void {
        self.parser.panic_mode = false;

        while (self.parser.current.token_type != .token_eof) {
            if (self.parser.previous.token_type == .token_semicolon) return;

            switch (self.parser.current.token_type) {
                .token_class, .token_fun, .token_var, .token_for, .token_if, .token_while, .token_print, .token_return => return,
                else => self.advance(),
            }
        }
    }

    // Parsing helpers.

    fn advance(self: *Compiler) void {
        self.parser.previous = self.parser.current;

        while (true) {
            const token = self.scanner.scanNext();
            self.parser.current = token;

            if (token.token_type != .token_error) break;

            self.errorAtCurr(token.str);
        }
    }

    fn match(self: *Compiler, expected_token: TokenType) bool {
        if (self.check(expected_token)) {
            self.advance();

            return true;
        }

        return false;
    }

    fn consume(self: *Compiler, expected_token: TokenType, msg: []const u8) void {
        if (self.check(expected_token)) {
            self.advance();

            return;
        }

        self.errorAtCurr(msg);
    }

    inline fn check(self: *Compiler, token_type: TokenType) bool {
        return self.parser.current.token_type == token_type;
    }

    // Emitters

    fn emitOpCode(self: *Compiler, alloc: std.mem.Allocator, op: OpCode) !void {
        var current_chunk = self.currentChunk();
        return current_chunk.write(alloc, @intFromEnum(op), self.parser.current.line);
    }

    fn emitOpCodes(self: *Compiler, alloc: std.mem.Allocator, op1: OpCode, op2: OpCode) !void {
        try self.emitOpCode(alloc, op1);
        try self.emitOpCode(alloc, op2);
    }

    fn emitOpReturn(self: *Compiler, alloc: std.mem.Allocator) !void {
        return self.emitOpCode(alloc, .op_return);
    }

    fn endCompilation(self: *Compiler, alloc: std.mem.Allocator) !void {
        try self.emitOpReturn(alloc);

        if (builtin.mode == .Debug) {
            debug.disassembleChunk(self.currentChunk(), "code");
        }
    }

    fn currentChunk(self: *Compiler) *Chunk {
        return self.compiling_chunk;
    }

    // Error reporting helpers.

    fn errorAtCurr(self: *Compiler, msg: []const u8) void {
        errorAt(self, self.parser.current, msg);
    }

    fn errorAtPrev(self: *Compiler, msg: []const u8) void {
        errorAt(self, self.parser.previous, msg);
    }

    fn errorAt(self: *Compiler, token: Token, msg: []const u8) void {
        if (self.parser.panic_mode) return;

        self.parser.panic_mode = true;

        std.debug.print("[line {d}] Error", .{token.line});

        switch (token.token_type) {
            .token_error => {},
            .token_eof => {
                std.debug.print(" at end", .{});
            },
            else => std.debug.print(" at '{s}'", .{token.str}),
        }

        std.debug.print(": {s}\n", .{msg});

        self.parser.had_error = true;
    }
};
