const E = enum { a, b };
export fn entry1() void {
    switch (E.a) {
        .a => {},
    }
}
export fn entry2() void {
    switch (E.a) {
        .a, .b => {},
        else => {},
    }
}

const T = union(E) { a: u32, b };
export fn entry3() void {
    switch (T{ .a = 0 }) {
        .a => {},
    }
}
export fn entry4() void {
    switch (T{ .a = 0 }) {
        .a, .b => {},
        else => {},
    }
}

const Error = error{ MyError, MyOtherError };
export fn entry5() void {
    switch (Error.MyError) {
        error.MyError => {},
    }
}
export fn entry6() void {
    switch (Error.MyError) {
        error.MyError, error.MyOtherError => {},
        else => {},
    }
}

const U = packed union { a: u1, b: i1 };
export fn entry7() void {
    switch (U{ .a = 0 }) {
        .{ .a = 0 } => {},
    }
}
export fn entry8() void {
    switch (U{ .a = 0 }) {
        .{ .a = 0 }, .{ .a = 1 } => {},
        else => {},
    }
}

const S = packed struct { a: u1 };
export fn entry9() void {
    switch (S{ .a = 0 }) {
        .{ .a = 0 } => {},
    }
}
export fn entry10() void {
    switch (S{ .a = 0 }) {
        .{ .a = 0 }, .{ .a = 1 } => {},
        else => {},
    }
}

export fn entry11() void {
    switch (@as(u1, 0)) {
        0 => {},
    }
}
export fn entry12() void {
    switch (@as(u1, 0)) {
        0, 1 => {},
        else => {},
    }
}

export fn entry13() void {
    switch (true) {
        true => {},
    }
}
export fn entry14() void {
    switch (true) {
        true, false => {},
        else => {},
    }
}

export fn entry15() void {
    switch ({}) {}
}
export fn entry16() void {
    switch ({}) {
        {} => {},
        else => {},
    }
}

export fn entry17() void {
    switch (123) {
        123 => {},
    }
}

export fn entry18() void {
    switch (.foo) {
        .foo => {},
    }
}

fn bar() void {}
export fn entry19() void {
    switch (bar) {
        bar => {},
    }
}

const baz: *u8 = @ptrFromInt(123);
export fn entry20() void {
    switch (baz) {
        baz => {},
    }
}

export fn entry21() void {
    switch (u32) {
        u32 => {},
    }
}

export fn entry22() void {
    switch (@as(anyerror, error.MyError)) {
        error.MyError => {},
    }
}

// error
//
// :3:5: error: switch must handle all possibilities
// :1:21: note: unhandled enumeration value: 'b'
// :1:11: note: enum 'tmp.E' declared here
// :10:14: error: unreachable else prong; all cases already handled
// :16:5: error: switch must handle all possibilities
// :1:21: note: unhandled enumeration value: 'b'
// :1:11: note: enum 'tmp.E' declared here
// :23:14: error: unreachable else prong; all cases already handled
// :29:5: error: switch must handle all possibilities
// :29:5: note: unhandled error value: 'error.MyOtherError'
// :36:14: error: unreachable else prong; all cases already handled
// :42:5: error: switch must handle all possibilities
// :49:14: error: unreachable else prong; all cases already handled
// :55:5: error: switch must handle all possibilities
// :62:14: error: unreachable else prong; all cases already handled
// :67:5: error: switch must handle all possibilities
// :74:14: error: unreachable else prong; all cases already handled
// :79:5: error: switch must handle all possibilities
// :86:14: error: unreachable else prong; all cases already handled
// :91:5: error: switch must handle all possibilities
// :96:14: error: unreachable else prong; all cases already handled
// :101:5: error: else prong required when switching on type 'comptime_int'
// :107:5: error: else prong required when switching on type '@EnumLiteral()'
// :114:5: error: else prong required when switching on type 'fn () void'
// :121:5: error: else prong required when switching on type '*u8'
// :127:5: error: else prong required when switching on type 'type'
// :133:5: error: else prong required when switching on type 'anyerror'
