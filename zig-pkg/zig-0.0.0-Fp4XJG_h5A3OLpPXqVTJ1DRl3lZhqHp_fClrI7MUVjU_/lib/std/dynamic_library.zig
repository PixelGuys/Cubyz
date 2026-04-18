const builtin = @import("builtin");
const native_os = builtin.os.tag;

const std = @import("std.zig");
const Io = std.Io;
const mem = std.mem;
const testing = std.testing;
const elf = std.elf;
const windows = std.os.windows;
const posix = std.posix;

/// Cross-platform dynamic library loading and symbol lookup.
/// Platform-specific functionality is available through the `inner` field.
pub const DynLib = struct {
    const InnerType = switch (native_os) {
        .linux => if (!builtin.link_libc or builtin.abi == .musl and builtin.link_mode == .static)
            ElfDynLib
        else
            DlDynLib,
        .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos, .freebsd, .netbsd, .openbsd, .dragonfly, .illumos => DlDynLib,
        else => struct {
            const open = @compileError("unsupported platform");
            const openZ = @compileError("unsupported platform");
        },
    };

    inner: InnerType,

    pub const Error = ElfDynLibError || DlDynLibError;

    /// Trusts the file. Malicious file will be able to execute arbitrary code.
    pub fn open(path: []const u8) Error!DynLib {
        if (InnerType == ElfDynLib) {
            return .{ .inner = try InnerType.open(path, null) };
        } else {
            return .{ .inner = try InnerType.open(path) };
        }
    }

    /// Trusts the file. Malicious file will be able to execute arbitrary code.
    pub fn openZ(path_c: [*:0]const u8) Error!DynLib {
        if (InnerType == ElfDynLib) {
            return .{ .inner = try InnerType.openZ(path_c, null) };
        } else {
            return .{ .inner = try InnerType.openZ(path_c) };
        }
    }

    /// Trusts the file.
    pub fn close(self: *DynLib) void {
        return self.inner.close();
    }

    pub fn lookup(self: *DynLib, comptime T: type, name: [:0]const u8) ?T {
        return self.inner.lookup(T, name);
    }
};

// The link_map structure is not completely specified beside the fields
// reported below, any libc is free to store additional data in the remaining
// space.
// An iterator is provided in order to traverse the linked list in a idiomatic
// fashion.
const LinkMap = extern struct {
    addr: usize,
    name: [*:0]const u8,
    ld: ?*elf.Dyn,
    next: ?*LinkMap,
    prev: ?*LinkMap,

    pub const Iterator = struct {
        current: ?*LinkMap,

        pub fn end(self: *Iterator) bool {
            return self.current == null;
        }

        pub fn next(self: *Iterator) ?*LinkMap {
            if (self.current) |it| {
                self.current = it.next;
                return it;
            }
            return null;
        }
    };
};

const RDebug = extern struct {
    version: i32,
    map: ?*LinkMap,
    brk: usize,
    ldbase: usize,
};

/// TODO fix comparisons of extern symbol pointers so we don't need this helper function.
pub fn get_DYNAMIC() ?[*]const elf.Dyn {
    return @extern([*]const elf.Dyn, .{
        .name = "_DYNAMIC",
        .linkage = .weak,
        .visibility = .hidden,
    });
}

pub fn linkmap_iterator() error{InvalidExe}!LinkMap.Iterator {
    const _DYNAMIC = get_DYNAMIC() orelse {
        // No PT_DYNAMIC means this is a statically-linked non-PIE program.
        return .{ .current = null };
    };

    const link_map_ptr = init: {
        var i: usize = 0;
        while (_DYNAMIC[i].d_tag != elf.DT_NULL) : (i += 1) {
            switch (_DYNAMIC[i].d_tag) {
                elf.DT_DEBUG => {
                    const ptr = @as(?*RDebug, @ptrFromInt(_DYNAMIC[i].d_val));
                    if (ptr) |r_debug| {
                        if (r_debug.version != 1) return error.InvalidExe;
                        break :init r_debug.map;
                    }
                },
                elf.DT_PLTGOT => {
                    const ptr = @as(?[*]usize, @ptrFromInt(_DYNAMIC[i].d_val));
                    if (ptr) |got_table| {
                        // The address to the link_map structure is stored in
                        // the second slot
                        break :init @as(?*LinkMap, @ptrFromInt(got_table[1]));
                    }
                },
                else => {},
            }
        }
        return .{ .current = null };
    };

    return .{ .current = link_map_ptr };
}

/// Separated to avoid referencing `ElfDynLib`, because its field types may not
/// be valid on other targets.
const ElfDynLibError = error{
    FileTooBig,
    NotElfFile,
    NotDynamicLibrary,
    MissingDynamicLinkingInformation,
    ElfStringSectionNotFound,
    ElfSymSectionNotFound,
    ElfHashTableNotFound,
    Canceled,
    Streaming,
} || Io.File.OpenError || posix.MMapError;

pub const ElfDynLib = struct {
    strings: [*:0]u8,
    syms: [*]elf.Sym,
    hash_table: HashTable,
    versym: ?[*]elf.Versym,
    verdef: ?*elf.Verdef,
    memory: []align(std.heap.page_size_min) u8,

    pub const Error = ElfDynLibError;

    const HashTable = union(enum) {
        dt_hash: [*]posix.Elf_Symndx,
        dt_gnu_hash: *elf.gnu_hash.Header,
    };

    fn openPath(io: Io, path: []const u8) !Io.Dir {
        if (path.len == 0) return error.NotDir;
        var parts = std.mem.tokenizeScalar(u8, path, '/');
        var parent = if (path[0] == '/') try Io.Dir.cwd().openDir(io, "/", .{}) else Io.Dir.cwd();
        while (parts.next()) |part| {
            const child = try parent.openDir(io, part, .{});
            parent.close(io);
            parent = child;
        }
        return parent;
    }

    fn resolveFromSearchPath(io: Io, search_path: []const u8, file_name: []const u8, delim: u8) ?Io.File {
        var paths = std.mem.tokenizeScalar(u8, search_path, delim);
        while (paths.next()) |p| {
            var dir = openPath(io, p) catch continue;
            defer dir.close(io);
            return dir.openFile(io, file_name, .{}) catch continue;
        }
        return null;
    }

    fn resolveFromParent(io: Io, dir_path: []const u8, file_name: []const u8) ?Io.File {
        var dir = Io.Dir.cwd().openDir(io, dir_path, .{}) catch return null;
        defer dir.close(io);
        return dir.openFile(io, file_name, .{}) catch null;
    }

    // This implements enough to be able to load system libraries in general
    // Places where it differs from dlopen:
    // - DT_RPATH of the calling binary is not used as a search path
    // - DT_RUNPATH of the calling binary is not used as a search path
    // - /etc/ld.so.cache is not read
    fn resolveFromName(io: Io, path_or_name: []const u8, LD_LIBRARY_PATH: ?[]const u8) !Io.File {
        // If filename contains a slash ("/"), then it is interpreted as a (relative or absolute) pathname
        if (std.mem.findScalarPos(u8, path_or_name, 0, '/')) |_| {
            return Io.Dir.cwd().openFile(io, path_or_name, .{});
        }

        // Only read LD_LIBRARY_PATH if the binary is not setuid/setgid
        if (std.os.linux.geteuid() == std.os.linux.getuid() and
            std.os.linux.getegid() == std.os.linux.getgid())
        {
            if (LD_LIBRARY_PATH) |ld_library_path| {
                if (resolveFromSearchPath(io, ld_library_path, path_or_name, ':')) |file| {
                    return file;
                }
            }
        }

        // Lastly the directories /lib and /usr/lib are searched (in this exact order)
        if (resolveFromParent(io, "/lib", path_or_name)) |file| return file;
        if (resolveFromParent(io, "/usr/lib", path_or_name)) |file| return file;
        return error.FileNotFound;
    }

    /// Trusts the file. Malicious file will be able to execute arbitrary code.
    pub fn open(path: []const u8, LD_LIBRARY_PATH: ?[]const u8) Error!ElfDynLib {
        const io = std.Options.debug_io;

        const file = try resolveFromName(io, path, LD_LIBRARY_PATH);
        defer file.close(io);

        const stat = try file.stat(io);
        const size = std.math.cast(usize, stat.size) orelse return error.FileTooBig;

        const page_size = std.heap.pageSize();

        // This one is to read the ELF info. We do more mmapping later
        // corresponding to the actual LOAD sections.
        const file_bytes = try posix.mmap(
            null,
            mem.alignForward(usize, size, page_size),
            .{ .READ = true },
            .{ .TYPE = .PRIVATE },
            file.handle,
            0,
        );
        defer posix.munmap(file_bytes);

        const eh = @as(*elf.Ehdr, @ptrCast(file_bytes.ptr));
        if (!mem.eql(u8, eh.e_ident[0..4], elf.MAGIC)) return error.NotElfFile;
        if (eh.e_type != elf.ET.DYN) return error.NotDynamicLibrary;

        const elf_addr = @intFromPtr(file_bytes.ptr);

        // Iterate over the program header entries to find out the
        // dynamic vector as well as the total size of the virtual memory.
        var maybe_dynv: ?[*]usize = null;
        var virt_addr_end: usize = 0;
        {
            var i: usize = 0;
            var ph_addr: usize = elf_addr + eh.e_phoff;
            while (i < eh.e_phnum) : ({
                i += 1;
                ph_addr += eh.e_phentsize;
            }) {
                const ph = @as(*elf.Phdr, @ptrFromInt(ph_addr));
                switch (ph.p_type) {
                    elf.PT_LOAD => virt_addr_end = @max(virt_addr_end, ph.p_vaddr + ph.p_memsz),
                    elf.PT_DYNAMIC => maybe_dynv = @as([*]usize, @ptrFromInt(elf_addr + ph.p_offset)),
                    else => {},
                }
            }
        }
        const dynv = maybe_dynv orelse return error.MissingDynamicLinkingInformation;

        // Reserve the entire range (with no permissions) so that we can do MAP.FIXED below.
        const all_loaded_mem = try posix.mmap(
            null,
            virt_addr_end,
            .{},
            .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
            -1,
            0,
        );
        errdefer posix.munmap(all_loaded_mem);

        const base = @intFromPtr(all_loaded_mem.ptr);

        // Now iterate again and actually load all the program sections.
        {
            var i: usize = 0;
            var ph_addr: usize = elf_addr + eh.e_phoff;
            while (i < eh.e_phnum) : ({
                i += 1;
                ph_addr += eh.e_phentsize;
            }) {
                const ph = @as(*elf.Phdr, @ptrFromInt(ph_addr));
                switch (ph.p_type) {
                    elf.PT_LOAD => {
                        // The VirtAddr may not be page-aligned; in such case there will be
                        // extra nonsense mapped before/after the VirtAddr,MemSiz
                        const aligned_addr = (base + ph.p_vaddr) & ~(@as(usize, page_size) - 1);
                        const extra_bytes = (base + ph.p_vaddr) - aligned_addr;
                        const extended_memsz = mem.alignForward(usize, ph.p_memsz + extra_bytes, page_size);
                        const ptr = @as([*]align(std.heap.page_size_min) u8, @ptrFromInt(aligned_addr));
                        const prot = elfToProt(ph.p_flags);
                        if ((ph.p_flags & elf.PF_W) == 0) {
                            // If it does not need write access, it can be mapped from the fd.
                            _ = try posix.mmap(
                                ptr,
                                extended_memsz,
                                prot,
                                .{ .TYPE = .PRIVATE, .FIXED = true },
                                file.handle,
                                ph.p_offset - extra_bytes,
                            );
                        } else {
                            const sect_mem = try posix.mmap(
                                ptr,
                                extended_memsz,
                                prot,
                                .{ .TYPE = .PRIVATE, .FIXED = true, .ANONYMOUS = true },
                                -1,
                                0,
                            );
                            @memcpy(sect_mem[0..ph.p_filesz], file_bytes[0..ph.p_filesz]);
                        }
                    },
                    else => {},
                }
            }
        }

        var maybe_strings: ?[*:0]u8 = null;
        var maybe_syms: ?[*]elf.Sym = null;
        var maybe_hashtab: ?[*]posix.Elf_Symndx = null;
        var maybe_gnu_hash: ?*elf.gnu_hash.Header = null;
        var maybe_versym: ?[*]elf.Versym = null;
        var maybe_verdef: ?*elf.Verdef = null;

        {
            var i: usize = 0;
            while (dynv[i] != 0) : (i += 2) {
                const p = base + dynv[i + 1];
                switch (dynv[i]) {
                    elf.DT_STRTAB => maybe_strings = @ptrFromInt(p),
                    elf.DT_SYMTAB => maybe_syms = @ptrFromInt(p),
                    elf.DT_HASH => maybe_hashtab = @ptrFromInt(p),
                    elf.DT_GNU_HASH => maybe_gnu_hash = @ptrFromInt(p),
                    elf.DT_VERSYM => maybe_versym = @ptrFromInt(p),
                    elf.DT_VERDEF => maybe_verdef = @ptrFromInt(p),
                    else => {},
                }
            }
        }

        const hash_table: HashTable = if (maybe_gnu_hash) |gnu_hash|
            .{ .dt_gnu_hash = gnu_hash }
        else if (maybe_hashtab) |hashtab|
            .{ .dt_hash = hashtab }
        else
            return error.ElfHashTableNotFound;

        return .{
            .memory = all_loaded_mem,
            .strings = maybe_strings orelse return error.ElfStringSectionNotFound,
            .syms = maybe_syms orelse return error.ElfSymSectionNotFound,
            .hash_table = hash_table,
            .versym = maybe_versym,
            .verdef = maybe_verdef,
        };
    }

    /// Trusts the file. Malicious file will be able to execute arbitrary code.
    pub fn openZ(path_c: [*:0]const u8, LD_LIBRARY_PATH: ?[]const u8) Error!ElfDynLib {
        return open(mem.sliceTo(path_c, 0), LD_LIBRARY_PATH);
    }

    /// Trusts the file
    pub fn close(self: *ElfDynLib) void {
        posix.munmap(self.memory);
        self.* = undefined;
    }

    pub fn lookup(self: *const ElfDynLib, comptime T: type, name: [:0]const u8) ?T {
        if (self.lookupAddress("", name)) |symbol| {
            return @as(T, @ptrFromInt(symbol));
        } else {
            return null;
        }
    }

    pub const GnuHashSection32 = struct {
        symoffset: u32,
        bloom_shift: u32,
        bloom: []u32,
        buckets: []u32,
        chain: [*]elf.gnu_hash.ChainEntry,

        pub fn fromPtr(header: *elf.gnu_hash.Header) @This() {
            const header_offset = @intFromPtr(header);
            const bloom_offset = header_offset + @sizeOf(elf.gnu_hash.Header);
            const buckets_offset = bloom_offset + header.bloom_size * @sizeOf(u32);
            const chain_offset = buckets_offset + header.nbuckets * @sizeOf(u32);

            const bloom_ptr: [*]u32 = @ptrFromInt(bloom_offset);
            const buckets_ptr: [*]u32 = @ptrFromInt(buckets_offset);
            const chain_ptr: [*]elf.gnu_hash.ChainEntry = @ptrFromInt(chain_offset);

            return .{
                .symoffset = header.symoffset,
                .bloom_shift = header.bloom_shift,
                .bloom = bloom_ptr[0..header.bloom_size],
                .buckets = buckets_ptr[0..header.nbuckets],
                .chain = chain_ptr,
            };
        }
    };

    pub const GnuHashSection64 = struct {
        symoffset: u32,
        bloom_shift: u32,
        bloom: []u64,
        buckets: []u32,
        chain: [*]elf.gnu_hash.ChainEntry,

        pub fn fromPtr(header: *elf.gnu_hash.Header) @This() {
            const header_offset = @intFromPtr(header);
            const bloom_offset = header_offset + @sizeOf(elf.gnu_hash.Header);
            const buckets_offset = bloom_offset + header.bloom_size * @sizeOf(u64);
            const chain_offset = buckets_offset + header.nbuckets * @sizeOf(u32);

            const bloom_ptr: [*]u64 = @ptrFromInt(bloom_offset);
            const buckets_ptr: [*]u32 = @ptrFromInt(buckets_offset);
            const chain_ptr: [*]elf.gnu_hash.ChainEntry = @ptrFromInt(chain_offset);

            return .{
                .symoffset = header.symoffset,
                .bloom_shift = header.bloom_shift,
                .bloom = bloom_ptr[0..header.bloom_size],
                .buckets = buckets_ptr[0..header.nbuckets],
                .chain = chain_ptr,
            };
        }
    };

    /// ElfDynLib specific
    /// Returns the address of the symbol
    pub fn lookupAddress(self: *const ElfDynLib, vername: []const u8, name: []const u8) ?usize {
        const maybe_versym = if (self.verdef == null) null else self.versym;

        const OK_TYPES = (1 << elf.STT_NOTYPE | 1 << elf.STT_OBJECT | 1 << elf.STT_FUNC | 1 << elf.STT_COMMON);
        const OK_BINDS = (1 << elf.STB_GLOBAL | 1 << elf.STB_WEAK | 1 << elf.STB_GNU_UNIQUE);

        switch (self.hash_table) {
            .dt_hash => |hashtab| {
                var i: usize = 0;
                while (i < hashtab[1]) : (i += 1) {
                    if (0 == (@as(u32, 1) << @as(u5, @intCast(self.syms[i].st_info & 0xf)) & OK_TYPES)) continue;
                    if (0 == (@as(u32, 1) << @as(u5, @intCast(self.syms[i].st_info >> 4)) & OK_BINDS)) continue;
                    if (0 == self.syms[i].st_shndx) continue;
                    if (!mem.eql(u8, name, mem.sliceTo(self.strings + self.syms[i].st_name, 0))) continue;
                    if (maybe_versym) |versym| {
                        if (!checkver(self.verdef.?, versym[i], vername, self.strings))
                            continue;
                    }
                    return @intFromPtr(self.memory.ptr) + self.syms[i].st_value;
                }
            },
            .dt_gnu_hash => |gnu_hash_header| {
                const GnuHashSection = switch (@bitSizeOf(usize)) {
                    32 => GnuHashSection32,
                    64 => GnuHashSection64,
                    else => |bit_size| @compileError("Unsupported bit size " ++ bit_size),
                };

                const gnu_hash_section: GnuHashSection = .fromPtr(gnu_hash_header);
                const hash = elf.gnu_hash.calculate(name);

                const bloom_index = (hash / @bitSizeOf(usize)) % gnu_hash_header.bloom_size;
                const bloom_val = gnu_hash_section.bloom[bloom_index];

                const bit_index_0 = hash % @bitSizeOf(usize);
                const bit_index_1 = (hash >> @intCast(gnu_hash_header.bloom_shift)) % @bitSizeOf(usize);

                const one: usize = 1;
                const bit_mask: usize = (one << @intCast(bit_index_0)) | (one << @intCast(bit_index_1));

                if (bloom_val & bit_mask != bit_mask) {
                    // Symbol is not in bloom filter, so it definitely isn't here.
                    return null;
                }

                const bucket_index = hash % gnu_hash_header.nbuckets;
                const chain_index = gnu_hash_section.buckets[bucket_index] - gnu_hash_header.symoffset;

                const chains = gnu_hash_section.chain;
                const hash_as_entry: elf.gnu_hash.ChainEntry = @bitCast(hash);

                var current_index = chain_index;
                var at_end_of_chain = false;
                while (!at_end_of_chain) : (current_index += 1) {
                    const current_entry = chains[current_index];
                    at_end_of_chain = current_entry.end_of_chain;

                    if (current_entry.hash != hash_as_entry.hash) continue;

                    // check that symbol matches
                    const symbol_index = current_index + gnu_hash_header.symoffset;
                    const symbol = self.syms[symbol_index];

                    if (0 == (@as(u32, 1) << @as(u5, @intCast(symbol.st_info & 0xf)) & OK_TYPES)) continue;
                    if (0 == (@as(u32, 1) << @as(u5, @intCast(symbol.st_info >> 4)) & OK_BINDS)) continue;
                    if (0 == symbol.st_shndx) continue;

                    const symbol_name = mem.sliceTo(self.strings + symbol.st_name, 0);
                    if (!mem.eql(u8, name, symbol_name)) {
                        continue;
                    }

                    if (maybe_versym) |versym| {
                        if (!checkver(self.verdef.?, versym[symbol_index], vername, self.strings)) {
                            continue;
                        }
                    }

                    return @intFromPtr(self.memory.ptr) + symbol.st_value;
                }
            },
        }

        return null;
    }

    fn elfToProt(elf_prot: u64) posix.PROT {
        return .{
            .READ = (elf_prot & elf.PF_R) != 0,
            .WRITE = (elf_prot & elf.PF_W) != 0,
            .EXEC = (elf_prot & elf.PF_X) != 0,
        };
    }
};

fn checkver(def_arg: *elf.Verdef, vsym_arg: elf.Versym, vername: []const u8, strings: [*:0]u8) bool {
    var def = def_arg;
    const vsym_index = vsym_arg.VERSION;
    while (true) {
        if (0 == (def.flags & elf.VER_FLG_BASE) and @intFromEnum(def.ndx) == vsym_index) break;
        if (def.next == 0) return false;
        def = @ptrFromInt(@intFromPtr(def) + def.next);
    }
    const aux: *elf.Verdaux = @ptrFromInt(@intFromPtr(def) + def.aux);
    return mem.eql(u8, vername, mem.sliceTo(strings + aux.name, 0));
}

test "ElfDynLib" {
    if (native_os != .linux) return error.SkipZigTest;
    try testing.expectError(error.FileNotFound, ElfDynLib.open("invalid_so.so", null));
    try testing.expectError(error.FileNotFound, ElfDynLib.openZ("invalid_so.so", null));
}

/// Separated to avoid referencing `DlDynLib`, because its field types may not
/// be valid on other targets.
const DlDynLibError = error{ FileNotFound, NameTooLong };

pub const DlDynLib = struct {
    pub const Error = DlDynLibError;

    handle: *anyopaque,

    pub fn open(path: []const u8) Error!DlDynLib {
        const path_c = try posix.toPosixPath(path);
        return openZ(&path_c);
    }

    pub fn openZ(path_c: [*:0]const u8) Error!DlDynLib {
        return .{
            .handle = std.c.dlopen(path_c, .{ .LAZY = true }) orelse {
                return error.FileNotFound;
            },
        };
    }

    pub fn close(self: *DlDynLib) void {
        switch (posix.errno(std.c.dlclose(self.handle))) {
            .SUCCESS => return,
            else => unreachable,
        }
        self.* = undefined;
    }

    pub fn lookup(self: *DlDynLib, comptime T: type, name: [:0]const u8) ?T {
        // dlsym (and other dl-functions) secretly take shadow parameter - return address on stack
        // https://gcc.gnu.org/bugzilla/show_bug.cgi?id=66826
        if (@call(.never_tail, std.c.dlsym, .{ self.handle, name.ptr })) |symbol| {
            return @as(T, @ptrCast(@alignCast(symbol)));
        } else {
            return null;
        }
    }

    /// DlDynLib specific
    /// Returns human readable string describing most recent error than occurred from `lookup`
    /// or `null` if no error has occurred since initialization or when `getError` was last called.
    pub fn getError() ?[:0]const u8 {
        return mem.span(std.c.dlerror());
    }
};

test "dynamic_library" {
    const libname = switch (native_os) {
        .linux, .freebsd, .openbsd, .illumos => "invalid_so.so",
        .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => "invalid_dylib.dylib",
        else => return error.SkipZigTest,
    };

    try testing.expectError(error.FileNotFound, DynLib.open(libname));
    try testing.expectError(error.FileNotFound, DynLib.openZ(libname.ptr));
}
