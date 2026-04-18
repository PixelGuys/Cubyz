lock: Io.RwLock,
ntdll_handle: ?if (load_dll_notification_procs) *anyopaque else noreturn,
notification_cookie: ?LDR.DLL_NOTIFICATION.COOKIE,
modules: std.ArrayList(Module),

pub const init: SelfInfo = .{
    .lock = .init,
    .ntdll_handle = null,
    .notification_cookie = null,
    .modules = .empty,
};
pub fn deinit(si: *SelfInfo, io: Io) void {
    const gpa = std.debug.getDebugInfoAllocator();
    if (si.notification_cookie) |cookie| unregister: {
        switch ((si.getNtdllProc(.LdrUnregisterDllNotification) catch break :unregister)(cookie)) {
            .SUCCESS => {},
            else => |status| windows.unexpectedStatus(status) catch break :unregister,
        }
    }
    if (si.ntdll_handle) |handle| switch (windows.ntdll.LdrUnloadDll(handle)) {
        .SUCCESS => {},
        else => |status| windows.unexpectedStatus(status) catch {},
    };
    for (si.modules.items) |*module| module.deinit(gpa, io);
    si.modules.deinit(gpa);
}

pub fn getSymbols(
    si: *SelfInfo,
    io: Io,
    symbol_allocator: Allocator,
    text_arena: Allocator,
    address: usize,
    resolve_inline_callers: bool,
    symbols: *std.ArrayList(std.debug.Symbol),
) Error!void {
    const gpa = std.debug.getDebugInfoAllocator();
    try si.lock.lockShared(io);
    defer si.lock.unlockShared(io);
    const module = try si.findModule(gpa, address);
    const di = try module.getDebugInfo(gpa, io);
    return di.getSymbols(
        symbol_allocator,
        text_arena,
        address - @intFromPtr(module.entry.DllBase),
        resolve_inline_callers,
        symbols,
    );
}

pub fn getModuleName(si: *SelfInfo, io: Io, address: usize) Error![]const u8 {
    const gpa = std.debug.getDebugInfoAllocator();
    try si.lock.lockShared(io);
    defer si.lock.unlockShared(io);
    const module = try si.findModule(gpa, address);
    return module.name orelse {
        const name = try std.unicode.wtf16LeToWtf8Alloc(gpa, module.entry.BaseDllName.slice());
        module.name = name;
        return name;
    };
}
pub fn getModuleSlide(si: *SelfInfo, io: Io, address: usize) Error!usize {
    const gpa = std.debug.getDebugInfoAllocator();
    try si.lock.lockShared(io);
    defer si.lock.unlockShared(io);
    const module = try si.findModule(gpa, address);
    return module.base_address;
}

pub const can_unwind: bool = switch (builtin.cpu.arch) {
    else => true,
    // On x86, `RtlVirtualUnwind` does not exist. We could in theory use `RtlCaptureStackBackTrace`
    // instead, but on x86, it turns out that function is just... doing FP unwinding with esp! It's
    // hard to find implementation details to confirm that, but the most authoritative source I have
    // is an entry in the LLVM mailing list from 2020/08/16 which contains this quote:
    //
    // > x86 doesn't have what most architectures would consider an "unwinder" in the sense of
    // > restoring registers; there is simply a linked list of frames that participate in SEH and
    // > that desire to be called for a dynamic unwind operation, so RtlCaptureStackBackTrace
    // > assumes that EBP-based frames are in use and walks an EBP-based frame chain on x86 - not
    // > all x86 code is written with EBP-based frames so while even though we generally build the
    // > OS that way, you might always run the risk of encountering external code that uses EBP as a
    // > general purpose register for which such an unwind attempt for a stack trace would fail.
    //
    // Regardless, it's easy to effectively confirm this hypothesis just by compiling some code with
    // `-fomit-frame-pointer -OReleaseFast` and observing that `RtlCaptureStackBackTrace` returns an
    // empty trace when it's called in such an application. Note that without `-OReleaseFast` or
    // similar, LLVM seems reluctant to ever clobber ebp, so you'll get a trace returned which just
    // contains all of the kernel32/ntdll frames but none of your own. Don't be deceived---this is
    // just coincidental!
    //
    // Anyway, the point is, the only stack walking primitive on x86-windows is FP unwinding. We
    // *could* ask Microsoft to do that for us with `RtlCaptureStackBackTrace`... but better to just
    // use our existing FP unwinder in `std.debug`!
    .x86 => false,
};
pub const UnwindContext = struct {
    pc: usize,
    cur: windows.CONTEXT,
    history_table: windows.UNWIND_HISTORY_TABLE,
    pub fn init(ctx: *const std.debug.cpu_context.Native) UnwindContext {
        return .{
            .pc = @returnAddress(),
            .cur = switch (builtin.cpu.arch) {
                .x86_64 => std.mem.zeroInit(windows.CONTEXT, .{
                    .Rax = ctx.gprs.get(.rax),
                    .Rcx = ctx.gprs.get(.rcx),
                    .Rdx = ctx.gprs.get(.rdx),
                    .Rbx = ctx.gprs.get(.rbx),
                    .Rsp = ctx.gprs.get(.rsp),
                    .Rbp = ctx.gprs.get(.rbp),
                    .Rsi = ctx.gprs.get(.rsi),
                    .Rdi = ctx.gprs.get(.rdi),
                    .R8 = ctx.gprs.get(.r8),
                    .R9 = ctx.gprs.get(.r9),
                    .R10 = ctx.gprs.get(.r10),
                    .R11 = ctx.gprs.get(.r11),
                    .R12 = ctx.gprs.get(.r12),
                    .R13 = ctx.gprs.get(.r13),
                    .R14 = ctx.gprs.get(.r14),
                    .R15 = ctx.gprs.get(.r15),
                    .Rip = ctx.gprs.get(.rip),
                }),
                .aarch64 => .{
                    .ContextFlags = 0,
                    .Cpsr = 0,
                    .DUMMYUNIONNAME = .{ .X = ctx.x },
                    .Sp = ctx.sp,
                    .Pc = ctx.pc,
                    .V = @splat(.{ .B = @splat(0) }),
                    .Fpcr = 0,
                    .Fpsr = 0,
                    .Bcr = @splat(0),
                    .Bvr = @splat(0),
                    .Wcr = @splat(0),
                    .Wvr = @splat(0),
                },
                .thumb => .{
                    .ContextFlags = 0,
                    .R0 = ctx.r[0],
                    .R1 = ctx.r[1],
                    .R2 = ctx.r[2],
                    .R3 = ctx.r[3],
                    .R4 = ctx.r[4],
                    .R5 = ctx.r[5],
                    .R6 = ctx.r[6],
                    .R7 = ctx.r[7],
                    .R8 = ctx.r[8],
                    .R9 = ctx.r[9],
                    .R10 = ctx.r[10],
                    .R11 = ctx.r[11],
                    .R12 = ctx.r[12],
                    .Sp = ctx.r[13],
                    .Lr = ctx.r[14],
                    .Pc = ctx.r[15],
                    .Cpsr = 0,
                    .Fpcsr = 0,
                    .Padding = 0,
                    .DUMMYUNIONNAME = .{ .S = @splat(0) },
                    .Bvr = @splat(0),
                    .Bcr = @splat(0),
                    .Wvr = @splat(0),
                    .Wcr = @splat(0),
                    .Padding2 = @splat(0),
                },
                else => comptime unreachable,
            },
            .history_table = std.mem.zeroes(windows.UNWIND_HISTORY_TABLE),
        };
    }
    pub fn deinit(ctx: *UnwindContext) void {
        _ = ctx;
    }
    pub fn getFp(ctx: *UnwindContext) usize {
        return ctx.cur.getRegs().bp;
    }
};
pub fn unwindFrame(si: *SelfInfo, io: Io, context: *UnwindContext) Error!usize {
    _ = si;
    _ = io;

    const current_regs = context.cur.getRegs();
    var image_base: usize = undefined;
    if (windows.ntdll.RtlLookupFunctionEntry(current_regs.ip, &image_base, &context.history_table)) |runtime_function| {
        var handler_data: ?*anyopaque = null;
        var establisher_frame: usize = undefined;
        _ = windows.ntdll.RtlVirtualUnwind(
            windows.UNW_FLAG_NHANDLER,
            image_base,
            current_regs.ip,
            runtime_function,
            &context.cur,
            &handler_data,
            &establisher_frame,
            null,
        );
    } else {
        // leaf function
        context.cur.setIp(@as(*const usize, @ptrFromInt(current_regs.sp)).*);
        context.cur.setSp(current_regs.sp + @sizeOf(usize));
    }

    const next_regs = context.cur.getRegs();
    const tib = &windows.teb().NtTib;
    if (next_regs.sp < @intFromPtr(tib.StackLimit) or next_regs.sp > @intFromPtr(tib.StackBase)) {
        context.pc = 0;
        return 0;
    }
    // Like `DwarfUnwindContext.unwindFrame`, adjust our next lookup pc in case the `call` was this
    // function's last instruction making `next_regs.ip` one byte past its end.
    context.pc = next_regs.ip -| 1;
    return next_regs.ip;
}

const Module = struct {
    entry: *const LDR.DATA_TABLE_ENTRY,
    name: ?[]const u8,
    di: ?(Error!DebugInfo),

    const DebugInfo = struct {
        arena: std.heap.ArenaAllocator.State,
        coff_image_base: u64,
        mapped_file: ?MappedFile,
        dwarf: ?Dwarf,
        pdb: ?Pdb,
        coff_section_headers: []coff.SectionHeader,

        const MappedFile = struct {
            file: Io.File,
            section_handle: windows.HANDLE,
            section_view: []const u8,
            fn deinit(mf: *const MappedFile, io: Io) void {
                const process_handle = windows.GetCurrentProcess();
                switch (windows.ntdll.NtUnmapViewOfSection(
                    process_handle,
                    @constCast(mf.section_view.ptr),
                )) {
                    .SUCCESS => {},
                    else => |status| windows.unexpectedStatus(status) catch {},
                }
                windows.CloseHandle(mf.section_handle);
                mf.file.close(io);
            }
        };

        fn deinit(di: *DebugInfo, gpa: Allocator, io: Io) void {
            if (di.dwarf) |*dwarf| dwarf.deinit(gpa);
            if (di.pdb) |*pdb| {
                pdb.file_reader.file.close(io);
                pdb.deinit();
            }
            if (di.mapped_file) |*mf| mf.deinit(io);

            var arena = di.arena.promote(gpa);
            arena.deinit();
        }

        fn getSymbols(
            di: *DebugInfo,
            symbol_allocator: Allocator,
            text_arena: Allocator,
            vaddr: usize,
            resolve_inline_callers: bool,
            symbols: *std.ArrayList(std.debug.Symbol),
        ) Error!void {
            pdb: {
                const pdb = &(di.pdb orelse break :pdb);
                var coff_section: *align(1) const coff.SectionHeader = undefined;
                const mod_index = for (pdb.sect_contribs) |sect_contrib| {
                    if (sect_contrib.section > di.coff_section_headers.len) continue;
                    // Remember that SectionContribEntry.Section is 1-based.
                    coff_section = &di.coff_section_headers[sect_contrib.section - 1];

                    const vaddr_start = coff_section.virtual_address + sect_contrib.offset;
                    const vaddr_end = vaddr_start + sect_contrib.size;
                    if (vaddr >= vaddr_start and vaddr < vaddr_end) {
                        break sect_contrib.module_index;
                    }
                } else {
                    // we have no information to add to the address
                    break :pdb;
                };
                const module = pdb.getModule(mod_index) catch |err| switch (err) {
                    error.InvalidDebugInfo,
                    error.MissingDebugInfo,
                    error.OutOfMemory,
                    => |e| return e,

                    error.ReadFailed,
                    error.EndOfStream,
                    => return error.InvalidDebugInfo,
                } orelse {
                    return error.InvalidDebugInfo; // bad module index
                };

                const addr = vaddr - coff_section.virtual_address;
                const maybe_proc = pdb.getProcSym(module, addr);
                const compile_unit_name = fs.path.basename(module.obj_file_name);
                const symbols_top = symbols.items.len;
                if (maybe_proc) |proc| {
                    const offset_in_func = addr - proc.code_offset;
                    var last_inlinee: ?u32 = null;
                    var iter = pdb.getInlinees(module, proc);
                    while (iter.next(module)) |inline_site| {
                        // Filter out duplicate inline sites. Tools like llvm-addr2line output
                        // duplicate sites in the same cases as us if we elide this check,
                        // implying that they exist in the underlying data and are not indicative
                        // of a parser bug. No useful information is lost here since an inline site
                        // can't actually reference itself.
                        if (inline_site.inlinee == last_inlinee) continue;

                        // If our address points into this site, get the source location(s) it
                        // points at
                        for (pdb.getInlineeSourceLines(
                            module,
                            inline_site.inlinee,
                        )) |inlinee_src_line| {
                            const maybe_loc = pdb.getInlineSiteSourceLocation(
                                text_arena,
                                module,
                                inline_site,
                                inlinee_src_line.info,
                                offset_in_func,
                            ) catch continue;
                            const loc = maybe_loc orelse continue;

                            // If we aren't trying to resolve inline callers, and we've matched a
                            // new inline site, we want to overwrite the previously appended
                            // results.
                            if (!resolve_inline_callers and inline_site.inlinee != last_inlinee) {
                                symbols.items.len = symbols_top;
                            }

                            // Only resolve the name if we're resolving inline callers, otherwise
                            // wait until we're done to avoid duplicated work.
                            const name = if (resolve_inline_callers)
                                pdb.findInlineeName(inline_site.inlinee)
                            else
                                null;

                            try symbols.append(symbol_allocator, .{
                                .name = name,
                                .compile_unit_name = compile_unit_name,
                                .source_location = loc,
                            });

                            last_inlinee = inline_site.inlinee;
                        }
                    }

                    if (resolve_inline_callers) {
                        // Inline sites are stored in the pdb in reverse order, so we reverse the
                        // matching sites here. We could alternatively use the parent fields to
                        // determine the order, but this would introduce seemingly unecessary
                        // complexity.
                        std.mem.reverse(std.debug.Symbol, symbols.items);
                    } else if (last_inlinee) |inlinee| {
                        // If we aren't resolving inline callers, then all results will have the
                        // same inline site, and we resolve its name once at the end.
                        const name = pdb.findInlineeName(inlinee);
                        for (symbols.items) |*symbol| symbol.name = name;
                    }
                }

                // If there's room for another symbol, add the actual proc
                if (resolve_inline_callers or symbols.items.len == 0) {
                    try symbols.append(symbol_allocator, .{
                        .name = if (maybe_proc) |proc| pdb.getSymbolName(proc) else null,
                        .compile_unit_name = compile_unit_name,
                        .source_location = pdb.getLineNumberInfo(text_arena, module, addr) catch null,
                    });
                }

                return;
            }

            dwarf: {
                const dwarf = &(di.dwarf orelse break :dwarf);
                const addr = vaddr + di.coff_image_base;
                return dwarf.getSymbols(
                    symbol_allocator,
                    text_arena,
                    native_endian,
                    addr,
                    resolve_inline_callers,
                    symbols,
                );
            }

            return error.MissingDebugInfo;
        }
    };

    fn deinit(module: *Module, gpa: Allocator, io: Io) void {
        if (module.name) |name| gpa.free(name);
        if (module.di) |*di_or_err| if (di_or_err.*) |*di| di.deinit(gpa, io) else |_| {};
        module.* = undefined;
    }

    fn getDebugInfo(module: *Module, gpa: Allocator, io: Io) Error!*DebugInfo {
        if (module.di == null) module.di = loadDebugInfo(module, gpa, io);
        return if (module.di.?) |*di| di else |err| err;
    }
    fn loadDebugInfo(module: *const Module, gpa: Allocator, io: Io) Error!DebugInfo {
        const mapped_ptr: [*]const u8 = @ptrCast(module.entry.DllBase);
        const mapped = mapped_ptr[0..module.entry.SizeOfImage];
        var coff_obj = coff.Coff.init(mapped, true) catch return error.InvalidDebugInfo;

        var arena_instance: std.heap.ArenaAllocator = .init(gpa);
        errdefer arena_instance.deinit();
        const arena = arena_instance.allocator();

        // The string table is not mapped into memory by the loader, so if a section name is in the
        // string table then we have to map the full image file from disk. This can happen when
        // a binary is produced with -gdwarf, since the section names are longer than 8 bytes.
        const mapped_file: ?DebugInfo.MappedFile = mapped: {
            if (!coff_obj.strtabRequired()) break :mapped null;
            var path_buffer: [4 + windows.PATH_MAX_WIDE]u16 = undefined;
            path_buffer[0..4].* = .{ '\\', '?', '?', '\\' }; // openFileAbsoluteW requires the prefix to be present
            const path_slice = module.entry.FullDllName.slice();
            @memcpy(path_buffer[4..][0..path_slice.len], path_slice);
            const coff_file = Io.Threaded.dirOpenFileWtf16(
                null,
                path_buffer[0 .. 4 + path_slice.len],
                .{},
            ) catch |err| switch (err) {
                error.Canceled => |e| return e,
                error.Unexpected => |e| return e,
                error.FileNotFound => return error.MissingDebugInfo,

                error.FileTooBig,
                error.IsDir,
                error.NotDir,
                error.SymLinkLoop,
                error.NameTooLong,
                error.BadPathName,
                => return error.InvalidDebugInfo,

                error.SystemResources,
                error.WouldBlock,
                error.AccessDenied,
                error.PermissionDenied,
                error.NoSpaceLeft,
                error.DeviceBusy,
                error.NoDevice,
                error.PathAlreadyExists,
                error.PipeBusy,
                error.NetworkNotFound,
                error.AntivirusInterference,
                error.ProcessFdQuotaExceeded,
                error.SystemFdQuotaExceeded,
                error.FileLocksUnsupported,
                error.FileBusy,
                error.ReadOnlyFileSystem,
                => return error.ReadFailed,
            };
            errdefer coff_file.close(io);
            var section_handle: windows.HANDLE = undefined;
            const create_section_rc = windows.ntdll.NtCreateSection(
                &section_handle,
                .{
                    .SPECIFIC = .{ .SECTION = .{
                        .QUERY = true,
                        .MAP_READ = true,
                    } },
                    .STANDARD = .{ .RIGHTS = .REQUIRED },
                },
                null,
                null,
                .{ .READONLY = true },
                // The documentation states that if no AllocationAttribute is specified,
                // then SEC_COMMIT is the default.
                // In practice, this isn't the case and specifying 0 will result in INVALID_PARAMETER_6.
                .{ .COMMIT = true },
                coff_file.handle,
            );
            if (create_section_rc != .SUCCESS) return error.MissingDebugInfo;
            errdefer windows.CloseHandle(section_handle);
            var coff_len: usize = 0;
            var section_view_ptr: ?[*]const u8 = null;
            const process_handle = windows.GetCurrentProcess();
            const map_section_rc = windows.ntdll.NtMapViewOfSection(
                section_handle,
                process_handle,
                @ptrCast(&section_view_ptr),
                null,
                0,
                null,
                &coff_len,
                .Unmap,
                .{},
                .{ .READONLY = true },
            );
            if (map_section_rc != .SUCCESS) return error.MissingDebugInfo;
            errdefer switch (windows.ntdll.NtUnmapViewOfSection(
                process_handle,
                @constCast(section_view_ptr.?),
            )) {
                .SUCCESS => {},
                else => |status| windows.unexpectedStatus(status) catch {},
            };
            const section_view = section_view_ptr.?[0..coff_len];
            coff_obj = coff.Coff.init(section_view, false) catch return error.InvalidDebugInfo;
            break :mapped .{
                .file = coff_file,
                .section_handle = section_handle,
                .section_view = section_view,
            };
        };
        errdefer if (mapped_file) |*mf| mf.deinit(io);

        const coff_image_base = coff_obj.getImageBase();

        var opt_dwarf: ?Dwarf = dwarf: {
            if (coff_obj.getSectionByName(".debug_info") == null) break :dwarf null;

            var sections: Dwarf.SectionArray = undefined;
            inline for (@typeInfo(Dwarf.Section.Id).@"enum".fields, 0..) |section, i| {
                sections[i] = if (coff_obj.getSectionByName("." ++ section.name)) |section_header| .{
                    .data = try coff_obj.getSectionDataAlloc(section_header, arena),
                    .owned = false,
                } else null;
            }
            break :dwarf .{ .sections = sections };
        };
        errdefer if (opt_dwarf) |*dwarf| dwarf.deinit(gpa);

        if (opt_dwarf) |*dwarf| {
            dwarf.open(gpa, native_endian) catch |err| switch (err) {
                error.Overflow,
                error.EndOfStream,
                error.StreamTooLong,
                error.ReadFailed,
                => return error.InvalidDebugInfo,

                error.InvalidDebugInfo,
                error.MissingDebugInfo,
                error.OutOfMemory,
                => |e| return e,
            };
        }

        var opt_pdb: ?Pdb = pdb: {
            const path = coff_obj.getPdbPath() catch {
                return error.InvalidDebugInfo;
            } orelse {
                break :pdb null;
            };
            const pdb_file_open_result = if (fs.path.isAbsolute(path)) res: {
                break :res Io.Dir.cwd().openFile(io, path, .{});
            } else res: {
                const self_dir = std.process.executableDirPathAlloc(io, gpa) catch |err| switch (err) {
                    error.OutOfMemory, error.Unexpected => |e| return e,
                    else => return error.ReadFailed,
                };
                defer gpa.free(self_dir);
                const abs_path = try fs.path.join(gpa, &.{ self_dir, path });
                defer gpa.free(abs_path);
                break :res Io.Dir.cwd().openFile(io, abs_path, .{});
            };
            const pdb_file = pdb_file_open_result catch |err| switch (err) {
                error.FileNotFound, error.IsDir => break :pdb null,
                else => return error.ReadFailed,
            };
            errdefer pdb_file.close(io);

            const pdb_reader = try arena.create(Io.File.Reader);
            pdb_reader.* = pdb_file.reader(io, try arena.alloc(u8, 4096));

            var pdb = Pdb.init(gpa, pdb_reader) catch |err| switch (err) {
                error.OutOfMemory, error.ReadFailed, error.Unexpected => |e| return e,
                else => return error.InvalidDebugInfo,
            };
            errdefer pdb.deinit();
            pdb.parseInfoStream() catch |err| switch (err) {
                error.UnknownPDBVersion => return error.UnsupportedDebugInfo,
                error.EndOfStream => return error.InvalidDebugInfo,

                error.InvalidDebugInfo,
                error.MissingDebugInfo,
                error.OutOfMemory,
                error.ReadFailed,
                => |e| return e,
            };
            pdb.parseDbiStream() catch |err| switch (err) {
                error.UnknownPDBVersion => return error.UnsupportedDebugInfo,

                error.EndOfStream,
                error.EOF,
                error.StreamTooLong,
                error.WriteFailed,
                => return error.InvalidDebugInfo,

                error.InvalidDebugInfo,
                error.OutOfMemory,
                error.ReadFailed,
                => |e| return e,
            };
            pdb.parseIpiStream() catch |err| switch (err) {
                error.UnknownPDBVersion => return error.UnsupportedDebugInfo,

                error.EndOfStream,
                => return error.InvalidDebugInfo,

                error.OutOfMemory,
                error.ReadFailed,
                => |e| return e,
            };

            if (!std.mem.eql(u8, &coff_obj.guid, &pdb.guid) or coff_obj.age != pdb.age)
                return error.InvalidDebugInfo;

            break :pdb pdb;
        };
        errdefer if (opt_pdb) |*pdb| {
            pdb.file_reader.file.close(io);
            pdb.deinit();
        };

        const coff_section_headers: []coff.SectionHeader = if (opt_pdb != null) csh: {
            break :csh try coff_obj.getSectionHeadersAlloc(arena);
        } else &.{};

        return .{
            .arena = arena_instance.state,
            .coff_image_base = coff_image_base,
            .mapped_file = mapped_file,
            .dwarf = opt_dwarf,
            .pdb = opt_pdb,
            .coff_section_headers = coff_section_headers,
        };
    }
};

/// Assumes we already hold `si.lock`.
fn findModule(si: *SelfInfo, gpa: Allocator, address: usize) error{ MissingDebugInfo, OutOfMemory, Unexpected }!*Module {
    for (si.modules.items) |*mod| {
        const base = @intFromPtr(mod.entry.DllBase);
        if (address >= base and address < base + mod.entry.SizeOfImage) return mod;
    }
    try si.modules.ensureUnusedCapacity(gpa, 1);
    var entry: *LDR.DATA_TABLE_ENTRY = undefined;
    switch (windows.ntdll.LdrFindEntryForAddress(@ptrFromInt(address), &entry)) {
        .SUCCESS => {},
        .DLL_NOT_FOUND => return error.MissingDebugInfo,
        else => |status| return windows.unexpectedStatus(status),
    }
    if (si.notification_cookie == null) {
        var notification_cookie: LDR.DLL_NOTIFICATION.COOKIE = undefined;
        switch ((try si.getNtdllProc(.LdrRegisterDllNotification))(
            .{},
            &dllNotification,
            si,
            &notification_cookie,
        )) {
            .SUCCESS => si.notification_cookie = notification_cookie,
            else => |status| return windows.unexpectedStatus(status),
        }
    }
    const mod = si.modules.addOneAssumeCapacity();
    mod.* = .{ .entry = entry, .name = null, .di = null };
    return mod;
}

inline fn getNtdllProc(
    si: *SelfInfo,
    comptime proc: std.meta.DeclEnum(windows.ntdll),
) !@TypeOf(&@field(windows.ntdll, @tagName(proc))) {
    return if (load_dll_notification_procs)
        @ptrCast(try si.loadNtdllProc(@tagName(proc)))
    else
        &@field(windows.ntdll, @tagName(proc));
}
fn loadNtdllProc(si: *SelfInfo, name: []const u8) Io.UnexpectedError!*anyopaque {
    const ntdll_handle = si.ntdll_handle orelse ntdll_handle: {
        var ntdll_handle: *anyopaque = undefined;
        switch (windows.ntdll.LdrLoadDll(null, null, &.init(
            &.{ 'n', 't', 'd', 'l', 'l', '.', 'd', 'l', 'l' },
        ), &ntdll_handle)) {
            .SUCCESS => {},
            .DLL_NOT_FOUND => return error.Unexpected,
            else => |status| return windows.unexpectedStatus(status),
        }
        si.ntdll_handle = ntdll_handle;
        break :ntdll_handle ntdll_handle;
    };
    var proc_addr: *anyopaque = undefined;
    switch (windows.ntdll.LdrGetProcedureAddress(ntdll_handle, &.init(name), 0, &proc_addr)) {
        .SUCCESS => {},
        else => |status| return windows.unexpectedStatus(status),
    }
    return proc_addr;
}

fn dllNotification(
    reason: LDR.DLL_NOTIFICATION.REASON,
    data: *const LDR.DLL_NOTIFICATION.DATA,
    context: ?*anyopaque,
) callconv(.winapi) void {
    const si: *SelfInfo = @ptrCast(@alignCast(context));
    switch (reason) {
        .LOADED => {},
        .UNLOADED => {
            const io = std.Options.debug_io;
            si.lock.lockUncancelable(io);
            defer si.lock.unlock(io);
            for (si.modules.items, 0..) |*mod, mod_index| {
                if (mod.entry.DllBase != data.Unloaded.DllBase) continue;
                mod.deinit(std.debug.getDebugInfoAllocator(), io);
                _ = si.modules.swapRemove(mod_index);
                break;
            }
        },
    }
}

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Dwarf = std.debug.Dwarf;
const Pdb = std.debug.Pdb;
const Error = std.debug.SelfInfoError;
const coff = std.coff;
const fs = std.fs;
const windows = std.os.windows;
const LDR = windows.LDR;

const builtin = @import("builtin");
const native_endian = builtin.target.cpu.arch.endian();
const load_dll_notification_procs = builtin.abi == .msvc and switch (builtin.zig_backend) {
    .stage2_c => true,
    else => switch (builtin.output_mode) {
        .Exe => false,
        .Lib => switch (builtin.link_mode) {
            .static => true,
            .dynamic => false,
        },
        .Obj => true,
    },
};

const SelfInfo = @This();
