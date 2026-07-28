const std = @import("std");
const testing = std.testing;

pub const TokenType = enum {
    // Single-character tokens.
    token_left_paren,
    token_right_paren,
    token_left_square,
    token_right_square,
    token_left_brace,
    token_right_brace,
    token_comma,
    token_dot,
    token_minus,
    token_plus,
    token_semicolon,
    token_slash,
    token_star,
    // One or two character tokens.
    token_plus_plus,
    token_bang,
    token_bang_equal,
    token_equal,
    token_equal_equal,
    token_greater,
    token_greater_equal,
    token_less,
    token_less_equal,
    // Literals.
    token_identifier,
    token_string,
    token_number,
    // Keywords.
    token_true,
    token_false,
    token_or,
    token_and,
    token_if,
    token_else,
    token_for,
    token_while,
    token_fun,
    token_return,
    token_class,
    token_super,
    token_this,
    token_var,
    token_nil,
    token_print,
    // Special case
    token_error,
    token_eof,
};

pub const Token = struct {
    token_type: TokenType,
    str: []const u8,
    line: usize,
};

pub const Scanner = struct {
    start: [*]const u8,
    current: [*]const u8,
    eof: [*]const u8,

    line: usize,

    pub fn init(self: *Scanner, source: []const u8) void {
        self.start = source.ptr;
        self.current = source.ptr;
        self.eof = source.ptr + source.len;
        self.line = 0;
    }

    pub fn scanNext(self: *Scanner) Token {
        self.skipWhitespace();
        self.start = self.current;

        if (self.isAtEof()) return self.makeToken(TokenType.token_eof);

        const ch = self.advance();

        if (isAlpha(ch)) return self.consumeIdentifier();
        if (isDigit(ch)) return self.consumeNumber();

        return switch (ch) {
            '{' => self.makeToken(TokenType.token_left_brace),
            '}' => self.makeToken(TokenType.token_right_brace),
            '[' => self.makeToken(TokenType.token_left_square),
            ']' => self.makeToken(TokenType.token_right_square),
            '(' => self.makeToken(TokenType.token_left_paren),
            ')' => self.makeToken(TokenType.token_right_paren),
            ';' => self.makeToken(TokenType.token_semicolon),
            ',' => self.makeToken(TokenType.token_comma),
            '.' => self.makeToken(TokenType.token_dot),

            '-' => self.makeToken(TokenType.token_minus),
            '*' => self.makeToken(TokenType.token_star),
            '/' => self.makeToken(TokenType.token_slash),
            '+' => self.makeToken(if (self.match('+')) TokenType.token_plus_plus else TokenType.token_plus),

            '<' => self.makeToken(if (self.match('=')) TokenType.token_less_equal else TokenType.token_less),
            '>' => self.makeToken(if (self.match('=')) TokenType.token_greater_equal else TokenType.token_greater),
            '=' => self.makeToken(if (self.match('=')) TokenType.token_equal_equal else TokenType.token_equal),
            '!' => self.makeToken(if (self.match('=')) TokenType.token_bang_equal else TokenType.token_bang),

            '"' => self.consumeString(),

            else => self.makeErrorToken("Unexpected character."),
        };
    }

    fn consumeIdentifier(self: *Scanner) Token {
        while (isAlpha(self.peek()) or isDigit(self.peek())) {
            _ = self.advance();
        }

        return self.makeToken(self.inferIdentifierToken());
    }

    fn consumeString(self: *Scanner) Token {
        // TODO: So far escaping is not covered
        // i.e: not consider \" as an end of sequence
        while (self.peek() != '"' and !self.isAtEof()) {
            if (self.peek() == '\n') {
                self.line += 1;
            }
            _ = self.advance();
        }

        if (self.isAtEof()) return self.makeErrorToken("Unterminated string.");

        _ = self.advance(); // Consuming the closing quote
        return self.makeToken(TokenType.token_string);
    }

    fn consumeNumber(self: *Scanner) Token {
        while (isDigit(self.peek())) {
            _ = self.advance();
        }

        if (self.peek() == '.' and isDigit(self.peekNext())) {
            _ = self.advance();
            while (isDigit(self.peek())) {
                _ = self.advance();
            }
        }

        return self.makeToken(TokenType.token_number);
    }

    fn skipWhitespace(self: *Scanner) void {
        while (true) {
            switch (self.peek()) {
                ' ', '\t', '\r' => {
                    _ = self.advance();
                },
                '\n' => {
                    self.line += 1;
                    _ = self.advance();
                },
                '/' => {
                    if (self.peekNext() == '/') {
                        while (self.peek() != '\n' and !self.isAtEof()) {
                            _ = self.advance();
                        }
                    } else {
                        return;
                    }
                },
                else => return,
            }
        }
    }

    inline fn peek(self: Scanner) u8 {
        if (self.isAtEof()) return 0;

        return self.current[0];
    }

    inline fn peekNext(self: Scanner) u8 {
        if (self.isAtEof()) return 0;
        if (self.current + 1 == self.eof) return 0;

        return (self.current + 1)[0];
    }

    inline fn advance(self: *Scanner) u8 {
        const curr = self.current[0];
        self.current += 1;
        return curr;
    }

    inline fn match(self: *Scanner, expected: u8) bool {
        if (self.isAtEof()) return false;
        if (self.current[0] != expected) return false;

        self.current += 1;

        return true;
    }

    inline fn isAtEof(self: Scanner) bool {
        return self.eof == self.current;
    }

    fn isAlpha(char: u8) bool {
        return (char >= 'a' and char <= 'z') or (char >= 'A' and char <= 'Z') or char == '_';
    }

    fn isDigit(char: u8) bool {
        return char >= '0' and char <= '9';
    }

    fn inferIdentifierToken(self: *Scanner) TokenType {
        return switch (self.start[0]) {
            'a' => self.checkKeyword(1, "nd", TokenType.token_and),
            'c' => self.checkKeyword(1, "lass", TokenType.token_class),
            'e' => self.checkKeyword(1, "lse", TokenType.token_else),
            'f' => if (self.current - self.start > 1) switch (self.start[1]) {
                'a' => self.checkKeyword(2, "lse", TokenType.token_false),
                'o' => self.checkKeyword(2, "r", TokenType.token_for),
                'u' => self.checkKeyword(2, "n", TokenType.token_fun),
                else => TokenType.token_identifier,
            } else TokenType.token_identifier,
            'i' => self.checkKeyword(1, "f", TokenType.token_if),
            'n' => self.checkKeyword(1, "il", TokenType.token_nil),
            'o' => self.checkKeyword(1, "r", TokenType.token_or),
            'p' => self.checkKeyword(1, "rint", TokenType.token_print),
            'r' => self.checkKeyword(1, "eturn", TokenType.token_return),
            's' => self.checkKeyword(1, "uper", TokenType.token_super),
            't' => if (self.current - self.start > 1) switch (self.start[1]) {
                'h' => self.checkKeyword(2, "is", TokenType.token_this),
                'r' => self.checkKeyword(2, "ue", TokenType.token_true),
                else => TokenType.token_identifier,
            } else TokenType.token_identifier,
            'v' => self.checkKeyword(1, "ar", TokenType.token_var),
            'w' => self.checkKeyword(1, "hile", TokenType.token_while),
            else => TokenType.token_identifier,
        };
    }

    fn checkKeyword(self: *Scanner, pos: usize, keyword_part: []const u8, token_type: TokenType) TokenType {
        if (self.current - self.start == pos + keyword_part.len and
            std.mem.eql(u8, self.start[pos..(pos + keyword_part.len)], keyword_part))
        {
            return token_type;
        }

        return TokenType.token_identifier;
    }

    fn makeToken(self: *Scanner, tokenType: TokenType) Token {
        const len = self.current - self.start;

        return Token{
            .token_type = tokenType,
            .str = self.start[0..len],
            .line = self.line,
        };
    }

    fn makeErrorToken(self: *Scanner, msg: []const u8) Token {
        return .{
            .token_type = TokenType.token_error,
            .str = msg,
            .line = self.line,
        };
    }
};

// Testing Section

fn expectTokens(scanner: *Scanner, expect_tokens: []struct { TokenType, []const u8 }) !void {
    for (expect_tokens) |tuple| {
        const token = scanner.scanNext();
        const exp_type, const exp_str = tuple;
        try testing.expectEqual(exp_type, token.token_type);
        try testing.expectEqualStrings(exp_str, token.str);
    }
}

fn expectToken(scanner: *Scanner, expected_type: TokenType, expected_str: []const u8) !void {
    const token = scanner.scanNext();
    try testing.expectEqual(expected_type, token.token_type);
    try testing.expectEqualStrings(expected_str, token.str);
}

fn expectEof(scanner: *Scanner) !void {
    const eof_token = scanner.scanNext();
    try testing.expectEqual(TokenType.token_eof, eof_token.token_type);
}

test "expect parsing simple combination of tokenw with 1-2 chars" {
    const source = "{} () [] > < = ! . , ; >= <= != == + - *";
    var scanner: Scanner = undefined;
    scanner.init(source);

    try expectToken(&scanner, TokenType.token_left_brace, "{");
    try expectToken(&scanner, TokenType.token_right_brace, "}");
    try expectToken(&scanner, TokenType.token_left_paren, "(");
    try expectToken(&scanner, TokenType.token_right_paren, ")");
    try expectToken(&scanner, TokenType.token_left_square, "[");
    try expectToken(&scanner, TokenType.token_right_square, "]");
    try expectToken(&scanner, TokenType.token_greater, ">");
    try expectToken(&scanner, TokenType.token_less, "<");
    try expectToken(&scanner, TokenType.token_equal, "=");
    try expectToken(&scanner, TokenType.token_bang, "!");
    try expectToken(&scanner, TokenType.token_dot, ".");
    try expectToken(&scanner, TokenType.token_comma, ",");
    try expectToken(&scanner, TokenType.token_semicolon, ";");
    try expectToken(&scanner, TokenType.token_greater_equal, ">=");
    try expectToken(&scanner, TokenType.token_less_equal, "<=");
    try expectToken(&scanner, TokenType.token_bang_equal, "!=");
    try expectToken(&scanner, TokenType.token_equal_equal, "==");
    try expectToken(&scanner, TokenType.token_plus, "+");
    try expectToken(&scanner, TokenType.token_minus, "-");
    try expectToken(&scanner, TokenType.token_star, "*");
    try expectEof(&scanner);
}

test "expect parsing string tokens" {
    const source = " \"sum of technologies\" ";
    var scanner: Scanner = undefined;
    scanner.init(source);

    try expectToken(&scanner, TokenType.token_string, "\"sum of technologies\"");
    try expectEof(&scanner);
}

test "expect paraing number tokens" {
    const source = " 123 443.432 0.343 54353453 ";
    var scanner: Scanner = undefined;
    scanner.init(source);

    try expectToken(&scanner, TokenType.token_number, "123");
    try expectToken(&scanner, TokenType.token_number, "443.432");
    try expectToken(&scanner, TokenType.token_number, "0.343");
    try expectToken(&scanner, TokenType.token_number, "54353453");
    try expectEof(&scanner);
}

test "expect parsing keywords" {
    const source =
        \\ and or class else
        \\ if nil print return
        \\ true this
        \\ super var while
        \\ false for fun
    ;
    var scanner: Scanner = undefined;
    scanner.init(source);

    try expectToken(&scanner, TokenType.token_and, "and");
    try expectToken(&scanner, TokenType.token_or, "or");
    try expectToken(&scanner, TokenType.token_class, "class");
    try expectToken(&scanner, TokenType.token_else, "else");
    try expectToken(&scanner, TokenType.token_if, "if");
    try expectToken(&scanner, TokenType.token_nil, "nil");
    try expectToken(&scanner, TokenType.token_print, "print");
    try expectToken(&scanner, TokenType.token_return, "return");
    try expectToken(&scanner, TokenType.token_true, "true");
    try expectToken(&scanner, TokenType.token_this, "this");
    try expectToken(&scanner, TokenType.token_super, "super");
    try expectToken(&scanner, TokenType.token_var, "var");
    try expectToken(&scanner, TokenType.token_while, "while");
    try expectToken(&scanner, TokenType.token_false, "false");
    try expectToken(&scanner, TokenType.token_for, "for");
    try expectToken(&scanner, TokenType.token_fun, "fun");

    try expectEof(&scanner);
}

test "expect parsing identifiers" {
    const keyword_src =
        \\ words is here
        \\ classy elsewhere
        \\ ififif andor
        \\ orand nilable
        \\ printy returny superbowl
        \\ vario whileboy
        \\ truely falseie forly funly
        \\ funfun thisisnotakeyword
    ;

    var scanner: Scanner = undefined;
    scanner.init(keyword_src);

    try expectToken(&scanner, TokenType.token_identifier, "words");
    try expectToken(&scanner, TokenType.token_identifier, "is");
    try expectToken(&scanner, TokenType.token_identifier, "here");
    try expectToken(&scanner, TokenType.token_identifier, "classy");
    try expectToken(&scanner, TokenType.token_identifier, "elsewhere");
    try expectToken(&scanner, TokenType.token_identifier, "ififif");
    try expectToken(&scanner, TokenType.token_identifier, "andor");
    try expectToken(&scanner, TokenType.token_identifier, "orand");
    try expectToken(&scanner, TokenType.token_identifier, "nilable");
    try expectToken(&scanner, TokenType.token_identifier, "printy");
    try expectToken(&scanner, TokenType.token_identifier, "returny");
    try expectToken(&scanner, TokenType.token_identifier, "superbowl");
    try expectToken(&scanner, TokenType.token_identifier, "vario");
    try expectToken(&scanner, TokenType.token_identifier, "whileboy");
    try expectToken(&scanner, TokenType.token_identifier, "truely");
    try expectToken(&scanner, TokenType.token_identifier, "falseie");
    try expectToken(&scanner, TokenType.token_identifier, "forly");
    try expectToken(&scanner, TokenType.token_identifier, "funly");
    try expectToken(&scanner, TokenType.token_identifier, "funfun");
    try expectToken(&scanner, TokenType.token_identifier, "thisisnotakeyword");
    try expectEof(&scanner);
}

test "expect to recognize unexpected character in the seq of tokens" {
    const listing = "var keyword = 1 + @";

    var scanner: Scanner = undefined;
    scanner.init(listing);

    try expectToken(&scanner, TokenType.token_var, "var");
    try expectToken(&scanner, TokenType.token_identifier, "keyword");
    try expectToken(&scanner, TokenType.token_equal, "=");
    try expectToken(&scanner, TokenType.token_number, "1");
    try expectToken(&scanner, TokenType.token_plus, "+");
    try expectToken(&scanner, TokenType.token_error, "Unexpected character.");
    try expectEof(&scanner);
}

test "expect to recognize unterminated string" {
    const listing = "var keyword = \"something is";

    var scanner: Scanner = undefined;
    scanner.init(listing);

    try expectToken(&scanner, TokenType.token_var, "var");
    try expectToken(&scanner, TokenType.token_identifier, "keyword");
    try expectToken(&scanner, TokenType.token_equal, "=");
    try expectToken(&scanner, TokenType.token_error, "Unterminated string.");
}
