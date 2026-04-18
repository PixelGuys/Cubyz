const std = @import("../std.zig");
const Io = std.Io;
const File = Io.File;
const Allocator = std.mem.Allocator;
const pdb = std.pdb;
const assert = std.debug.assert;

const Pdb = @This();

file_reader: *File.Reader,
msf: Msf,
allocator: Allocator,
string_table: ?*MsfStream,
ipi: ?[]u8,
modules: []Module,
sect_contribs: []pdb.SectionContribEntry,
guid: [16]u8,
age: u32,

pub const Module = struct {
    mod_info: pdb.ModInfo,
    module_name: []u8,
    obj_file_name: []u8,
    // The fields below are filled on demand.
    populated: bool,
    symbols: []u8,
    subsect_info: []u8,
    checksum_offset: ?usize,
    /// The inlinee source lines, sorted by inlinee. This saves us from repeatedly doing linear
    /// searches over all inlinees. We prefer binary search over a hashmap as LLVM somtimes outputs
    /// multiple entries for a single inlinee ID, see `getInlineeSourceLines` for more info.
    inlinee_source_lines: []InlineeSourceLine,

    pub fn deinit(self: *Module, allocator: Allocator) void {
        allocator.free(self.module_name);
        allocator.free(self.obj_file_name);
        if (self.populated) {
            allocator.free(self.symbols);
            allocator.free(self.subsect_info);
            allocator.free(self.inlinee_source_lines);
        }
    }
};

pub fn init(gpa: Allocator, file_reader: *File.Reader) !Pdb {
    return .{
        .file_reader = file_reader,
        .allocator = gpa,
        .string_table = null,
        .ipi = null,
        .msf = try Msf.init(gpa, file_reader),
        .modules = &.{},
        .sect_contribs = &.{},
        .guid = undefined,
        .age = undefined,
    };
}

pub fn deinit(self: *Pdb) void {
    const gpa = self.allocator;
    self.msf.deinit(gpa);
    if (self.ipi) |ipi| gpa.free(ipi);
    for (self.modules) |*module| {
        module.deinit(gpa);
    }
    gpa.free(self.modules);
    gpa.free(self.sect_contribs);
}

pub fn parseDbiStream(self: *Pdb) !void {
    var stream = self.getStream(pdb.StreamType.dbi) orelse
        return error.InvalidDebugInfo;

    const gpa = self.allocator;
    const reader = &stream.interface;

    const header = try reader.takeStruct(pdb.DbiStreamHeader, .little);
    if (header.version_header != 19990903) // V70, only value observed by LLVM team
        return error.UnknownPDBVersion;
    // if (header.Age != age)
    //     return error.UnmatchingPDB;

    const mod_info_size = header.mod_info_size;
    const section_contrib_size = header.section_contribution_size;

    var modules = std.array_list.Managed(Module).init(gpa);
    errdefer modules.deinit();

    // Module Info Substream
    var mod_info_offset: usize = 0;
    while (mod_info_offset != mod_info_size) {
        const mod_info = try reader.takeStruct(pdb.ModInfo, .little);
        var this_record_len: usize = @sizeOf(pdb.ModInfo);

        var module_name: Io.Writer.Allocating = .init(gpa);
        defer module_name.deinit();
        this_record_len += try reader.streamDelimiterLimit(&module_name.writer, 0, .limited(1024));
        assert(reader.buffered()[0] == 0); // TODO change streamDelimiterLimit API
        reader.toss(1);
        this_record_len += 1;

        var obj_file_name: Io.Writer.Allocating = .init(gpa);
        defer obj_file_name.deinit();
        this_record_len += try reader.streamDelimiterLimit(&obj_file_name.writer, 0, .limited(1024));
        assert(reader.buffered()[0] == 0); // TODO change streamDelimiterLimit API
        reader.toss(1);
        this_record_len += 1;

        if (this_record_len % 4 != 0) {
            const round_to_next_4 = (this_record_len | 0x3) + 1;
            const march_forward_bytes = round_to_next_4 - this_record_len;
            try stream.seekBy(@as(isize, @intCast(march_forward_bytes)));
            this_record_len += march_forward_bytes;
        }

        try modules.append(.{
            .mod_info = mod_info,
            .module_name = try module_name.toOwnedSlice(),
            .obj_file_name = try obj_file_name.toOwnedSlice(),

            .populated = false,
            .symbols = undefined,
            .subsect_info = undefined,
            .checksum_offset = null,
            .inlinee_source_lines = undefined,
        });

        mod_info_offset += this_record_len;
        if (mod_info_offset > mod_info_size)
            return error.InvalidDebugInfo;
    }

    // Section Contribution Substream
    var sect_contribs = std.array_list.Managed(pdb.SectionContribEntry).init(gpa);
    errdefer sect_contribs.deinit();

    var sect_cont_offset: usize = 0;
    if (section_contrib_size != 0) {
        const version = reader.takeEnum(pdb.SectionContrSubstreamVersion, .little) catch |err| switch (err) {
            error.InvalidEnumTag, error.EndOfStream => return error.InvalidDebugInfo,
            error.ReadFailed => return error.ReadFailed,
        };
        _ = version;
        sect_cont_offset += @sizeOf(u32);
    }
    while (sect_cont_offset != section_contrib_size) {
        const entry = try sect_contribs.addOne();
        entry.* = try reader.takeStruct(pdb.SectionContribEntry, .little);
        sect_cont_offset += @sizeOf(pdb.SectionContribEntry);

        if (sect_cont_offset > section_contrib_size)
            return error.InvalidDebugInfo;
    }

    self.modules = try modules.toOwnedSlice();
    self.sect_contribs = try sect_contribs.toOwnedSlice();
}

pub fn parseIpiStream(self: *Pdb) !void {
    const gpa = self.allocator;
    const stream = self.getStream(.ipi) orelse return;
    const header = try stream.interface.peekStruct(pdb.IpiStreamHeader, .little);
    if (header.version != .v80) // only value observed by LLVM team
        return error.UnknownPDBVersion;
    self.ipi = try stream.interface.readAlloc(gpa, @sizeOf(pdb.IpiStreamHeader) + header.type_record_bytes);
}

pub fn parseInfoStream(self: *Pdb) !void {
    var stream = self.getStream(pdb.StreamType.pdb) orelse return error.InvalidDebugInfo;
    const reader = &stream.interface;

    // Parse the InfoStreamHeader.
    const version = try reader.takeInt(u32, .little);
    const signature = try reader.takeInt(u32, .little);
    _ = signature;
    const age = try reader.takeInt(u32, .little);
    const guid = try reader.takeArray(16);

    if (version != 20000404) // VC70, only value observed by LLVM team
        return error.UnknownPDBVersion;

    self.guid = guid.*;
    self.age = age;

    const gpa = self.allocator;

    // Find the string table.
    const string_table_index = str_tab_index: {
        const name_bytes_len = try reader.takeInt(u32, .little);
        const name_bytes = try reader.readAlloc(gpa, name_bytes_len);
        defer gpa.free(name_bytes);

        const HashTableHeader = extern struct {
            size: u32,
            capacity: u32,

            fn maxLoad(cap: u32) u32 {
                return cap * 2 / 3 + 1;
            }
        };
        const hash_tbl_hdr = try reader.takeStruct(HashTableHeader, .little);
        if (hash_tbl_hdr.capacity == 0)
            return error.InvalidDebugInfo;

        if (hash_tbl_hdr.size > HashTableHeader.maxLoad(hash_tbl_hdr.capacity))
            return error.InvalidDebugInfo;

        const present = try readSparseBitVector(reader, gpa);
        defer gpa.free(present);
        if (present.len != hash_tbl_hdr.size)
            return error.InvalidDebugInfo;
        const deleted = try readSparseBitVector(reader, gpa);
        defer gpa.free(deleted);

        for (present) |_| {
            const name_offset = try reader.takeInt(u32, .little);
            const name_index = try reader.takeInt(u32, .little);
            if (name_offset > name_bytes.len)
                return error.InvalidDebugInfo;
            const name = std.mem.sliceTo(name_bytes[name_offset..], 0);
            if (std.mem.eql(u8, name, "/names")) {
                break :str_tab_index name_index;
            }
        }
        return error.MissingDebugInfo;
    };

    self.string_table = self.getStreamById(string_table_index) orelse
        return error.MissingDebugInfo;
}

pub fn getProcSym(self: *Pdb, module: *Module, address: u64) ?*align(1) pdb.ProcSym {
    _ = self;
    std.debug.assert(module.populated);
    var reader: Io.Reader = .fixed(module.symbols);
    while (true) {
        const prefix = reader.takeStructPointer(pdb.RecordPrefix) catch return null;
        if (prefix.record_len < 2)
            return null;
        reader.discardAll(prefix.record_len - @sizeOf(u16)) catch return null;
        switch (prefix.record_kind) {
            .lproc32, .gproc32 => {
                const proc_sym: *align(1) pdb.ProcSym = @ptrCast(prefix);
                if (address >= proc_sym.code_offset and address < proc_sym.code_offset + proc_sym.code_size) {
                    return proc_sym;
                }
            },
            else => {},
        }
    }
    return null;
}

pub const InlineSiteSymIterator = struct {
    module_index: usize,
    offset: usize,
    end: usize,

    const empty: InlineSiteSymIterator = .{
        .module_index = 0,
        .offset = 0,
        .end = 0,
    };

    pub fn next(iter: *InlineSiteSymIterator, module: *Module) ?*align(1) pdb.InlineSiteSym {
        while (iter.offset < iter.end) {
            const inline_prefix: *align(1) pdb.RecordPrefix = @ptrCast(&module.symbols[iter.offset]);
            const end = iter.offset + inline_prefix.record_len + @sizeOf(u16);
            if (end > iter.end) return null;
            defer iter.offset = end;
            switch (inline_prefix.record_kind) {
                // Skip nested procedures
                .lproc32,
                .lproc32_st,
                .gproc32,
                .gproc32_st,
                .lproc32_id,
                .gproc32_id,
                .lproc32_dpc,
                .lproc32_dpc_id,
                => {
                    const skip: *align(1) pdb.ProcSym = @ptrCast(inline_prefix);
                    iter.offset = skip.end;
                },
                .inlinesite,
                .inlinesite2,
                => return @ptrCast(inline_prefix),
                else => {},
            }
        }

        return null;
    }
};

pub const BinaryAnnotation = union(enum) {
    code_offset: u32,
    change_code_offset_base: u32,
    change_code_offset: u32,
    change_code_length: u32,
    change_file: u32,
    change_line_offset: i32,
    change_line_end_delta: u32,
    change_range_kind: RangeKind,
    change_column_start: u32,
    change_column_end_delta: i32,
    change_code_offset_and_line_offset: struct { code_delta: u32, line_delta: i32 },
    change_code_length_and_code_offset: struct { length: u32, delta: u32 },
    change_column_end: u32,

    pub const RangeKind = enum(u32) { expression = 0, statement = 1 };

    /// A virtual machine that processed binary annotations.
    pub const RangeIterator = struct {
        annotations: Iterator,
        curr: PartialRange,
        /// The previous range is tracked as the code length is sometimes implied by the subsequent
        /// range.
        prev: ?PartialRange,

        const PartialRange = struct {
            line_offset: i32,
            file_id: ?u32,
            code_offset: u32,
            code_length: ?u32,

            /// Resolves a partial range to a range with a definite length, or returns null if this
            /// is not possible.
            fn resolve(self: PartialRange, next_code_offset: ?u32) ?Range {
                return .{
                    .line_offset = self.line_offset,
                    .file_id = self.file_id,
                    .code_offset = self.code_offset,
                    .code_length = b: {
                        if (self.code_length) |l| break :b l;
                        const end = next_code_offset orelse return null;
                        break :b end - self.code_offset;
                    },
                };
            }
        };

        pub fn init(annotations: Iterator) RangeIterator {
            return .{
                .annotations = annotations,
                .curr = .{
                    .line_offset = 0,
                    .file_id = null,
                    .code_offset = 0,
                    .code_length = null,
                },
                .prev = null,
            };
        }

        pub const Range = struct {
            line_offset: i32,
            file_id: ?u32,
            code_offset: u32,
            code_length: u32,

            pub fn contains(self: Range, offset_in_func: usize) bool {
                return self.code_offset <= offset_in_func and
                    offset_in_func < self.code_offset + self.code_length;
            }
        };

        pub fn next(self: *RangeIterator) error{InvalidDebugInfo}!?Range {
            while (try self.annotations.next()) |annotation| {
                switch (annotation) {
                    .change_code_offset => |delta| {
                        self.curr.code_offset += delta;
                    },
                    .change_code_length => |length| {
                        if (self.prev) |*prev| prev.code_length = prev.code_length orelse length;
                        self.curr.code_offset += length;
                    },
                    // LLVM has code to emit these, but I wasn't able to figure out how trigger it
                    // so this logic is untested.
                    .change_file => |file_id| {
                        self.curr.file_id = file_id;
                    },
                    // LLVM never emits this opcode, but it's clear enough how to interpret it so we
                    // may as well handle it in case they emit it in the future
                    .change_code_length_and_code_offset => |info| {
                        self.curr.code_length = info.length;
                        self.curr.code_offset += info.delta;
                    },
                    .change_line_offset => |delta| {
                        self.curr.line_offset += delta;
                    },
                    .change_code_offset_and_line_offset => |info| {
                        self.curr.code_offset += info.code_delta;
                        self.curr.line_offset += info.line_delta;
                    },

                    // Not emitted by LLVM at the time of writing, and we don't want to add support
                    // without a test case. Safe to ignore since we don't use this info right now.
                    .change_line_end_delta,
                    .change_column_start,
                    .change_column_end_delta,
                    .change_column_end,
                    => {},

                    // Not emitted by LLVM at the time of writing. Various sources conflict on how
                    // these opcodes should be interpreted, so we make no attempt to handle them.
                    .code_offset,
                    .change_code_offset_base,
                    .change_range_kind,
                    => {
                        self.annotations = .empty;
                        self.prev = null;
                        return null;
                    },
                }

                // If we have a new code offset, return the previous range if it exists, resolving
                // its length if necessary.
                switch (annotation) {
                    .change_code_offset,
                    .change_code_offset_and_line_offset,
                    .change_code_length_and_code_offset,
                    => {},
                    else => continue,
                }
                defer self.prev = self.curr;
                const prev = self.prev orelse continue;
                return prev.resolve(self.curr.code_offset);
            }

            // If we've processed all the binary operations but still have a previous range leftover
            // with a known length, return it.
            const prev = self.prev orelse return null;
            defer self.prev = null;
            return prev.resolve(null);
        }
    };

    pub const Iterator = struct {
        reader: Io.Reader,

        pub const empty: Iterator = .{ .reader = .ending_instance };

        pub fn next(self: *Iterator) error{InvalidDebugInfo}!?BinaryAnnotation {
            return take(&self.reader) catch |err| switch (err) {
                error.ReadFailed => return error.InvalidDebugInfo,
                error.EndOfStream => return null,
            };
        }
    };

    pub fn take(reader: *Io.Reader) Io.Reader.Error!BinaryAnnotation {
        const op = std.enums.fromInt(
            pdb.BinaryAnnotationOpcode,
            try takePackedU32(reader),
        ) orelse return error.ReadFailed;
        switch (op) {
            // Microsoft's docs say that invalid is used as padding, though it is left ambiguous
            // whether padding is allowed internally or only after all instructions are complete.
            // Empirically, the latter appears to be the case, at least with the output from LLVM
            // that I've tested.
            .invalid => return error.EndOfStream,
            .code_offset => return .{
                .code_offset = try expect(takePackedU32(reader)),
            },
            .change_code_offset_base => return .{
                .change_code_offset_base = try expect(takePackedU32(reader)),
            },
            .change_code_offset => return .{
                .change_code_offset = try expect(takePackedU32(reader)),
            },
            .change_code_length => return .{
                .change_code_length = try expect(takePackedU32(reader)),
            },
            .change_file => return .{
                .change_file = try expect(takePackedU32(reader)),
            },
            .change_line_offset => return .{
                .change_line_offset = try expect(takePackedI32(reader)),
            },
            .change_line_end_delta => return .{
                .change_line_end_delta = try expect(takePackedU32(reader)),
            },
            .change_range_kind => return .{
                .change_range_kind = std.enums.fromInt(
                    RangeKind,
                    try expect(takePackedU32(reader)),
                ) orelse return error.ReadFailed,
            },
            .change_column_start => return .{
                .change_column_start = try expect(takePackedU32(reader)),
            },
            .change_column_end_delta => return .{
                .change_column_end_delta = try expect(takePackedI32(reader)),
            },
            .change_code_offset_and_line_offset => {
                const EncodedArgs = packed struct(u32) {
                    code_delta: u4,
                    encoded_line_delta: u28,
                };
                const args: EncodedArgs = @bitCast(try expect(takePackedU32(reader)));
                return .{
                    .change_code_offset_and_line_offset = .{
                        .code_delta = args.code_delta,
                        .line_delta = decodeI32(args.encoded_line_delta),
                    },
                };
            },
            .change_code_length_and_code_offset => return .{
                .change_code_length_and_code_offset = .{
                    .length = try expect(takePackedU32(reader)),
                    .delta = try expect(takePackedU32(reader)),
                },
            },
            .change_column_end => return .{
                .change_column_end = try expect(takePackedU32(reader)),
            },
        }
    }

    // Adapted from:
    // https://github.com/microsoft/microsoft-pdb/blob/805655a28bd8198004be2ac27e6e0290121a5e89/include/cvinfo.h#L4942
    pub fn takePackedU32(reader: *Io.Reader) Io.Reader.Error!u32 {
        const b0: u32 = try reader.takeByte();
        if (b0 & 0x80 == 0x00) return b0;

        const b1: u32 = try reader.takeByte();
        if (b0 & 0xC0 == 0x80) return ((b0 & 0x3F) << 8) | b1;

        const b2: u32 = try reader.takeByte();
        const b3: u32 = try reader.takeByte();
        if (b0 & 0xE0 == 0xC0) return ((b0 & 0x1f) << 24) | (b1 << 16) | (b2 << 8) | b3;

        return error.ReadFailed;
    }

    pub fn takePackedI32(reader: *Io.Reader) Io.Reader.Error!i32 {
        return decodeI32(try takePackedU32(reader));
    }

    pub fn decodeI32(u: u32) i32 {
        const i: i32 = @bitCast(u);
        if (i & 1 != 0) {
            return -(i >> 1);
        } else {
            return i >> 1;
        }
    }

    fn expect(value: anytype) error{ReadFailed}!@typeInfo(@TypeOf(value)).error_union.payload {
        comptime assert(@typeInfo(@TypeOf(value)).error_union.error_set == Io.Reader.Error);
        return value catch error.ReadFailed;
    }
};

pub fn findInlineeName(self: *const Pdb, inlinee: u32) ?[]const u8 {
    // According to LLVM, the high bit *can* be used to indicate that a type index comes from the
    // ipi stream in which case that bit needs to be cleared. LLVM doesn't generate data in this
    // manner, but we may as well handle it since it just involves a single bitwise and.
    // https://llvm.org/docs/PDB/TpiStream.html#type-indices
    const type_index = inlinee & 0x7FFFFFFF;

    var reader: Io.Reader = .fixed(self.ipi orelse return null);
    const header = reader.takeStructPointer(pdb.IpiStreamHeader) catch return null;
    for (header.type_index_begin..header.type_index_end) |curr_type_index| {
        const prefix = reader.takeStructPointer(pdb.LfRecordPrefix) catch return null;
        if (prefix.len < 2) return null;
        reader.discardAll(prefix.len - @sizeOf(u16)) catch return null;

        if (curr_type_index == type_index) {
            switch (prefix.kind) {
                .func_id => {
                    const func: *align(1) pdb.LfFuncId = @ptrCast(prefix);
                    return std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&func.name[0])), 0);
                },
                .mfunc_id => {
                    const func: *align(1) pdb.LfMFuncId = @ptrCast(prefix);
                    return std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&func.name[0])), 0);
                },
                else => return null,
            }
        }
    }
    return null;
}

pub fn getInlinees(self: *Pdb, module: *Module, proc_sym: *align(1) const pdb.ProcSym) InlineSiteSymIterator {
    const module_index = module - self.modules.ptr;
    const offset = @intFromPtr(proc_sym) -
        @intFromPtr(module.symbols.ptr) +
        proc_sym.record_len +
        @sizeOf(u16);
    const symbols_end = @intFromPtr(module.symbols.ptr) + module.symbols.len;
    if (offset > symbols_end or proc_sym.end > symbols_end) return .empty;
    return .{
        .module_index = module_index,
        .offset = offset,
        .end = proc_sym.end,
    };
}

pub fn getBinaryAnnotations(self: *Pdb, module: *Module, site: *align(1) const pdb.InlineSiteSym) BinaryAnnotation.Iterator {
    _ = self;
    var start: usize = @intFromPtr(site) + @sizeOf(pdb.InlineSiteSym);
    var end = start + site.record_len + @sizeOf(u16) - @sizeOf(pdb.InlineSiteSym);
    switch (site.record_kind) {
        .inlinesite => {},
        .inlinesite2 => start += @sizeOf(pdb.InlineSiteSym2) - @sizeOf(pdb.InlineSiteSym),
        else => end = start,
    }
    if (start < @intFromPtr(module.symbols.ptr) or end > @intFromPtr(module.symbols.ptr) + module.symbols.len) return .empty;
    const len = end - start;
    const ptr: [*]const u8 = @ptrFromInt(start);
    const slice = ptr[0..len];
    return .{ .reader = Io.Reader.fixed(slice) };
}

pub fn getInlineSiteSourceLocation(
    self: *Pdb,
    gpa: Allocator,
    mod: *Module,
    site: *align(1) const pdb.InlineSiteSym,
    inlinee_src_line: *align(1) const pdb.InlineeSourceLine,
    offset_in_func: usize,
) !?std.debug.SourceLocation {
    var ranges: BinaryAnnotation.RangeIterator = .init(self.getBinaryAnnotations(mod, site));
    while (try ranges.next()) |range| {
        if (!range.contains(offset_in_func)) continue;

        const file_id = range.file_id orelse inlinee_src_line.file_id;
        const file_name = try self.getFileName(gpa, mod, file_id);
        errdefer self.allocator.free(file_name);

        return .{
            .line = inlinee_src_line.source_line_num +% @as(u32, @bitCast(range.line_offset)),
            // LLVM doesn't currently emit column information for inlined calls in PDBs.
            .column = 0,
            .file_name = file_name,
        };
    }
    return null;
}

pub fn getFileName(self: *Pdb, gpa: Allocator, mod: *Module, file_id: u32) ![]const u8 {
    const checksum_offset = mod.checksum_offset orelse return error.MissingDebugInfo;
    const subsect_index = checksum_offset + file_id;
    const chksum_hdr: *align(1) pdb.FileChecksumEntryHeader = @ptrCast(&mod.subsect_info[subsect_index]);
    const strtab_offset = @sizeOf(pdb.StringTableHeader) + chksum_hdr.file_name_offset;
    self.string_table.?.seekTo(strtab_offset) catch return error.InvalidDebugInfo;
    const string_reader = &self.string_table.?.interface;
    var source_file_name: Io.Writer.Allocating = .init(gpa);
    defer source_file_name.deinit();
    _ = try string_reader.streamDelimiterLimit(&source_file_name.writer, 0, .limited(1024));
    assert(string_reader.buffered()[0] == 0); // TODO change streamDelimiterLimit API
    string_reader.toss(1);
    return try source_file_name.toOwnedSlice();
}

pub fn getSymbolName(self: *Pdb, proc_sym: *align(1) const pdb.ProcSym) []const u8 {
    _ = self;
    return std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&proc_sym.name[0])), 0);
}

pub const InlineeSourceLine = struct {
    signature: pdb.InlineeSourceLineSignature,
    info: *align(1) const pdb.InlineeSourceLine,

    fn lessThan(_: void, lhs: InlineeSourceLine, rhs: InlineeSourceLine) bool {
        return lhs.info.inlinee < rhs.info.inlinee;
    }

    fn compare(inlinee: u32, self: InlineeSourceLine) std.math.Order {
        return std.math.order(inlinee, self.info.inlinee);
    }
};

/// Returns all `InlineeSourceLine`s for a given module with the given inlinee. Ideally there would
/// only be one entry per inlinee, but LLVM appears to assign all functions that share a name the
/// same inlinee ID. This appears to be a bug, so the best the caller can do right now is print all
/// the results.
pub fn getInlineeSourceLines(
    self: *Pdb,
    mod: *Module,
    inlinee: u32,
) []const InlineeSourceLine {
    _ = self;

    // Binary search to an arbitrary match, if there are other matches they will be adjacent
    const any = std.sort.binarySearch(
        InlineeSourceLine,
        mod.inlinee_source_lines,
        inlinee,
        InlineeSourceLine.compare,
    ) orelse return &.{};

    // Linearly scan to the first match
    const begin = b: {
        var begin = any;
        while (begin > 0) {
            const prev = begin - 1;
            if (mod.inlinee_source_lines[prev].info.inlinee != inlinee) break;
            begin = prev;
        }
        break :b begin;
    };

    // Linearly scan to the last match
    const end = b: {
        var end = any + 1;
        while (end < mod.inlinee_source_lines.len and
            mod.inlinee_source_lines[end].info.inlinee == inlinee) : (end += 1)
        {}
        break :b end;
    };

    // Return a slice of all the matches
    return mod.inlinee_source_lines[begin..end];
}

pub fn getLineNumberInfo(self: *Pdb, gpa: Allocator, module: *Module, address: u64) !std.debug.SourceLocation {
    std.debug.assert(module.populated);
    const subsect_info = module.subsect_info;

    var sect_offset: usize = 0;
    var skip_len: usize = undefined;
    while (sect_offset != subsect_info.len) : (sect_offset += skip_len) {
        const subsect_hdr: *align(1) pdb.DebugSubsectionHeader = @ptrCast(&subsect_info[sect_offset]);
        skip_len = subsect_hdr.length;
        sect_offset += @sizeOf(pdb.DebugSubsectionHeader);

        switch (subsect_hdr.kind) {
            .lines => {
                var line_index = sect_offset;

                const line_hdr: *align(1) pdb.LineFragmentHeader = @ptrCast(&subsect_info[line_index]);
                if (line_hdr.reloc_segment == 0)
                    return error.MissingDebugInfo;
                line_index += @sizeOf(pdb.LineFragmentHeader);
                const frag_vaddr_start = line_hdr.reloc_offset;
                const frag_vaddr_end = frag_vaddr_start + line_hdr.code_size;

                if (address >= frag_vaddr_start and address < frag_vaddr_end) {
                    // There is an unknown number of LineBlockFragmentHeaders (and their accompanying line and column records)
                    // from now on. We will iterate through them, and eventually find a SourceLocation that we're interested in,
                    // breaking out to :subsections. If not, we will make sure to not read anything outside of this subsection.
                    const subsection_end_index = sect_offset + subsect_hdr.length;

                    while (line_index < subsection_end_index) {
                        const block_hdr: *align(1) pdb.LineBlockFragmentHeader = @ptrCast(&subsect_info[line_index]);
                        line_index += @sizeOf(pdb.LineBlockFragmentHeader);
                        const start_line_index = line_index;

                        const has_column = line_hdr.flags.have_columns;

                        // All line entries are stored inside their line block by ascending start address.
                        // Heuristic: we want to find the last line entry
                        // that has a vaddr_start <= address.
                        // This is done with a simple linear search.
                        var line_i: u32 = 0;
                        while (line_i < block_hdr.num_lines) : (line_i += 1) {
                            const line_num_entry: *align(1) pdb.LineNumberEntry = @ptrCast(&subsect_info[line_index]);
                            line_index += @sizeOf(pdb.LineNumberEntry);

                            const vaddr_start = frag_vaddr_start + line_num_entry.offset;
                            if (address < vaddr_start) {
                                break;
                            }
                        }

                        // line_i == 0 would mean that no matching pdb.LineNumberEntry was found.
                        if (line_i > 0) {
                            const file_name = try self.getFileName(gpa, module, block_hdr.name_index);
                            errdefer gpa.free(file_name);

                            const line_entry_idx = line_i - 1;

                            const column = if (has_column) blk: {
                                const start_col_index = start_line_index + @sizeOf(pdb.LineNumberEntry) * block_hdr.num_lines;
                                const col_index = start_col_index + @sizeOf(pdb.ColumnNumberEntry) * line_entry_idx;
                                const col_num_entry: *align(1) pdb.ColumnNumberEntry = @ptrCast(&subsect_info[col_index]);
                                break :blk col_num_entry.start_column;
                            } else 0;

                            const found_line_index = start_line_index + line_entry_idx * @sizeOf(pdb.LineNumberEntry);
                            const line_num_entry: *align(1) pdb.LineNumberEntry = @ptrCast(&subsect_info[found_line_index]);

                            return .{
                                .file_name = file_name,
                                .line = line_num_entry.flags.start,
                                .column = column,
                            };
                        }
                    }

                    // Checking that we are not reading garbage after the (possibly) multiple block fragments.
                    if (line_index != subsection_end_index) {
                        return error.InvalidDebugInfo;
                    }
                }
            },
            else => {},
        }

        if (sect_offset > subsect_info.len)
            return error.InvalidDebugInfo;
    }

    return error.MissingDebugInfo;
}

pub fn getModule(self: *Pdb, index: usize) !?*Module {
    if (index >= self.modules.len)
        return null;

    const mod = &self.modules[index];
    if (mod.populated)
        return mod;

    // At most one can be non-zero.
    if (mod.mod_info.c11_byte_size != 0 and mod.mod_info.c13_byte_size != 0)
        return error.InvalidDebugInfo;
    if (mod.mod_info.c13_byte_size == 0)
        return error.InvalidDebugInfo;

    const stream = self.getStreamById(mod.mod_info.module_sym_stream) orelse
        return error.MissingDebugInfo;
    const reader = &stream.interface;

    const signature = try reader.takeInt(u32, .little);
    if (signature != 4)
        return error.InvalidDebugInfo;

    const gpa = self.allocator;

    mod.symbols = try reader.readAlloc(gpa, mod.mod_info.sym_byte_size - 4);
    errdefer gpa.free(mod.symbols);
    mod.subsect_info = try reader.readAlloc(gpa, mod.mod_info.c13_byte_size);
    errdefer gpa.free(mod.subsect_info);
    mod.inlinee_source_lines = b: {
        var inlinee_source_lines: std.ArrayList(InlineeSourceLine) = .empty;
        defer inlinee_source_lines.deinit(gpa);
        var subsects: Io.Reader = .fixed(mod.subsect_info);
        while (subsects.takeStructPointer(pdb.DebugSubsectionHeader) catch null) |subsect_hdr| {
            var subsect: Io.Reader = .fixed(subsects.take(subsect_hdr.length) catch return null);
            if (subsect_hdr.kind == .inlinee_lines) {
                const inlinee_source_line_signature = subsect.takeEnum(pdb.InlineeSourceLineSignature, .little) catch return error.InvalidDebugInfo;
                const has_extra_files = switch (inlinee_source_line_signature) {
                    .normal => false,
                    .ex => true,
                    else => continue,
                };
                while (subsect.takeStructPointer(pdb.InlineeSourceLine) catch null) |info| {
                    if (has_extra_files) {
                        const file_count = subsect.takeInt(u32, .little) catch
                            return error.InvalidDebugInfo;
                        const file_bytes = std.math.mul(usize, file_count, @sizeOf(u32)) catch return error.InvalidDebugInfo;
                        subsect.discardAll(file_bytes) catch
                            return error.InvalidDebugInfo;
                    }

                    try inlinee_source_lines.append(gpa, .{
                        .signature = inlinee_source_line_signature,
                        .info = info,
                    });
                }
            }
        }

        std.mem.sortUnstable(InlineeSourceLine, inlinee_source_lines.items, {}, InlineeSourceLine.lessThan);
        break :b try inlinee_source_lines.toOwnedSlice(gpa);
    };
    errdefer gpa.free(mod.inlinee_source_lines);

    var sect_offset: usize = 0;
    var skip_len: usize = undefined;
    while (sect_offset != mod.subsect_info.len) : (sect_offset += skip_len) {
        const subsect_hdr: *align(1) pdb.DebugSubsectionHeader = @ptrCast(&mod.subsect_info[sect_offset]);
        skip_len = subsect_hdr.length;
        sect_offset += @sizeOf(pdb.DebugSubsectionHeader);

        switch (subsect_hdr.kind) {
            .file_checksums => {
                mod.checksum_offset = sect_offset;
                break;
            },
            else => {},
        }

        if (sect_offset > mod.subsect_info.len)
            return error.InvalidDebugInfo;
    }

    mod.populated = true;
    return mod;
}

pub fn getStreamById(self: *Pdb, id: u32) ?*MsfStream {
    if (id >= self.msf.streams.len) return null;
    return &self.msf.streams[id];
}

pub fn getStream(self: *Pdb, stream: pdb.StreamType) ?*MsfStream {
    const id = @intFromEnum(stream);
    return self.getStreamById(id);
}

/// https://llvm.org/docs/PDB/MsfFile.html
const Msf = struct {
    directory: MsfStream,
    streams: []MsfStream,

    fn init(gpa: Allocator, file_reader: *File.Reader) !Msf {
        const superblock = try file_reader.interface.takeStruct(pdb.SuperBlock, .little);

        if (!std.mem.eql(u8, &superblock.file_magic, pdb.SuperBlock.expect_magic))
            return error.InvalidDebugInfo;
        if (superblock.free_block_map_block != 1 and superblock.free_block_map_block != 2)
            return error.InvalidDebugInfo;
        if (superblock.num_blocks * superblock.block_size != try file_reader.getSize())
            return error.InvalidDebugInfo;
        switch (superblock.block_size) {
            // llvm only supports 4096 but we can handle any of these values
            512, 1024, 2048, 4096 => {},
            else => return error.InvalidDebugInfo,
        }

        const dir_block_count = blockCountFromSize(superblock.num_directory_bytes, superblock.block_size);
        if (dir_block_count > superblock.block_size / @sizeOf(u32))
            return error.UnhandledBigDirectoryStream; // cf. BlockMapAddr comment.

        try file_reader.seekTo(superblock.block_size * superblock.block_map_addr);
        const dir_blocks = try gpa.alloc(u32, dir_block_count);
        errdefer gpa.free(dir_blocks);
        for (dir_blocks) |*b| {
            b.* = try file_reader.interface.takeInt(u32, .little);
        }
        var directory_buffer: [64]u8 = undefined;
        var directory = MsfStream.init(superblock.block_size, file_reader, dir_blocks, &directory_buffer);

        const begin = directory.logicalPos();
        const stream_count = try directory.interface.takeInt(u32, .little);
        const stream_sizes = try gpa.alloc(u32, stream_count);
        defer gpa.free(stream_sizes);

        // Microsoft's implementation uses @as(u32, -1) for inexistent streams.
        // These streams are not used, but still participate in the file
        // and must be taken into account when resolving stream indices.
        const nil_size = 0xFFFFFFFF;
        for (stream_sizes) |*s| {
            const size = try directory.interface.takeInt(u32, .little);
            s.* = if (size == nil_size) 0 else blockCountFromSize(size, superblock.block_size);
        }

        const streams = try gpa.alloc(MsfStream, stream_count);
        errdefer gpa.free(streams);

        for (streams, stream_sizes) |*stream, size| {
            if (size == 0) {
                stream.* = .empty;
                continue;
            }
            const blocks = try gpa.alloc(u32, size);
            errdefer gpa.free(blocks);
            for (blocks) |*block| {
                const block_id = try directory.interface.takeInt(u32, .little);
                // Index 0 is reserved for the superblock.
                // In theory, every page which is `n * block_size + 1` or `n * block_size + 2`
                // is also reserved, for one of the FPMs. However, LLVM has been observed to map
                // these into actual streams, so allow it for compatibility.
                if (block_id == 0 or block_id >= superblock.num_blocks) return error.InvalidBlockIndex;
                block.* = block_id;
            }
            const buffer = try gpa.alloc(u8, 64);
            errdefer gpa.free(buffer);
            stream.* = .init(superblock.block_size, file_reader, blocks, buffer);
        }

        const end = directory.logicalPos();
        if (end - begin != superblock.num_directory_bytes)
            return error.InvalidStreamDirectory;

        return .{
            .directory = directory,
            .streams = streams,
        };
    }

    fn deinit(self: *Msf, gpa: Allocator) void {
        gpa.free(self.directory.blocks);
        for (self.streams) |*stream| {
            gpa.free(stream.interface.buffer);
            gpa.free(stream.blocks);
        }
        gpa.free(self.streams);
    }
};

const MsfStream = struct {
    file_reader: *File.Reader,
    next_read_pos: u64,
    blocks: []u32,
    block_size: u32,
    interface: Io.Reader,
    err: ?Error,

    const Error = File.Reader.SeekError;

    const empty: MsfStream = .{
        .file_reader = undefined,
        .next_read_pos = 0,
        .blocks = &.{},
        .block_size = undefined,
        .interface = .ending_instance,
        .err = null,
    };

    fn init(block_size: u32, file_reader: *File.Reader, blocks: []u32, buffer: []u8) MsfStream {
        return .{
            .file_reader = file_reader,
            .next_read_pos = 0,
            .blocks = blocks,
            .block_size = block_size,
            .interface = .{
                .vtable = &.{ .stream = stream },
                .buffer = buffer,
                .seek = 0,
                .end = 0,
            },
            .err = null,
        };
    }

    fn stream(r: *Io.Reader, w: *Io.Writer, limit: Io.Limit) Io.Reader.StreamError!usize {
        const ms: *MsfStream = @alignCast(@fieldParentPtr("interface", r));

        var block_id: usize = @intCast(ms.next_read_pos / ms.block_size);
        if (block_id >= ms.blocks.len) return error.EndOfStream;
        var block = ms.blocks[block_id];
        var offset = ms.next_read_pos % ms.block_size;

        ms.file_reader.seekTo(block * ms.block_size + offset) catch |err| {
            ms.err = err;
            return error.ReadFailed;
        };

        var remaining = @intFromEnum(limit);
        while (remaining != 0) {
            const stream_len: usize = @min(remaining, ms.block_size - offset);
            const n = try ms.file_reader.interface.stream(w, .limited(stream_len));
            remaining -= n;
            offset += n;

            // If we're at the end of a block, go to the next one.
            if (offset == ms.block_size) {
                offset = 0;
                block_id += 1;
                if (block_id >= ms.blocks.len) break; // End of Stream
                block = ms.blocks[block_id];
                ms.file_reader.seekTo(block * ms.block_size) catch |err| {
                    ms.err = err;
                    return error.ReadFailed;
                };
            }
        }

        const total = @intFromEnum(limit) - remaining;
        ms.next_read_pos += total;
        return total;
    }

    pub fn logicalPos(ms: *const MsfStream) u64 {
        return ms.next_read_pos - ms.interface.bufferedLen();
    }

    pub fn seekBy(ms: *MsfStream, len: i64) !void {
        ms.next_read_pos = @as(u64, @intCast(@as(i64, @intCast(ms.logicalPos())) + len));
        if (ms.next_read_pos >= ms.blocks.len * ms.block_size) return error.EOF;
        ms.interface.tossBuffered();
    }

    pub fn seekTo(ms: *MsfStream, len: u64) !void {
        ms.next_read_pos = len;
        if (ms.next_read_pos >= ms.blocks.len * ms.block_size) return error.EOF;
        ms.interface.tossBuffered();
    }

    fn getSize(ms: *const MsfStream) u64 {
        return ms.blocks.len * ms.block_size;
    }

    fn getFilePos(ms: *const MsfStream) u64 {
        const pos = ms.logicalPos();
        const block_id = pos / ms.block_size;
        const block = ms.blocks[block_id];
        const offset = pos % ms.block_size;

        return block * ms.block_size + offset;
    }
};

fn readSparseBitVector(reader: *Io.Reader, allocator: Allocator) ![]u32 {
    const num_words = try reader.takeInt(u32, .little);
    var list = std.array_list.Managed(u32).init(allocator);
    errdefer list.deinit();
    var word_i: u32 = 0;
    while (word_i != num_words) : (word_i += 1) {
        const word = try reader.takeInt(u32, .little);
        var bit_i: u5 = 0;
        while (true) : (bit_i += 1) {
            if (word & (@as(u32, 1) << bit_i) != 0) {
                try list.append(word_i * 32 + bit_i);
            }
            if (bit_i == std.math.maxInt(u5)) break;
        }
    }
    return try list.toOwnedSlice();
}

fn blockCountFromSize(size: u32, block_size: u32) u32 {
    return (size + block_size - 1) / block_size;
}
