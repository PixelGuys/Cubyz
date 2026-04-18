const MemoryMap = @This();

const builtin = @import("builtin");
const native_os = builtin.os.tag;
const is_windows = native_os == .windows;

const std = @import("../../std.zig");
const Io = std.Io;
const File = Io.File;
const Allocator = std.mem.Allocator;

file: File,
/// Byte index inside `file` where `memory` starts. Page-aligned.
offset: u64,
/// Memory that may or may not remain consistent with file contents. Use `read`
/// and `write` to ensure synchronization points. Length has no alignment
/// requirement.
memory: []align(std.heap.page_size_min) u8,
/// Tells whether it is memory-mapped or file operations. On Windows this also
/// has a section handle.
section: ?Section,

pub const Section = if (is_windows) std.os.windows.HANDLE else void;

pub const CreateError = error{
    /// One of the following:
    /// * The `File.Kind` is not `file`.
    /// * The file is not open for reading and read access protections enabled.
    /// * The file is not open for writing and write access protections enabled.
    AccessDenied,
    /// The `prot` argument asks for `PROT_EXEC` but the mapped area belongs to a file on
    /// a filesystem that was mounted no-exec.
    PermissionDenied,
    LockedMemoryLimitExceeded,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
} || Allocator.Error || File.ReadPositionalError;

pub const CreateOptions = struct {
    /// Size of the mapping, in bytes. If this is longer than the file size,
    /// `memory` beyond the file end will be filled with zeroes and it is
    /// unspecified whether, after calling `write`, the file length will be
    /// set to `len` or remain unchanged.
    ///
    /// This value has no minimum alignment requirement, but may gain
    /// efficiency benefits from being a multiple of `File.Stat.block_size`.
    len: usize,
    /// When this has read set to false, bytes that are not modified before a
    /// sync may have the original file contents, or may be set to zero.
    protection: std.process.MemoryProtection = .{ .read = true, .write = true },
    /// If set to `true`, allows bytes observed before calling `read` to be
    /// undefined, and bytes unwritten before calling `write` to write
    /// undefined memory to the file.
    undefined_contents: bool = false,
    /// Prefault the pages. If this option is unsupported, it is silently
    /// ignored. Aside from custom Io implementations, this option is only
    /// supported on Linux.
    populate: bool = true,
    /// Asserted to be a multiple of page size which can be obtained via
    /// `std.heap.pageSize`.
    offset: u64 = 0,
};

/// To release the resources associated with the returned `MemoryMap`, call
/// `destroy`.
pub fn create(io: Io, file: File, options: CreateOptions) CreateError!MemoryMap {
    return io.vtable.fileMemoryMapCreate(io.userdata, file, options);
}

/// If `write` is not called before this function, changes to `memory` may or may
/// not be synchronized to `file`.
pub fn destroy(mm: *MemoryMap, io: Io) void {
    io.vtable.fileMemoryMapDestroy(io.userdata, mm);
}

pub const SetLengthError = error{
    /// Changing the mapping length could not be done atomically. Caller must
    /// use `destroy` and `create` to resize the mapping.
    OperationUnsupported,
    /// One of the following:
    /// * The `File.Kind` is not `file`.
    /// * The file is not open for reading and read access protections enabled.
    /// * The file is not open for writing and write access protections enabled.
    AccessDenied,
    /// The `prot` argument asks for `PROT_EXEC` but the mapped area belongs to a file on
    /// a filesystem that was mounted no-exec.
    PermissionDenied,
    LockedMemoryLimitExceeded,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
} || Allocator.Error || File.SetLengthError;

/// Change the size of the mapping. This does not sync the contents. The size
/// of the file after calling this is unspecified until `write` is called.
///
/// May change the pointer address of `memory`.
pub fn setLength(mm: *MemoryMap, io: Io, new_len: usize) SetLengthError!void {
    return io.vtable.fileMemoryMapSetLength(io.userdata, mm, new_len);
}

/// Synchronizes the contents of `memory` from `file`.
pub fn read(mm: *MemoryMap, io: Io) File.ReadPositionalError!void {
    return io.vtable.fileMemoryMapRead(io.userdata, mm);
}

/// Synchronizes the contents of `memory` to `file`.
///
/// If `memory.len` is greater than file size, the bytes beyond the end of the
/// file may be dropped, or they may be written, extending the size of the
/// file.
pub fn write(mm: *MemoryMap, io: Io) File.WritePositionalError!void {
    return io.vtable.fileMemoryMapWrite(io.userdata, mm);
}
