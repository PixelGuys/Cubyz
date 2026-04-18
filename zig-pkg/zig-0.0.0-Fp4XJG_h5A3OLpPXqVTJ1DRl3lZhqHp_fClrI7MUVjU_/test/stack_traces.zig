const std = @import("std");

pub fn addCases(cases: *@import("tests.zig").StackTracesContext, os: std.Target.Os.Tag) void {
    cases.addCase(.{
        .name = "simple panic",
        .source =
        \\pub fn main() void {
        \\    foo();
        \\}
        \\fn foo() void {
        \\    @panic("oh no");
        \\}
        \\
        ,
        .unwind = .any,
        .expect_panic = true,
        .expect =
        \\panic: oh no
        \\source.zig:5:5: [address] in foo
        \\    @panic("oh no");
        \\    ^
        \\source.zig:2:8: [address] in main
        \\    foo();
        \\       ^
        \\
        ,
        .expect_strip =
        \\panic: oh no
        \\???:?:?: [address] in source.foo
        \\???:?:?: [address] in source.main
        \\
        ,
    });

    cases.addCase(.{
        .name = "simple panic with no unwind strategy",
        .source =
        \\pub fn main() void {
        \\    foo();
        \\}
        \\fn foo() void {
        \\    @panic("oh no");
        \\}
        \\
        ,
        .unwind = .none,
        .expect_panic = true,
        .expect = "panic: oh no",
        .expect_strip = "panic: oh no",
    });

    cases.addCase(.{
        .name = "dump current trace",
        .source =
        \\pub fn main() void {
        \\    foo(bar());
        \\}
        \\fn bar() void {
        \\    qux(123);
        \\}
        \\fn foo(_: void) void {}
        \\fn qux(x: u32) void {
        \\    std.debug.dumpCurrentStackTrace(.{});
        \\    _ = x;
        \\}
        \\const std = @import("std");
        \\
        ,
        .unwind = .safe,
        .expect_panic = false,
        .expect =
        \\source.zig:9:36: [address] in qux
        \\    std.debug.dumpCurrentStackTrace(.{});
        \\                                   ^
        \\source.zig:5:8: [address] in bar
        \\    qux(123);
        \\       ^
        \\source.zig:2:12: [address] in main
        \\    foo(bar());
        \\           ^
        \\
        ,
        .expect_strip =
        \\???:?:?: [address] in source.qux
        \\???:?:?: [address] in source.bar
        \\???:?:?: [address] in source.main
        \\
        ,
    });

    cases.addCase(.{
        .name = "dump current trace with no unwind strategy",
        .source =
        \\pub fn main() void {
        \\    foo(bar());
        \\}
        \\fn bar() void {
        \\    qux(123);
        \\}
        \\fn foo(_: void) void {}
        \\fn qux(x: u32) void {
        \\    std.debug.print("pre\n", .{});
        \\    std.debug.dumpCurrentStackTrace(.{});
        \\    std.debug.print("post\n", .{});
        \\    _ = x;
        \\}
        \\const std = @import("std");
        \\
        ,
        .unwind = .no_safe,
        .expect_panic = false,
        .expect = "pre\npost\n",
        .expect_strip = "pre\npost\n",
    });

    cases.addCase(.{
        .name = "dump captured trace",
        .source =
        \\pub fn main() void {
        \\    var stack_trace_buf: [8]usize = undefined;
        \\    dumpIt(&captureIt(&stack_trace_buf));
        \\}
        \\fn captureIt(buf: []usize) std.debug.StackTrace {
        \\    return captureItInner(buf);
        \\}
        \\fn dumpIt(st: *const std.debug.StackTrace) void {
        \\    std.debug.dumpStackTrace(st);
        \\}
        \\fn captureItInner(buf: []usize) std.debug.StackTrace {
        \\    return std.debug.captureCurrentStackTrace(.{}, buf);
        \\}
        \\const std = @import("std");
        \\
        ,
        .unwind = .safe,
        .expect_panic = false,
        .expect =
        \\source.zig:12:46: [address] in captureItInner
        \\    return std.debug.captureCurrentStackTrace(.{}, buf);
        \\                                             ^
        \\source.zig:6:26: [address] in captureIt
        \\    return captureItInner(buf);
        \\                         ^
        \\source.zig:3:22: [address] in main
        \\    dumpIt(&captureIt(&stack_trace_buf));
        \\                     ^
        \\
        ,
        .expect_strip =
        \\???:?:?: [address] in source.captureItInner
        \\???:?:?: [address] in source.captureIt
        \\???:?:?: [address] in source.main
        \\
        ,
    });

    cases.addCase(.{
        .name = "dump captured trace with no unwind strategy",
        .source =
        \\pub fn main() void {
        \\    var stack_trace_buf: [8]usize = undefined;
        \\    dumpIt(&captureIt(&stack_trace_buf));
        \\}
        \\fn captureIt(buf: []usize) std.debug.StackTrace {
        \\    return captureItInner(buf);
        \\}
        \\fn dumpIt(st: *const std.debug.StackTrace) void {
        \\    std.debug.dumpStackTrace(st);
        \\}
        \\fn captureItInner(buf: []usize) std.debug.StackTrace {
        \\    return std.debug.captureCurrentStackTrace(.{}, buf);
        \\}
        \\const std = @import("std");
        \\
        ,
        .unwind = .no_safe,
        .expect_panic = false,
        .expect = "(empty stack trace)\n",
        .expect_strip = "(empty stack trace)\n",
    });

    cases.addCase(.{
        .name = "dump captured trace on thread",
        .source =
        \\pub fn main() !void {
        \\    var stack_trace_buf: [8]usize = undefined;
        \\    const t = try std.Thread.spawn(.{}, threadMain, .{&stack_trace_buf});
        \\    t.join();
        \\}
        \\fn threadMain(stack_trace_buf: []usize) void {
        \\    dumpIt(&captureIt(stack_trace_buf));
        \\}
        \\fn captureIt(buf: []usize) std.debug.StackTrace {
        \\    return captureItInner(buf);
        \\}
        \\fn dumpIt(st: *const std.debug.StackTrace) void {
        \\    std.debug.dumpStackTrace(st);
        \\}
        \\fn captureItInner(buf: []usize) std.debug.StackTrace {
        \\    return std.debug.captureCurrentStackTrace(.{}, buf);
        \\}
        \\const std = @import("std");
        \\
        ,
        .unwind = .safe,
        .expect_panic = false,
        .expect =
        \\source.zig:16:46: [address] in captureItInner
        \\    return std.debug.captureCurrentStackTrace(.{}, buf);
        \\                                             ^
        \\source.zig:10:26: [address] in captureIt
        \\    return captureItInner(buf);
        \\                         ^
        \\source.zig:7:22: [address] in threadMain
        \\    dumpIt(&captureIt(stack_trace_buf));
        \\                     ^
        \\
        ,
        .expect_strip =
        \\???:?:?: [address] in source.captureItInner
        \\???:?:?: [address] in source.captureIt
        \\???:?:?: [address] in source.threadMain
        \\
        ,
    });

    cases.addCase(.{
        .name = "simple inline panic",
        .source =
        \\pub fn main() void {
        \\    foo();
        \\}
        \\inline fn foo() void {
        \\    @panic("oh no");
        \\}
        \\
        ,
        .unwind = .any,
        .expect_panic = true,
        .expect = switch (os) {
            // LLVM doesn't emit column info in the binary annotations for inlinee callees in PDBs,
            // so the first location has only a row.
            .windows =>
            \\panic: oh no
            \\source.zig:5: [address] in foo
            \\    @panic("oh no");
            \\
            \\source.zig:2:8: [address] in main
            \\    foo();
            \\       ^
            \\
            ,
            // On all other platforms, we resolve the innermost inline callee but we don't yet
            // resolve the inline callers.
            else =>
            \\panic: oh no
            \\source.zig:5:5: [address] in foo
            \\    @panic("oh no");
            \\    ^
            ,
        },
        .expect_strip = switch (os) {
            .windows =>
            \\panic: oh no
            \\???:?:?: [address] in source.foo
            \\???:?:?: [address] in source.main
            \\
            ,
            else =>
            \\panic: oh no
            \\???:?:?: [address] in source.foo
            \\
            ,
        },
    });

    // Make sure all inline calls are resolved and in the right order!
    cases.addCase(.{
        .name = "nested inline panic",
        .source =
        \\pub fn main() void {
        \\    foo();
        \\}
        \\inline fn foo() void {
        \\    bar();
        \\}
        \\inline fn bar() void {
        \\    baz();
        \\}
        \\inline fn baz() void {
        \\    @panic("oh no");
        \\}
        \\
        ,
        .unwind = .any,
        .expect_panic = true,
        // This switch serves a similar purpose as in "inline panic".
        .expect = switch (os) {
            .windows =>
            \\panic: oh no
            \\source.zig:11: [address] in baz
            \\    @panic("oh no");
            \\
            \\source.zig:8: [address] in bar
            \\    baz();
            \\
            \\source.zig:5: [address] in foo
            \\    bar();
            \\
            \\source.zig:2:8: [address] in main
            \\    foo();
            \\       ^
            \\
            ,
            else =>
            \\panic: oh no
            \\source.zig:11:5: [address] in baz
            \\    @panic("oh no");
            \\    ^
            ,
        },
        .expect_strip = switch (os) {
            .windows =>
            \\panic: oh no
            \\???:?:?: [address] in baz
            \\???:?:?: [address] in bar
            \\???:?:?: [address] in foo
            \\???:?:?: [address] in main
            \\
            ,
            else =>
            \\panic: oh no
            \\???:?:?: [address] in baz
            \\
            ,
        },
    });
}
