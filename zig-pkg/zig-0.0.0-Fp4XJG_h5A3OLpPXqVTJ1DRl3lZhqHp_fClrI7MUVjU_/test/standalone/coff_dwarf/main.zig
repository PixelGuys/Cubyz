const std = @import("std");
const fatal = std.process.fatal;

extern fn add(a: u32, b: u32, addr: *usize) u32;

pub fn main(init: std.process.Init) void {
    const io = init.io;

    var di: std.debug.SelfInfo = .init;
    defer di.deinit(io);

    var add_addr: usize = undefined;
    _ = add(1, 2, &add_addr);

    const debug_gpa = std.debug.getDebugInfoAllocator();
    const symbol_allocator = debug_gpa;

    var symbols: std.ArrayList(std.debug.Symbol) = .empty;
    defer symbols.deinit(symbol_allocator);

    var text_arena: std.heap.ArenaAllocator = .init(debug_gpa);
    defer text_arena.deinit();

    di.getSymbols(
        io,
        symbol_allocator,
        text_arena.allocator(),
        add_addr,
        false,
        &symbols,
    ) catch |err| fatal("failed to get symbol: {t}", .{err});

    if (symbols.items.len != 1) fatal("expected 1 symbol, found {}", .{symbols.items.len});
    const symbol = symbols.items[0];

    if (symbol.name == null) fatal("failed to resolve symbol name", .{});
    if (symbol.compile_unit_name == null) fatal("failed to resolve compile unit", .{});
    if (symbol.source_location == null) fatal("failed to resolve source location", .{});

    if (!std.mem.eql(u8, symbol.name.?, "add")) {
        fatal("incorrect symbol name '{s}'", .{symbol.name.?});
    }
    const sl = &symbol.source_location.?;
    if (!std.mem.eql(u8, std.fs.path.basename(sl.file_name), "shared_lib.c")) {
        fatal("incorrect file name '{s}'", .{sl.file_name});
    }
    if (sl.line != 3 or sl.column != 0) {
        fatal("incorrect line/column :{d}:{d}", .{ sl.line, sl.column });
    }
}
