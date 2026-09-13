// TODO: Introspection of local variable (names disappear during an exection in vm and exist only in compiler)
// Debugging in this case is combersome (sort this out)

const std = @import("std");
const builtin = @import("builtin");

const Chunk = @import("chunk.zig").Chunk;
const debug = @import("debug.zig");
const GcAllocator = @import("gc-allocator.zig").GcAllocator;
const ObjectString = @import("object.zig").ObjectString;
const OpCode = @import("op_code.zig").OpCode;
const scn = @import("scanner.zig");
const Scanner = scn.Scanner;
const Token = scn.Token;
const TokenType = scn.TokenType;
const Value = @import("value.zig").Value;

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
    const RuleFn = *const fn (self: *Compiler, alloc: std.mem.Allocator, can_assign: bool) anyerror!void;
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
    table[@intFromEnum(TokenType.token_identifier)] = .{ .prefix = Compiler.variable, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_string)] = .{ .prefix = Compiler.string, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_number)] = .{ .prefix = Compiler.number, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_true)] = .{ .prefix = Compiler.literal, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_false)] = .{ .prefix = Compiler.literal, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_or)] = .{ .prefix = null, .infix = Compiler.logicOr, .precedence = .ex_or };
    table[@intFromEnum(TokenType.token_and)] = .{ .prefix = null, .infix = Compiler.logicAnd, .precedence = .ex_and };
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
    table[@intFromEnum(TokenType.token_const)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_nil)] = .{ .prefix = Compiler.literal, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_print)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_error)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };
    table[@intFromEnum(TokenType.token_eof)] = .{ .prefix = null, .infix = null, .precedence = .ex_none };

    break :rls table;
};

pub const CompilerError = error{
    ParseError,
};

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

const LocalVar = struct {
    const Modifier = packed struct {
        initialized: bool,
        mutable: bool,
    };

    name: []const u8,
    depth: i32,
    modifier: Modifier,
};

const MAX_U8_PLUS1 = std.math.maxInt(u8) + 1;
const MAX_U16 = std.math.maxInt(u16);

pub const Compiler = struct {
    const Self = @This();

    locals: [MAX_U8_PLUS1]LocalVar,
    locals_count: i32,
    locals_depth: i32,

    scanner: Scanner,
    parser: Parser,
    compiling_chunk: *Chunk,

    pub fn compile(self: *Compiler, alloc: std.mem.Allocator, source: []const u8, chunk: *Chunk) !void {
        self.init();

        self.compiling_chunk = chunk;
        self.scanner.init(source);

        self.advance();

        while (!self.match(.token_eof)) {
            try self.declaration(alloc);
        }

        try self.endCompilation(alloc);

        if (self.parser.had_error) {
            self.parser.had_error = false;
            return CompilerError.ParseError;
        }
    }

    inline fn init(self: *Compiler) void {
        self.locals_count = 0;
        self.locals_depth = 0;

        self.parser.had_error = false;
        self.parser.panic_mode = false;
    }

    // Statements

    fn declaration(self: *Compiler, alloc: std.mem.Allocator) anyerror!void {
        const mutable_var = self.match(.token_var);

        if (mutable_var or self.match(.token_const)) {
            try self.varDeclaration(alloc, mutable_var);
        } else {
            try self.statement(alloc);
        }

        if (self.parser.panic_mode) {
            self.synchronization();
        }
    }

    fn varDeclaration(self: *Compiler, alloc: std.mem.Allocator, mutable: bool) !void {
        const chunk = self.getCurrentChunk();

        self.consume(.token_identifier, "Expect variable name.");
        const var_name_token = self.parser.previous;

        const local_variable_declaration = self.locals_depth > 0;

        if (local_variable_declaration) {
            var i = self.locals_count - 1;

            while (i >= 0 and self.locals[@intCast(i)].depth == self.locals_depth) : (i -= 1) {
                if (std.mem.eql(u8, self.locals[@intCast(i)].name, var_name_token.str)) {
                    self.errorAt(var_name_token, "Already a variable with this name in this scope.");
                }
            }

            self.addLocal(var_name_token.str, .{ .initialized = false, .mutable = mutable });
        }

        if (self.match(.token_equal)) {
            try self.expression(alloc);
        } else {
            if (!mutable) {
                self.errorAtPrev("Const should be set explicitly.");
                return;
            }

            try self.emitOpCode(alloc, .op_nil);
        }

        self.consume(.token_semicolon, "Expect ';' after var declaration.");

        if (local_variable_declaration) {
            self.markLastLocalInitialized();
        } else {
            const var_name = try ObjectString.dupe(alloc, var_name_token.str);
            try chunk.writeConstantAs(alloc, .op_define_global, .{ .val_obj = var_name.asObject() }, var_name_token.line);
        }
    }

    fn statement(self: *Compiler, alloc: std.mem.Allocator) !void {
        if (self.match(.token_print)) {
            try self.printStatement(alloc);
        } else if (self.match(.token_left_brace)) {
            self.beginScope();
            try self.blockStatement(alloc);
            try self.endScope(alloc);
        } else if (self.match(.token_if)) {
            try self.ifStatement(alloc);
        } else {
            try self.expressionStatement(alloc);
        }
    }

    fn ifStatement(self: *Compiler, alloc: std.mem.Allocator) anyerror!void {
        self.consume(.token_left_paren, "Expect '(' after if statement.");
        try self.expression(alloc);
        self.consume(.token_right_paren, "Expect ')' after condition.");

        const then_jump_pos = try self.emitJump(alloc, .op_jump_if_false);
        try self.emitOpCode(alloc, .op_pop);

        try self.statement(alloc);

        const else_jump_pos = try self.emitJump(alloc, .op_jump);

        self.patchJump(then_jump_pos);
        try self.emitOpCode(alloc, .op_pop);

        if (self.match(.token_else)) {
            try self.statement(alloc);
        }

        self.patchJump(else_jump_pos);
    }

    fn blockStatement(self: *Compiler, alloc: std.mem.Allocator) !void {
        while (!self.check(.token_right_brace) and !self.check(.token_eof)) {
            try self.declaration(alloc);
        }

        self.consume(.token_right_brace, "Expect '}' after block statements.");
    }

    fn printStatement(self: *Compiler, alloc: std.mem.Allocator) !void {
        try self.expression(alloc);

        self.consume(.token_semicolon, "Expect ';' after expression.");

        try self.emitOpCode(alloc, .op_print);
    }

    fn expressionStatement(self: *Compiler, alloc: std.mem.Allocator) !void {
        try self.expression(alloc);

        self.consume(.token_semicolon, "Expect ';' after expression.");

        try self.emitOpCode(alloc, .op_pop);
    }

    // Expressions, Pratt.

    fn expression(self: *Compiler, alloc: std.mem.Allocator) !void {
        try self.parsePrecedence(alloc, .ex_assignment);
    }

    fn number(self: *Compiler, alloc: std.mem.Allocator, _: bool) !void {
        const const_value: f64 = try std.fmt.parseFloat(f64, self.parser.previous.str);

        var current_chunk = self.getCurrentChunk();
        try current_chunk.writeConstantAs(alloc, .op_constant, Value{ .val_number = const_value }, self.parser.previous.line);
    }

    fn string(self: *Compiler, alloc: std.mem.Allocator, _: bool) !void {
        var current_chunk = self.getCurrentChunk();
        const token = self.parser.previous;

        var obj_string = try ObjectString.dupe(alloc, token.str[1 .. token.str.len - 1]);
        try current_chunk.writeConstantAs(alloc, .op_constant, Value{ .val_obj = obj_string.asObject() }, self.parser.previous.line);
    }

    fn grouping(self: *Compiler, alloc: std.mem.Allocator, _: bool) !void {
        try self.expression(alloc);

        self.consume(.token_right_paren, "Expect ')' after expression.");
    }

    fn logicAnd(self: *Compiler, alloc: std.mem.Allocator, _: bool) !void {
        const end_jump = try self.emitJump(alloc, .op_jump_if_false);
        try self.emitOpCode(alloc, .op_pop);

        try self.parsePrecedence(alloc, .ex_and);

        self.patchJump(end_jump);
    }

    fn logicOr(self: *Compiler, alloc: std.mem.Allocator, _: bool) !void {
        const end_jump = try self.emitJump(alloc, .op_jump_if_true);
        try self.emitOpCode(alloc, .op_pop);

        try self.parsePrecedence(alloc, .ex_or);

        self.patchJump(end_jump);
    }

    fn binary(self: *Compiler, alloc: std.mem.Allocator, _: bool) !void {
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

    fn unary(self: *Compiler, alloc: std.mem.Allocator, _: bool) !void {
        const operator_type = self.parser.previous.token_type;

        // Compile the operand.
        try self.parsePrecedence(alloc, .ex_unary);

        try switch (operator_type) {
            .token_bang => self.emitOpCode(alloc, .op_not),
            .token_minus => self.emitOpCode(alloc, .op_negate),
            else => unreachable,
        };
    }

    fn variable(self: *Compiler, alloc: std.mem.Allocator, can_assign: bool) !void {
        const current_chunk = self.getCurrentChunk();
        const token = self.parser.previous;

        const local_index = self.resolveLocal(token.str);

        if (local_index) |index| {
            @branchHint(.likely);

            if (can_assign and self.match(.token_equal)) {
                if (!self.locals[index].modifier.mutable) {
                    self.errorAtPrev("Const can not be set after initialization.");
                }

                try self.expression(alloc);
                try self.emitOpByteArg(alloc, .op_set_local, index);
            } else {
                try self.emitOpByteArg(alloc, .op_get_local, index);
            }
        } else {
            const variable_name = try ObjectString.dupe(alloc, token.str);
            const variable_boxed = Value{ .val_obj = variable_name.asObject() };

            if (can_assign and self.match(.token_equal)) {
                try self.expression(alloc);
                try current_chunk.writeConstantAs(alloc, .op_set_global, variable_boxed, token.line);
            } else {
                try current_chunk.writeConstantAs(alloc, .op_get_global, variable_boxed, token.line);
            }
        }
    }

    fn literal(self: *Compiler, alloc: std.mem.Allocator, _: bool) !void {
        try switch (self.parser.previous.token_type) {
            .token_nil => self.emitOpCode(alloc, .op_nil),
            .token_true => self.emitOpCode(alloc, .op_true),
            .token_false => self.emitOpCode(alloc, .op_false),
            else => unreachable,
        };
    }

    fn parsePrecedence(self: *Compiler, alloc: std.mem.Allocator, precedence: Precedence) !void {
        self.advance();

        const can_assign = @intFromEnum(precedence) <= @intFromEnum(Precedence.ex_assignment);

        if (rules[@intFromEnum(self.parser.previous.token_type)].prefix) |prefix_rule| {
            try prefix_rule(self, alloc, can_assign);
        } else {
            self.errorAtPrev("Unexpected expression.");

            return;
        }

        while (@intFromEnum(precedence) <= @intFromEnum(rules[@intFromEnum(self.parser.current.token_type)].precedence)) {
            self.advance();

            if (rules[@intFromEnum(self.parser.previous.token_type)].infix) |infix_rule| {
                try infix_rule(self, alloc, can_assign);
            }
        }

        if (can_assign and self.match(.token_equal)) {
            self.errorAtPrev("Invalid assignment target.");
        }
    }

    // Jumps

    fn emitJump(self: *Compiler, alloc: std.mem.Allocator, comptime op_code: OpCode) !u16 {
        switch (op_code) {
            .op_jump_if_true, .op_jump_if_false, .op_jump => {},
            else => @compileError("Expect only jump related operations."),
        }

        try self.emitOp2ByteArgs(alloc, op_code, 0xFF, 0xFF);

        return @intCast(self.getCurrentChunk().code.items.len - 2);
    }

    fn patchJump(self: *Compiler, jump_op_offset: u16) void {
        const items = self.getCurrentChunk().code.items;
        const current_jump_pos = items.len - jump_op_offset - 2;

        if (jump_op_offset > MAX_U16) {
            self.errorAtCurr("Too many code lines to jump over.");
        }

        items[jump_op_offset] = @intCast(current_jump_pos & 0xFF);
        items[jump_op_offset + 1] = @intCast((current_jump_pos >> 8) & 0xFF);
    }

    // Scope and local related code related functions

    fn addLocal(self: *Compiler, local_name: []const u8, modifier: LocalVar.Modifier) void {
        if (self.locals_count == MAX_U8_PLUS1) {
            self.errorAtPrev("Too many local variables defined.");

            return;
        }

        self.locals[@intCast(self.locals_count)].name = local_name;
        self.locals[@intCast(self.locals_count)].depth = self.locals_depth;
        self.locals[@intCast(self.locals_count)].modifier = modifier;

        self.locals_count += 1;
    }

    inline fn markLastLocalInitialized(self: *Compiler) void {
        self.locals[@intCast(self.locals_count - 1)].modifier.initialized = true;
    }

    fn beginScope(self: *Compiler) void {
        self.locals_depth += 1;
    }

    fn endScope(self: *Compiler, alloc: std.mem.Allocator) !void {
        const current_scope = self.locals_depth;
        self.locals_depth -= 1;

        var i = self.locals_count - 1;
        var pop_count: u8 = 0;

        while (i >= 0 and self.locals[@intCast(i)].depth >= current_scope) : (i -= 1) {
            pop_count += 1;
            self.locals_count -= 1;
        }

        if (pop_count > 0) {
            try self.emitOpByteArg(alloc, .op_popn, pop_count);
        }
    }

    // End scope related functions

    // Synchronisation

    fn synchronization(self: *Compiler) void {
        self.parser.panic_mode = false;

        while (self.parser.current.token_type != .token_eof) {
            if (self.parser.previous.token_type == .token_semicolon) return;

            switch (self.parser.current.token_type) {
                .token_class, .token_fun, .token_var, .token_const, .token_for, .token_if, .token_while, .token_print, .token_return => return,
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

    fn resolveLocal(self: *Compiler, name: []const u8) ?u8 {
        var i = self.locals_count - 1;

        while (i >= 0) : (i -= 1) {
            if (std.mem.eql(u8, self.locals[@intCast(i)].name, name)) {
                if (!self.locals[@intCast(i)].modifier.initialized) {
                    self.errorAtPrev("Can't read local variable in its own initializer.");
                }

                return @intCast(i);
            }
        }

        return null;
    }

    inline fn check(self: *Compiler, token_type: TokenType) bool {
        return self.parser.current.token_type == token_type;
    }

    // Emitters

    fn emitOpCode(self: *Compiler, alloc: std.mem.Allocator, op: OpCode) !void {
        var current_chunk = self.getCurrentChunk();
        try current_chunk.write(alloc, @intFromEnum(op), self.parser.current.line);
    }

    fn emitOpByteArg(self: *Compiler, alloc: std.mem.Allocator, op: OpCode, arg: u8) !void {
        var current_chunk = self.getCurrentChunk();
        try current_chunk.write(alloc, @intFromEnum(op), self.parser.current.line);
        try current_chunk.write(alloc, arg, self.parser.current.line);
    }

    fn emitOp2ByteArgs(self: *Compiler, alloc: std.mem.Allocator, op: OpCode, arg: u8, arg2: u8) !void {
        var current_chunk = self.getCurrentChunk();
        try current_chunk.write(alloc, @intFromEnum(op), self.parser.current.line);
        try current_chunk.write(alloc, arg, self.parser.current.line);
        try current_chunk.write(alloc, arg2, self.parser.current.line);
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
            debug.disassembleChunk(self.getCurrentChunk(), "code");
        }
    }

    fn getCurrentChunk(self: *Compiler) *Chunk {
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
