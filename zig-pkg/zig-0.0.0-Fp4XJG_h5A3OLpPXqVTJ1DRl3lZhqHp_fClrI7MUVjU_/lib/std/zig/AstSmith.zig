//! Generates a valid AST and corresponding source.
//!
//! This is based directly off grammer.peg

const std = @import("../std.zig");
const assert = std.debug.assert;
const Token = std.zig.Token;
const Smith = std.testing.Smith;
const Weight = Smith.Weight;
const AstSmith = @This();

smith: *Smith,

source_buf: [16384]u8,
source_len: usize,

token_tag_buf: [2048]Token.Tag,
token_start_buf: [2048]std.zig.Ast.ByteOffset,
tokens_len: usize,

/// For `.asterisk`, this also includes `.asterisk2`
not_token: ?Token.Tag,
not_token_comptime: bool,
/// ExprSuffix
///     <- KEYWORD_or
///      / KEYWORD_and
///      / CompareOp
///      / BitwiseOp
///      / BitShiftOp
///      / AdditionOp
///      / MultiplyOp
///      / EXCLAMATIONMARK
///      / SuffixOp
///      / FnCallArguments
not_expr_suffix: bool,
/// LabelableExpr
///   <- Block
///    / SwitchExpr
///    / LoopExpr
not_labelable_expr: ?enum { colon, expr },
not_label: bool,
not_break_label: bool,
not_block_expr: bool,
not_expr_statement: bool,

prev_ids_buf: [256]struct { start: u16, len: u16 },
/// This may be larger than `prev_ids` in which case,
///   x % prev_ids.len = next index
///   @min(x, prev_ids) = length
prev_ids_len: usize,

/// `generate` must be called on the returned value before any other methods
pub fn init(smith: *Smith) AstSmith {
    return .{
        .smith = smith,

        .source_buf = undefined,
        .source_len = 0,

        .token_tag_buf = undefined,
        .token_start_buf = undefined,
        .tokens_len = 0,

        .not_token = null,
        .not_token_comptime = false,
        .not_expr_suffix = false,
        .not_labelable_expr = null,
        .not_label = false,
        .not_break_label = false,
        .not_block_expr = false,
        .not_expr_statement = false,

        .prev_ids_buf = undefined,
        .prev_ids_len = 0,
    };
}

pub fn source(t: *AstSmith) [:0]u8 {
    return t.source_buf[0..t.source_len :0];
}

/// The Slice is not backed by a MultiArrayList, so calling deinit or toMultiArrayList is illegal.
pub fn tokens(t: *AstSmith) std.zig.Ast.TokenList.Slice {
    var slice: std.zig.Ast.TokenList.Slice = .{
        .ptrs = undefined,
        .len = t.tokens_len,
        .capacity = t.tokens_len,
    };
    comptime assert(slice.ptrs.len == 2);
    slice.ptrs[@intFromEnum(std.zig.Ast.TokenList.Field.tag)] = @ptrCast(&t.token_tag_buf);
    slice.ptrs[@intFromEnum(std.zig.Ast.TokenList.Field.start)] = @ptrCast(&t.token_start_buf);
    return slice;
}

pub const Error = error{ OutOfMemory, SkipZigTest };
const SourceError = error{SkipZigTest};

pub fn generate(a: *AstSmith, gpa: std.mem.Allocator) Error!std.zig.Ast {
    try a.generateSource();
    const ast = try std.zig.Ast.parseTokens(gpa, a.source(), a.tokens(), .zig);
    assert(ast.errors.len == 0);
    return ast;
}

pub fn generateSource(a: *AstSmith) SourceError!void {
    try a.pegRoot();
    try a.ensureSourceCapacity(1);
    a.source_buf[a.source_len] = 0;
    try a.addTokenTag(.eof);
}

/// For choices which can introduce a variable number of expressions, this should be used to reduce
/// unbounded recursion.
//
// `inline` to propogate caller's return address
inline fn smithListItemBool(a: *AstSmith) bool {
    return a.smith.boolWeighted(63, 1);
}

/// For choices which can introduce a variable number of expressions, this should be used to reduce
/// unbounded recursion.
//
// `inline` to propogate caller's return address
inline fn smithListItemEos(a: *AstSmith) bool {
    return a.smith.eosWeightedSimple(1, 63);
}

fn sourceCapacity(a: *AstSmith) []u8 {
    return a.source_buf[a.source_len..];
}

fn sourceCapacityLen(a: *AstSmith) usize {
    return a.source_buf.len - a.source_len;
}

fn ensureSourceCapacity(a: *AstSmith, n: usize) SourceError!void {
    if (a.sourceCapacityLen() < n) return error.SkipZigTest;
}

fn addSourceByte(a: *AstSmith, byte: u8) SourceError!void {
    try a.ensureSourceCapacity(1);
    a.addSourceByteAssumeCapacity(byte);
}

fn addSourceByteAssumeCapacity(a: *AstSmith, byte: u8) void {
    a.sourceCapacity()[0] = byte;
    a.source_len += 1;
}

fn addSource(a: *AstSmith, bytes: []const u8) SourceError!void {
    try a.ensureSourceCapacity(bytes.len);
    a.addSourceAssumeCapacity(bytes);
}

fn addSourceAssumeCapacity(a: *AstSmith, bytes: []const u8) void {
    @memcpy(a.sourceCapacity()[0..bytes.len], bytes);
    a.source_len += bytes.len;
}

fn addSourceAsSlice(a: *AstSmith, len: usize) SourceError![]u8 {
    try a.ensureSourceCapacity(len);
    return a.addSourceAsSliceAssumeCapacity(len);
}

fn addSourceAsSliceAssumeCapacity(a: *AstSmith, len: usize) []u8 {
    const slice = a.sourceCapacity()[0..len];
    a.source_len += len;
    return slice;
}

fn tokenCapacityLen(a: *AstSmith) usize {
    return a.token_tag_buf.len - a.tokens_len;
}

fn ensureTokenCapacity(a: *AstSmith, n: usize) SourceError!void {
    if (a.tokenCapacityLen() < n) return error.SkipZigTest;
}

fn isAlphanumeric(c: u8) bool {
    return switch (c) {
        '_', 'a'...'z', 'A'...'Z', '0'...'9' => true,
        else => false,
    };
}

/// For tokens starting with alphanumerics, this ensures
/// previous tokens followed by end_of_word aren't altered.
///
/// end_of_word <- ![a-zA-Z0-9_] skip
fn preservePegEndOfWord(a: *AstSmith) SourceError!void {
    if (a.source_len > 0 and isAlphanumeric(a.source_buf[a.source_len - 1])) {
        try a.addSourceByte(' ');
    }
}

/// Assumes the token has not been written yet
fn addTokenTag(a: *AstSmith, tag: Token.Tag) SourceError!void {
    assert(tag != a.not_token);
    if (a.not_token == .asterisk) assert(tag != .asterisk_asterisk);
    a.not_token = null;

    if (a.not_token_comptime) assert(tag != .keyword_comptime);
    a.not_token_comptime = false;

    if (a.not_label and tag == .identifier) {
        a.not_token = .colon;
    }
    a.not_label = false;

    if (a.not_break_label and tag == .colon) {
        a.not_token = .identifier;
    }
    a.not_break_label = false;

    if (a.not_labelable_expr) |part| switch (part) {
        .colon => a.not_labelable_expr = if (tag == .colon) .expr else null,
        .expr => switch (tag) {
            .l_brace => unreachable,
            .keyword_inline => {},
            .keyword_for => unreachable,
            .keyword_while => unreachable,
            .keyword_switch => unreachable,
            else => a.not_labelable_expr = null,
        },
    };

    a.not_expr_suffix = false;
    a.not_block_expr = false;
    a.not_expr_statement = false;

    try a.ensureTokenCapacity(1);
    a.token_tag_buf[a.tokens_len] = tag;
    a.token_start_buf[a.tokens_len] = @intCast(a.source_len);
    a.tokens_len += 1;
}

/// Asserts the token has a lexeme (those without have corresponding methods)
fn pegToken(a: *AstSmith, tag: Token.Tag) SourceError!void {
    const lexeme = tag.lexeme().?;

    switch (lexeme[0]) {
        '_', 'a'...'z', 'A'...'Z', '0'...'9' => try a.preservePegEndOfWord(),
        '*' => if (a.tokens_len > 0 and a.source_buf[a.source_len - 1] == '*' and
            a.token_tag_buf[a.tokens_len - 1] != .asterisk_asterisk)
        {
            try a.addSourceByte(' ');
        },
        '.' => if (a.tokens_len > 0 and switch (a.source_buf[a.source_len - 1]) {
            '.' => true,
            '0'...'9', 'a'...'z', 'A'...'Z' => a.token_tag_buf[a.tokens_len - 1] == .number_literal,
            else => false,
        }) {
            try a.addSourceByte(' ');
        },
        '+', '-' => if (a.tokens_len > 0 and a.token_tag_buf[a.tokens_len - 1] == .number_literal and
            switch (a.source_buf[a.source_len - 1]) {
                'e', 'E', 'p', 'P' => true,
                else => false,
            })
        {
            // Would otherwise be tokenized as the sign of a float's exponent
            //
            // e.g. "0xFE" ++ "+" ++ "2" (number_literal, plus, number_literal)
            try a.addSourceByte(' ');
        },
        else => {},
    }

    if (isAlphanumeric(lexeme[0])) try a.preservePegEndOfWord();

    try a.addTokenTag(tag);
    try a.addSource(lexeme);
    try a.pegSkip();
}

/// Asserts `a.source_len != 0`
fn pegTokenWhitespaceAround(a: *AstSmith, tag: Token.Tag) SourceError!void {
    switch (a.source_buf[a.source_len - 1]) {
        ' ', '\n' => {},
        else => try a.addSourceByte(' '),
    }
    try a.addTokenTag(tag);
    try a.addSource(tag.lexeme().?);
    switch (a.smith.value(enum { space, line_break, cr_line_break })) {
        // This is not the same as 'skip' since comments are not whitespace
        .space => try a.addSourceByte(' '),
        .line_break => try a.addSourceByte('\n'),
        .cr_line_break => try a.addSource("\r\n"),
    }
    try a.pegSkip();
}

/// Root <- skip ContainerMembers eof
fn pegRoot(a: *AstSmith) SourceError!void {
    try a.pegSkip();
    try a.pegContainerMembers();
}

/// ContainerMembers <- container_doc_comment? ContainerDeclaration* (ContainerField COMMA)*
///                     (ContainerField / ContainerDeclaration*)
fn pegContainerMembers(a: *AstSmith) SourceError!void {
    if (a.smith.boolWeighted(63, 1)) {
        try a.pegContainerDocComment();
    }
    while (!a.smithListItemEos()) {
        try a.pegContainerDeclaration();
    }
    while (!a.smithListItemEos()) {
        try a.pegContainerField();
        try a.pegToken(.comma);
    }
    if (a.smithListItemBool()) {
        if (a.smith.value(bool)) {
            try a.pegContainerField();
        } else while (true) {
            try a.pegContainerDeclaration();
            if (a.smithListItemEos()) break;
        }
    }
}

/// ContainerDeclaration <- TestDecl / ComptimeDecl / doc_comment? KEYWORD_pub? Decl
fn pegContainerDeclaration(a: *AstSmith) SourceError!void {
    switch (a.smith.value(enum { TestDecl, ComptimeDecl, Decl })) {
        .TestDecl => try a.pegTestDecl(),
        .ComptimeDecl => try a.pegComptimeDecl(),
        .Decl => {
            try a.pegMaybeDocComment();
            if (a.smith.value(bool)) {
                try a.pegToken(.keyword_pub);
            }
            try a.pegDecl();
        },
    }
}

/// KEYWORD_test (STRINGLITERALSINGLE / IDENTIFIER)? Block
fn pegTestDecl(a: *AstSmith) SourceError!void {
    try a.pegToken(.keyword_test);
    switch (a.smith.value(enum { none, string, id })) {
        .none => {},
        .string => try a.pegStringLiteralSingle(),
        .id => try a.pegIdentifier(),
    }
    try a.pegBlock();
}

/// ComptimeDecl <- KEYWORD_comptime Block
fn pegComptimeDecl(a: *AstSmith) SourceError!void {
    try a.pegToken(.keyword_comptime);
    try a.pegBlock();
}

/// Decl
///    <- (KEYWORD_export / KEYWORD_inline / KEYWORD_noinline)? FnProto (SEMICOLON / Block)
///     / KEYWORD_extern STRINGLITERALSINGLE? FnProto SEMICOLON
///     / (KEYWORD_export / KEYWORD_extern STRINGLITERALSINGLE?)? KEYWORD_threadlocal?
///     GlobalVarDecl
fn pegDecl(a: *AstSmith) SourceError!void {
    const Modifier = enum(u8) {
        none,
        @"export",
        @"extern",
        extern_library,
        @"inline",
        @"noinline",
    };
    const is_fn = a.smith.value(bool);
    const fn_modifiers = Smith.baselineWeights(Modifier);
    const var_modifiers: []const Weight = &.{.rangeAtMost(Modifier, .none, .extern_library, 1)};
    const modifier = a.smith.valueWeighted(Modifier, if (is_fn) fn_modifiers else var_modifiers);

    switch (modifier) {
        .none => {},
        .@"export" => try a.pegToken(.keyword_export),
        .@"extern" => try a.pegToken(.keyword_extern),
        .extern_library => {
            try a.pegToken(.keyword_extern);
            try a.pegStringLiteralSingle();
        },
        .@"inline" => try a.pegToken(.keyword_inline),
        .@"noinline" => try a.pegToken(.keyword_noinline),
    }

    if (is_fn) {
        try a.pegFnProto();
        if (modifier == .@"extern" or modifier == .extern_library or a.smith.value(bool)) {
            try a.pegToken(.semicolon);
        } else {
            try a.pegBlock();
        }
    } else {
        if (a.smith.value(bool)) try a.pegToken(.keyword_threadlocal);
        try a.pegGlobalVarDecl();
    }
}

/// FnProto <- KEYWORD_fn IDENTIFIER? LPAREN ParamDeclList RPAREN ByteAlign? AddrSpace?
///          LinkSection? CallConv? EXCLAMATIONMARK? TypeExpr !ExprSuffix
fn pegFnProto(a: *AstSmith) SourceError!void {
    try a.pegToken(.keyword_fn);
    if (a.smith.value(bool)) {
        try a.pegIdentifier();
    }
    try a.pegToken(.l_paren);
    try a.pegParamDeclList();
    try a.pegToken(.r_paren);
    if (a.smith.value(bool)) {
        try a.pegByteAlign();
    }
    if (a.smith.value(bool)) {
        try a.pegAddrSpace();
    }
    if (a.smith.value(bool)) {
        try a.pegLinkSection();
    }
    if (a.smith.value(bool)) {
        try a.pegCallConv();
    }
    if (a.smith.value(bool)) {
        try a.pegToken(.bang);
    }
    try a.pegTypeExpr();
    a.not_expr_suffix = true;
}

/// VarDeclProto <- (KEYWORD_const / KEYWORD_var) IDENTIFIER (COLON TypeExpr)? ByteAlign?
///               AddrSpace? LinkSection?
fn pegVarDeclProto(a: *AstSmith) SourceError!void {
    try a.pegToken(if (a.smith.value(bool)) .keyword_var else .keyword_const);
    try a.pegIdentifier();

    if (a.smith.value(bool)) {
        try a.pegToken(.colon);
        try a.pegTypeExpr();
    }

    if (a.smith.value(bool)) {
        try a.pegByteAlign();
    }

    if (a.smith.value(bool)) {
        try a.pegAddrSpace();
    }

    if (a.smith.value(bool)) {
        try a.pegLinkSection();
    }
}

/// GlobalVarDecl <- VarDeclProto (EQUAL Expr)? SEMICOLON
fn pegGlobalVarDecl(a: *AstSmith) SourceError!void {
    try a.pegVarDeclProto();
    if (a.smithListItemBool()) {
        try a.pegToken(.equal);
        try a.pegExpr();
    }
    try a.pegToken(.semicolon);
}

/// ContainerField <- doc_comment? (KEYWORD_comptime / !KEYWORD_comptime) !KEYWORD_fn
///                 (IDENTIFIER COLON !(IDENTIFIER COLON)) TypeExpr ByteAlign? (EQUAL Expr)?
fn pegContainerField(a: *AstSmith) SourceError!void {
    try a.pegMaybeDocComment();
    if (a.smith.value(bool)) {
        try a.pegToken(.keyword_comptime);
    }
    if (a.smith.value(bool)) {
        try a.pegIdentifier();
        try a.pegToken(.colon);
    } else {
        a.not_token = .keyword_fn;
        a.not_token_comptime = true;
        a.not_label = true;
    }
    try a.pegTypeExpr();
    if (a.smith.value(bool)) {
        try a.pegByteAlign();
    }
    if (a.smith.value(bool)) {
        try a.pegToken(.equal);
        try a.pegExpr();
    }
}

/// BlockStatement
///     <- Statement
///      / KEYWORD_defer BlockExprStatement
///      / KEYWORD_errdefer Payload? BlockExprStatement
///      / !ExprStatement (KEYWORD_comptime !BlockExpr)? VarAssignStatement
fn pegBlockStatement(a: *AstSmith) SourceError!void {
    const Kind = enum {
        statement,
        defer_statement,
        errdefer_statement,
        var_assign,
        comptime_var_assign,
    };
    const weights = Smith.baselineWeights(Kind) ++ &[1]Weight{.value(Kind, .statement, 4)};
    switch (a.smith.valueWeighted(Kind, weights)) {
        .statement => try a.pegStatement(),
        .defer_statement, .errdefer_statement => |kind| {
            try a.pegToken(switch (kind) {
                .defer_statement => .keyword_defer,
                .errdefer_statement => .keyword_errdefer,
                else => unreachable,
            });
            try a.pegBlockExprStatement();
        },
        .var_assign, .comptime_var_assign => |kind| {
            a.not_expr_statement = true;
            if (kind == .comptime_var_assign) {
                try a.pegToken(.keyword_comptime);
                a.not_block_expr = true;
            }
            try a.pegVarAssignStatement();
        },
    }
}

/// Statement
///     <- ExprStatement
///      / KEYWORD_suspend BlockExprStatement
///      / !ExprStatement (KEYWORD_comptime !BlockExpr)? AssignExpr SEMICOLON
///
/// ExprStatement
///     <- IfStatement
///      / LabeledStatement
///      / KEYWORD_nosuspend BlockExprStatement
///      / KEYWORD_comptime BlockExpr
fn pegStatement(a: *AstSmith) SourceError!void {
    switch (a.smith.value(enum {
        if_statement,
        labeled_statement,
        comptime_block_expr,

        nosuspend_statement,
        suspend_statement,
        assign_expr,
        comptime_assign_expr,
    })) {
        .if_statement => try a.pegIfStatement(),
        .labeled_statement => try a.pegLabeledStatement(),
        .comptime_block_expr => {
            try a.pegToken(.keyword_comptime);
            try a.pegBlockExpr();
        },

        .nosuspend_statement,
        .suspend_statement,
        => |kind| {
            try a.pegToken(switch (kind) {
                .nosuspend_statement => .keyword_nosuspend,
                .suspend_statement => .keyword_suspend,
                else => unreachable,
            });
            try a.pegBlockExprStatement();
        },
        .assign_expr, .comptime_assign_expr => |kind| {
            a.not_expr_statement = true;
            if (kind == .comptime_assign_expr) {
                try a.pegToken(.keyword_comptime);
                a.not_block_expr = true;
            }
            try a.pegAssignExpr();
            try a.pegToken(.semicolon);
        },
    }
}

/// IfStatement
///     <- IfPrefix BlockExpr ( KEYWORD_else Payload? Statement )?
///      / IfPrefix !BlockExpr AssignExpr ( SEMICOLON / KEYWORD_else Payload? Statement )
fn pegIfStatement(a: *AstSmith) SourceError!void {
    try a.pegIfPrefix();
    const is_assign = a.smith.value(bool);
    if (!is_assign) {
        try a.pegBlockExpr();
    } else {
        a.not_block_expr = true;
        try a.pegAssignExpr();
    }
    if (a.not_token != .keyword_else and a.smithListItemBool()) {
        try a.pegToken(.keyword_else);
        if (a.smith.value(bool)) {
            try a.pegPayload();
        }
        try a.pegStatement();
    } else if (is_assign) {
        try a.pegToken(.semicolon);
    } else {
        a.not_token = .keyword_else;
    }
}

/// LabeledStatement <- BlockLabel? (Block / LoopStatement / SwitchExpr)
fn pegLabeledStatement(a: *AstSmith) SourceError!void {
    if (a.smith.value(bool)) {
        try a.pegBlockLabel();
    }
    switch (a.smith.value(enum { block, loop_statement, switch_expr })) {
        .block => try a.pegBlock(),
        .loop_statement => try a.pegLoopStatement(),
        .switch_expr => try a.pegSwitchExpr(),
    }
}

/// LoopStatement <- KEYWORD_inline? (ForStatement / WhileStatement)
fn pegLoopStatement(a: *AstSmith) SourceError!void {
    if (a.smith.value(bool)) {
        try a.pegToken(.keyword_inline);
    }
    if (a.smith.value(bool)) {
        try a.pegForStatement();
    } else {
        try a.pegWhileStatement();
    }
}

/// ForStatement
///     <- ForPrefix BlockExpr ( KEYWORD_else Statement / !KEYWORD_else )
///      / ForPrefix !BlockExpr AssignExpr ( SEMICOLON / KEYWORD_else Statement )
fn pegForStatement(a: *AstSmith) SourceError!void {
    try a.pegForPrefix();
    const is_assign = a.smith.value(bool);
    if (!is_assign) {
        try a.pegBlockExpr();
    } else {
        a.not_block_expr = true;
        try a.pegAssignExpr();
    }
    if (a.not_token != .keyword_else and a.smithListItemBool()) {
        try a.pegToken(.keyword_else);
        try a.pegStatement();
    } else if (is_assign) {
        try a.pegToken(.semicolon);
    } else {
        a.not_token = .keyword_else;
    }
}

/// WhileStatement
///     <- WhilePrefix BlockExpr ( KEYWORD_else Payload? Statement )?
///      / WhilePrefix !BlockExpr AssignExpr ( SEMICOLON / KEYWORD_else Payload? Statement )
fn pegWhileStatement(a: *AstSmith) SourceError!void {
    try a.pegWhilePrefix();
    const is_assign = a.smith.value(bool);
    if (!is_assign) {
        try a.pegBlockExpr();
    } else {
        a.not_block_expr = true;
        try a.pegAssignExpr();
    }
    if (a.not_token != .keyword_else and a.smithListItemBool()) {
        try a.pegToken(.keyword_else);
        if (a.smith.value(bool)) {
            try a.pegPayload();
        }
        try a.pegStatement();
    } else if (is_assign) {
        try a.pegToken(.semicolon);
    } else {
        a.not_token = .keyword_else;
    }
}

/// BlockExprStatement
///     <- BlockExpr
///      / !BlockExpr AssignExpr SEMICOLON
fn pegBlockExprStatement(a: *AstSmith) SourceError!void {
    if (a.smith.value(bool)) {
        try a.pegBlockExpr();
    } else {
        a.not_block_expr = true;
        try a.pegAssignExpr();
        try a.pegToken(.semicolon);
    }
}

/// BlockExpr <- BlockLabel? Block
fn pegBlockExpr(a: *AstSmith) SourceError!void {
    if (a.smith.value(bool)) {
        try a.pegBlockLabel();
    }
    try a.pegBlock();
}

/// VarAssignStatement <- (Expr / VarDeclProto) (COMMA (Expr / VarDeclProto))* EQUAL Expr SEMICOLON
fn pegVarAssignStatement(a: *AstSmith) SourceError!void {
    while (true) {
        if (a.smith.value(bool)) {
            try a.pegVarDeclProto();
        } else {
            try a.pegExpr();
        }

        if (a.smithListItemEos()) {
            break;
        } else {
            try a.pegToken(.comma);
        }
    }

    try a.pegToken(.equal);
    try a.pegExpr();
    try a.pegToken(.semicolon);
}

/// AssignExpr <- Expr (AssignOp Expr / (COMMA Expr)+ EQUAL Expr)?
fn pegAssignExpr(a: *AstSmith) SourceError!void {
    try a.pegExpr();
    if (a.smith.value(bool)) {
        if (!a.smithListItemBool()) {
            try a.pegAssignOp();
        } else {
            while (true) {
                try a.pegToken(.comma);
                try a.pegExpr();
                if (a.smithListItemEos()) break;
            }
            try a.pegToken(.equal);
        }
        try a.pegExpr();
    }
}

/// SingleAssignExpr <- Expr (AssignOp Expr)?
fn pegSingleAssignExpr(a: *AstSmith) SourceError!void {
    try a.pegExpr();
    if (a.smith.value(bool)) {
        try a.pegAssignOp();
        try a.pegExpr();
    }
}

/// Expr <- BoolOrExpr
const pegExpr = pegBoolOrExpr;

/// BoolOrExpr <- BoolAndExpr (KEYWORD_or BoolAndExpr)*
fn pegBoolOrExpr(a: *AstSmith) SourceError!void {
    try a.pegBoolAndExpr();
    while (!a.not_expr_suffix and !a.smithListItemEos()) {
        try a.pegTokenWhitespaceAround(.keyword_or);
        try a.pegBoolAndExpr();
    }
}

/// BoolAndExpr <- CompareExpr (KEYWORD_and CompareExpr)*
fn pegBoolAndExpr(a: *AstSmith) SourceError!void {
    try a.pegCompareExpr();
    while (!a.not_expr_suffix and !a.smithListItemEos()) {
        try a.pegTokenWhitespaceAround(.keyword_and);
        try a.pegCompareExpr();
    }
}

/// CompareExpr <- BitwiseExpr (CompareOp BitwiseExpr)?
fn pegCompareExpr(a: *AstSmith) SourceError!void {
    try a.pegBitwiseExpr();
    if (!a.not_expr_suffix and a.smithListItemBool()) {
        try a.pegCompareOp();
        try a.pegBitwiseExpr();
    }
}

/// BitwiseExpr <- BitShiftExpr (BitwiseOp BitShiftExpr)*
fn pegBitwiseExpr(a: *AstSmith) SourceError!void {
    try a.pegBitShiftExpr();
    while (!a.not_expr_suffix and !a.smithListItemEos()) {
        try a.pegBitwiseOp();
        try a.pegBitShiftExpr();
    }
}

/// BitShiftExpr <- AdditionExpr (BitShiftOp AdditionExpr)*
fn pegBitShiftExpr(a: *AstSmith) SourceError!void {
    try a.pegAdditionExpr();
    while (!a.not_expr_suffix and !a.smithListItemEos()) {
        try a.pegBitShiftOp();
        try a.pegAdditionExpr();
    }
}

/// AdditionExpr <- MultiplyExpr (AdditionOp MultiplyExpr)*
fn pegAdditionExpr(a: *AstSmith) SourceError!void {
    try a.pegMultiplyExpr();
    while (!a.not_expr_suffix and !a.smithListItemEos()) {
        try a.pegAdditionOp();
        try a.pegMultiplyExpr();
    }
}

/// MultiplyExpr <- PrefixExpr (MultiplyOp PrefixExpr)*
fn pegMultiplyExpr(a: *AstSmith) SourceError!void {
    try a.pegPrefixExpr();
    while (!a.not_expr_suffix and !a.smithListItemEos()) {
        try a.pegMultiplyOp();
        try a.pegPrefixExpr();
    }
}

/// PrefixExpr <- PrefixOp* PrimaryExpr
fn pegPrefixExpr(a: *AstSmith) SourceError!void {
    while (!a.smithListItemEos()) {
        try a.pegPrefixOp();
    }
    try a.pegPrimaryExpr();
}

/// PrimaryExpr
///     <- AsmExpr
///      / IfExpr
///      / KEYWORD_break (BreakLabel / !BreakLabel) (Expr !ExprSuffix / !SinglePtrTypeStart)
///      / KEYWORD_comptime Expr !ExprSuffix
///      / KEYWORD_nosuspend Expr !ExprSuffix
///      / KEYWORD_continue (BreakLabel / !BreakLabel) (Expr !ExprSuffix / !SinglePtrTypeStart)
///      / KEYWORD_resume Expr !ExprSuffix
///      / KEYWORD_return (Expr !ExprSuffix / !SinglePtrTypeStart)
///      / BlockLabel? LoopExpr
///      / Block
///      / CurlySuffixExpr
fn pegPrimaryExpr(a: *AstSmith) SourceError!void {
    const Kind = enum(u8) {
        curly_suffix_expr,
        @"return",
        @"continue",
        @"break",
        block,
        asm_expr,
        // Always contain more expressions
        if_expr,
        loop_expr,
        @"resume",
        @"comptime",
        @"nosuspend",
    };

    switch (a.smith.valueWeighted(Kind, &.{
        .value(Kind, .curly_suffix_expr, 75),
        .rangeAtMost(Kind, .@"return", .asm_expr, 4),
        .rangeAtMost(Kind, .if_expr, .@"nosuspend", 1),
    })) {
        .curly_suffix_expr => try a.pegCurlySuffixExpr(),

        .block => if (a.not_labelable_expr != .expr and !a.not_block_expr and !a.not_expr_statement) {
            try a.pegBlock();
        } else {
            // Group
            try a.pegToken(.l_paren);
            try a.pegBlock();
            try a.pegToken(.r_paren);
        },
        .asm_expr => try a.pegAsmExpr(),
        .if_expr => if (!a.not_expr_statement) {
            try a.pegIfExpr();
        } else {
            // Group
            try a.pegToken(.l_paren);
            try a.pegIfExpr();
            try a.pegToken(.r_paren);
        },
        .loop_expr => {
            const group = a.not_labelable_expr == .expr or a.not_expr_statement;
            if (group) try a.pegToken(.l_paren);
            if (!a.not_label and a.not_token != .identifier and a.smith.value(bool)) {
                try a.pegBlockLabel();
            }
            try a.pegLoopExpr();
            if (group) try a.pegToken(.r_paren);
        },

        .@"return",
        .@"comptime",
        .@"nosuspend",
        .@"resume",
        .@"break",
        .@"continue",
        => |t| {
            const group = a.not_expr_statement and (t == .@"nosuspend" or t == .@"comptime");
            if (group) try a.pegToken(.l_paren);

            const kw: Token.Tag, const label, const expr = switch (t) {
                .@"return" => .{ .keyword_return, false, a.smithListItemBool() },
                .@"comptime" => .{ .keyword_comptime, false, true },
                .@"nosuspend" => .{ .keyword_nosuspend, false, true },
                .@"resume" => .{ .keyword_resume, false, true },
                .@"break" => .{ .keyword_break, a.smith.value(bool), a.smithListItemBool() },
                .@"continue" => .{ .keyword_continue, a.smith.value(bool), a.smithListItemBool() },
                else => unreachable,
            };
            try a.pegToken(kw);
            if (label) {
                try a.pegBreakLabel();
            } else {
                a.not_break_label = true;
            }
            if (expr) {
                try a.pegExpr();
                a.not_expr_suffix = true;
            } else {
                a.not_token = .asterisk;
            }

            if (group) try a.pegToken(.r_paren);
        },
    }
}

/// IfExpr <- IfPrefix Expr (KEYWORD_else Payload? Expr)? !ExprSuffix
fn pegIfExpr(a: *AstSmith) SourceError!void {
    try a.pegIfPrefix();
    try a.pegExpr();
    const Else = enum { none, @"else", else_payload };
    switch (if (a.not_token != .keyword_else) a.smith.value(Else) else .none) {
        .none => a.not_token = .keyword_else,
        .@"else" => {
            try a.pegToken(.keyword_else);
            try a.pegExpr();
        },
        .else_payload => {
            try a.pegToken(.keyword_else);
            try a.pegPayload();
            try a.pegExpr();
        },
    }
    a.not_expr_suffix = true;
}

/// Block <- LBRACE Statement* RBRACE
fn pegBlock(a: *AstSmith) SourceError!void {
    try a.pegToken(.l_brace);
    while (!a.smithListItemEos()) {
        try a.pegBlockStatement();
    }
    try a.pegToken(.r_brace);
}

/// LoopExpr <- KEYWORD_inline? (ForExpr / WhileExpr)
fn pegLoopExpr(a: *AstSmith) SourceError!void {
    if (a.smith.value(bool)) {
        try a.pegToken(.keyword_inline);
    }

    if (a.smith.value(bool)) {
        try a.pegForExpr();
    } else {
        try a.pegWhileExpr();
    }
}

/// ForExpr <- ForPrefix Expr (KEYWORD_else Expr / !KEYWORD_else) !ExprSuffix
fn pegForExpr(a: *AstSmith) SourceError!void {
    try a.pegForPrefix();
    try a.pegExpr();
    if (a.not_token != .keyword_else and a.smith.value(bool)) {
        try a.pegToken(.keyword_else);
        try a.pegExpr();
    } else {
        a.not_token = .keyword_else;
    }
    a.not_expr_suffix = true;
}

/// WhileExpr <- WhilePrefix Expr (KEYWORD_else Payload? Expr)? !ExprSuffix
fn pegWhileExpr(a: *AstSmith) SourceError!void {
    try a.pegWhilePrefix();
    try a.pegExpr();
    const Else = enum { none, @"else", else_payload };
    switch (if (a.not_token != .keyword_else) a.smith.value(Else) else .none) {
        .none => a.not_token = .keyword_else,
        .@"else" => {
            try a.pegToken(.keyword_else);
            try a.pegExpr();
        },
        .else_payload => {
            try a.pegToken(.keyword_else);
            try a.pegPayload();
            try a.pegExpr();
        },
    }
    a.not_expr_suffix = true;
}

/// CurlySuffixExpr <- TypeExpr InitList?
fn pegCurlySuffixExpr(a: *AstSmith) SourceError!void {
    try a.pegTypeExpr();
    if (!a.not_expr_suffix and a.smith.value(bool)) {
        try a.pegInitList();
    }
}

/// InitList
///     <- LBRACE FieldInit (COMMA FieldInit)* COMMA? RBRACE
///      / LBRACE Expr (COMMA Expr)* COMMA? RBRACE
///      / LBRACE RBRACE
fn pegInitList(a: *AstSmith) SourceError!void {
    try a.pegToken(.l_brace);
    if (a.smithListItemBool()) {
        if (a.smith.value(bool)) {
            try a.pegFieldInit();
            while (!a.smithListItemEos()) {
                try a.pegToken(.comma);
                try a.pegFieldInit();
            }
        } else {
            try a.pegExpr();
            while (!a.smithListItemEos()) {
                try a.pegToken(.comma);
                try a.pegExpr();
            }
        }
        if (a.smith.value(bool)) {
            try a.pegToken(.comma);
        }
    }
    try a.pegToken(.r_brace);
}

/// PrefixTypeOp* ErrorUnionExpr
fn pegTypeExpr(a: *AstSmith) SourceError!void {
    while (!a.smithListItemEos()) {
        try a.pegPrefixTypeOp();
    }
    try a.pegErrorUnionExpr();
}

/// ErrorUnionExpr <- SuffixExpr (EXCLAMATIONMARK TypeExpr)?
fn pegErrorUnionExpr(a: *AstSmith) SourceError!void {
    try a.pegSuffixExpr();
    if (!a.not_expr_suffix and a.smithListItemBool()) {
        try a.pegToken(.bang);
        try a.pegTypeExpr();
    }
}

/// SuffixExpr
///    <- PrimaryTypeExpr (SuffixOp / FnCallArguments)*
fn pegSuffixExpr(a: *AstSmith) SourceError!void {
    try a.pegPrimaryTypeExpr();
    while (!a.not_expr_suffix and !a.smithListItemEos()) {
        if (a.smith.value(bool)) {
            try a.pegSuffixOp();
        } else {
            try a.pegFnCallArguments();
        }
    }
}

/// PrimaryTypeExpr
///     <- BUILTINIDENTIFIER FnCallArguments
///      / CHAR_LITERAL
///      / ContainerDecl
///      / DOT IDENTIFIER
///      / DOT InitList
///      / ErrorSetDecl
///      / FLOAT
///      / FnProto
///      / GroupedExpr
///      / LabeledTypeExpr
///      / IDENTIFIER !(COLON LabelableExpr)
///      / IfTypeExpr
///      / INTEGER
///      / KEYWORD_comptime TypeExpr !ExprSuffix
///      / KEYWORD_error DOT IDENTIFIER
///      / KEYWORD_anyframe
///      / KEYWORD_unreachable
///      / STRINGLITERAL
fn pegPrimaryTypeExpr(a: *AstSmith) SourceError!void {
    const Kind = enum(u8) {
        identifier,
        float,
        integer,
        char_literal,
        string_literal,
        enum_literal,
        error_literal,
        unreachable_type,
        anyframe_type,

        // Containing zero or more expressions
        builtin_call,
        array_literal,
        container_decl,
        fn_proto,
        error_set,

        // Containing one or more epressions
        grouped,
        labeled_type_expr,
        if_type_expr,
        comptime_expr,
    };

    switch (a.smith.valueWeighted(Kind, &.{
        .rangeAtMost(Kind, .identifier, .anyframe_type, 5),
        .rangeAtMost(Kind, .builtin_call, .error_set, 2),
        .rangeAtMost(Kind, .grouped, .comptime_expr, 1),
    })) {
        .identifier => if (a.not_token != .identifier) {
            try a.pegIdentifier();
            a.not_labelable_expr = .colon;
        } else {
            // Group
            try a.pegToken(.l_paren);
            try a.pegIdentifier();
            try a.pegToken(.r_paren);
        },
        .float => try a.pegFloat(),
        .integer => try a.pegInteger(),
        .char_literal => try a.pegCharLiteral(),
        .string_literal => try a.pegStringLiteral(),
        .enum_literal => {
            try a.pegToken(.period);
            try a.pegIdentifier();
        },
        .error_literal => {
            try a.pegToken(.keyword_error);
            try a.pegToken(.period);
            try a.pegIdentifier();
        },
        .unreachable_type => try a.pegToken(.keyword_unreachable),
        .anyframe_type => try a.pegToken(.keyword_anyframe),

        .builtin_call => {
            try a.pegBuiltinIdentifier();
            try a.pegFnCallArguments();
        },
        .array_literal => {
            try a.pegToken(.period);
            try a.pegInitList();
        },
        .container_decl => try a.pegContainerDecl(),
        .fn_proto => if (a.not_token != .keyword_fn) {
            try a.pegFnProto();
        } else {
            // Group
            try a.pegToken(.l_paren);
            try a.pegFnProto();
            try a.pegToken(.r_paren);
        },
        .error_set => try a.pegErrorSetDecl(),

        .grouped => try a.pegGroupedExpr(),
        .labeled_type_expr => try a.pegLabeledTypeExpr(),
        .if_type_expr => if (!a.not_expr_statement) {
            try a.pegIfTypeExpr();
        } else {
            // Group
            try a.pegToken(.l_paren);
            try a.pegIfTypeExpr();
            try a.pegToken(.r_paren);
        },
        .comptime_expr => if (!a.not_token_comptime and !a.not_expr_statement) {
            try a.pegToken(.keyword_comptime);
            try a.pegTypeExpr();
        } else {
            // Group
            try a.pegToken(.l_paren);
            try a.pegToken(.keyword_comptime);
            try a.pegTypeExpr();
            try a.pegToken(.r_paren);
        },
    }
}

/// ContainerDecl <- (KEYWORD_extern / KEYWORD_packed)? ContainerDeclAuto
fn pegContainerDecl(a: *AstSmith) SourceError!void {
    switch (a.smith.value(enum { auto, @"extern", @"packed" })) {
        .auto => {},
        .@"extern" => try a.pegToken(.keyword_extern),
        .@"packed" => try a.pegToken(.keyword_packed),
    }
    try a.pegContainerDeclAuto();
}

/// ErrorSetDecl <- KEYWORD_error LBRACE IdentifierList RBRACE
fn pegErrorSetDecl(a: *AstSmith) SourceError!void {
    try a.pegToken(.keyword_error);
    try a.pegToken(.l_brace);
    try a.pegIdentifierList();
    try a.pegToken(.r_brace);
}

/// GroupedExpr <- LPAREN Expr RPAREN
fn pegGroupedExpr(a: *AstSmith) SourceError!void {
    try a.pegToken(.l_paren);
    try a.pegExpr();
    try a.pegToken(.r_paren);
}

/// IfTypeExpr <- IfPrefix TypeExpr (KEYWORD_else Payload? TypeExpr)? !ExprSuffix
fn pegIfTypeExpr(a: *AstSmith) SourceError!void {
    try a.pegIfPrefix();
    try a.pegTypeExpr();
    const Else = enum { none, @"else", else_payload };
    switch (if (a.not_token != .keyword_else) a.smith.value(Else) else .none) {
        .none => a.not_token = .keyword_else,
        .@"else" => {
            try a.pegToken(.keyword_else);
            try a.pegTypeExpr();
        },
        .else_payload => {
            try a.pegToken(.keyword_else);
            try a.pegPayload();
            try a.pegTypeExpr();
        },
    }
    a.not_expr_suffix = true;
}

/// LabeledTypeExpr
///     <- BlockLabel Block
///      / BlockLabel? LoopTypeExpr
///      / BlockLabel? SwitchExpr
fn pegLabeledTypeExpr(a: *AstSmith) SourceError!void {
    const kind = a.smith.value(enum { block, loop, @"switch" });
    const not_any = a.not_labelable_expr == .expr or a.not_expr_statement;
    const no_label = a.not_label or a.not_token == .identifier;
    const no_block = no_label or a.not_block_expr;
    const group = not_any or (kind == .block and no_block);
    if (group) try a.pegToken(.l_paren);

    switch (kind) {
        .block => {
            try a.pegBlockLabel();
            try a.pegBlock();
        },
        .loop => {
            if (!no_label and a.smith.value(bool)) {
                try a.pegBlockLabel();
            }
            try a.pegLoopTypeExpr();
        },
        .@"switch" => {
            if (!no_label and a.smith.value(bool)) {
                try a.pegBlockLabel();
            }
            try a.pegSwitchExpr();
        },
    }

    if (group) try a.pegToken(.r_paren);
}

/// LoopTypeExpr <- KEYWORD_inline? (ForTypeExpr / WhileTypeExpr)
fn pegLoopTypeExpr(a: *AstSmith) SourceError!void {
    if (a.smith.value(bool)) {
        try a.pegToken(.keyword_inline);
    }

    if (a.smith.value(bool)) {
        try a.pegForTypeExpr();
    } else {
        try a.pegWhileTypeExpr();
    }
}

/// ForTypeExpr <- ForPrefix TypeExpr (KEYWORD_else TypeExpr / !KEYWORD_else) !ExprSuffix
fn pegForTypeExpr(a: *AstSmith) SourceError!void {
    try a.pegForPrefix();
    try a.pegTypeExpr();
    if (a.not_token != .keyword_else and a.smith.value(bool)) {
        try a.pegToken(.keyword_else);
        try a.pegTypeExpr();
    } else {
        a.not_token = .keyword_else;
    }
    a.not_expr_suffix = true;
}

/// WhileTypeExpr <- WhilePrefix TypeExpr (KEYWORD_else Payload? TypeExpr)? !ExprSuffix
fn pegWhileTypeExpr(a: *AstSmith) SourceError!void {
    try a.pegWhilePrefix();
    try a.pegTypeExpr();
    const Else = enum { none, @"else", else_payload };
    switch (if (a.not_token != .keyword_else) a.smith.value(Else) else .none) {
        .none => a.not_token = .keyword_else,
        .@"else" => {
            try a.pegToken(.keyword_else);
            try a.pegTypeExpr();
        },
        .else_payload => {
            try a.pegToken(.keyword_else);
            try a.pegPayload();
            try a.pegTypeExpr();
        },
    }
    a.not_expr_suffix = true;
}

/// SwitchExpr <- KEYWORD_switch LPAREN Expr RPAREN LBRACE SwitchProngList RBRACE
fn pegSwitchExpr(a: *AstSmith) SourceError!void {
    try a.pegToken(.keyword_switch);
    try a.pegToken(.l_paren);
    try a.pegExpr();
    try a.pegToken(.r_paren);

    try a.pegToken(.l_brace);
    try a.pegSwitchProngList();
    try a.pegToken(.r_brace);
}

/// AsmExpr <- KEYWORD_asm KEYWORD_volatile? LPAREN Expr AsmOutput? RPAREN
fn pegAsmExpr(a: *AstSmith) SourceError!void {
    try a.pegToken(.keyword_asm);
    if (a.smith.value(bool)) {
        try a.pegToken(.keyword_volatile);
    }
    try a.pegToken(.l_paren);
    try a.pegExpr();
    if (a.smith.value(bool)) {
        try a.pegAsmOutput();
    }
    try a.pegToken(.r_paren);
}

/// AsmOutput <- COLON AsmOutputList AsmInput?
fn pegAsmOutput(a: *AstSmith) SourceError!void {
    try a.pegToken(.colon);
    try a.pegAsmOutputList();
    if (a.smith.value(bool)) {
        try a.pegAsmInput();
    }
}

/// AsmOutputItem <- LBRACKET IDENTIFIER RBRACKET STRINGLITERALSINGLE LPAREN (MINUSRARROW TypeExpr / IDENTIFIER) RPAREN
fn pegAsmOutputItem(a: *AstSmith) SourceError!void {
    try a.pegToken(.l_bracket);
    try a.pegIdentifier();
    try a.pegToken(.r_bracket);
    try a.pegStringLiteralSingle();
    try a.pegToken(.l_paren);
    if (a.smith.value(bool)) {
        try a.pegToken(.arrow);
        try a.pegTypeExpr();
    } else {
        try a.pegIdentifier();
    }
    try a.pegToken(.r_paren);
}

/// AsmInput <- COLON AsmInputList AsmClobbers?
fn pegAsmInput(a: *AstSmith) SourceError!void {
    try a.pegToken(.colon);
    try a.pegAsmInputList();
    if (a.smith.value(bool)) {
        try a.pegAsmClobbers();
    }
}

/// AsmInputItem <- LBRACKET IDENTIFIER RBRACKET STRINGLITERALSINGLE LPAREN Expr RPAREN
fn pegAsmInputItem(a: *AstSmith) SourceError!void {
    try a.pegToken(.l_bracket);
    try a.pegIdentifier();
    try a.pegToken(.r_bracket);
    try a.pegStringLiteralSingle();
    try a.pegToken(.l_paren);
    try a.pegExpr();
    try a.pegToken(.r_paren);
}

/// AsmClobbers <- COLON Expr
fn pegAsmClobbers(a: *AstSmith) SourceError!void {
    try a.pegToken(.colon);
    try a.pegExpr();
}

/// BreakLabel <- COLON IDENTIFIER
fn pegBreakLabel(a: *AstSmith) SourceError!void {
    try a.pegToken(.colon);
    try a.pegIdentifier();
}

/// BlockLabel <- IDENTIFIER COLON
fn pegBlockLabel(a: *AstSmith) SourceError!void {
    try a.pegIdentifier();
    try a.pegToken(.colon);
}

/// FieldInit <- DOT IDENTIFIER EQUAL Expr
fn pegFieldInit(a: *AstSmith) SourceError!void {
    try a.pegToken(.period);
    try a.pegIdentifier();
    try a.pegToken(.equal);
    try a.pegExpr();
}

/// WhileContinueExpr <- COLON LPAREN AssignExpr RPAREN
fn pegWhileContinueExpr(a: *AstSmith) SourceError!void {
    try a.pegToken(.colon);
    try a.pegToken(.l_paren);
    try a.pegAssignExpr();
    try a.pegToken(.r_paren);
}

/// LinkSection <- KEYWORD_linksection LPAREN Expr RPAREN
fn pegLinkSection(a: *AstSmith) SourceError!void {
    try a.pegToken(.keyword_linksection);
    try a.pegToken(.l_paren);
    try a.pegExpr();
    try a.pegToken(.r_paren);
}

/// AddrSpace <- KEYWORD_addrspace LPAREN Expr RPAREN
fn pegAddrSpace(a: *AstSmith) SourceError!void {
    try a.pegToken(.keyword_addrspace);
    try a.pegToken(.l_paren);
    try a.pegExpr();
    try a.pegToken(.r_paren);
}

/// CallConv <- KEYWORD_callconv LPAREN Expr RPAREN
fn pegCallConv(a: *AstSmith) SourceError!void {
    try a.pegToken(.keyword_callconv);
    try a.pegToken(.l_paren);
    try a.pegExpr();
    try a.pegToken(.r_paren);
}

/// ParamDecl <- doc_comment? (KEYWORD_noalias / KEYWORD_comptime)?
///            ((IDENTIFIER COLON) / !KEYWORD_comptime !(IDENTIFIER COLON))
///            ParamType
fn pegParamDecl(a: *AstSmith) SourceError!void {
    try a.pegMaybeDocComment();
    const modifier = a.smith.value(enum { none, @"noalias", @"comptime" });
    switch (modifier) {
        .none => a.not_token_comptime = true,
        .@"noalias" => try a.pegToken(.keyword_noalias),
        .@"comptime" => try a.pegToken(.keyword_comptime),
    }
    if (a.smith.value(bool)) {
        try a.pegIdentifier();
        try a.pegToken(.colon);
    } else {
        a.not_label = true;
    }
    try a.pegParamType();
}

/// ParamType
///     <- KEYWORD_anytype
///      / TypeExpr
fn pegParamType(a: *AstSmith) SourceError!void {
    if (a.smith.value(bool)) {
        try a.pegToken(.keyword_anytype);
    } else {
        try a.pegTypeExpr();
    }
}

/// IfPrefix <- KEYWORD_if LPAREN Expr RPAREN PtrPayload?
fn pegIfPrefix(a: *AstSmith) SourceError!void {
    try a.pegToken(.keyword_if);
    try a.pegToken(.l_paren);
    try a.pegExpr();
    try a.pegToken(.r_paren);
    try a.pegPtrPayload();
}

/// WhilePrefix <- KEYWORD_while LPAREN Expr RPAREN PtrPayload? WhileContinueExpr?
fn pegWhilePrefix(a: *AstSmith) SourceError!void {
    try a.pegToken(.keyword_while);
    try a.pegToken(.l_paren);
    try a.pegExpr();
    try a.pegToken(.r_paren);

    if (a.smith.value(bool)) {
        try a.pegPtrPayload();
    }

    if (a.smith.value(bool)) {
        try a.pegWhileContinueExpr();
    }
}

/// ForPrefix <- KEYWORD_for LPAREN ForArgumentsList RPAREN PtrListPayload
///
/// An additional requirement checked in the Parser is that the number of
/// arguments and payload elements are the same.
fn pegForPrefix(a: *AstSmith) SourceError!void {
    try a.pegToken(.keyword_for);
    try a.pegToken(.l_paren);
    const n = try a.pegForArgumentsList();
    try a.pegToken(.r_paren);
    try a.pegPtrListPayload(n);
}

/// Payload <- PIPE IDENTIFIER PIPE
fn pegPayload(a: *AstSmith) SourceError!void {
    try a.pegToken(.pipe);
    try a.pegIdentifier();
    try a.pegToken(.pipe);
}

/// PtrPayload <- PIPE ASTERISK? IDENTIFIER PIPE
fn pegPtrPayload(a: *AstSmith) SourceError!void {
    try a.pegToken(.pipe);
    if (a.smith.value(bool)) {
        try a.pegToken(.asterisk);
    }
    try a.pegIdentifier();
    try a.pegToken(.pipe);
}

/// PtrIndexPayload <- PIPE ASTERISK? IDENTIFIER (COMMA IDENTIFIER)? PIPE
fn pegPtrIndexPayload(a: *AstSmith) SourceError!void {
    try a.pegToken(.pipe);
    if (a.smith.value(bool)) {
        try a.pegToken(.asterisk);
    }
    try a.pegIdentifier();
    if (a.smith.value(bool)) {
        try a.pegToken(.comma);
        try a.pegIdentifier();
    }
    try a.pegToken(.pipe);
}

/// PtrListPayload <- PIPE ASTERISK? IDENTIFIER (COMMA ASTERISK? IDENTIFIER)* COMMA? PIPE
fn pegPtrListPayload(a: *AstSmith, n: usize) SourceError!void {
    try a.pegToken(.pipe);
    if (a.smith.value(bool)) {
        try a.pegToken(.asterisk);
    }
    try a.pegIdentifier();

    for (1..n) |_| {
        try a.pegToken(.comma);
        if (a.smith.value(bool)) {
            try a.pegToken(.asterisk);
        }
        try a.pegIdentifier();
    }

    if (a.smith.value(bool)) {
        try a.pegToken(.comma);
    }
    try a.pegToken(.pipe);
}

/// SwitchProng <- KEYWORD_inline? SwitchCase EQUALRARROW PtrIndexPayload? SingleAssignExpr
fn pegSwitchProng(a: *AstSmith) SourceError!void {
    if (a.smith.value(bool)) {
        try a.pegToken(.keyword_inline);
    }
    try a.pegSwitchCase();
    try a.pegToken(.equal_angle_bracket_right);
    if (a.smith.value(bool)) {
        try a.pegPtrIndexPayload();
    }
    try a.pegSingleAssignExpr();
}

/// SwitchCase
///     <- SwitchItem (COMMA SwitchItem)* COMMA?
///      / KEYWORD_else
fn pegSwitchCase(a: *AstSmith) SourceError!void {
    if (a.smith.value(bool)) {
        try a.pegSwitchItem();
        while (!a.smithListItemEos()) {
            try a.pegToken(.comma);
            try a.pegSwitchItem();
        }
        if (a.smith.value(bool)) {
            try a.pegToken(.comma);
        }
    } else {
        try a.pegToken(.keyword_else);
    }
}

/// SwitchItem <- Expr (DOT3 Expr)?
fn pegSwitchItem(a: *AstSmith) SourceError!void {
    try a.pegExpr();
    if (a.smith.value(bool)) {
        try a.pegToken(.ellipsis3);
        try a.pegExpr();
    }
}

/// ForArgumentsList <- ForItem (COMMA ForItem)* COMMA?
fn pegForArgumentsList(a: *AstSmith) SourceError!usize {
    try a.pegForItem();
    var n: usize = 1;
    while (!a.smithListItemEos()) {
        try a.pegToken(.comma);
        try a.pegForItem();
        n += 1;
    }
    if (a.smith.value(bool)) {
        try a.pegToken(.comma);
    }
    return n;
}

/// ForItem <- Expr (DOT2 Expr?)?
fn pegForItem(a: *AstSmith) SourceError!void {
    try a.pegExpr();
    const components = a.smith.valueRangeAtMost(u2, 0, 2);
    if (components >= 1) try a.pegToken(.ellipsis2);
    if (components >= 2) try a.pegExpr();
}

/// AssignOp
///     <- ASTERISKEQUAL
///      / ASTERISKPIPEEQUAL
///      / SLASHEQUAL
///      / PERCENTEQUAL
///      / PLUSEQUAL
///      / PLUSPIPEEQUAL
///      / MINUSEQUAL
///      / MINUSPIPEEQUAL
///      / LARROW2EQUAL
///      / LARROW2PIPEEQUAL
///      / RARROW2EQUAL
///      / AMPERSANDEQUAL
///      / CARETEQUAL
///      / PIPEEQUAL
///      / ASTERISKPERCENTEQUAL
///      / PLUSPERCENTEQUAL
///      / MINUSPERCENTEQUAL
///      / EQUAL
fn pegAssignOp(a: *AstSmith) SourceError!void {
    const tags = [_]Token.Tag{
        .asterisk_equal,
        .asterisk_pipe_equal,
        .slash_equal,
        .percent_equal,
        .plus_equal,
        .plus_pipe_equal,
        .minus_equal,
        .minus_pipe_equal,
        .angle_bracket_angle_bracket_left_equal,
        .angle_bracket_angle_bracket_left_pipe_equal,
        .angle_bracket_angle_bracket_right_equal,
        .ampersand_equal,
        .caret_equal,
        .pipe_equal,
        .asterisk_percent_equal,
        .plus_percent_equal,
        .minus_percent_equal,
        .equal,
    };
    try a.pegToken(tags[a.smith.index(tags.len)]);
}

/// CompareOp
///     <- EQUALEQUAL
///      / EXCLAMATIONMARKEQUAL
///      / LARROW
///      / RARROW
///      / LARROWEQUAL
///      / RARROWEQUAL
fn pegCompareOp(a: *AstSmith) SourceError!void {
    const tags = [_]Token.Tag{
        .equal_equal,
        .bang_equal,
        .angle_bracket_left,
        .angle_bracket_right,
        .angle_bracket_left_equal,
        .angle_bracket_right_equal,
    };
    try a.pegTokenWhitespaceAround(tags[a.smith.index(tags.len)]);
}

/// BitwiseOp
///     <- AMPERSAND
///      / CARET
///      / PIPE
///      / KEYWORD_orelse
///      / KEYWORD_catch Payload?
fn pegBitwiseOp(a: *AstSmith) SourceError!void {
    const tags = [_]Token.Tag{
        .ampersand,
        .caret,
        .pipe,
        .keyword_orelse,
        .keyword_catch,
    };
    const tag = tags[a.smith.index(tags.len)];
    try a.pegTokenWhitespaceAround(tag);
    if (tag == .keyword_catch and a.smith.value(bool)) {
        try a.pegPayload();
    }
}

/// BitShiftOp
///     <- LARROW2
///      / RARROW2
///      / LARROW2PIPE
fn pegBitShiftOp(a: *AstSmith) SourceError!void {
    const tags = [_]Token.Tag{
        .angle_bracket_angle_bracket_left,
        .angle_bracket_angle_bracket_right,
        .angle_bracket_angle_bracket_left_pipe,
    };
    try a.pegTokenWhitespaceAround(tags[a.smith.index(tags.len)]);
}

/// AdditionOp
///     <- PLUS
///      / MINUS
///      / PLUS2
///      / PLUSPERCENT
///      / MINUSPERCENT
///      / PLUSPIPE
///      / MINUSPIPE
fn pegAdditionOp(a: *AstSmith) SourceError!void {
    const tags = [_]Token.Tag{
        .plus,
        .minus,
        .plus_plus,
        .plus_percent,
        .minus_percent,
        .plus_pipe,
        .minus_pipe,
    };
    try a.pegTokenWhitespaceAround(tags[a.smith.index(tags.len)]);
}

/// MultiplyOp
///     <- PIPE2
///      / ASTERISK
///      / SLASH
///      / PERCENT
///      / ASTERISK2
///      / ASTERISKPERCENT
///      / ASTERISKPIPE
fn pegMultiplyOp(a: *AstSmith) SourceError!void {
    const tags = [_]Token.Tag{
        .asterisk,
        .asterisk_asterisk,
        .pipe_pipe,
        .slash,
        .percent,
        .asterisk_percent,
        .asterisk_pipe,
    };
    const start = @as(u8, 2) * @intFromBool(a.not_token == .asterisk);
    try a.pegTokenWhitespaceAround(tags[a.smith.valueRangeLessThan(u8, start, tags.len)]);
}

/// PrefixOp
///     <- EXCLAMATIONMARK
///      / MINUS
///      / TILDE
///      / MINUSPERCENT
///      / AMPERSAND
///      / KEYWORD_try
fn pegPrefixOp(a: *AstSmith) SourceError!void {
    const tags = [_]Token.Tag{
        .bang,
        .minus,
        .tilde,
        .minus_percent,
        .ampersand,
        .keyword_try,
    };
    try a.pegToken(tags[a.smith.index(tags.len)]);
}

/// PrefixTypeOp
///     <- QUESTIONMARK
///      / KEYWORD_anyframe MINUSRARROW
///      / (ManyPtrTypeStart / SliceTypeStart) KEYWORD_allowzero? ByteAlign? AddrSpace?
///      KEYWORD_const? KEYWORD_volatile?
///      / SinglePtrTypeStart KEYWORD_allowzero? BitAlign? AddrSpace?
///      KEYWORD_const? KEYWORD_volatile?
///      / ArrayTypeStart
fn pegPrefixTypeOp(a: *AstSmith) SourceError!void {
    switch (a.smith.value(enum {
        optional,
        anyframe_arrow,
        array,
        single_pointer,
        many_pointer,
        slice,
    })) {
        .optional => try a.pegToken(.question_mark),
        .anyframe_arrow => {
            try a.pegToken(.keyword_anyframe);
            try a.pegToken(.arrow);
        },
        .array => try a.pegArrayTypeStart(),
        .single_pointer, .many_pointer, .slice => |kind| {
            const is_single = kind == .single_pointer and a.not_token != .asterisk;
            if (is_single) {
                try a.pegSinglePtrTypeStart();
            } else if (kind == .many_pointer) {
                try a.pegManyPtrTypeStart();
            } else {
                try a.pegSliceTypeStart();
            }

            if (a.smith.value(bool)) {
                try a.pegToken(.keyword_allowzero);
            }
            if (a.smith.value(bool)) {
                if (is_single) {
                    try a.pegBitAlign();
                } else {
                    try a.pegByteAlign();
                }
            }
            if (a.smith.value(bool)) {
                try a.pegAddrSpace();
            }
            if (a.smith.value(bool)) {
                try a.pegToken(.keyword_const);
            }
            if (a.smith.value(bool)) {
                try a.pegToken(.keyword_volatile);
            }
        },
    }
}

/// SuffixOp
///     <- LBRACKET Expr (DOT2 (Expr? (COLON Expr)?)?)? RBRACKET
///      / DOT IDENTIFIER
///      / DOTASTERISK
///      / DOTQUESTIONMARK
fn pegSuffixOp(a: *AstSmith) SourceError!void {
    switch (a.smith.value(enum { slice, field, deref, unwrap })) {
        .slice => {
            try a.pegToken(.l_bracket);
            try a.pegExpr();

            const components = a.smith.value(u2);
            if (components >= 1) try a.pegToken(.ellipsis2);
            if (components >= 2) try a.pegExpr();
            if (components >= 3) {
                try a.pegToken(.colon);
                try a.pegExpr();
            }

            try a.pegToken(.r_bracket);
        },
        .field => {
            try a.pegToken(.period);
            try a.pegIdentifier();
        },
        .deref => try a.pegToken(.period_asterisk),
        .unwrap => {
            try a.pegToken(.period);
            try a.pegToken(.question_mark);
        },
    }
}

/// FnCallArguments <- LPAREN ExprList RPAREN
fn pegFnCallArguments(a: *AstSmith) SourceError!void {
    try a.pegToken(.l_paren);
    try a.pegExprList();
    try a.pegToken(.r_paren);
}

/// SliceTypeStart <- LBRACKET (COLON Expr)? RBRACKET
fn pegSliceTypeStart(a: *AstSmith) SourceError!void {
    try a.pegToken(.l_bracket);
    if (a.smith.value(bool)) {
        try a.pegToken(.colon);
        try a.pegExpr();
    }
    try a.pegToken(.r_bracket);
}

/// SinglePtrTypeStart <- ASTERISK / ASTERISK2
fn pegSinglePtrTypeStart(a: *AstSmith) SourceError!void {
    try a.pegToken(if (!a.smith.value(bool)) .asterisk else .asterisk_asterisk);
}

/// ManyPtrTypeStart <- LBRACKET ASTERISK (LETTERC / COLON Expr)? RBRACKET
fn pegManyPtrTypeStart(a: *AstSmith) SourceError!void {
    try a.pegToken(.l_bracket);
    try a.pegToken(.asterisk);
    switch (a.smith.value(enum { many, many_c, many_sentinel })) {
        .many => {},
        .many_c => {
            // No need for `preservePegEndOfWord` because the previous token is an asterisk
            try a.addTokenTag(.identifier);
            try a.addSourceByte('c');
        },
        .many_sentinel => {
            try a.pegToken(.colon);
            try a.pegExpr();
        },
    }
    try a.pegToken(.r_bracket);
}

/// ArrayTypeStart <- LBRACKET !(ASTERISK / ASTERISK2) Expr (COLON Expr)? RBRACKET
fn pegArrayTypeStart(a: *AstSmith) SourceError!void {
    try a.pegToken(.l_bracket);
    a.not_token = .asterisk;
    try a.pegExpr();
    if (a.smith.value(bool)) {
        try a.pegToken(.colon);
        try a.pegExpr();
    }
    try a.pegToken(.r_bracket);
}

/// ContainerDeclAuto <- ContainerDeclType LBRACE ContainerMembers RBRACE
fn pegContainerDeclAuto(a: *AstSmith) SourceError!void {
    try a.pegContainerDeclType();
    try a.pegToken(.l_brace);
    try a.pegContainerMembers();
    try a.pegToken(.r_brace);
}

/// ContainerDeclType
///     <- KEYWORD_struct (LPAREN Expr RPAREN)?
///      / KEYWORD_opaque
///      / KEYWORD_enum (LPAREN Expr RPAREN)?
///      / KEYWORD_union (LPAREN (KEYWORD_enum (LPAREN Expr RPAREN)? / !KEYWORD_enum Expr) RPAREN)?
fn pegContainerDeclType(a: *AstSmith) SourceError!void {
    switch (a.smith.value(enum { @"struct", @"opaque", @"enum", @"union" })) {
        .@"struct", .@"enum" => |c| {
            const is_struct = c == .@"struct" or a.not_token == .keyword_enum;
            try a.pegToken(if (is_struct) .keyword_struct else .keyword_enum);
            if (a.smith.value(bool)) {
                try a.pegToken(.l_paren);
                try a.pegExpr();
                try a.pegToken(.r_paren);
            }
        },
        .@"opaque" => try a.pegToken(.keyword_opaque),
        .@"union" => {
            try a.pegToken(.keyword_union);
            switch (a.smith.value(enum { no_tag, expr_tag, enum_tag, enum_expr_tag })) {
                .no_tag => {},
                .expr_tag => {
                    try a.pegToken(.l_paren);
                    a.not_token = .keyword_enum;
                    try a.pegExpr();
                    try a.pegToken(.r_paren);
                },
                .enum_tag => {
                    try a.pegToken(.l_paren);
                    try a.pegToken(.keyword_enum);
                    try a.pegToken(.r_paren);
                },
                .enum_expr_tag => {
                    try a.pegToken(.l_paren);
                    try a.pegToken(.keyword_enum);
                    try a.pegToken(.l_paren);
                    try a.pegExpr();
                    try a.pegToken(.r_paren);
                    try a.pegToken(.r_paren);
                },
            }
        },
    }
}

/// ByteAlign <- KEYWORD_align LPAREN Expr RPAREN
fn pegByteAlign(a: *AstSmith) SourceError!void {
    try a.pegToken(.keyword_align);
    try a.pegToken(.l_paren);
    try a.pegExpr();
    try a.pegToken(.r_paren);
}

/// BitAlign <- KEYWORD_align LPAREN Expr (COLON Expr COLON Expr)? RPAREN
fn pegBitAlign(a: *AstSmith) SourceError!void {
    try a.pegToken(.keyword_align);
    try a.pegToken(.l_paren);
    try a.pegExpr();
    if (a.smith.value(bool)) {
        try a.pegToken(.colon);
        try a.pegExpr();
        try a.pegToken(.colon);
        try a.pegExpr();
    }
    try a.pegToken(.r_paren);
}

/// IdentifierList <- (doc_comment? IDENTIFIER COMMA)* (doc_comment? IDENTIFIER)?
fn pegIdentifierList(a: *AstSmith) SourceError!void {
    while (!a.smith.eos()) {
        try a.pegMaybeDocComment();
        try a.pegIdentifier();
        try a.pegToken(.comma);
    }
    if (a.smith.value(bool)) {
        try a.pegMaybeDocComment();
        try a.pegIdentifier();
    }
}

/// SwitchProngList <- (SwitchProng COMMA)* SwitchProng?
fn pegSwitchProngList(a: *AstSmith) SourceError!void {
    while (!a.smithListItemEos()) {
        try a.pegSwitchProng();
        try a.pegToken(.comma);
    }
    if (a.smithListItemBool()) {
        try a.pegSwitchProng();
    }
}

/// AsmOutputList <- (AsmOutputItem COMMA)* AsmOutputItem?
fn pegAsmOutputList(a: *AstSmith) SourceError!void {
    while (!a.smithListItemEos()) {
        try a.pegAsmOutputItem();
        try a.pegToken(.comma);
    }
    if (a.smithListItemBool()) {
        try a.pegAsmOutputItem();
    }
}

/// AsmInputList <- (AsmInputItem COMMA)* AsmInputItem?
fn pegAsmInputList(a: *AstSmith) SourceError!void {
    while (!a.smithListItemEos()) {
        try a.pegAsmInputItem();
        try a.pegToken(.comma);
    }
    if (a.smithListItemBool()) {
        try a.pegAsmInputItem();
    }
}

/// ParamDeclList <- (ParamDecl COMMA)* (ParamDecl / DOT3 COMMA?)?
fn pegParamDeclList(a: *AstSmith) SourceError!void {
    while (!a.smithListItemEos()) {
        try a.pegParamDecl();
        try a.pegToken(.comma);
    }
    const Final = enum { none, dot3, dot3_comma, param };
    switch (a.smith.valueWeighted(Final, &.{
        .rangeLessThan(Final, .none, .param, 2),
        .value(Final, .param, 1),
    })) {
        .none => {},
        .dot3 => try a.pegToken(.ellipsis3),
        .dot3_comma => {
            try a.pegToken(.ellipsis3);
            try a.pegToken(.comma);
        },
        .param => try a.pegParamDecl(),
    }
}

/// ExprList <- (Expr COMMA)* Expr?
fn pegExprList(a: *AstSmith) SourceError!void {
    while (!a.smithListItemEos()) {
        try a.pegExpr();
        try a.pegToken(.comma);
    }
    if (a.smithListItemBool()) {
        try a.pegExpr();
    }
}

/// container_doc_comment <- ('//!' non_control_utf8* [ \n]* skip)+
fn pegContainerDocComment(a: *AstSmith) SourceError!void {
    while (true) {
        try a.addTokenTag(.container_doc_comment);
        try a.pegGenericLine("//!", .any);
        try a.pegSkip();
        if (a.smith.eos()) break;
    }
}

/// doc_comment?
fn pegMaybeDocComment(a: *AstSmith) SourceError!void {
    // A specific hash is provided here since this function is likely to be inlined,
    // however having all doc comments with the same uid is beneficial.
    if (a.smith.boolWeightedWithHash(63, 1, 0x39b94392)) {
        try a.pegDocComment();
    }
}

/// doc_comment <- ('///' non_control_utf8* [ \n]* skip)+
fn pegDocComment(a: *AstSmith) SourceError!void {
    if (a.source_len > 0 and a.source_buf[a.source_len - 1] != '\n') {
        try a.addSourceByte('\n');
    }
    while (true) {
        try a.addTokenTag(.doc_comment);
        try a.pegGenericLine("///", .doc_comment);
        try a.pegSkip();
        if (a.smith.eosWeightedSimple(1, 3)) break;
    }
}

/// line_comment <- '//' ![!/] non_control_utf8* / '////' non_control_utf8*
fn pegLineComment(a: *AstSmith) SourceError!void {
    return a.pegGenericLine("//", .line_comment);
}

/// line_string <- '\\\\' non_control_utf8* [ \n]*
fn pegLineString(a: *AstSmith) SourceError!void {
    try a.addTokenTag(.multiline_string_literal_line);
    return a.pegGenericLine("\\\\", .any);
}

/// non_control_utf8 <- [\040-\377]
///
/// Used for line, doc, and container comments as well as
/// multiline string literal lines.
fn pegGenericLine(
    a: *AstSmith,
    prefix: []const u8,
    /// Adds constraints to what the line contains
    prefix_kind: enum { any, line_comment, doc_comment },
) SourceError!void {
    const cr = a.smith.value(bool);
    const newline_len = @intFromBool(cr) + @as(usize, 1);

    try a.ensureSourceCapacity(prefix.len + newline_len);
    a.addSourceAssumeCapacity(prefix);

    const line = a.variableChar(newline_len, 0, &.{
        .rangeAtMost(u8, ' ', 0x7f - 1, 1),
        .rangeAtMost(u8, 0x7f + 1, 0xff, 1),
    });
    if (line.len >= 1) switch (prefix_kind) {
        .any => {},
        .line_comment => {
            // Convert doc comments to quadruple slashes when possible;
            // Otherwise, and for container doc comments, erase the '/' or '!'
            if (line[0] == '/' and line.len >= 2) {
                line[1] = '/';
            } else if (line[0] == '/' or line[0] == '!') {
                line[0] = ' ';
            }
        },
        .doc_comment => {
            // Avoid quadruple slashes
            if (line[0] == '/') {
                line[0] = ' ';
            }
        },
    };

    if (cr) a.addSourceByteAssumeCapacity('\r');
    a.addSourceByteAssumeCapacity('\n');
}

/// skip <- ([ \n] / line_comment)*
fn pegSkip(a: *AstSmith) SourceError!void {
    if (a.smith.boolWeighted(63, 1)) {
        while (true) {
            const Kind = enum {
                space,
                line_break,
                cr_line_break,
                line_comment,
                line_comment_zig_fmt_off,
                line_comment_zig_fmt_on,
            };

            const weights = Smith.baselineWeights(Kind) ++
                [_]Weight{.value(Kind, .space, 11)};
            switch (a.smith.valueWeighted(Kind, weights)) {
                .space => try a.addSourceByte(' '),
                .line_break => try a.addSourceByte('\n'),
                .cr_line_break => try a.addSource("\r\n"),
                .line_comment => try a.pegLineComment(),
                .line_comment_zig_fmt_off => try a.addSource("//zig fmt: off\n"),
                .line_comment_zig_fmt_on => try a.addSource("//zig fmt: on\n"),
            }

            if (a.smith.eos()) break;
        }
    }
}

const bin_weights: []const Weight = &.{.rangeAtMost(u8, '0', '1', 1)};
const oct_weights: []const Weight = &.{.rangeAtMost(u8, '0', '7', 1)};
const dec_weights: []const Weight = &.{.rangeAtMost(u8, '0', '9', 1)};
const hex_weights: []const Weight = &.{
    .rangeAtMost(u8, '0', '9', 1),
    .rangeAtMost(u8, 'a', 'f', 1),
    .rangeAtMost(u8, 'A', 'F', 1),
};

/// Asserts enough capacity for at `min + reserved_capacity`
fn variableChar(
    a: *AstSmith,
    reserved_capacity: usize,
    min: usize,
    weights: []const Weight,
) []u8 {
    const capacity = a.sourceCapacity();
    const max_out = capacity.len - reserved_capacity;

    const len_weights: [3]Weight = .{
        .rangeAtMost(u32, @intCast(min), @min(2, max_out), 32678),
        // For the below `.rangeAtMost` is not used because max may be less than min.
        // In this case, the weights are omitted.
        .{ .min = 3, .max = @min(16, max_out), .weight = 512 },
        // Still allow much longer sequences to test parsing overflows
        .{ .min = 17, .max = @min(256, max_out), .weight = 1 },
    };
    const n_weights = @as(usize, 1) + @intFromBool(max_out >= 3) + @intFromBool(max_out >= 17);

    const len = a.smith.sliceWeighted(capacity, len_weights[0..n_weights], weights);
    a.source_len += len;
    return capacity[0..len];
}

/// char_escape
///     <- "\\x" hex hex
///      / "\\u{" hex+ "}"
///      / "\\" [nr\\t'"]
/// char_char
///     <- multibyte_utf8
///      / char_escape
///      / ![\\'\n] non_control_ascii
///
/// string_char
///     <- multibyte_utf8
///      / char_escape
///      / ![\\"\n] non_control_ascii
fn pegChar(a: *AstSmith, quote: u8) SourceError!void {
    const Char = enum(u8) {
        ascii,
        unicode_2,
        unicode_3,
        unicode_4,
        hex_escape,
        unicode_escape,
        char_escape,
    };
    const weights = Smith.baselineWeights(Char) ++ &[_]Weight{.value(Char, .ascii, 32)};
    switch (a.smith.valueWeighted(Char, weights)) {
        .ascii => try a.addSourceByte(a.smith.valueWeighted(u8, &.{
            .rangeAtMost(u8, ' ', quote - 1, 1),
            .rangeAtMost(u8, quote + 1, '\\' - 1, 1),
            .rangeAtMost(u8, '\\' + 1, 0x7e, 1),
        })),
        .unicode_2 => assert(2 == std.unicode.wtf8Encode(
            a.smith.valueRangeLessThan(u21, 0x80, 0x800),
            try a.addSourceAsSlice(2),
        ) catch unreachable),
        .unicode_3 => assert(3 == std.unicode.wtf8Encode(
            a.smith.valueRangeLessThan(u21, 0x800, 0x10000),
            try a.addSourceAsSlice(3),
        ) catch unreachable),
        .unicode_4 => assert(4 == std.unicode.wtf8Encode(
            a.smith.valueRangeLessThan(u21, 0x10000, 0x110000),
            try a.addSourceAsSlice(4),
        ) catch unreachable),
        .hex_escape => {
            try a.ensureSourceCapacity(4);
            a.addSourceAssumeCapacity("\\x");
            a.smith.bytesWeighted(a.addSourceAsSliceAssumeCapacity(2), hex_weights);
        },
        .unicode_escape => {
            try a.ensureSourceCapacity(5);
            a.addSourceAssumeCapacity("\\u{");
            _ = a.variableChar(1, 1, hex_weights);
            a.addSourceByteAssumeCapacity('}');
        },
        .char_escape => {
            try a.ensureSourceCapacity(2);
            a.addSourceByteAssumeCapacity('\\');
            a.addSourceByteAssumeCapacity(a.smith.valueWeighted(u8, &.{
                .value(u8, 'n', 1),
                .value(u8, 'r', 1),
                .value(u8, 't', 1),
                .value(u8, '\\', 1),
                .value(u8, '\'', 1),
                .value(u8, '"', 1),
            }));
        },
    }
}

/// CHAR_LITERAL <- ['] char_char ['] skip
fn pegCharLiteral(a: *AstSmith) SourceError!void {
    try a.addTokenTag(.char_literal);
    try a.addSourceByte('\'');
    try a.pegChar('\'');
    try a.addSourceByte('\'');
    try a.pegSkip();
}

///FLOAT
///    <- '0x' hex_int '.' hex_int ([pP] [-+]? dec_int)? skip
///     /      dec_int '.' dec_int ([eE] [-+]? dec_int)? skip
///     / '0x' hex_int [pP] [-+]? dec_int skip
///     /      dec_int [eE] [-+]? dec_int skip
fn pegFloat(a: *AstSmith) SourceError!void {
    try a.preservePegEndOfWord();
    try a.addTokenTag(.number_literal);

    const hex = a.smith.value(bool);
    const exp = a.smith.value(packed struct(u3) {
        kind: enum(u2) { none, no_sign, minus, plus },
        upper: bool,
    });
    const dot = exp.kind == .none or a.smith.value(bool);

    var reserved: usize = @intFromBool(hex) * "0x".len + "0".len + @intFromBool(dot) * ".0".len +
        switch (exp.kind) {
            .none => 0,
            .no_sign => "e0".len,
            .minus => "e-0".len,
            .plus => "e+0".len,
        };
    try a.ensureSourceCapacity(reserved);

    if (hex) {
        reserved -= 2;
        a.addSourceAssumeCapacity("0x");
    }
    const digits = if (hex) hex_weights else dec_weights;

    reserved -= 1;
    _ = a.variableChar(reserved, 1, digits);

    if (dot) {
        reserved -= 2;
        a.addSourceByteAssumeCapacity('.');
        _ = a.variableChar(reserved, 1, digits);
    }

    if (exp.kind != .none) {
        reserved -= 1;
        const case_diff = @as(u8, 'a' - 'A') * @intFromBool(exp.upper);
        a.addSourceByteAssumeCapacity(@as(u8, if (hex) 'p' else 'e') - case_diff);

        if (exp.kind != .no_sign) {
            reserved -= 1;
            a.addSourceByteAssumeCapacity(if (exp.kind == .plus) '+' else '-');
        }

        reserved -= 1;
        assert(reserved == 0);
        _ = a.variableChar(reserved, 1, dec_weights);
    }
}

///INTEGER
///    <- '0b' bin_int skip
///     / '0o' oct_int skip
///     / '0x' hex_int skip
///     /      dec_int skip
fn pegInteger(a: *AstSmith) SourceError!void {
    try a.preservePegEndOfWord();
    try a.addTokenTag(.number_literal);
    const Base = enum { bin, dec, oct, hex };
    const base_weights: []const Weight = Smith.baselineWeights(Base) ++
        &[_]Weight{ .value(Base, .dec, 6), .value(Base, .hex, 2) };
    const digits, const prefix = switch (a.smith.valueWeighted(Base, base_weights)) {
        .bin => .{ bin_weights, "0b" },
        .oct => .{ oct_weights, "0o" },
        .dec => .{ dec_weights, "" },
        .hex => .{ hex_weights, "0x" },
    };
    try a.ensureSourceCapacity(prefix.len + 1);
    if (prefix.len != 0) a.addSourceAssumeCapacity(prefix);
    _ = a.variableChar(0, 1, digits);
}

/// Does not include 'skip'. Does not add any token tag.
fn stringLiteralSingleInner(a: *AstSmith) SourceError!void {
    try a.addSourceByte('"');
    while (!a.smith.eosWeightedSimple(3, 1)) {
        try a.pegChar('"');
    }
    try a.addSourceByte('"');
}

/// STRINGLITERALSINGLE <- ["] string_char* ["] skip
fn pegStringLiteralSingle(a: *AstSmith) SourceError!void {
    try a.addTokenTag(.string_literal);
    try a.stringLiteralSingleInner();
    try a.pegSkip();
}

/// STRINGLITERAL
///     <- STRINGLITERALSINGLE
///      / (line_string skip)+
fn pegStringLiteral(a: *AstSmith) SourceError!void {
    if (a.smith.value(bool)) {
        try a.pegStringLiteralSingle();
    } else {
        while (true) {
            try a.pegLineString();
            try a.pegSkip();
            if (a.smith.eos()) break;
        }
    }
}

const alphanumeric_weights: [4]Weight = .{
    .rangeAtMost(u8, '0', '9', 1),
    .rangeAtMost(u8, 'A', 'Z', 1),
    .rangeAtMost(u8, 'a', 'z', 1),
    .value(u8, '_', 1),
};

/// IDENTIFIER
///     <- !keyword [A-Za-z_] [A-Za-z0-9_]* skip
///      / '@' STRINGLITERALSINGLE
fn pegIdentifier(a: *AstSmith) SourceError!void {
    const Kind = enum(u2) { underscore, regular_identifier, quoted_identifier, copy_identifier };
    const kind_weights: [4]Weight = .{
        .value(Kind, .underscore, 6),
        .value(Kind, .regular_identifier, 3),
        .value(Kind, .quoted_identifier, 1),
        .value(Kind, .copy_identifier, 6),
    };
    const n_weights = @as(usize, kind_weights.len) - @intFromBool(a.prev_ids_len == 0);
    const kind = a.smith.valueWeighted(Kind, kind_weights[0..n_weights]);

    switch (kind) {
        .underscore => {
            try a.preservePegEndOfWord();
            try a.addTokenTag(.identifier);
            try a.addSourceByte('_');
        },
        .regular_identifier => {
            try a.preservePegEndOfWord();
            try a.addTokenTag(.identifier);

            const start = a.source_len;
            try a.addSourceByte(a.smith.valueWeighted(u8, alphanumeric_weights[1..]));
            _ = a.variableChar(0, 0, &alphanumeric_weights);

            if (Token.getKeyword(a.source_buf[start..a.source_len]) != null) {
                a.source_buf[start] = '_'; // No keywords start with '_'
            }
        },
        .quoted_identifier => {
            try a.addTokenTag(.identifier);
            try a.addSourceByte('@');
            try a.stringLiteralSingleInner();
        },
        .copy_identifier => {
            const n_prev = @min(a.prev_ids_len, a.prev_ids_buf.len);
            const prev_i = a.smith.valueRangeLessThan(u16, 0, n_prev);
            const prev = a.prev_ids_buf[prev_i];

            if (a.source_buf[prev.start] != '@') try a.preservePegEndOfWord();
            try a.addTokenTag(.identifier);
            try a.addSource(a.source_buf[prev.start..][0..prev.len]);
        },
    }
    try a.pegSkip();
    if (kind != .copy_identifier) {
        const start = a.token_start_buf[a.tokens_len - 1];
        a.prev_ids_buf[a.prev_ids_len % a.prev_ids_buf.len] = .{
            .start = @intCast(start),
            .len = @intCast(a.source_len - start),
        };
        a.prev_ids_len += 1;
    }
}

/// BUILTINIDENTIFIER <- '@'[A-Za-z_][A-Za-z0-9_]* skip
fn pegBuiltinIdentifier(a: *AstSmith) SourceError!void {
    try a.addTokenTag(.builtin);
    if (a.smith.boolWeighted(1, 31)) {
        if (a.smith.boolWeighted(1, 8)) {
            // Pointer cast (reordable with zig fmt)
            const ids = [_][]const u8{
                "@ptrCast",
                "@addrspaceCast",
                "@alignCast",
                "@constCast",
                "@volatileCast",
            };
            try a.addSource(ids[a.smith.index(ids.len)]);
        } else {
            const ids = std.zig.BuiltinFn.list.keys();
            try a.addSource(ids[a.smith.index(ids.len)]);
        }
    } else {
        try a.ensureSourceCapacity(2);
        a.addSourceByteAssumeCapacity('@');
        a.addSourceByteAssumeCapacity(a.smith.valueWeighted(u8, alphanumeric_weights[1..]));
        _ = a.variableChar(0, 0, &alphanumeric_weights);
    }
    try a.pegSkip();
}

test AstSmith {
    try std.testing.fuzz({}, checkGenerated, .{});
}

fn checkGenerated(_: void, smith: *Smith) !void {
    var a: AstSmith = .init(smith);
    try a.generateSource();

    { // Check tokenization matches source
        errdefer a.logBadSource(null);

        const token_tags = a.token_tag_buf[0..a.tokens_len];
        const token_starts = a.token_start_buf[0..a.tokens_len];
        try std.testing.expectEqual(Token.Tag.eof, token_tags[token_tags.len - 1]);

        var tokenizer: std.zig.Tokenizer = .init(a.source());
        for (token_tags, token_starts) |tag, start| {
            const tok = tokenizer.next();
            try std.testing.expectEqual(tok.tag, tag);
            try std.testing.expectEqual(tok.loc.start, start);
            if (tag == .invalid) return error.InvalidToken;
        }
    }

    var fba_buf: [1 << 18]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&fba_buf);
    const ast = std.zig.Ast.parseTokens(fba.allocator(), a.source(), a.tokens(), .zig) catch
        return error.SkipZigTest;

    errdefer a.logBadSource(ast);
    try std.testing.expectEqual(0, ast.errors.len);
}

fn logBadSource(a: *AstSmith, ast: ?std.zig.Ast) void {
    var buf: [256]u8 = undefined;
    const ls = std.debug.lockStderr(&buf);
    defer std.debug.unlockStderr();
    a.logBadSourceInner(ls.terminal(), ast) catch {};
}

fn logBadSourceInner(a: *AstSmith, t: std.Io.Terminal, ast: ?std.zig.Ast) std.Io.Writer.Error!void {
    try a.logSourceInner(t);
    const w = t.writer;

    if (ast) |bad_ast| {
        try w.writeAll("=== Parse Errors ===\n");
        for (bad_ast.errors) |err| {
            const loc = bad_ast.tokenLocation(0, err.token);
            try w.print("{}:{}: ", .{ loc.line + 1, loc.column + 1 });
            try bad_ast.renderError(err, w);
            try w.writeByte('\n');
        }
    } else {
        t.setColor(.dim) catch {};
        try w.writeAll("=== Tokens ===\n");
        t.setColor(.reset) catch {};
        for (
            0..,
            a.token_tag_buf[0..a.tokens_len],
            a.token_start_buf[0..a.tokens_len],
        ) |i, tag, start| {
            try w.print("#{} @{}: {t}\n", .{ i, start, tag });
        }

        t.setColor(.dim) catch {};
        try w.writeAll("\n=== Expected Tokens ===\n");
        t.setColor(.reset) catch {};

        var tokenizer: std.zig.Tokenizer = .init(a.source());
        var i: usize = 0;
        while (true) {
            const tok = tokenizer.next();
            try w.print("#{} @{}-{}: {t}\n", .{ i, tok.loc.start, tok.loc.end, tok.tag });
            i += 1;
            if (tok.tag == .invalid or tok.tag == .eof) break;
        }
    }
}

pub fn logSource(a: *AstSmith) void {
    var buf: [256]u8 = undefined;
    const ls = std.debug.lockStderr(&buf);
    defer std.debug.unlockStderr();
    a.logSourceInner(ls.terminal()) catch {};
}

fn logSourceInner(a: *AstSmith, t: std.Io.Terminal) std.Io.Writer.Error!void {
    const w = t.writer;

    t.setColor(.dim) catch {};
    try w.writeAll("=== Source ===\n");
    t.setColor(.reset) catch {};

    var line: usize = 1;
    try w.print("{: >5} ", .{line});
    for (a.source()) |c| switch (c) {
        ' '...0x7e => try w.writeByte(c),
        '\n' => {
            line += 1;
            try w.print("\n{: >5} ", .{line});
        },
        '\r' => {
            t.setColor(.cyan) catch {};
            try w.writeAll("\\r");
            t.setColor(.reset) catch {};
        },
        '\t' => {
            t.setColor(.cyan) catch {};
            try w.writeAll("\\t");
            t.setColor(.reset) catch {};
        },
        else => {
            t.setColor(.cyan) catch {};
            try w.print("\\x{x:0>2}", .{c});
            t.setColor(.reset) catch {};
        },
    };
    try w.writeByte('\n');
}
