const WindowsSdk = @This();
const builtin = @import("builtin");

const std = @import("std");
const Io = std.Io;
const Dir = std.Io.Dir;
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;
const Environ = std.process.Environ;
const L = std.unicode.wtf8ToWtf16LeStringLiteral;
const is_32_bit = @bitSizeOf(usize) == 32;

windows10sdk: ?Installation,
windows81sdk: ?Installation,
msvc_lib_dir: ?[]const u8,

const windows = std.os.windows;

const windows_kits_reg_key = "Microsoft\\Windows Kits\\Installed Roots";

// https://learn.microsoft.com/en-us/windows/win32/msi/productversion
const version_major_minor_max_length = "255.255".len;
// ProductVersion in registry (created by Visual Studio installer) probably also follows this rule
const product_version_max_length = version_major_minor_max_length + ".65535".len;

/// Find path and version of Windows 10 SDK and Windows 8.1 SDK, and find path to MSVC's `lib/` directory.
/// Caller owns the result's fields.
/// Returns memory allocated by `gpa`
pub fn find(
    gpa: Allocator,
    io: Io,
    arch: std.Target.Cpu.Arch,
    environ_map: *const Environ.Map,
) error{ OutOfMemory, NotFound, PathTooLong }!WindowsSdk {
    if (builtin.os.tag != .windows) return error.NotFound;

    var registry: Registry = .{};
    defer registry.deinit();

    // If this key doesn't exist, neither the Win 8 SDK nor the Win 10 SDK is installed
    const roots_key = registry.openSoftwareKey(.{ .root = .local_machine, .wow64 = .wow64_32 }, L(windows_kits_reg_key)) catch |err| switch (err) {
        error.KeyNotFound => return error.NotFound,
    };
    defer roots_key.close();

    const windows10sdk = Installation.find(gpa, io, &registry, roots_key, L("KitsRoot10"), "", L("v10.0")) catch |err| switch (err) {
        error.InstallationNotFound => null,
        error.PathTooLong => null,
        error.VersionTooLong => null,
        error.OutOfMemory => return error.OutOfMemory,
    };
    errdefer if (windows10sdk) |*w| w.free(gpa);

    const windows81sdk = Installation.find(gpa, io, &registry, roots_key, L("KitsRoot81"), "winver", L("v8.1")) catch |err| switch (err) {
        error.InstallationNotFound => null,
        error.PathTooLong => null,
        error.VersionTooLong => null,
        error.OutOfMemory => return error.OutOfMemory,
    };
    errdefer if (windows81sdk) |*w| w.free(gpa);

    const msvc_lib_dir: ?[]const u8 = MsvcLibDir.find(gpa, io, &registry, arch, environ_map) catch |err| switch (err) {
        error.MsvcLibDirNotFound => null,
        error.OutOfMemory => return error.OutOfMemory,
    };
    errdefer gpa.free(msvc_lib_dir);

    return .{
        .windows10sdk = windows10sdk,
        .windows81sdk = windows81sdk,
        .msvc_lib_dir = msvc_lib_dir,
    };
}

pub fn free(sdk: WindowsSdk, gpa: Allocator) void {
    if (sdk.windows10sdk) |*w10sdk| {
        w10sdk.free(gpa);
    }
    if (sdk.windows81sdk) |*w81sdk| {
        w81sdk.free(gpa);
    }
    if (sdk.msvc_lib_dir) |msvc_lib_dir| {
        gpa.free(msvc_lib_dir);
    }
}

/// Iterates via `iterator` and collects all folders with names starting with `strip_prefix`
/// and a version. Returns slice of version strings sorted in descending order.
/// Caller owns result.
fn iterateAndFilterByVersion(
    iterator: *Dir.Iterator,
    gpa: Allocator,
    io: Io,
    prefix: []const u8,
) error{OutOfMemory}![][]const u8 {
    const Version = struct {
        nums: [4]u32,
        build: []const u8,

        fn parseNum(num: []const u8) ?u32 {
            if (num[0] == '0' and num.len > 1) return null;
            return std.fmt.parseInt(u32, num, 10) catch null;
        }

        fn order(lhs: @This(), rhs: @This()) std.math.Order {
            return std.mem.order(u32, &lhs.nums, &rhs.nums).differ() orelse
                std.mem.order(u8, lhs.build, rhs.build);
        }
    };
    var versions = std.array_list.Managed(Version).init(gpa);
    var dirs = std.array_list.Managed([]const u8).init(gpa);
    defer {
        versions.deinit();
        for (dirs.items) |filtered_dir| gpa.free(filtered_dir);
        dirs.deinit();
    }

    iterate: while (iterator.next(io) catch null) |entry| {
        if (entry.kind != .directory) continue;
        if (!std.mem.startsWith(u8, entry.name, prefix)) continue;

        var version: Version = .{
            .nums = .{0} ** 4,
            .build = "",
        };
        const suffix = entry.name[prefix.len..];
        const underscore = std.mem.findScalar(u8, entry.name, '_');
        var num_it = std.mem.splitScalar(u8, suffix[0 .. underscore orelse suffix.len], '.');
        version.nums[0] = Version.parseNum(num_it.first()) orelse continue;
        for (version.nums[1..]) |*num|
            num.* = Version.parseNum(num_it.next() orelse break) orelse continue :iterate
        else if (num_it.next()) |_| continue;

        const name = try gpa.dupe(u8, suffix);
        errdefer gpa.free(name);
        if (underscore) |pos| version.build = name[pos + 1 ..];

        try versions.append(version);
        try dirs.append(name);
    }

    std.mem.sortUnstableContext(0, dirs.items.len, struct {
        versions: []Version,
        dirs: [][]const u8,
        pub fn lessThan(context: @This(), lhs: usize, rhs: usize) bool {
            return context.versions[lhs].order(context.versions[rhs]).compare(.gt);
        }
        pub fn swap(context: @This(), lhs: usize, rhs: usize) void {
            std.mem.swap(Version, &context.versions[lhs], &context.versions[rhs]);
            std.mem.swap([]const u8, &context.dirs[lhs], &context.dirs[rhs]);
        }
    }{ .versions = versions.items, .dirs = dirs.items });
    return dirs.toOwnedSlice();
}

/// Not a general purpose implementation of an ntdll-based Registry API.
/// Only intended to support the particular calls necessary for the purposes of finding
/// the SDK/MSVC installation paths.
///
/// The advapi32 APIs internally open and cache `\Registry\Machine` and the current user
/// key when HKEY_LOCAL_MACHINE (HKLM) and HKEY_CURRENT_USER (HKCU) are passed, and also
/// rewrite key path values to go through WOW6432Node when appropriate.
///
/// For example, when opening `Software\Foo` relative to `HKEY_LOCAL_MACHINE` with
/// the WOW64_32KEY option set, that will end up as a call to NtLoadKeyEx with the path
/// rewritten to `Software\WOW6432Node\Foo` relative to a cached `\REGISTRY\Machine`
/// key.
///
/// For our purposes, we really only care about 4 potential variations of the `Software` key:
/// - Relative to HKLM, no redirection through WOW6432Node
/// - Relative to HKLM, redirected through WOW6432Node
/// - Relative to HKCU, no redirection through WOW6432Node
/// - Relative to HKCU, redirected through WOW6432Node
/// (e.g. all the values we care about are within one of those `Software` keys)
///
/// So, we cache those variants of the Software keys instead of HKLM/HKCU and treat them
/// as the "root" keys that the user can specify, which in turn (1) allows all provided key
/// paths to be agnostic to WOW6432Node, (2) avoids the need for internal path rewriting,
/// and (3) works correctly on 32-bit targets without any special support.
///
/// For example, instead of an advapi32 call with `Software\Foo` relative to
/// `HKEY_LOCAL_MACHINE` which may get rewritten to `Software\WOW6432Node\Foo`,
/// the equivalent is now a call to open `Foo` relative to some Software key variant.
const Registry = struct {
    cache: Cache = .{},

    pub fn deinit(self: Registry) void {
        if (!is_32_bit) {
            if (self.cache.hklm_software_foreign) |key| windows.CloseHandle(key);
            if (self.cache.hkcu_software_foreign) |key| windows.CloseHandle(key);
        }
        if (self.cache.hklm_software_native) |key| windows.CloseHandle(key);
        if (self.cache.hkcu_software_native) |key| windows.CloseHandle(key);
        if (self.cache.hkcu) |key| windows.CloseHandle(key);
    }

    const Cache = struct {
        hklm_software_foreign: if (is_32_bit) void else ?windows.HANDLE = if (is_32_bit) {} else null,
        hkcu_software_foreign: if (is_32_bit) void else ?windows.HANDLE = if (is_32_bit) {} else null,
        hklm_software_native: ?windows.HANDLE = null,
        hkcu_software_native: ?windows.HANDLE = null,
        hkcu: ?windows.HANDLE = null,

        fn getSoftware(cache: *const Cache, variant: Software) ?windows.HANDLE {
            if (!is_32_bit and variant.wow64 == .wow64_32) {
                return switch (variant.root) {
                    .local_machine => cache.hklm_software_foreign,
                    .current_user => cache.hkcu_software_foreign,
                };
            }
            return switch (variant.root) {
                .local_machine => cache.hklm_software_native,
                .current_user => cache.hkcu_software_native,
            };
        }
    };

    // This does not correspond to HKEY_LOCAL_MACHINE/HKEY_CURRENT_USER
    // since WOW64 redirection is applicable to e.g. `HKLM\Software` instead of
    // HKLM/HKCU directly. Since we are only ever interested in the
    // `Software` key, it makes more sense to treat `Software` as the "root"
    // since that allows us to work entirely with relative paths that are agnostic
    // to WOW6432Node redirection.
    const Software = struct {
        root: Root,
        wow64: Wow64 = .native,

        const Root = enum {
            local_machine,
            current_user,
        };

        fn getOrOpenKey(self: Software, registry: *Registry) !Key {
            if (registry.cache.getSoftware(self)) |handle| {
                return .{ .handle = handle };
            }

            const is_foreign = !is_32_bit and self.wow64 == .wow64_32;
            switch (self.root) {
                .local_machine => {
                    const path = if (is_foreign) L("\\Registry\\Machine\\Software\\WOW6432Node") else L("\\Registry\\Machine\\Software");
                    var key: Key = undefined;
                    const attr: windows.OBJECT.ATTRIBUTES = .{
                        .RootDirectory = null,
                        .Attributes = .{},
                        .ObjectName = @constCast(&windows.UNICODE_STRING.init(path)),
                        .SecurityDescriptor = null,
                        .SecurityQualityOfService = null,
                    };
                    const status = windows.ntdll.NtOpenKeyEx(
                        &key.handle,
                        .{ .MAXIMUM_ALLOWED = true },
                        &attr,
                        .{},
                    );
                    switch (status) {
                        .SUCCESS => {},
                        else => return error.KeyNotFound,
                    }
                    if (is_foreign) {
                        registry.cache.hklm_software_foreign = key.handle;
                    } else {
                        registry.cache.hklm_software_native = key.handle;
                    }
                    return key;
                },
                .current_user => {
                    const cu_handle: windows.HANDLE = registry.cache.hkcu orelse hkcu: {
                        var cu_handle: windows.HANDLE = undefined;
                        const status = windows.ntdll.RtlOpenCurrentUser(
                            .{ .MAXIMUM_ALLOWED = true },
                            &cu_handle,
                        );
                        switch (status) {
                            .SUCCESS => {},
                            else => return error.KeyNotFound,
                        }
                        registry.cache.hkcu = cu_handle;
                        break :hkcu cu_handle;
                    };
                    const cu_key: Registry.Key = .{ .handle = cu_handle };
                    const path = if (is_foreign) L("Software\\WOW6432Node") else L("Software");
                    const key = try cu_key.open(path);
                    if (is_foreign) {
                        registry.cache.hkcu_software_foreign = key.handle;
                    } else {
                        registry.cache.hkcu_software_native = key.handle;
                    }
                    return key;
                },
            }
        }
    };

    /// For 32-bit programs on a 64-bit operating system, the WOW64
    /// version of ntdll.dll handles the WOW6432Node redirection before
    /// calling into ntdll.dll proper, so no special handling is needed
    /// and this setting is irrelevant in that case.
    const Wow64 = enum {
        /// Use 64-bit registry on 64-bit targets and 32-bit registry on
        /// 32-bit targets.
        native,
        /// Go through WOW6432Node on both 32-bit and 64-bit targets,
        /// if relevant (ignored for 32-bit programs executed on a 32-bit
        /// OS).
        wow64_32,
    };

    fn tryOpenSoftwareKeyWithPrecedence(registry: *Registry, variants: []const Software, sub_path: []const u16) error{KeyNotFound}!Key {
        for (variants) |variant| {
            return registry.openSoftwareKey(variant, sub_path) catch continue;
        }
        return error.KeyNotFound;
    }

    fn openSoftwareKey(registry: *Registry, software: Software, sub_path: []const u16) error{KeyNotFound}!Key {
        const software_key = try software.getOrOpenKey(registry);
        return software_key.open(sub_path);
    }

    const Key = struct {
        handle: windows.HANDLE,

        fn close(self: Key) void {
            windows.CloseHandle(self.handle);
        }

        fn open(self: Key, sub_path: []const u16) error{KeyNotFound}!Key {
            var key: Key = undefined;
            const attr: windows.OBJECT.ATTRIBUTES = .{
                .RootDirectory = self.handle,
                .Attributes = .{},
                .ObjectName = @constCast(&windows.UNICODE_STRING.init(sub_path)),
                .SecurityDescriptor = null,
                .SecurityQualityOfService = null,
            };
            const status = windows.ntdll.NtOpenKeyEx(
                &key.handle,
                .{ .SPECIFIC = .{
                    .KEY = .{
                        .QUERY_VALUE = true,
                        .ENUMERATE_SUB_KEYS = true,
                    },
                } },
                &attr,
                .{},
            );
            switch (status) {
                .SUCCESS => return key,
                else => return error.KeyNotFound,
            }
        }

        const ValueEntry = union(enum) {
            default: void,
            name: []const u16,
        };

        fn getString(
            key: Key,
            gpa: Allocator,
            entry: ValueEntry,
            comptime result_encoding: enum { wtf16, wtf8 },
        ) error{ OutOfMemory, ValueNameNotFound, NotAString, StringNotFound }!(switch (result_encoding) {
            .wtf8 => []u8,
            .wtf16 => []u16,
        }) {
            const num_data_bytes = windows.MAX_PATH * 2;
            const stack_buf_len = @sizeOf(windows.KEY.VALUE.PARTIAL_INFORMATION) + num_data_bytes;
            var stack_info_buf: [stack_buf_len]u8 align(@alignOf(windows.KEY.VALUE.PARTIAL_INFORMATION)) = undefined;
            var result_len: windows.ULONG = undefined;
            const rc = windows.ntdll.NtQueryValueKey(
                key.handle,
                switch (entry) {
                    .name => |name| @constCast(&windows.UNICODE_STRING.init(name)),
                    .default => @constCast(&windows.UNICODE_STRING.empty),
                },
                .Partial,
                &stack_info_buf,
                stack_buf_len,
                &result_len,
            );
            var heap_info_buf: ?[]align(@alignOf(windows.KEY.VALUE.PARTIAL_INFORMATION)) u8 = null;
            defer if (heap_info_buf) |buf| gpa.free(buf);

            const info: *const windows.KEY.VALUE.PARTIAL_INFORMATION = switch (rc) {
                .SUCCESS => @ptrCast(&stack_info_buf),
                .BUFFER_OVERFLOW, .BUFFER_TOO_SMALL => heap_info: {
                    heap_info_buf = try gpa.alignedAlloc(u8, .of(windows.KEY.VALUE.PARTIAL_INFORMATION), result_len);
                    const heap_rc = windows.ntdll.NtQueryValueKey(
                        key.handle,
                        switch (entry) {
                            .name => |name| @constCast(&windows.UNICODE_STRING.init(name)),
                            .default => @constCast(&windows.UNICODE_STRING.empty),
                        },
                        .Partial,
                        heap_info_buf.?.ptr,
                        @intCast(heap_info_buf.?.len),
                        &result_len,
                    );
                    switch (heap_rc) {
                        .SUCCESS => break :heap_info @ptrCast(heap_info_buf.?.ptr),
                        .OBJECT_NAME_NOT_FOUND => return error.ValueNameNotFound,
                        else => return error.StringNotFound,
                    }
                },
                .OBJECT_NAME_NOT_FOUND => return error.ValueNameNotFound,
                else => return error.StringNotFound,
            };

            switch (info.Type) {
                .SZ => {},
                else => return error.NotAString,
            }

            const data_wtf16_with_nul = @as([*]const u16, @ptrCast(@alignCast(info.data())))[0..@divExact(info.DataLength, 2)];
            const data_wtf16 = std.mem.trimEnd(u16, data_wtf16_with_nul, L("\x00"));
            switch (result_encoding) {
                .wtf16 => return gpa.dupe(u16, data_wtf16),
                .wtf8 => return std.unicode.wtf16LeToWtf8Alloc(gpa, data_wtf16),
            }
        }

        fn getDword(key: Key, entry: ValueEntry) error{ ValueNameNotFound, NotADword, DwordNotFound }!windows.DWORD {
            const num_data_bytes = @sizeOf(windows.DWORD);
            const buf_len = @sizeOf(windows.KEY.VALUE.PARTIAL_INFORMATION) + num_data_bytes;
            var info_buf: [buf_len]u8 align(@alignOf(windows.KEY.VALUE.PARTIAL_INFORMATION)) = undefined;
            var result_len: windows.ULONG = undefined;
            const rc = windows.ntdll.NtQueryValueKey(
                key.handle,
                switch (entry) {
                    .name => |name| @constCast(&windows.UNICODE_STRING.init(name)),
                    .default => @constCast(&windows.UNICODE_STRING.empty),
                },
                .Partial,
                &info_buf,
                buf_len,
                &result_len,
            );
            switch (rc) {
                .SUCCESS => {},
                .OBJECT_NAME_NOT_FOUND => return error.ValueNameNotFound,
                else => return error.DwordNotFound,
            }

            const info: *const windows.KEY.VALUE.PARTIAL_INFORMATION = @ptrCast(&info_buf);

            switch (info.Type) {
                .DWORD => {},
                else => return error.NotADword,
            }

            return std.mem.bytesToValue(windows.DWORD, info.data());
        }
    };
};

pub const Installation = struct {
    path: []const u8,
    version: []const u8,

    /// Find path and version of Windows SDK.
    /// Caller owns the result's fields.
    fn find(
        gpa: Allocator,
        io: Io,
        registry: *Registry,
        roots_key: Registry.Key,
        roots_subkey: []const u16,
        prefix: []const u8,
        version_key_name: []const u16,
    ) error{ OutOfMemory, InstallationNotFound, PathTooLong, VersionTooLong }!Installation {
        roots: {
            const installation = findFromRoot(gpa, io, roots_key, roots_subkey, prefix) catch
                break :roots;
            if (installation.isValidVersion(roots_key)) return installation;
            installation.free(gpa);
        }
        {
            const installation = try findFromInstallationFolder(gpa, registry, version_key_name);
            if (installation.isValidVersion(roots_key)) return installation;
            installation.free(gpa);
        }
        return error.InstallationNotFound;
    }

    fn findFromRoot(
        gpa: Allocator,
        io: Io,
        roots_key: Registry.Key,
        roots_subkey: []const u16,
        prefix: []const u8,
    ) error{ OutOfMemory, InstallationNotFound, PathTooLong, VersionTooLong }!Installation {
        const path = path: {
            const path_w_maybe_with_trailing_slash = roots_key.getString(gpa, .{ .name = roots_subkey }, .wtf16) catch |err| switch (err) {
                error.NotAString,
                error.ValueNameNotFound,
                error.StringNotFound,
                => return error.InstallationNotFound,

                error.OutOfMemory => return error.OutOfMemory,
            };
            defer gpa.free(path_w_maybe_with_trailing_slash);

            if (!std.fs.path.isAbsoluteWindowsWtf16(path_w_maybe_with_trailing_slash)) {
                return error.InstallationNotFound;
            }

            const path_w = std.mem.trimEnd(u16, path_w_maybe_with_trailing_slash, L("\\/"));
            break :path try std.unicode.wtf16LeToWtf8Alloc(gpa, path_w);
        };
        errdefer gpa.free(path);

        const version = version: {
            var buf: [Dir.max_path_bytes]u8 = undefined;
            const sdk_lib_dir_path = std.fmt.bufPrint(buf[0..], "{s}\\Lib\\", .{path}) catch |err| switch (err) {
                error.NoSpaceLeft => return error.PathTooLong,
            };
            if (!Dir.path.isAbsolute(sdk_lib_dir_path)) return error.InstallationNotFound;

            // enumerate files in sdk path looking for latest version
            var sdk_lib_dir = Dir.openDirAbsolute(io, sdk_lib_dir_path, .{
                .iterate = true,
            }) catch |err| switch (err) {
                error.NameTooLong => return error.PathTooLong,
                else => return error.InstallationNotFound,
            };
            defer sdk_lib_dir.close(io);

            var iterator = sdk_lib_dir.iterate();
            const versions = try iterateAndFilterByVersion(&iterator, gpa, io, prefix);
            if (versions.len == 0) return error.InstallationNotFound;
            defer {
                for (versions[1..]) |version| gpa.free(version);
                gpa.free(versions);
            }
            break :version versions[0];
        };
        errdefer gpa.free(version);

        return .{ .path = path, .version = version };
    }

    fn findFromInstallationFolder(
        gpa: Allocator,
        registry: *Registry,
        version_key_name: []const u16,
    ) error{ OutOfMemory, InstallationNotFound, PathTooLong, VersionTooLong }!Installation {
        const key_name = try std.mem.concat(gpa, u16, &.{ L("Microsoft\\Microsoft SDKs\\Windows\\"), version_key_name });
        defer gpa.free(key_name);

        const key = registry.tryOpenSoftwareKeyWithPrecedence(switch (is_32_bit) {
            true => &.{
                .{ .root = .local_machine },
                .{ .root = .current_user },
            },
            false => &.{
                .{ .root = .local_machine, .wow64 = .wow64_32 },
                .{ .root = .current_user, .wow64 = .wow64_32 },
                .{ .root = .local_machine, .wow64 = .native },
                .{ .root = .current_user, .wow64 = .native },
            },
        }, key_name) catch {
            return error.InstallationNotFound;
        };
        defer key.close();

        const path: []const u8 = path: {
            const path_w_maybe_with_trailing_slash = key.getString(gpa, .{ .name = L("InstallationFolder") }, .wtf16) catch |err| switch (err) {
                error.NotAString,
                error.ValueNameNotFound,
                error.StringNotFound,
                => return error.InstallationNotFound,

                error.OutOfMemory => return error.OutOfMemory,
            };
            defer gpa.free(path_w_maybe_with_trailing_slash);

            if (!std.fs.path.isAbsoluteWindowsWtf16(path_w_maybe_with_trailing_slash)) {
                return error.InstallationNotFound;
            }

            const path_w = std.mem.trimEnd(u16, path_w_maybe_with_trailing_slash, L("\\/"));
            break :path try std.unicode.wtf16LeToWtf8Alloc(gpa, path_w);
        };
        errdefer gpa.free(path);

        const version: []const u8 = version: {
            // Microsoft doesn't include the .0 in the ProductVersion key
            const version_without_0 = key.getString(gpa, .{ .name = L("ProductVersion") }, .wtf16) catch |err| switch (err) {
                error.NotAString,
                error.ValueNameNotFound,
                error.StringNotFound,
                => return error.InstallationNotFound,

                error.OutOfMemory => return error.OutOfMemory,
            };
            defer gpa.free(version_without_0);

            if (version_without_0.len + ".0".len > product_version_max_length) {
                return error.VersionTooLong;
            }

            var version: std.array_list.Managed(u8) = try .initCapacity(gpa, version_without_0.len + 2);
            errdefer version.deinit();

            try std.unicode.wtf16LeToWtf8ArrayList(&version, version_without_0);
            try version.appendSlice(".0");

            break :version try version.toOwnedSlice();
        };
        errdefer gpa.free(version);

        return .{ .path = path, .version = version };
    }

    /// Check whether this version is enumerated in registry.
    fn isValidVersion(installation: Installation, roots_key: Registry.Key) bool {
        var version_buf: [product_version_max_length]u16 = undefined;
        const version_len = std.unicode.wtf8ToWtf16Le(&version_buf, installation.version) catch return false;
        const version = version_buf[0..version_len];
        const options_key_name = "Installed Options";
        const buf_len = product_version_max_length + options_key_name.len + 2;
        var buf: [buf_len]u16 = undefined;
        var query: std.ArrayList(u16) = .initBuffer(&buf);
        query.appendSliceAssumeCapacity(version);
        query.appendAssumeCapacity('\\');
        query.appendSliceAssumeCapacity(L(options_key_name));

        const options_key = roots_key.open(query.items) catch |err| switch (err) {
            error.KeyNotFound => return false,
        };
        defer options_key.close();

        const option_name = comptime switch (builtin.target.cpu.arch) {
            .thumb => "OptionId.DesktopCPParm",
            .aarch64 => "OptionId.DesktopCPParm64",
            .x86 => "OptionId.DesktopCPPx86",
            .x86_64 => "OptionId.DesktopCPPx64",
            else => |tag| @compileError("Windows SDK cannot be detected on architecture " ++ tag),
        };

        const reg_value = options_key.getDword(.{ .name = L(option_name) }) catch return false;
        return (reg_value == 1);
    }

    fn free(install: Installation, gpa: Allocator) void {
        gpa.free(install.path);
        gpa.free(install.version);
    }
};

const MsvcLibDir = struct {
    fn findInstancesDirViaSetup(gpa: Allocator, io: Io, registry: *Registry) error{ OutOfMemory, PathNotFound }!Dir {
        const vs_setup_key_path = L("Microsoft\\VisualStudio\\Setup");
        const vs_setup_key = registry.openSoftwareKey(.{ .root = .local_machine }, vs_setup_key_path) catch |err| switch (err) {
            error.KeyNotFound => return error.PathNotFound,
        };
        defer vs_setup_key.close();

        const packages_path = vs_setup_key.getString(gpa, .{ .name = L("CachePath") }, .wtf8) catch |err| switch (err) {
            error.NotAString,
            error.ValueNameNotFound,
            error.StringNotFound,
            => return error.PathNotFound,

            error.OutOfMemory => return error.OutOfMemory,
        };
        defer gpa.free(packages_path);

        if (!std.fs.path.isAbsolute(packages_path)) return error.PathNotFound;

        const instances_path = try std.fs.path.join(gpa, &.{ packages_path, "_Instances" });
        defer gpa.free(instances_path);

        return Dir.openDirAbsolute(io, instances_path, .{ .iterate = true }) catch return error.PathNotFound;
    }

    fn findInstancesDirViaCLSID(gpa: Allocator, io: Io, registry: *Registry) error{ OutOfMemory, PathNotFound }!Dir {
        const setup_configuration_clsid = "{177f0c4a-1cd3-4de7-a32c-71dbbb9fa36d}";

        // HKEY_CLASSES_ROOT is not a single key but instead a combination of
        // HKCU\Software\Classes and HKLM\Software\Classes with HKCU taking precedent
        // https://learn.microsoft.com/en-us/windows/win32/sysinfo/hkey-classes-root-key
        //
        // Instead of a CLASSES_ROOT abstraction, we emulate the behavior with a more
        // general abstraction, which also means we need to include `Classes` in the path since
        // we're starting from the `Software` keys instead of the "classes root".
        //
        // The advapi32 APIs with `HKEY_CLASSES_ROOT` go through `\REGISTRY\USER\<SID>_Classes`
        // instead of `\REGISTRY\USER\<SID>\Software\Classes`, but we go through the latter
        // because it allows us to take advantage of `RtlOpenCurrentUser` to avoid needing to implement
        // the logic for getting the current user registry path, and it appears that the two keys are
        // effectively equivalent. Further investigation of the relationship of these keys would probably
        // be beneficial, though.
        const setup_config_key = registry.tryOpenSoftwareKeyWithPrecedence(&.{
            .{ .root = .current_user },
            .{ .root = .local_machine },
        }, L("Classes\\CLSID\\" ++ setup_configuration_clsid)) catch |err| switch (err) {
            error.KeyNotFound => return error.PathNotFound,
        };
        defer setup_config_key.close();

        const inproc_server = setup_config_key.open(L("InprocServer32")) catch return error.PathNotFound;
        const dll_path = inproc_server.getString(gpa, .default, .wtf8) catch |err| switch (err) {
            error.NotAString,
            error.ValueNameNotFound,
            error.StringNotFound,
            => return error.PathNotFound,

            error.OutOfMemory => return error.OutOfMemory,
        };
        defer gpa.free(dll_path);

        if (!std.fs.path.isAbsolute(dll_path)) return error.PathNotFound;

        var path_it = std.fs.path.componentIterator(dll_path);
        // the .dll filename
        _ = path_it.last();
        const root_path = while (path_it.previous()) |dir_component| {
            if (std.ascii.eqlIgnoreCase(dir_component.name, "VisualStudio")) {
                break dir_component.path;
            }
        } else {
            return error.PathNotFound;
        };

        const instances_path = try std.fs.path.join(gpa, &.{ root_path, "Packages", "_Instances" });
        defer gpa.free(instances_path);

        return Dir.openDirAbsolute(io, instances_path, .{ .iterate = true }) catch return error.PathNotFound;
    }

    fn findInstancesDir(
        gpa: Allocator,
        io: Io,
        registry: *Registry,
        environ_map: *const Environ.Map,
    ) error{ OutOfMemory, PathNotFound }!Dir {
        // First, try getting the packages cache path from the registry.
        // This only seems to exist when the path is different from the default.
        method1: {
            return findInstancesDirViaSetup(gpa, io, registry) catch |err| switch (err) {
                error.OutOfMemory => |e| return e,
                error.PathNotFound => break :method1,
            };
        }
        // Otherwise, try to get the path from the .dll that would have been
        // loaded via COM for SetupConfiguration.
        method2: {
            return findInstancesDirViaCLSID(gpa, io, registry) catch |err| switch (err) {
                error.OutOfMemory => |e| return e,
                error.PathNotFound => break :method2,
            };
        }
        // If that can't be found, fall back to manually appending
        // `Microsoft\VisualStudio\Packages\_Instances` to %PROGRAMDATA%
        method3: {
            const program_data = std.zig.EnvVar.PROGRAMDATA.get(environ_map) orelse break :method3;

            if (!std.fs.path.isAbsolute(program_data)) break :method3;

            const instances_path = try Dir.path.join(gpa, &.{
                program_data, "Microsoft", "VisualStudio", "Packages", "_Instances",
            });
            defer gpa.free(instances_path);

            return Dir.openDirAbsolute(io, instances_path, .{ .iterate = true }) catch break :method3;
        }
        return error.PathNotFound;
    }

    /// Intended to be equivalent to `ISetupHelper.ParseVersion`
    /// Example: 17.4.33205.214 -> 0x0011000481b500d6
    fn parseVersionQuad(version: []const u8) error{InvalidVersion}!u64 {
        var it = std.mem.splitScalar(u8, version, '.');
        const a = it.first();
        const b = it.next() orelse return error.InvalidVersion;
        const c = it.next() orelse return error.InvalidVersion;
        const d = it.next() orelse return error.InvalidVersion;
        if (it.next()) |_| return error.InvalidVersion;
        var result: u64 = undefined;
        var result_bytes = std.mem.asBytes(&result);

        std.mem.writeInt(
            u16,
            result_bytes[0..2],
            std.fmt.parseUnsigned(u16, d, 10) catch return error.InvalidVersion,
            .little,
        );
        std.mem.writeInt(
            u16,
            result_bytes[2..4],
            std.fmt.parseUnsigned(u16, c, 10) catch return error.InvalidVersion,
            .little,
        );
        std.mem.writeInt(
            u16,
            result_bytes[4..6],
            std.fmt.parseUnsigned(u16, b, 10) catch return error.InvalidVersion,
            .little,
        );
        std.mem.writeInt(
            u16,
            result_bytes[6..8],
            std.fmt.parseUnsigned(u16, a, 10) catch return error.InvalidVersion,
            .little,
        );

        return result;
    }

    /// Intended to be equivalent to ISetupConfiguration.EnumInstances:
    /// https://learn.microsoft.com/en-us/dotnet/api/microsoft.visualstudio.setup.configuration
    /// but without the use of COM in order to avoid a dependency on ole32.dll
    ///
    /// The logic in this function is intended to match what ISetupConfiguration does
    /// under-the-hood, as verified using Procmon.
    fn findViaCOM(
        gpa: Allocator,
        io: Io,
        registry: *Registry,
        arch: std.Target.Cpu.Arch,
        environ_map: *const Environ.Map,
    ) error{ OutOfMemory, PathNotFound }![]const u8 {
        // Typically `%PROGRAMDATA%\Microsoft\VisualStudio\Packages\_Instances`
        // This will contain directories with names of instance IDs like 80a758ca,
        // which will contain `state.json` files that have the version and
        // installation directory.
        var instances_dir = try findInstancesDir(gpa, io, registry, environ_map);
        defer instances_dir.close(io);

        var state_subpath_buf: [Dir.max_name_bytes + 32]u8 = undefined;
        var latest_version_lib_dir: std.ArrayList(u8) = .empty;
        errdefer latest_version_lib_dir.deinit(gpa);

        var latest_version: u64 = 0;
        var instances_dir_it = instances_dir.iterateAssumeFirstIteration();
        while (instances_dir_it.next(io) catch return error.PathNotFound) |entry| {
            if (entry.kind != .directory) continue;

            var writer: Writer = .fixed(&state_subpath_buf);

            writer.writeAll(entry.name) catch unreachable;
            writer.writeByte(Dir.path.sep) catch unreachable;
            writer.writeAll("state.json") catch unreachable;

            const json_contents = instances_dir.readFileAlloc(io, writer.buffered(), gpa, .limited(std.math.maxInt(usize))) catch continue;
            defer gpa.free(json_contents);

            var parsed = std.json.parseFromSlice(std.json.Value, gpa, json_contents, .{}) catch continue;
            defer parsed.deinit();

            if (parsed.value != .object) continue;
            const catalog_info = parsed.value.object.get("catalogInfo") orelse continue;
            if (catalog_info != .object) continue;
            const product_version_value = catalog_info.object.get("buildVersion") orelse continue;
            if (product_version_value != .string) continue;
            const product_version_text = product_version_value.string;
            const parsed_version = parseVersionQuad(product_version_text) catch continue;

            // We want to end up with the most recent version installed
            if (parsed_version <= latest_version) continue;

            const installation_path = parsed.value.object.get("installationPath") orelse continue;
            if (installation_path != .string) continue;

            const lib_dir_path = libDirFromInstallationPath(gpa, io, installation_path.string, arch) catch |err| switch (err) {
                error.OutOfMemory => |e| return e,
                error.PathNotFound => continue,
            };
            defer gpa.free(lib_dir_path);

            latest_version_lib_dir.clearRetainingCapacity();
            try latest_version_lib_dir.appendSlice(gpa, lib_dir_path);
            latest_version = parsed_version;
        }

        if (latest_version_lib_dir.items.len == 0) return error.PathNotFound;
        return latest_version_lib_dir.toOwnedSlice(gpa);
    }

    fn libDirFromInstallationPath(
        gpa: Allocator,
        io: Io,
        installation_path: []const u8,
        arch: std.Target.Cpu.Arch,
    ) error{ OutOfMemory, PathNotFound }![]const u8 {
        var lib_dir_buf = try std.array_list.Managed(u8).initCapacity(gpa, installation_path.len + 64);
        errdefer lib_dir_buf.deinit();

        lib_dir_buf.appendSliceAssumeCapacity(installation_path);

        if (!Dir.path.isSep(lib_dir_buf.getLast())) {
            try lib_dir_buf.append('\\');
        }
        const installation_path_with_trailing_sep_len = lib_dir_buf.items.len;

        try lib_dir_buf.appendSlice("VC\\Auxiliary\\Build\\Microsoft.VCToolsVersion.default.txt");
        var default_tools_version_buf: [512]u8 = undefined;
        const default_tools_version_contents = Dir.cwd().readFile(io, lib_dir_buf.items, &default_tools_version_buf) catch {
            return error.PathNotFound;
        };
        var tokenizer = std.mem.tokenizeAny(u8, default_tools_version_contents, " \r\n");
        const default_tools_version = tokenizer.next() orelse return error.PathNotFound;

        lib_dir_buf.shrinkRetainingCapacity(installation_path_with_trailing_sep_len);
        try lib_dir_buf.appendSlice("VC\\Tools\\MSVC\\");
        try lib_dir_buf.appendSlice(default_tools_version);
        try lib_dir_buf.appendSlice("\\Lib\\");
        try lib_dir_buf.appendSlice(switch (arch) {
            .thumb => "arm",
            .aarch64 => "arm64",
            .x86 => "x86",
            .x86_64 => "x64",
            else => unreachable,
        });

        if (!verifyLibDir(io, lib_dir_buf.items)) {
            return error.PathNotFound;
        }

        return lib_dir_buf.toOwnedSlice();
    }

    // https://learn.microsoft.com/en-us/visualstudio/install/tools-for-managing-visual-studio-instances?view=vs-2022#editing-the-registry-for-a-visual-studio-instance
    fn findViaRegistry(
        gpa: Allocator,
        io: Io,
        arch: std.Target.Cpu.Arch,
        environ_map: *const Environ.Map,
    ) error{ OutOfMemory, PathNotFound }![]const u8 {
        // %localappdata%\Microsoft\VisualStudio\
        // %appdata%\Local\Microsoft\VisualStudio\
        const local_app_data_path = std.zig.EnvVar.LOCALAPPDATA.get(environ_map) orelse return error.PathNotFound;
        const visualstudio_folder_path = try Dir.path.join(gpa, &.{
            local_app_data_path, "Microsoft\\VisualStudio\\",
        });
        defer gpa.free(visualstudio_folder_path);

        if (!Dir.path.isAbsolute(visualstudio_folder_path)) return error.PathNotFound;
        // To make things easier later on, we open the VisualStudio directory here which
        // allows us to pass relative paths to NtLoadKeyEx in order to avoid dealing with
        // conversion to NT namespace paths.
        var visualstudio_folder = Dir.openDirAbsolute(io, visualstudio_folder_path, .{
            .iterate = true,
        }) catch return error.PathNotFound;
        defer visualstudio_folder.close(io);

        const vs_versions: []const []const u8 = vs_versions: {
            // enumerate folders that contain `privateregistry.bin`, looking for all versions
            // f.i. %localappdata%\Microsoft\VisualStudio\17.0_9e9cbb98\
            var iterator = visualstudio_folder.iterate();
            break :vs_versions try iterateAndFilterByVersion(&iterator, gpa, io, "");
        };
        defer {
            for (vs_versions) |vs_version| gpa.free(vs_version);
            gpa.free(vs_versions);
        }
        var key_path_buf: [windows.NAME_MAX * 2]u16 = undefined;
        var sub_path_buf: [windows.NAME_MAX * 2]u16 = undefined;
        const source_directories: []const u8 = source_directories: for (vs_versions) |vs_version| {
            const sub_path = blk: {
                var buf: std.ArrayList(u16) = .initBuffer(&sub_path_buf);
                buf.items.len += std.unicode.wtf8ToWtf16Le(buf.unusedCapacitySlice(), vs_version) catch unreachable;
                buf.appendSliceAssumeCapacity(L("\\privateregistry.bin"));
                break :blk buf.items;
            };

            // The goal is to emulate advapi32.RegLoadAppKeyW with a direct call
            // to NtLoadKeyEx instead.
            //
            // RegLoadAppKeyW loads the hive into a registry key of the format:
            // \REGISTRY\A\{fdb2baa5-8ca8-ef03-78d0-3b1f868fd2a9}
            // where `\REGISTRY\A` is a special unenumerable location intended for
            // per-app hives, and the GUID is randomly generated (in testing, it
            // was different for each run of the program).
            //
            // The OS is responsible for cleaning up `\REGISTRY\A` whenever all handles
            // to one of its keys are closed, so we don't have to do anything special
            // with regards to that.

            const temp_key_path = blk: {
                var guid: windows.GUID = undefined;
                io.random(std.mem.asBytes(&guid));

                var guid_buf: [38]u8 = undefined;
                const guid_str = std.fmt.bufPrint(&guid_buf, "{f}", .{guid}) catch unreachable;

                var buf: std.ArrayList(u16) = .initBuffer(&key_path_buf);
                buf.appendSliceAssumeCapacity(L("\\REGISTRY\\A\\"));
                buf.items.len += std.unicode.wtf8ToWtf16Le(buf.unusedCapacitySlice(), guid_str) catch unreachable;
                break :blk buf.items;
            };

            const target_key: windows.OBJECT.ATTRIBUTES = .{
                .RootDirectory = null,
                .Attributes = .{},
                .ObjectName = @constCast(&windows.UNICODE_STRING.init(temp_key_path)),
                .SecurityDescriptor = null,
            };
            const source_file: windows.OBJECT.ATTRIBUTES = .{
                .RootDirectory = visualstudio_folder.handle,
                .Attributes = .{},
                .ObjectName = @constCast(&windows.UNICODE_STRING.init(sub_path)),
                .SecurityDescriptor = null,
            };
            var root_key: Registry.Key = undefined;
            const rc = windows.ntdll.NtLoadKeyEx(
                &target_key,
                &source_file,
                .{
                    .APP_HIVE = true,
                    // This wasn't set by RegLoadAppKeyW, but it seems relevant
                    // since we aren't intending to do any modifcation of the hive.
                    .OPEN_READ_ONLY = true,
                },
                null,
                null,
                .{ .SPECIFIC = .{
                    .KEY = .{
                        .QUERY_VALUE = true,
                        .ENUMERATE_SUB_KEYS = true,
                    },
                } },
                &root_key.handle,
                null,
            );
            switch (rc) {
                .SUCCESS => {},
                else => continue,
            }
            defer root_key.close();

            const config_path = blk: {
                var buf: std.ArrayList(u16) = .initBuffer(&key_path_buf);
                buf.appendSliceAssumeCapacity(L("Software\\Microsoft\\VisualStudio\\"));
                buf.items.len += std.unicode.wtf8ToWtf16Le(buf.unusedCapacitySlice(), vs_version) catch unreachable;
                buf.appendSliceAssumeCapacity(L("_Config"));
                break :blk buf.items;
            };
            const config_key = root_key.open(config_path) catch continue;

            const source_directories_value = config_key.getString(gpa, .{ .name = L("Source Directories") }, .wtf8) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => continue,
            };

            break :source_directories source_directories_value;
        } else return error.PathNotFound;
        defer gpa.free(source_directories);

        var source_directories_split = std.mem.splitScalar(u8, source_directories, ';');

        const msvc_dir: []const u8 = msvc_dir: {
            const msvc_include_dir_maybe_with_trailing_slash = try gpa.dupe(u8, source_directories_split.first());

            if (msvc_include_dir_maybe_with_trailing_slash.len > Dir.max_path_bytes or !Dir.path.isAbsolute(msvc_include_dir_maybe_with_trailing_slash)) {
                gpa.free(msvc_include_dir_maybe_with_trailing_slash);
                return error.PathNotFound;
            }

            var msvc_dir = std.array_list.Managed(u8).fromOwnedSlice(gpa, msvc_include_dir_maybe_with_trailing_slash);
            errdefer msvc_dir.deinit();

            // String might contain trailing slash, so trim it here
            if (msvc_dir.items.len > "C:\\".len and msvc_dir.getLast() == '\\') _ = msvc_dir.pop();

            // Remove `\include` at the end of path
            if (std.mem.endsWith(u8, msvc_dir.items, "\\include")) {
                msvc_dir.shrinkRetainingCapacity(msvc_dir.items.len - "\\include".len);
            }

            try msvc_dir.appendSlice("\\Lib\\");
            try msvc_dir.appendSlice(switch (arch) {
                .thumb => "arm",
                .aarch64 => "arm64",
                .x86 => "x86",
                .x86_64 => "x64",
                else => unreachable,
            });
            const msvc_dir_with_arch = try msvc_dir.toOwnedSlice();
            break :msvc_dir msvc_dir_with_arch;
        };
        errdefer gpa.free(msvc_dir);

        if (!verifyLibDir(io, msvc_dir)) {
            return error.PathNotFound;
        }

        return msvc_dir;
    }

    fn findViaVs7Key(
        gpa: Allocator,
        io: Io,
        registry: *Registry,
        arch: std.Target.Cpu.Arch,
        environ_map: *const Environ.Map,
    ) error{ OutOfMemory, PathNotFound }![]const u8 {
        var base_path: std.array_list.Managed(u8) = base_path: {
            try_env: {
                if (environ_map.get("VS140COMNTOOLS")) |VS140COMNTOOLS| {
                    if (VS140COMNTOOLS.len < "C:\\Common7\\Tools".len) break :try_env;
                    if (!Dir.path.isAbsolute(VS140COMNTOOLS)) break :try_env;
                    var list = std.array_list.Managed(u8).init(gpa);
                    errdefer list.deinit();

                    try list.appendSlice(VS140COMNTOOLS); // C:\Program Files (x86)\Microsoft Visual Studio 14.0\Common7\Tools
                    // String might contain trailing slash, so trim it here
                    if (list.items.len > "C:\\".len and list.getLast() == '\\') _ = list.pop();
                    list.shrinkRetainingCapacity(list.items.len - "\\Common7\\Tools".len); // C:\Program Files (x86)\Microsoft Visual Studio 14.0
                    break :base_path list;
                }
            }

            const vs7_key = registry.openSoftwareKey(.{ .root = .local_machine, .wow64 = .wow64_32 }, L("Microsoft\\VisualStudio\\SxS\\VS7")) catch return error.PathNotFound;
            defer vs7_key.close();
            try_vs7_key: {
                const path_maybe_with_trailing_slash = vs7_key.getString(gpa, .{ .name = L("14.0") }, .wtf8) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => break :try_vs7_key,
                };

                if (path_maybe_with_trailing_slash.len > Dir.max_path_bytes or !Dir.path.isAbsolute(path_maybe_with_trailing_slash)) {
                    gpa.free(path_maybe_with_trailing_slash);
                    break :try_vs7_key;
                }

                var path = std.array_list.Managed(u8).fromOwnedSlice(gpa, path_maybe_with_trailing_slash);
                errdefer path.deinit();

                // String might contain trailing slash, so trim it here
                if (path.items.len > "C:\\".len and path.getLast() == '\\') _ = path.pop();
                break :base_path path;
            }
            return error.PathNotFound;
        };
        errdefer base_path.deinit();

        try base_path.appendSlice("\\VC\\lib\\");
        try base_path.appendSlice(switch (arch) {
            .thumb => "arm",
            .aarch64 => "arm64",
            .x86 => "", //x86 is in the root of the Lib folder
            .x86_64 => "amd64",
            else => unreachable,
        });

        if (!verifyLibDir(io, base_path.items)) {
            return error.PathNotFound;
        }

        const full_path = try base_path.toOwnedSlice();
        return full_path;
    }

    fn verifyLibDir(io: Io, lib_dir_path: []const u8) bool {
        std.debug.assert(Dir.path.isAbsolute(lib_dir_path)); // should be already handled in `findVia*`

        var dir = Dir.openDirAbsolute(io, lib_dir_path, .{}) catch return false;
        defer dir.close(io);

        const stat = dir.statFile(io, "vcruntime.lib", .{}) catch return false;
        if (stat.kind != .file)
            return false;

        return true;
    }

    /// Find path to MSVC's `lib/` directory.
    /// Caller owns the result.
    pub fn find(
        gpa: Allocator,
        io: Io,
        registry: *Registry,
        arch: std.Target.Cpu.Arch,
        environ_map: *const Environ.Map,
    ) error{ OutOfMemory, MsvcLibDirNotFound }![]const u8 {
        const full_path = MsvcLibDir.findViaCOM(gpa, io, registry, arch, environ_map) catch |err1| switch (err1) {
            error.OutOfMemory => return error.OutOfMemory,
            error.PathNotFound => MsvcLibDir.findViaRegistry(gpa, io, arch, environ_map) catch |err2| switch (err2) {
                error.OutOfMemory => return error.OutOfMemory,
                error.PathNotFound => MsvcLibDir.findViaVs7Key(gpa, io, registry, arch, environ_map) catch |err3| switch (err3) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.PathNotFound => return error.MsvcLibDirNotFound,
                },
            },
        };
        errdefer gpa.free(full_path);

        return full_path;
    }
};
