//! This file contains thin wrappers around Windows-specific APIs, with these
//! specific goals in mind:
//! * Convert "errno"-style error codes into Zig errors.
//! * When null-terminated or WTF16LE byte buffers are required, provide APIs which accept
//!   slices as well as APIs which accept null-terminated WTF16LE byte buffers.

const builtin = @import("builtin");
const native_arch = builtin.cpu.arch;

const std = @import("../std.zig");
const Io = std.Io;
const mem = std.mem;
const assert = std.debug.assert;
const math = std.math;
const maxInt = std.math.maxInt;
const UnexpectedError = std.posix.UnexpectedError;

pub const kernel32 = @import("windows/kernel32.zig");
pub const ntdll = @import("windows/ntdll.zig");
pub const ws2_32 = @import("windows/ws2_32.zig");
pub const crypt32 = @import("windows/crypt32.zig");
pub const nls = @import("windows/nls.zig");

pub const current_process: HANDLE = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));

pub const PS = struct {
    pub const ATTRIBUTE = extern struct {
        Attribute: Type,
        Size: SIZE_T,
        u: extern union {
            Value: ULONG_PTR,
            ValuePtr: PVOID,
        },
        ReturnLength: ?*SIZE_T,

        /// https://ntdoc.m417z.com/ps_attribute_num
        /// Tag type is `u16` based on PS_ATTRIBUTE_NUMBER_MASK being 0xFFFF
        pub const NUM = enum(u16) {
            ParentProcess = 0,
            DebugObject,
            Token,
            ClientId,
            TebAddress,
            ImageName,
            ImageInfo,
            MemoryReserve,
            PriorityClass,
            ErrorMode,
            StdHandleInfo,
            HandleList,
            GroupAffinity,
            PreferredNode,
            IdealProcessor,
            UmsThread,
            MitigationOptions,
            ProtectionLevel,
            SecureProcess,
            JobList,
            ChildProcessPolicy,
            AllApplicationPackagesPolicy,
            Win32kFilter,
            SafeOpenPromptOriginClaim,
            BnoIsolation,
            DesktopAppPolicy,
            Chpe,
            MitigationAuditOptions,
            MachineType,
            ComponentFilter,
            EnableOptionalXStateFeatures,
            SupportedMachines,
            SveVectorLength,
        };

        /// https://ntdoc.m417z.com/psattributevalue
        pub const Type = enum(ULONG_PTR) {
            TEB_ADDRESS = construct(.TebAddress, true, false, false),
            _,

            pub fn construct(num: NUM, thread: bool, input: bool, additive: bool) ULONG_PTR {
                var val: ULONG_PTR = @intFromEnum(num);
                if (thread) val |= 0x10000;
                if (input) val |= 0x20000;
                if (additive) val |= 0x40000;
                return val;
            }
        };

        pub const LIST = extern struct {
            TotalLength: SIZE_T,
            Attributes: [1]ATTRIBUTE,
        };
    };
};

pub const OBJECT = struct {
    // ref: um/winternl.h

    pub const ATTRIBUTES = extern struct {
        Length: ULONG = @sizeOf(ATTRIBUTES),
        RootDirectory: ?HANDLE = null,
        ObjectName: ?*UNICODE_STRING = @constCast(&UNICODE_STRING.empty),
        Attributes: Flags = .{},
        SecurityDescriptor: ?*anyopaque = null,
        SecurityQualityOfService: ?*anyopaque = null,

        // Valid values for the Attributes field
        pub const Flags = packed struct(ULONG) {
            Reserved0: u1 = 0,
            INHERIT: bool = false,
            Reserved2: u2 = 0,
            PERMANENT: bool = false,
            EXCLUSIVE: bool = false,
            /// If name-lookup code should ignore the case of the ObjectName member rather than performing an exact-match search.
            CASE_INSENSITIVE: bool = true,
            OPENIF: bool = false,
            OPENLINK: bool = false,
            KERNEL_HANDLE: bool = false,
            FORCE_ACCESS_CHECK: bool = false,
            IGNORE_IMPERSONATED_DEVICEMAP: bool = false,
            DONT_REPARSE: bool = false,
            Reserved13: u19 = 0,

            pub const VALID_ATTRIBUTES: ATTRIBUTES = .{
                .INHERIT = true,
                .PERMANENT = true,
                .EXCLUSIVE = true,
                .CASE_INSENSITIVE = true,
                .OPENIF = true,
                .OPENLINK = true,
                .KERNEL_HANDLE = true,
                .FORCE_ACCESS_CHECK = true,
                .IGNORE_IMPERSONATED_DEVICEMAP = true,
                .DONT_REPARSE = true,
            };
        };
    };

    pub const INFORMATION_CLASS = enum(c_int) {
        Basic = 0,
        Name = 1,
        Type = 2,
        Types = 3,
        HandleFlag = 4,
        Session = 5,
        _,

        pub const Max: @typeInfo(@This()).@"enum".tag_type = @typeInfo(@This()).@"enum".fields.len;
    };

    pub const NAME_INFORMATION = extern struct {
        Name: UNICODE_STRING,
    };
};

pub const FILE = struct {
    // ref: km/ntddk.h

    pub const END_OF_FILE_INFORMATION = extern struct {
        EndOfFile: LARGE_INTEGER,
    };

    pub const ALIGNMENT_INFORMATION = extern struct {
        AlignmentRequirement: ULONG,
    };

    pub const NAME_INFORMATION = extern struct {
        FileNameLength: ULONG,
        FileName: [1]WCHAR,
    };

    pub const DISPOSITION = packed struct(ULONG) {
        DELETE: bool = false,
        POSIX_SEMANTICS: bool = false,
        FORCE_IMAGE_SECTION_CHECK: bool = false,
        ON_CLOSE: bool = false,
        IGNORE_READONLY_ATTRIBUTE: bool = false,
        Reserved5: u27 = 0,

        pub const DO_NOT_DELETE: DISPOSITION = .{};

        pub const INFORMATION = extern struct {
            DeleteFile: BOOLEAN,

            pub const EX = extern struct {
                Flags: DISPOSITION,
            };
        };
    };

    pub const FS_VOLUME_INFORMATION = extern struct {
        VolumeCreationTime: LARGE_INTEGER,
        VolumeSerialNumber: ULONG,
        VolumeLabelLength: ULONG,
        SupportsObjects: BOOLEAN,
        VolumeLabel: [0]WCHAR,

        pub fn getVolumeLabel(fvi: *const FS_VOLUME_INFORMATION) []const WCHAR {
            return (&fvi).ptr[0..@divExact(fvi.VolumeLabelLength, @sizeOf(WCHAR))];
        }
    };

    // ref: km/ntifs.h

    pub const NAME_FLAGS = packed struct(UCHAR) {
        NTFS: bool = false,
        DOS: bool = false,
        Reserved2: u5 = 0,
        UNSPECIFIED: bool = false,
    };

    pub const NOTIFY = struct {
        pub const CHANGE = packed struct(ULONG) {
            FILE_NAME: bool = false,
            DIR_NAME: bool = false,
            ATTRIBUTES: bool = false,
            SIZE: bool = false,
            LAST_WRITE: bool = false,
            LAST_ACCESS: bool = false,
            CREATION: bool = false,
            EA: bool = false,
            SECURITY: bool = false,
            STREAM_NAME: bool = false,
            STREAM_SIZE: bool = false,
            STREAM_WRITE: bool = false,
            Reserved12: u20 = 0,
        };

        pub const INFORMATION = extern struct {
            NextEntryOffset: ULONG,
            Action: ULONG,
            FileNameLength: ULONG,
            FileName: [0]WCHAR,

            pub fn fileName(info: *INFORMATION) []WCHAR {
                const ptr: [*]WCHAR = @ptrCast(&info.FileName);
                return ptr[0..@divExact(info.FileNameLength, @sizeOf(WCHAR))];
            }
        };

        pub const EXTENDED_INFORMATION = extern struct {
            NextEntryOffset: ULONG,
            Action: ULONG,
            CreationTime: LARGE_INTEGER,
            LastModificationTime: LARGE_INTEGER,
            LastChangeTime: LARGE_INTEGER,
            LastAccessTime: LARGE_INTEGER,
            AllocatedLength: LARGE_INTEGER,
            FileSize: LARGE_INTEGER,
            FileAttributes: ATTRIBUTE,
            u: extern union {
                ReparsePointTag: ULONG,
                EaSize: ULONG,
            },
            FileId: LARGE_INTEGER,
            ParentFileId: LARGE_INTEGER,
            FileNameLength: ULONG,
            FileName: [0]WCHAR,

            pub fn fileName(info: *INFORMATION) []WCHAR {
                const ptr: [*]WCHAR = @ptrCast(&info.FileName);
                return ptr[0..@divExact(info.FileNameLength, @sizeOf(WCHAR))];
            }
        };

        pub const FULL_INFORMATION = extern struct {
            NextEntryOffset: ULONG,
            Action: ULONG,
            CreationTime: LARGE_INTEGER,
            LastModificationTime: LARGE_INTEGER,
            LastChangeTime: LARGE_INTEGER,
            LastAccessTime: LARGE_INTEGER,
            AllocatedLength: LARGE_INTEGER,
            FileSize: LARGE_INTEGER,
            FileAttributes: ATTRIBUTE,
            u: extern union {
                ReparsePointTag: ULONG,
                EaSize: ULONG,
            },
            FileId: LARGE_INTEGER,
            ParentFileId: LARGE_INTEGER,
            FileNameLength: ULONG,
            FileNameFlags: NAME_FLAGS,
            FileName: [0]WCHAR,

            pub fn fileName(info: *INFORMATION) []WCHAR {
                const ptr: [*]WCHAR = @ptrCast(&info.FileName);
                return ptr[0..@divExact(info.FileNameLength, @sizeOf(WCHAR))];
            }
        };
    };

    pub const PIPE = struct {
        /// Define the `NamedPipeType` flags for `NtCreateNamedPipeFile`
        pub const TYPE = packed struct(ULONG) {
            TYPE: enum(u1) {
                BYTE_STREAM = 0b0,
                MESSAGE = 0b1,
            } = .BYTE_STREAM,
            REMOTE_CLIENTS: enum(u1) {
                ACCEPT = 0b0,
                REJECT = 0b1,
            } = .ACCEPT,
            Reserved2: u30 = 0,

            pub const VALID_MASK: TYPE = .{
                .TYPE = .MESSAGE,
                .REMOTE_CLIENTS = .REJECT,
            };
        };

        /// Define the `CompletionMode` flags for `NtCreateNamedPipeFile`
        pub const COMPLETION_MODE = packed struct(ULONG) {
            OPERATION: enum(u1) {
                QUEUE = 0b0,
                COMPLETE = 0b1,
            } = .QUEUE,
            Reserved1: u31 = 0,
        };

        /// Define the `ReadMode` flags for `NtCreateNamedPipeFile`
        pub const READ_MODE = packed struct(ULONG) {
            MODE: enum(u1) {
                BYTE_STREAM = 0b0,
                MESSAGE = 0b1,
            },
            Reserved1: u31 = 0,
        };

        /// Define the `NamedPipeConfiguration` flags for `NtQueryInformationFile`
        pub const CONFIGURATION = enum(ULONG) {
            INBOUND = 0x00000000,
            OUTBOUND = 0x00000001,
            FULL_DUPLEX = 0x00000002,
        };

        /// Define the `NamedPipeState` flags for `NtQueryInformationFile`
        pub const STATE = enum(ULONG) {
            DISCONNECTED = 0x00000001,
            LISTENING = 0x00000002,
            CONNECTED = 0x00000003,
            CLOSING = 0x00000004,
        };

        /// Define the `NamedPipeEnd` flags for `NtQueryInformationFile`
        pub const END = enum(ULONG) {
            CLIENT = 0x00000000,
            SERVER = 0x00000001,
        };

        pub const INFORMATION = extern struct {
            ReadMode: READ_MODE,
            CompletionMode: COMPLETION_MODE,
        };

        pub const LOCAL_INFORMATION = extern struct {
            NamedPipeType: TYPE,
            NamedPipeConfiguration: CONFIGURATION,
            MaximumInstances: ULONG,
            CurrentInstances: ULONG,
            InboundQuota: ULONG,
            ReadDataAvailable: ULONG,
            OutboundQuota: ULONG,
            WriteQuotaAvailable: ULONG,
            NamedPipeState: STATE,
            NamedPipeEnd: END,
        };

        pub const REMOTE_INFORMATION = extern struct {
            CollectDataTime: LARGE_INTEGER,
            MaximumCollectionCount: ULONG,
        };

        pub const WAIT_FOR_BUFFER = extern struct {
            Timeout: LARGE_INTEGER,
            NameLength: ULONG,
            TimeoutSpecified: BOOLEAN,
            Name: [PATH_MAX_WIDE]WCHAR,

            pub const WAIT_FOREVER: LARGE_INTEGER = std.math.minInt(LARGE_INTEGER);

            pub fn init(opts: struct {
                Timeout: ?LARGE_INTEGER = null,
                Name: []const WCHAR,
            }) WAIT_FOR_BUFFER {
                var fpwfb: WAIT_FOR_BUFFER = .{
                    .Timeout = opts.Timeout orelse undefined,
                    .NameLength = @intCast(@sizeOf(WCHAR) * opts.Name.len),
                    .TimeoutSpecified = @intFromBool(opts.Timeout != null),
                    .Name = undefined,
                };
                @memcpy(fpwfb.Name[0..opts.Name.len], opts.Name);
                return fpwfb;
            }

            pub fn getName(fpwfb: *const WAIT_FOR_BUFFER) []const WCHAR {
                return fpwfb.Name[0..@divExact(fpwfb.NameLength, @sizeOf(WCHAR))];
            }

            pub fn toBuffer(fpwfb: *const WAIT_FOR_BUFFER) []const u8 {
                const start: [*]const u8 = @ptrCast(fpwfb);
                return start[0 .. @offsetOf(WAIT_FOR_BUFFER, "Name") + fpwfb.NameLength];
            }
        };
    };

    pub const ALL_INFORMATION = extern struct {
        BasicInformation: BASIC_INFORMATION,
        StandardInformation: STANDARD_INFORMATION,
        InternalInformation: INTERNAL_INFORMATION,
        EaInformation: EA_INFORMATION,
        AccessInformation: ACCESS_INFORMATION,
        PositionInformation: POSITION_INFORMATION,
        ModeInformation: MODE.INFORMATION,
        AlignmentInformation: ALIGNMENT_INFORMATION,
        NameInformation: NAME_INFORMATION,
    };

    pub const INTERNAL_INFORMATION = extern struct {
        IndexNumber: LARGE_INTEGER,
    };

    pub const EA_INFORMATION = extern struct {
        EaSize: ULONG,
    };

    pub const ACCESS_INFORMATION = extern struct {
        AccessFlags: ACCESS_MASK,
    };

    /// This is not separated into RENAME_INFORMATION and RENAME_INFORMATION_EX because
    /// the only difference is the `Flags` type (BOOLEAN before _EX, ULONG in the _EX),
    /// which doesn't affect the struct layout--the offset of RootDirectory is the same
    /// regardless.
    pub const RENAME_INFORMATION = extern struct {
        Flags: FLAGS,
        RootDirectory: ?HANDLE,
        FileNameLength: ULONG,
        FileName: [PATH_MAX_WIDE]WCHAR,

        pub fn init(opts: struct {
            Flags: FLAGS = .{},
            RootDirectory: ?HANDLE = null,
            FileName: []const WCHAR,
        }) RENAME_INFORMATION {
            var fri: RENAME_INFORMATION = .{
                .Flags = opts.Flags,
                .RootDirectory = opts.RootDirectory,
                .FileNameLength = @intCast(@sizeOf(WCHAR) * opts.FileName.len),
                .FileName = undefined,
            };
            @memcpy(fri.FileName[0..opts.FileName.len], opts.FileName);
            return fri;
        }

        pub const FLAGS = packed struct(ULONG) {
            REPLACE_IF_EXISTS: bool = false,
            POSIX_SEMANTICS: bool = false,
            SUPPRESS_PIN_STATE_INHERITANCE: bool = false,
            SUPPRESS_STORAGE_RESERVE_INHERITANCE: bool = false,
            AVAILABLE_SPACE: enum(u2) {
                NO_PRESERVE = 0b00,
                NO_INCREASE = 0b01,
                NO_DECREASE = 0b10,
                PRESERVE = 0b11,
            } = .NO_PRESERVE,
            IGNORE_READONLY_ATTRIBUTE: bool = false,
            RESIZE_SR: enum(u2) {
                NO_FORCE = 0b00,
                FORCE_TARGET = 0b01,
                FORCE_SOURCE = 0b10,
                FORCE = 0b11,
            } = .NO_FORCE,
            Reserved9: u23 = 0,
        };

        pub fn getFileName(ri: *const RENAME_INFORMATION) []const WCHAR {
            return ri.FileName[0..@divExact(ri.FileNameLength, @sizeOf(WCHAR))];
        }

        pub fn toBuffer(fri: *RENAME_INFORMATION) []u8 {
            const start: [*]u8 = @ptrCast(fri);
            // The ABI size of the documented struct is 24 bytes, and attempting to use any size
            // less than that will trigger INFO_LENGTH_MISMATCH, so enforce a minimum in cases where,
            // for example, FileNameLength is 1 so only 22 bytes are technically needed.
            const size = @max(24, @offsetOf(RENAME_INFORMATION, "FileName") + fri.FileNameLength);
            return start[0..size];
        }
    };

    // ref: km/wdm.h

    pub const INFORMATION_CLASS = enum(c_int) {
        Directory = 1,
        FullDirectory = 2,
        BothDirectory = 3,
        Basic = 4,
        Standard = 5,
        Internal = 6,
        Ea = 7,
        Access = 8,
        Name = 9,
        Rename = 10,
        Link = 11,
        Names = 12,
        Disposition = 13,
        Position = 14,
        FullEa = 15,
        Mode = 16,
        Alignment = 17,
        All = 18,
        Allocation = 19,
        EndOfFile = 20,
        AlternateName = 21,
        Stream = 22,
        Pipe = 23,
        PipeLocal = 24,
        PipeRemote = 25,
        MailslotQuery = 26,
        MailslotSet = 27,
        Compression = 28,
        ObjectId = 29,
        Completion = 30,
        MoveCluster = 31,
        Quota = 32,
        ReparsePoint = 33,
        NetworkOpen = 34,
        AttributeTag = 35,
        Tracking = 36,
        IdBothDirectory = 37,
        IdFullDirectory = 38,
        ValidDataLength = 39,
        ShortName = 40,
        IoCompletionNotification = 41,
        IoStatusBlockRange = 42,
        IoPriorityHint = 43,
        SfioReserve = 44,
        SfioVolume = 45,
        HardLink = 46,
        ProcessIdsUsingFile = 47,
        NormalizedName = 48,
        NetworkPhysicalName = 49,
        IdGlobalTxDirectory = 50,
        IsRemoteDevice = 51,
        Unused = 52,
        NumaNode = 53,
        StandardLink = 54,
        RemoteProtocol = 55,
        RenameBypassAccessCheck = 56,
        LinkBypassAccessCheck = 57,
        VolumeName = 58,
        Id = 59,
        IdExtdDirectory = 60,
        ReplaceCompletion = 61,
        HardLinkFullId = 62,
        IdExtdBothDirectory = 63,
        DispositionEx = 64,
        RenameEx = 65,
        RenameExBypassAccessCheck = 66,
        DesiredStorageClass = 67,
        Stat = 68,
        MemoryPartition = 69,
        StatLx = 70,
        CaseSensitive = 71,
        LinkEx = 72,
        LinkExBypassAccessCheck = 73,
        StorageReserveId = 74,
        CaseSensitiveForceAccessCheck = 75,
        KnownFolder = 76,
        StatBasic = 77,
        Id64ExtdDirectory = 78,
        Id64ExtdBothDirectory = 79,
        IdAllExtdDirectory = 80,
        IdAllExtdBothDirectory = 81,
        StreamReservation = 82,
        MupProvider = 83,
        _,

        pub const Maximum: @typeInfo(@This()).@"enum".tag_type = 1 + @typeInfo(@This()).@"enum".fields.len;
    };

    pub const BASIC_INFORMATION = extern struct {
        CreationTime: LARGE_INTEGER,
        LastAccessTime: LARGE_INTEGER,
        LastWriteTime: LARGE_INTEGER,
        ChangeTime: LARGE_INTEGER,
        FileAttributes: ATTRIBUTE,
    };

    pub const STANDARD_INFORMATION = extern struct {
        AllocationSize: LARGE_INTEGER,
        EndOfFile: LARGE_INTEGER,
        NumberOfLinks: ULONG,
        DeletePending: BOOLEAN,
        Directory: BOOLEAN,
    };

    pub const POSITION_INFORMATION = extern struct {
        CurrentByteOffset: LARGE_INTEGER,
    };

    pub const FULL_EA_INFORMATION = extern struct {
        NextEntryOffset: ULONG,
        Flags: UCHAR,
        EaNameLength: UCHAR,
        EaValueLength: USHORT,
        EaName: [0]CHAR,
    };

    pub const FS_DEVICE_INFORMATION = extern struct {
        DeviceType: DEVICE_TYPE,
        Characteristics: ULONG,
    };

    pub const USE_FILE_POINTER_POSITION = -2;

    // ref: um/WinBase.h

    pub const ATTRIBUTE_TAG_INFO = extern struct {
        FileAttributes: DWORD,
        ReparseTag: IO_REPARSE_TAG,
    };

    // ref: um/winnt.h

    pub const SHARE = packed struct(ULONG) {
        /// The file can be opened for read access by other threads.
        READ: bool = false,
        /// The file can be opened for write access by other threads.
        WRITE: bool = false,
        /// The file can be opened for delete access by other threads.
        DELETE: bool = false,
        Reserved3: u29 = 0,

        pub const VALID_FLAGS: SHARE = .{
            .READ = true,
            .WRITE = true,
            .DELETE = true,
        };
    };

    pub const ATTRIBUTE = packed struct(ULONG) {
        /// The file is read only. Applications can read the file, but cannot write to or delete it.
        READONLY: bool = false,
        /// The file is hidden. Do not include it in an ordinary directory listing.
        HIDDEN: bool = false,
        /// The file is part of or used exclusively by an operating system.
        SYSTEM: bool = false,
        Reserved3: u1 = 0,
        DIRECTORY: bool = false,
        /// The file should be archived. Applications use this attribute to mark files for backup or removal.
        ARCHIVE: bool = false,
        DEVICE: bool = false,
        /// The file does not have other attributes set. This attribute is valid only if used alone.
        NORMAL: bool = false,
        /// The file is being used for temporary storage.
        TEMPORARY: bool = false,
        SPARSE_FILE: bool = false,
        REPARSE_POINT: bool = false,
        COMPRESSED: bool = false,
        /// The data of a file is not immediately available. This attribute indicates that file data is physically moved to offline storage.
        /// This attribute is used by Remote Storage, the hierarchical storage management software. Applications should not arbitrarily change this attribute.
        OFFLINE: bool = false,
        NOT_CONTENT_INDEXED: bool = false,
        /// The file or directory is encrypted. For a file, this means that all data in the file is encrypted. For a directory, this means that encryption is
        /// the default for newly created files and subdirectories. For more information, see File Encryption.
        ///
        /// This flag has no effect if `SYSTEM` is also specified.
        ///
        /// This flag is not supported on Home, Home Premium, Starter, or ARM editions of Windows.
        ENCRYPTED: bool = false,
        INTEGRITY_STREAM: bool = false,
        VIRTUAL: bool = false,
        NO_SCRUB_DATA: bool = false,
        EA_or_RECALL_ON_OPEN: bool = false,
        PINNED: bool = false,
        UNPINNED: bool = false,
        Reserved21: u1 = 0,
        RECALL_ON_DATA_ACCESS: bool = false,
        Reserved23: u6 = 0,
        STRICTLY_SEQUENTIAL: bool = false,
        Reserved30: u2 = 0,
    };

    // ref: um/winternl.h

    /// Define the create disposition values
    pub const CREATE_DISPOSITION = enum(ULONG) {
        /// If the file already exists, replace it with the given file. If it does not, create the given file.
        SUPERSEDE = 0x00000000,
        /// If the file already exists, open it instead of creating a new file.
        /// If it does not, fail the request and do not create a new file.
        OPEN = 0x00000001,
        /// If the file already exists, fail the request and do not create or
        /// open the given file. If it does not, create the given file.
        CREATE = 0x00000002,
        /// If the file already exists, open it. If it does not, create the given file.
        OPEN_IF = 0x00000003,
        /// If the file already exists, open it and overwrite it. If it does not, fail the request.
        OVERWRITE = 0x00000004,
        /// If the file already exists, open it and overwrite it. If it does not, create the given file.
        OVERWRITE_IF = 0x00000005,

        pub const MAXIMUM_DISPOSITION: CREATE_DISPOSITION = .OVERWRITE_IF;
    };

    /// Define the create/open option flags
    pub const MODE = packed struct(ULONG) {
        /// The file being created or opened is a directory file. With this
        /// flag, the CreateDisposition parameter must be set to `.CREATE`,
        /// `.FILE_OPEN`, or `.OPEN_IF`. With this flag, other compatible
        /// CreateOptions flags include only the following: `SYNCHRONOUS_IO`,
        /// `WRITE_THROUGH`, `OPEN_FOR_BACKUP_INTENT`, and `OPEN_BY_FILE_ID`.
        DIRECTORY_FILE: bool = false,
        /// Applications that write data to the file must actually transfer the
        /// data into the file before any requested write operation is
        /// considered complete. This flag is automatically set if the
        /// CreateOptions flag `NO_INTERMEDIATE_BUFFERING` is set.
        WRITE_THROUGH: bool = false,
        /// All accesses to the file are sequential.
        SEQUENTIAL_ONLY: bool = false,
        /// The file cannot be cached or buffered in a driver's internal
        /// buffers. This flag is incompatible with the DesiredAccess
        /// `FILE_APPEND_DATA` flag.
        NO_INTERMEDIATE_BUFFERING: bool = false,
        IO: enum(u2) {
            /// All operations on the file are performed asynchronously.
            ASYNCHRONOUS = 0b00,
            /// All operations on the file are performed synchronously. Any
            /// wait on behalf of the caller is subject to premature
            /// termination from alerts. This flag also causes the I/O system
            /// to maintain the file position context. If this flag is set, the
            /// DesiredAccess `SYNCHRONIZE` flag also must be set.
            SYNCHRONOUS_ALERT = 0b01,
            /// All operations on the file are performed synchronously. Waits
            /// in the system to synchronize I/O queuing and completion are not
            /// subject to alerts. This flag also causes the I/O system to
            /// maintain the file position context. If this flag is set, the
            /// DesiredAccess `SYNCHRONIZE` flag also must be set.
            SYNCHRONOUS_NONALERT = 0b10,
            _,

            pub const VALID_FLAGS: @This() = @enumFromInt(0b11);
        },
        /// The file being opened must not be a directory file or this call
        /// fails. The file object being opened can represent a data file, a
        /// logical, virtual, or physical device, or a volume.
        NON_DIRECTORY_FILE: bool = false,
        /// Create a tree connection for this file in order to open it over the
        /// network. This flag is not used by device and intermediate drivers.
        CREATE_TREE_CONNECTION: bool = false,
        /// Complete this operation immediately with an alternate success code
        /// of `STATUS_OPLOCK_BREAK_IN_PROGRESS` if the target file is
        /// oplocked, rather than blocking the caller's thread. If the file is
        /// oplocked, another caller already has access to the file. This flag
        /// is not used by device and intermediate drivers.
        COMPLETE_IF_OPLOCKED: bool = false,
        /// If the extended attributes on an existing file being opened
        /// indicate that the caller must understand EAs to properly interpret
        /// the file, fail this request because the caller does not understand
        /// how to deal with EAs. This flag is irrelevant for device and
        /// intermediate drivers.
        NO_EA_KNOWLEDGE: bool = false,
        OPEN_REMOTE_INSTANCE: bool = false,
        /// Accesses to the file can be random, so no sequential read-ahead
        /// operations should be performed on the file by FSDs or the system.
        RANDOM_ACCESS: bool = false,
        /// Delete the file when the last handle to it is passed to `NtClose`.
        /// If this flag is set, the `DELETE` flag must be set in the
        /// DesiredAccess parameter.
        DELETE_ON_CLOSE: bool = false,
        /// The file name that is specified by the `ObjectAttributes` parameter
        /// includes the 8-byte file reference number for the file. This number
        /// is assigned by and specific to the particular file system. If the
        /// file is a reparse point, the file name will also include the name
        /// of a device. Note that the FAT file system does not support this
        /// flag. This flag is not used by device and intermediate drivers.
        OPEN_BY_FILE_ID: bool = false,
        /// The file is being opened for backup intent. Therefore, the system
        /// should check for certain access rights and grant the caller the
        /// appropriate access to the file before checking the DesiredAccess
        /// parameter against the file's security descriptor. This flag not
        /// used by device and intermediate drivers.
        OPEN_FOR_BACKUP_INTENT: bool = false,
        /// Suppress inheritance of `FILE_ATTRIBUTE.COMPRESSED` from the parent
        /// directory. This allows creation of a non-compressed file in a
        /// directory that is marked compressed.
        NO_COMPRESSION: bool = false,
        /// The file is being opened and an opportunistic lock on the file is
        /// being requested as a single atomic operation. The file system
        /// checks for oplocks before it performs the create operation and will
        /// fail the create with a return code of STATUS_CANNOT_BREAK_OPLOCK if
        /// the result would be to break an existing oplock. For more
        /// information, see the Remarks section.
        ///
        /// Windows Server 2008, Windows Vista, Windows Server 2003 and Windows
        /// XP:  This flag is not supported.
        ///
        /// This flag is supported on the following file systems: NTFS, FAT,
        /// and exFAT.
        OPEN_REQUIRING_OPLOCK: bool = false,
        Reserved17: u3 = 0,
        /// This flag allows an application to request a filter opportunistic
        /// lock to prevent other applications from getting share violations.
        /// If there are already open handles, the create request will fail
        /// with STATUS_OPLOCK_NOT_GRANTED. For more information, see the
        /// Remarks section.
        RESERVE_OPFILTER: bool = false,
        /// Open a file with a reparse point and bypass normal reparse point
        /// processing for the file. For more information, see the Remarks
        /// section.
        OPEN_REPARSE_POINT: bool = false,
        /// Instructs any filters that perform offline storage or
        /// virtualization to not recall the contents of the file as a result
        /// of this open.
        OPEN_NO_RECALL: bool = false,
        /// This flag instructs the file system to capture the user associated
        /// with the calling thread. Any subsequent calls to
        /// `FltQueryVolumeInformation` or `ZwQueryVolumeInformationFile` using
        /// the returned handle will assume the captured user, rather than the
        /// calling user at the time, for purposes of computing the free space
        /// available to the caller. This applies to the following
        /// FsInformationClass values: `FileFsSizeInformation`,
        /// `FileFsFullSizeInformation`, and `FileFsFullSizeInformationEx`.
        OPEN_FOR_FREE_SPACE_QUERY: bool = false,
        Reserved24: u8 = 0,

        pub const VALID_OPTION_FLAGS: MODE = .{
            .DIRECTORY_FILE = true,
            .WRITE_THROUGH = true,
            .SEQUENTIAL_ONLY = true,
            .NO_INTERMEDIATE_BUFFERING = true,
            .IO = .VALID_FLAGS,
            .NON_DIRECTORY_FILE = true,
            .CREATE_TREE_CONNECTION = true,
            .COMPLETE_IF_OPLOCKED = true,
            .NO_EA_KNOWLEDGE = true,
            .OPEN_REMOTE_INSTANCE = true,
            .RANDOM_ACCESS = true,
            .DELETE_ON_CLOSE = true,
            .OPEN_BY_FILE_ID = true,
            .OPEN_FOR_BACKUP_INTENT = true,
            .NO_COMPRESSION = true,
            .OPEN_REQUIRING_OPLOCK = true,
            .Reserved17 = 0b111,
            .RESERVE_OPFILTER = true,
            .OPEN_REPARSE_POINT = true,
            .OPEN_NO_RECALL = true,
            .OPEN_FOR_FREE_SPACE_QUERY = true,
        };

        pub const VALID_PIPE_OPTION_FLAGS: MODE = .{
            .WRITE_THROUGH = true,
            .IO = .VALID_FLAGS,
        };

        pub const VALID_MAILSLOT_OPTION_FLAGS: MODE = .{
            .WRITE_THROUGH = true,
            .IO = .VALID_FLAGS,
        };

        pub const VALID_SET_OPTION_FLAGS: MODE = .{
            .WRITE_THROUGH = true,
            .SEQUENTIAL_ONLY = true,
            .IO = .VALID_FLAGS,
        };

        // ref: km/ntifs.h

        pub const INFORMATION = extern struct {
            /// The set of flags that specify the mode in which the file can be
            /// accessed. These flags are a subset of `MODE`.
            Mode: MODE,
        };
    };
};

pub const DIRECTORY = struct {
    pub const NOTIFY_INFORMATION_CLASS = enum(c_int) {
        Notify = 1,
        NotifyExtended = 2,
        NotifyFull = 3,
        _,

        pub const Maximum: @typeInfo(@This()).@"enum".tag_type = 1 + @typeInfo(@This()).@"enum".fields.len;
    };
};

pub const CONSOLE = struct {
    pub const USER_IO = struct {
        pub const INFO = struct {
            pub const CP = extern struct {
                /// GetCP: output
                /// SetCP: input
                CodePage: UINT,
                /// input
                Mode: MODE,

                pub const MODE = enum(BOOLEAN.Backing) {
                    Input,
                    Output,
                };
            };

            pub const WRITE = extern struct {
                /// output, in bytes
                Size: DWORD,
                /// input
                Mode: MODE,

                pub const MODE = enum(BOOLEAN.Backing) {
                    Character,
                    WideCharacter,
                };
            };

            pub const FILL = extern struct {
                /// input
                dwWriteCoord: COORD,
                /// input
                Tag: WITH.Tag,
                /// input
                With: WITH.Payload,
                /// input/output, in characters
                nLength: DWORD,

                pub const WITH = union(enum(DWORD)) {
                    Character: CHAR = 1,
                    WideCharacter: WCHAR = 2,
                    Attribute: WORD = 3,

                    pub const Tag = @typeInfo(WITH).@"union".tag_type.?;
                    pub const Payload = PAYLOAD: {
                        const with_fields = @typeInfo(WITH).@"union".fields;
                        var field_names: [with_fields.len][]const u8 = undefined;
                        var field_types: [with_fields.len]type = undefined;
                        for (with_fields, &field_names, &field_types) |field, *field_name, *field_type| {
                            field_name.* = field.name;
                            field_type.* = field.type;
                        }
                        break :PAYLOAD @Union(.@"extern", null, &field_names, &field_types, &@splat(.{}));
                    };
                };
            };

            /// all output
            pub const SCREEN_BUFFER = extern struct {
                dwSize: COORD,
                dwCursorPosition: COORD,
                dwWindowPosition: COORD,
                wAttributes: WORD,
                dwWindowSize: COORD,
                dwMaximumWindowSize: COORD,
                wPopupAttributes: WORD,
                bFullscreenSupported: BOOL,
                ColorTable: [16]COLORREF,
            };

            pub const READ_OUTPUT_CHARACTER = extern struct {
                /// input
                dwReadCoord: COORD,
                Mode: MODE,
                /// output, in characters
                nLength: DWORD,

                pub const MODE = enum(DWORD) {
                    Character = 1,
                    WideCharacter = 2,
                };
            };
        };

        pub fn GET_CP(mode: INFO.CP.MODE) Header.With(INFO.CP) {
            return .init(.GetCP, .{ .CodePage = undefined, .Mode = mode });
        }
        pub const GET_MODE: Header.With(DWORD) = .init(.GetMode, undefined);
        pub fn SET_MODE(mode: DWORD) Header.With(DWORD) {
            return .init(.SetMode, mode);
        }
        pub fn WRITE(mode: INFO.WRITE.MODE) Header.With(INFO.WRITE) {
            return .init(.Write, .{ .Size = undefined, .Mode = mode });
        }
        pub fn FILL(with: INFO.FILL.WITH, len: DWORD, coord: COORD) Header.With(INFO.FILL) {
            return .init(.Fill, .{
                .dwWriteCoord = coord,
                .Tag = with,
                .With = switch (with) {
                    inline else => |payload, tag| @unionInit(
                        INFO.FILL.WITH.Payload,
                        @tagName(tag),
                        payload,
                    ),
                },
                .nLength = len,
            });
        }
        pub fn SET_CP(mode: INFO.CP.MODE, cp: UINT) Header.With(INFO.CP) {
            return .init(.SetCP, .{ .CodePage = cp, .Mode = mode });
        }
        pub const GET_SCREEN_BUFFER_INFO: Header.With(INFO.SCREEN_BUFFER) =
            .init(.GetScreenBufferInfo, undefined);
        pub fn SET_CURSOR_POSITION(coord: COORD) Header.With(COORD) {
            return .init(.SetCursorPosition, coord);
        }
        pub fn SET_TEXT_ATTRIBUTE(attribute: WORD) Header.With(WORD) {
            return .init(.SetTextAttribute, attribute);
        }
        pub fn READ_OUTPUT_CHARACTER(
            coord: COORD,
            mode: INFO.READ_OUTPUT_CHARACTER.MODE,
        ) Header.With(INFO.READ_OUTPUT_CHARACTER) {
            return .init(.ReadOutputCharacter, .{
                .dwReadCoord = coord,
                .Mode = mode,
                .nLength = undefined,
            });
        }

        pub const InputBuffer = extern struct {
            Size: u32,
            Pointer: *const anyopaque,
        };

        pub const OutputBuffer = extern struct {
            Size: u32,
            Pointer: *anyopaque,
        };

        pub fn Request(comptime in_len: u32, comptime out_len: u32) type {
            return extern struct {
                Handle: ?HANDLE,
                InputBuffersLength: u32,
                OutputBuffersLength: u32,
                InputBuffers: [in_len]InputBuffer,
                OutputBuffers: [out_len]OutputBuffer,

                pub fn init(
                    handle: ?HANDLE,
                    in: [in_len]InputBuffer,
                    out: [out_len]OutputBuffer,
                ) @This() {
                    return .{
                        .Handle = handle,
                        .InputBuffersLength = in_len,
                        .OutputBuffersLength = out_len,
                        .InputBuffers = in,
                        .OutputBuffers = out,
                    };
                }
            };
        }

        pub const Header = extern struct {
            Operation: Operation,
            Size: u32,

            pub fn With(comptime Data: type) type {
                return extern struct {
                    Header: Header,
                    Data: Data,

                    pub fn init(operation: Operation, data: Data) @This() {
                        return .{
                            .Header = .{ .Operation = operation, .Size = @sizeOf(Data) },
                            .Data = data,
                        };
                    }

                    pub fn request(
                        with: *@This(),
                        file: ?Io.File,
                        comptime in_len: u32,
                        in: [in_len]InputBuffer,
                        comptime out_len: u32,
                        out: [out_len]OutputBuffer,
                    ) Request(1 + in_len, 1 + out_len) {
                        return .init(
                            if (file) |f| f.handle else null,
                            [1]InputBuffer{.{
                                .Size = @offsetOf(@This(), "Data") + @sizeOf(Data),
                                .Pointer = with,
                            }} ++ in,
                            [1]OutputBuffer{.{ .Size = @sizeOf(Data), .Pointer = &with.Data }} ++ out,
                        );
                    }

                    pub fn operate(with: *@This(), io: Io, file: ?Io.File) Io.Cancelable!NTSTATUS {
                        return (try io.operate(.{ .device_io_control = .{
                            .file = .{
                                .handle = peb().ProcessParameters.ConsoleHandle,
                                .flags = .{ .nonblocking = false },
                            },
                            .code = IOCTL.CONDRV.ISSUE_USER_IO,
                            .in = @ptrCast(&with.request(file, 0, .{}, 0, .{})),
                        } })).device_io_control.u.Status;
                    }
                };
            }
        };

        pub const Operation = enum(u32) {
            GetCP = 0x1000000,
            GetMode = 0x1000001,
            SetMode = 0x1000002,
            Read = 0x1000005,
            Write = 0x1000006,
            Fill = 0x2000000,
            SetCP = 0x2000004,
            GetScreenBufferInfo = 0x2000007,
            SetCursorPosition = 0x200000a,
            SetTextAttribute = 0x200000d,
            ReadOutputCharacter = 0x200000f,
            _,
        };
    };
};

pub const AFD = packed struct(ULONG) {
    NO_FAST_IO: bool = false,
    OVERLAPPED: bool = false,
    Reserved0: u30 = 0,

    pub const Mutability = enum { @"const", @"var" };
    pub fn WSABUF(comptime mutability: Mutability) type {
        return extern struct {
            len: ULONG,
            buf: switch (mutability) {
                .@"const" => [*]const u8,
                .@"var" => [*]u8,
            },
        };
    }
    pub const GUARANTEE = enum(c_int) {
        BestEffort,
        ControlledLoad,
        Predictive,
        GuaranteedDelay,
        Guaranteed,
        _,
    };
    pub const DEVICE_NAME: []const u16 = &.{ '\\', 'D', 'e', 'v', 'i', 'c', 'e', '\\', 'A', 'f', 'd' };
    pub const ENDPOINT_TYPE = packed struct(ULONG) {
        CONNECTIONLESS: bool = false,
        Reserved1: u3 = 0,
        MESSAGEMODE: bool = false,
        Reserved5: u3 = 0,
        RAW: bool = false,
        Reserved9: u22 = 0,
        REGISTERED_IO: bool = false,
    };
    pub const OPEN_PACKET = extern struct {
        EndpointType: ENDPOINT_TYPE,
        GroupID: LONG,
        AddressFamily: LONG,
        SocketType: LONG,
        Protocol: LONG,
        TransportDeviceNameLength: ULONG,
        TransportDeviceName: [1]WCHAR,

        pub const NAME = "AfdOpenPacketXX";

        pub const FULL_EA_INFORMATION = extern struct {
            Header: FILE.FULL_EA_INFORMATION = .{
                .NextEntryOffset = 0,
                .Flags = 0,
                .EaNameLength = NAME.len,
                .EaValueLength = @sizeOf(OPEN_PACKET),
                .EaName = .{},
            },
            Name: [NAME.len:0]u8 = NAME.*,
            Value: OPEN_PACKET,
        };
    };
    pub const BIND_INFO = extern struct {
        Mode: MODE,

        pub const MODE = enum(ULONG) {
            Unix = 0,
            Passive = 1,
            Active = 2,
            _,
        };
    };
    pub const LISTEN_INFO = extern struct {
        UseSAN: BOOLEAN,
        MaximumConnectionQueue: ULONG,
        UseDelayedAcceptance: BOOLEAN,
    };
    pub const LISTEN_RESPONSE_INFO = extern struct {
        Sequence: ULONG,
    };
    pub const ACCEPT_INFO = extern struct {
        UseSAN: BOOLEAN,
        Sequence: ULONG,
        AcceptHandle: HANDLE,
    };
    pub const SUPER_ACCEPT_INFO = extern struct {
        UseSAN: BOOLEAN,
        AcceptHandle: HANDLE,
        AcceptEndpoint: PVOID,
        AcceptFileObject: PVOID,
        ReceiveDataLength: ULONG,
        LocalAddressLength: ULONG,
        RemoteAddressLength: ULONG,
        ListenResponseInfo: LISTEN_RESPONSE_INFO,
    };
    pub const DEFER_ACCEPT_INFO = extern struct {
        Sequence: ULONG,
        Reject: BOOLEAN,
    };
    pub const PARTIAL_DISCONNECT_INFO = extern struct {
        DisconnectMode: MODE,
        Timeout: LARGE_INTEGER,

        pub const MODE = packed struct(ULONG) {
            SEND: bool = false,
            RECEIVE: bool = false,
            ABORTIVE: bool = false,
            UNCONNECT_DATAGRAM: bool = false,
            Reserved4: u28 = 0,
        };
    };
    pub const RECEIVE_INFORMATION = extern struct {
        BytesAvailable: ULONG,
        ExpeditedBytesAvailable: ULONG,
    };
    pub const HANDLE_INFO = extern struct {
        TdiAddressHandle: HANDLE,
        TdiConnectionHandle: HANDLE,
    };
    pub const INFORMATION = extern struct {
        InformationType: TYPE,
        Information: extern union {
            Boolean: BOOLEAN,
            Ulong: ULONG,
            LargeInteger: LARGE_INTEGER,
        },

        pub const TYPE = enum(ULONG) {
            INLINE_MODE = 0x01,
            NONBLOCKING_MODE = 0x02,
            MAX_SEND_SIZE = 0x03,
            SENDS_PENDING = 0x04,
            MAX_PATH_SEND_SIZE = 0x05,
            RECEIVE_WINDOW_SIZE = 0x06,
            SEND_WINDOW_SIZE = 0x07,
            CONNECT_TIME = 0x08,
            CIRCULAR_QUEUEING = 0x09,
            GROUP_ID_AND_TYPE = 0x0A,
            _,
        };
    };
    pub const TRANSMIT_FILE_INFO = extern struct {
        Offset: LARGE_INTEGER,
        WriteLength: LARGE_INTEGER,
        SendPacketLength: ULONG,
        FileHandle: HANDLE,
        Head: PVOID,
        HeadLength: ULONG,
        Tail: PVOID,
        TailLength: ULONG,
        Flags: FLAGS,

        pub const FLAGS = packed struct(ULONG) {
            DISCONNECT: bool = false,
            REUSE_SOCKET: bool = false,
            WRITE_BEHIND: bool = false,
            Reserved3: u25 = 0,
        };
    };
    pub const QUEUE_APC_INFO = extern struct {
        Thread: HANDLE,
        ApcRoutine: PVOID,
        ApcContext: PVOID,
        SystemArgument1: PVOID,
        SystemArgument2: PVOID,
    };
    pub const SEND_INFO = extern struct {
        BufferArray: [*]const WSABUF(.@"const"),
        BufferCount: ULONG,
        AfdFlags: AFD,
        TdiFlags: TDI.SEND,
    };
    pub const SEND_DATAGRAM_INFO = extern struct {
        BufferArray: [*]const WSABUF(.@"const"),
        BufferCount: ULONG,
        AfdFlags: AFD,
        TdiRequest: TDI.REQUEST.SEND_DATAGRAM,
        TdiConnInfo: TDI.CONNECTION.INFORMATION,
    };
    pub const RECV_INFO = extern struct {
        BufferArray: [*]const WSABUF(.@"var"),
        BufferCount: ULONG,
        AfdFlags: AFD,
        TdiFlags: TDI.RECEIVE,
    };
    pub const RECV_DATAGRAM_INFO = extern struct {
        BufferArray: [*]const WSABUF(.@"var"),
        BufferCount: ULONG,
        AfdFlags: AFD,
        TdiFlags: TDI.RECEIVE,
        Address: PVOID,
        AddressLength: *ULONG,
    };
    pub const SOCKOPT_INFO = extern struct {
        mode: Mode,
        level: i32,
        optname: u32,
        ding: u32 = 1,
        optval: *const anyopaque,
        optlen: usize,

        pub const Mode = enum(u32) { set = 1, get = 2, special = 3, _ };

        pub const UNIX_PATH = extern struct { Unknown0: usize = 0, Path: [PATH_MAX_WIDE:0]u16 };
    };
};

pub const TDI = struct {
    pub const STATUS = NTSTATUS;
    pub const CONNECTION = struct {
        pub const CONTEXT = PVOID;
        pub const INFORMATION = extern struct {
            /// length of user data buffer
            UserDataLength: LONG,
            /// pointer to user data buffer
            UserData: PVOID,
            /// length of following buffer
            OptionsLength: LONG,
            /// pointer to buffer containing options
            Options: PVOID,
            /// length of following buffer
            RemoteAddressLength: LONG,
            /// buffer containing the remote address
            RemoteAddress: PVOID,
        };
    };
    pub const ADDRESS = struct {
        pub const TYPE = enum(USHORT) {
            /// unspecified
            UNSPEC = 0,
            /// local to host (pipes, portals,
            UNIX = 1,
            /// internetwork: UDP, TCP, etc.
            IP = 2,
            /// arpanet imp addresses
            IMPLINK = 3,
            /// pup protocols: e.g. BSP
            PUP = 4,
            /// mit CHAOS protocols
            CHAOS = 5,
            /// XEROX NS protocols
            NS = 6,
            /// Netware IPX
            IPX = 6,
            /// nbs protocols
            NBS = 7,
            /// european computer manufacturers
            ECMA = 8,
            /// datakit protocols
            DATAKIT = 9,
            /// CCITT protocols, X.25 etc
            CCITT = 10,
            /// IBM SNA
            SNA = 11,
            /// DECnet
            DECnet = 12,
            /// Direct data link interface
            DLI = 13,
            /// LAT
            LAT = 14,
            /// NSC Hyperchannel
            HYLINK = 15,
            /// AppleTalk
            APPLETALK = 16,
            /// Netbios Addresses
            NETBIOS = 17,
            @"8022" = 18,
            OSI_TSAP = 19,
            /// for WzMail
            NETONE = 20,
            /// Banyan VINES IP
            VNS = 21,
            /// NETBIOS address extensions
            NETBIOS_EX = 22,
            /// IP version 6
            IP6 = 23,
            /// WCHAR Netbios address
            NETBIOS_UNICODE_EX = 24,
            _,
        };
        pub const IP = extern struct {
            sin_port: USHORT,
            in_addr: ULONG,
            sin_zero: [8]UCHAR,
        };
        pub const IP6 = extern struct {
            sin_port: USHORT,
            flowinfo: ULONG,
            addr: [8]USHORT,
            scope_id: ULONG,
        };
    };
    pub const REQUEST = extern struct {
        Handle: extern union {
            AddressHandle: HANDLE,
            ConnectionContext: CONNECTION.CONTEXT,
            ControlChannel: HANDLE,
        },
        RequestNotifyObject: PVOID,
        RequestContext: PVOID,
        TdiStatus: TDI.STATUS,

        pub const STATUS = extern struct {
            /// status of request completion
            Status: TDI.STATUS,
            /// the request context
            RequestContext: PVOID,
            /// number of bytes transferred in the request
            BytesTransferred: ULONG,
        };
        pub const ASSOCIATE = extern struct {
            Request: REQUEST,
            AddressHandle: HANDLE,
        };
        pub const CONNECT = extern struct {
            Request: REQUEST,
            RequestConnectionInformation: *CONNECTION.INFORMATION,
            ReturnConnectionInformation: *CONNECTION.INFORMATION,
            Timeout: LARGE_INTEGER,
        };
        pub const ACCEPT = extern struct {
            Request: REQUEST,
            RequestConnectionInformation: *CONNECTION.INFORMATION,
            ReturnConnectionInformation: *CONNECTION.INFORMATION,
        };
        pub const LISTEN = extern struct {
            Request: REQUEST,
            RequestConnectionInformation: *CONNECTION.INFORMATION,
            ReturnConnectionInformation: *CONNECTION.INFORMATION,
            ListenFlags: USHORT,
        };
        pub const DISCONNECT = extern struct {
            Request: REQUEST,
            Timeout: LARGE_INTEGER,
        };
        pub const SEND = extern struct {
            Request: REQUEST,
            SendFlags: USHORT,
        };
        pub const RECEIVE = extern struct {
            Request: REQUEST,
            ReceiveFlags: USHORT,
        };
        pub const SEND_DATAGRAM = extern struct {
            Request: REQUEST,
            SendDatagramInformation: *CONNECTION.INFORMATION,
        };
    };
    pub const RECEIVE = packed struct(ULONG) {
        Reserved0: u2 = 0,
        BROADCAST: bool = false,
        MULTICAST: bool = false,
        PARTIAL: bool = false,
        NORMAL: bool = false,
        EXPEDITED: bool = false,
        PEEK: bool = false,
        NO_RESPONSE_EXP: bool = false,
        COPY_LOOKAHEAD: bool = false,
        ENTIRE_MESSAGE: bool = false,
        AT_DISPATCH_LEVEL: bool = false,
        CONTROL_INFO: bool = false,
        FORCE_INDICATION: bool = false,
        NO_PUSH: bool = false,
        Reserved12: u17 = 0,
    };
    pub const SEND = packed struct(ULONG) {
        Reserved0: u5 = 0,
        EXPEDITED: bool = false,
        PARTIAL: bool = false,
        NO_RESPONSE_EXPECTED: bool = false,
        NON_BLOCKING: bool = false,
        AND_DISCONNECT: bool = false,
        Reserved10: u22 = 0,
    };
};

pub const NET = struct {
    pub const LUID = packed struct(ULONG64) { Reserved: u24 = 0, Index: u24, IfType: u16 };
    pub const IFINDEX = enum(ULONG) { _ };
};

pub const DNS = struct {
    pub const INTERFACE_SETTINGS = extern struct {
        Version: ULONG,
        Flags: ULONG64,
        Domain: PWSTR,
        NameServer: PWSTR,
        SearchList: PWSTR,
        RegistrationEnabled: ULONG,
        RegisterAdapterName: ULONG,
        EnableLLMNR: ULONG,
        QueryAdapterName: ULONG,
        ProfileNameServer: PWSTR,
    };

    // ref: shared/windnsdef.h

    pub const ADDR_MAX_SOCKADDR_LENGTH = 32;

    pub const ADDR = extern struct {
        MaxSa: [ADDR_MAX_SOCKADDR_LENGTH]CHAR,
        DnsAddrUserDword: [8]DWORD,

        pub const ARRAY = extern struct {
            MaxCount: DWORD,
            AddrCount: DWORD,
            Tag: DWORD,
            Family: WORD,
            WordReserved: WORD,
            Flags: DWORD,
            MatchFlag: DWORD,
            Reserved1: DWORD,
            Reserved2: DWORD,
            AddrArray: [0]ADDR,
        };
    };

    pub const CUSTOM_SERVER = extern struct {
        ServerType: CUSTOM_SERVER.TYPE,
        Flags: FLAGS,
        Info: extern union {
            UDP: void,
            DOH: extern struct { Template: PWSTR },
            DOT: extern struct { Hostname: PWSTR },
        },
        MaxSa: [ADDR_MAX_SOCKADDR_LENGTH]CHAR,

        pub const TYPE = enum(DWORD) { UDP = 0x1, DOH = 0x2, DOT = 0x3, _ };
        pub const FLAGS = packed struct(ULONG64) {
            UDP_FALLBACK: bool = false,
            UPGRADE_FROM_WELL_KNOWN_SERVERS: bool = false,
            Reserved2: u62 = 0,
        };
    };

    // ref: um/WinDNS.h

    pub const STATUS = Win32Error;

    pub const TYPE = enum(WORD) {
        A = 0x0001,
        NS = 0x0002,
        MD = 0x0003,
        MF = 0x0004,
        CNAME = 0x0005,
        SOA = 0x0006,
        MB = 0x0007,
        MG = 0x0008,
        MR = 0x0009,
        NULL = 0x000a,
        WKS = 0x000b,
        PTR = 0x000c,
        HINFO = 0x000d,
        MINFO = 0x000e,
        MX = 0x000f,
        TEXT = 0x0010,
        RP = 0x0011,
        AFSDB = 0x0012,
        X25 = 0x0013,
        ISDN = 0x0014,
        RT = 0x0015,
        NSAP = 0x0016,
        NSAPPTR = 0x0017,
        SIG = 0x0018,
        KEY = 0x0019,
        PX = 0x001a,
        GPOS = 0x001b,
        AAAA = 0x001c,
        LOC = 0x001d,
        NXT = 0x001e,
        EID = 0x001f,
        NIMLOC = 0x0020,
        SRV = 0x0021,
        ATMA = 0x0022,
        NAPTR = 0x0023,
        KX = 0x0024,
        CERT = 0x0025,
        A6 = 0x0026,
        DNAME = 0x0027,
        SINK = 0x0028,
        OPT = 0x0029,
        DS = 0x002B,
        RRSIG = 0x002E,
        NSEC = 0x002F,
        DNSKEY = 0x0030,
        DHCID = 0x0031,
        UINFO = 0x0064,
        UID = 0x0065,
        GID = 0x0066,
        UNSPEC = 0x0067,
        ADDRS = 0x00f8,
        TKEY = 0x00f9,
        TSIG = 0x00fa,
        IXFR = 0x00fb,
        AXFR = 0x00fc,
        MAILB = 0x00fd,
        MAILA = 0x00fe,
        ALL = 0x00ff,
        WINS = 0xff01,
        WINSR = 0xff02,
        TLSA = 0x0034,
        SVCB = 0x0040,
        HTTPS = 0x0041,
        pub const NBSTAT: TYPE = .WINSR;
        pub const ANY: TYPE = .ALL;
    };

    pub const QUERY = packed struct(ULONG64) {
        pub const STANDARD: QUERY = .{};
        ACCEPT_TRUNCATED_RESPONSE: bool = false,
        USE_TCP_ONLY: bool = false,
        NO_RECURSION: bool = false,
        BYPASS_CACHE: bool = false,
        NO_WIRE_QUERY: bool = false,
        NO_LOCAL_NAME: bool = false,
        NO_HOSTS_FILE: bool = false,
        NO_NETBT: bool = false,
        WIRE_ONLY: bool = false,
        RETURN_MESSAGE: bool = false,
        MULTICAST_ONLY: bool = false,
        NO_MULTICAST: bool = false,
        TREAT_AS_FQDN: bool = false,
        ADDRCONFIG: bool = false,
        DUAL_ADDR: bool = false,
        Reserved15: u2 = 0,
        MULTICAST_WAIT: bool = false,
        MULTICAST_VERIFY: bool = false,
        Reserved19: u1 = 0,
        DONT_RESET_TTL_VALUES: bool = false,
        DISABLE_IDN_ENCODING: bool = false,
        Reserved22: u1 = 0,
        APPEND_MULTILABEL: bool = false,
        Reserved24: u34 = 0,
        PARSE_ALL_RECORDS: bool = false,
        Reserved59: u5 = 0,

        pub const REQUEST = extern struct {
            Version: DWORD,
            QueryName: PCWSTR,
            QueryType: TYPE,
            QueryOptions: QUERY = .STANDARD,
            pDnsServerList: ?*ADDR.ARRAY = null,
            InterfaceIndex: ULONG = 0,
            pQueryCompletionCallback: ?*const COMPLETION_ROUTINE = null,
            pQueryContext: ?*anyopaque = null,

            pub const @"3" = extern struct {
                Base: REQUEST,
                IsNetworkQueryRequired: BOOL = .FALSE,
                RequiredNetworkIndex: DWORD = 0,
                cCustomServers: DWORD = 0,
                pCustomServers: ?*CUSTOM_SERVER = null,
            };
        };
        pub const RESULT = extern struct {
            Version: ULONG,
            QueryStatus: STATUS,
            QueryOptions: QUERY,
            pQueryRecords: ?*RECORD,
            Reserved: ?*anyopaque,
        };
        pub const CANCEL = extern struct {
            Reserved: [32]CHAR align(8),
        };
        pub const COMPLETION_ROUTINE = fn (
            pQueryContext: ?*anyopaque,
            pQueryResults: *RESULT,
        ) callconv(.winapi) void;
    };
    pub const FREE_TYPE = enum(c_int) { Flat = 0, RecordList, ParsedMessageFields };
    pub const RECORD = extern struct {
        pNext: ?*RECORD,
        pName: *anyopaque,
        wType: TYPE,
        wDataLength: WORD,
        Flags: FLAGS,
        dwTtl: DWORD,
        dwReserved: DWORD,
        Data: extern union { A: [4]u8, AAAA: [16]u8 },

        pub const FLAGS = packed struct(DWORD) {
            Section: SECTION,
            Delete: u1,
            CharSet: u2,
            Unused: u3,
            Reserved: u24,
        };
    };
    pub const SECTION = enum(u2) { Question, Answer, Authority, Additional };
};

// ref: km/ntddk.h

pub const SYSTEM = struct {
    pub const INFORMATION_CLASS = enum(c_int) {
        Basic = 0,
        Performance = 2,
        TimeOfDay = 3,
        Process = 5,
        ProcessorPerformance = 8,
        Interrupt = 23,
        Exception = 33,
        RegistryQuota = 37,
        Lookaside = 45,
        CodeIntegrity = 103,
        Policy = 134,
        _,
    };

    pub const BASIC_INFORMATION = extern struct {
        Reserved: ULONG,
        TimerResolution: ULONG,
        PageSize: ULONG,
        NumberOfPhysicalPages: ULONG,
        LowestPhysicalPageNumber: ULONG,
        HighestPhysicalPageNumber: ULONG,
        AllocationGranularity: ULONG,
        MinimumUserModeAddress: ULONG_PTR,
        MaximumUserModeAddress: ULONG_PTR,
        ActiveProcessorsAffinityMask: KAFFINITY,
        NumberOfProcessors: UCHAR,
    };
};

pub const PROCESS = struct {
    pub const INFORMATION = extern struct {
        hProcess: HANDLE,
        hThread: HANDLE,
        dwProcessId: DWORD,
        dwThreadId: DWORD,
    };

    pub const INFOCLASS = enum(c_int) {
        BasicInformation = 0,
        QuotaLimits = 1,
        IoCounters = 2,
        VmCounters = 3,
        Times = 4,
        BasePriority = 5,
        RaisePriority = 6,
        DebugPort = 7,
        ExceptionPort = 8,
        AccessToken = 9,
        LdtInformation = 10,
        LdtSize = 11,
        DefaultHardErrorMode = 12,
        IoPortHandlers = 13,
        PooledUsageAndLimits = 14,
        WorkingSetWatch = 15,
        UserModeIOPL = 16,
        EnableAlignmentFaultFixup = 17,
        PriorityClass = 18,
        Wx86Information = 19,
        HandleCount = 20,
        AffinityMask = 21,
        PriorityBoost = 22,
        DeviceMap = 23,
        SessionInformation = 24,
        ForegroundInformation = 25,
        Wow64Information = 26,
        ImageFileName = 27,
        LUIDDeviceMapsEnabled = 28,
        BreakOnTermination = 29,
        DebugObjectHandle = 30,
        DebugFlags = 31,
        HandleTracing = 32,
        IoPriority = 33,
        ExecuteFlags = 34,
        TlsInformation = 35,
        Cookie = 36,
        ImageInformation = 37,
        CycleTime = 38,
        PagePriority = 39,
        InstrumentationCallback = 40,
        ThreadStackAllocation = 41,
        WorkingSetWatchEx = 42,
        ImageFileNameWin32 = 43,
        ImageFileMapping = 44,
        AffinityUpdateMode = 45,
        MemoryAllocationMode = 46,
        GroupInformation = 47,
        TokenVirtualizationEnabled = 48,
        OwnerInformation = 49,
        WindowInformation = 50,
        HandleInformation = 51,
        MitigationPolicy = 52,
        DynamicFunctionTableInformation = 53,
        HandleCheckingMode = 54,
        KeepAliveCount = 55,
        RevokeFileHandles = 56,
        WorkingSetControl = 57,
        HandleTable = 58,
        CheckStackExtentsMode = 59,
        CommandLineInformation = 60,
        ProtectionInformation = 61,
        MemoryExhaustion = 62,
        FaultInformation = 63,
        TelemetryIdInformation = 64,
        CommitReleaseInformation = 65,
        Reserved1Information = 66,
        Reserved2Information = 67,
        SubsystemProcess = 68,
        InPrivate = 70,
        RaiseUMExceptionOnInvalidHandleClose = 71,
        SubsystemInformation = 75,
        Win32kSyscallFilterInformation = 79,
        EnergyTrackingState = 82,
        NetworkIoCounters = 114,
        _,

        pub const Max: @typeInfo(@This()).@"enum".tag_type = 117;
    };

    pub const BASIC_INFORMATION = extern struct {
        ExitStatus: NTSTATUS,
        PebBaseAddress: *PEB,
        AffinityMask: ULONG_PTR,
        BasePriority: KPRIORITY,
        UniqueProcessId: ULONG_PTR,
        InheritedFromUniqueProcessId: ULONG_PTR,
    };

    pub const VM_COUNTERS = extern struct {
        PeakVirtualSize: SIZE_T,
        VirtualSize: SIZE_T,
        PageFaultCount: ULONG,
        PeakWorkingSetSize: SIZE_T,
        WorkingSetSize: SIZE_T,
        QuotaPeakPagedPoolUsage: SIZE_T,
        QuotaPagedPoolUsage: SIZE_T,
        QuotaPeakNonPagedPoolUsage: SIZE_T,
        QuotaNonPagedPoolUsage: SIZE_T,
        PagefileUsage: SIZE_T,
        PeakPagefileUsage: SIZE_T,
    };
};

pub const THREAD = struct {
    pub const INFOCLASS = enum(c_int) {
        BasicInformation = 0,
        Times = 1,
        Priority = 2,
        BasePriority = 3,
        AffinityMask = 4,
        ImpersonationToken = 5,
        DescriptorTableEntry = 6,
        EnableAlignmentFaultFixup = 7,
        EventPair_Reusable = 8,
        QuerySetWin32StartAddress = 9,
        ZeroTlsCell = 10,
        PerformanceCount = 11,
        AmILastThread = 12,
        IdealProcessor = 13,
        PriorityBoost = 14,
        SetTlsArrayAddress = 15,
        IsIoPending = 16,
        // Windows 2000+ from here
        HideFromDebugger = 17,
        // Windows XP+ from here
        BreakOnTermination = 18,
        SwitchLegacyState = 19,
        IsTerminated = 20,
        // Windows Vista+ from here
        LastSystemCall = 21,
        IoPriority = 22,
        CycleTime = 23,
        PagePriority = 24,
        ActualBasePriority = 25,
        TebInformation = 26,
        CSwitchMon = 27,
        // Windows 7+ from here
        CSwitchPmu = 28,
        Wow64Context = 29,
        GroupInformation = 30,
        UmsInformation = 31,
        CounterProfiling = 32,
        IdealProcessorEx = 33,
        // Windows 8+ from here
        CpuAccountingInformation = 34,
        // Windows 8.1+ from here
        SuspendCount = 35,
        // Windows 10+ from here
        HeterogeneousCpuPolicy = 36,
        ContainerId = 37,
        NameInformation = 38,
        SelectedCpuSets = 39,
        SystemThreadInformation = 40,
        ActualGroupAffinity = 41,
        DynamicCodePolicyInfo = 42,
        SubsystemInformation = 45,
        _,

        pub const Max: @typeInfo(@This()).@"enum".tag_type = 60;
    };

    pub const BASIC_INFORMATION = extern struct {
        ExitStatus: NTSTATUS,
        TebBaseAddress: PVOID,
        ClientId: CLIENT_ID,
        AffinityMask: KAFFINITY,
        Priority: KPRIORITY,
        BasePriority: KPRIORITY,
    };

    pub const CREATE_FLAGS = packed struct(ULONG) {
        CREATE_SUSPENDED: bool = false,
        SKIP_THREAD_ATTACH: bool = false,
        HIDE_FROM_DEBUGGER: bool = false,
        LOADER_WORKER: bool = false,
        SKIP_LOADER_INIT: bool = false,
        BYPASS_PROCESS_FREEZE: bool = false,
        Reserved6: u26 = 0,

        pub const NONE: CREATE_FLAGS = .{};
    };

    pub const StackSize = enum(SIZE_T) {
        /// The default size specified in the executable header
        default = 0,
        _,
    };
};

pub const MEMORY = struct {
    pub const BASIC_INFORMATION = extern struct {
        BaseAddress: PVOID,
        AllocationBase: PVOID,
        AllocationProtect: DWORD,
        PartitionId: WORD,
        RegionSize: SIZE_T,
        State: DWORD,
        Protect: DWORD,
        Type: DWORD,
    };
};

// ref: km/ntifs.h

pub const HEAP = opaque {
    pub const FLAGS = packed struct(u8) {
        /// Serialized access is not used when the heap functions access this heap. This option
        /// applies to all subsequent heap function calls. Alternatively, you can specify this
        /// option on individual heap function calls.
        ///
        /// The low-fragmentation heap (LFH) cannot be enabled for a heap created with this option.
        ///
        /// A heap created with this option cannot be locked.
        NO_SERIALIZE: bool = false,
        /// Specifies that the heap is growable. Must be specified if `HeapBase` is `NULL`.
        GROWABLE: bool = false,
        /// The system raises an exception to indicate failure (for example, an out-of-memory
        /// condition) for calls to `HeapAlloc` and `HeapReAlloc` instead of returning `NULL`.
        ///
        /// To ensure that exceptions are generated for all calls to an allocation function, specify
        /// `GENERATE_EXCEPTIONS` in the call to `HeapCreate`. In this case, it is not necessary to
        /// additionally specify `GENERATE_EXCEPTIONS` in the allocation function calls.
        GENERATE_EXCEPTIONS: bool = false,
        /// The allocated memory will be initialized to zero. Otherwise, the memory is not
        /// initialized to zero.
        ZERO_MEMORY: bool = false,
        REALLOC_IN_PLACE_ONLY: bool = false,
        TAIL_CHECKING_ENABLED: bool = false,
        FREE_CHECKING_ENABLED: bool = false,
        DISABLE_COALESCE_ON_FREE: bool = false,

        pub const CLASS = enum(u4) {
            /// process heap
            PROCESS,
            /// private heap
            PRIVATE,
            /// Kernel Heap
            KERNEL,
            /// GDI heap
            GDI,
            /// User heap
            USER,
            /// Console heap
            CONSOLE,
            /// User Desktop heap
            USER_DESKTOP,
            /// Csrss Shared heap
            CSRSS_SHARED,
            /// Csr Port heap
            CSR_PORT,
            _,

            pub const MASK: CLASS = @enumFromInt(maxInt(@typeInfo(CLASS).@"enum".tag_type));
        };

        pub const CREATE = packed struct(ULONG) {
            COMMON: FLAGS = .{},
            SEGMENT_HEAP: bool = false,
            /// Only applies to segment heap.  Applies pointer obfuscation which is
            /// generally excessive and unnecessary but is necessary for certain insecure
            /// heaps in win32k.
            ///
            /// Specifying HEAP_CREATE_HARDENED prevents the heap from using locks as
            /// pointers would potentially be exposed in heap metadata lock variables.
            /// Callers are therefore responsible for synchronizing access to hardened heaps.
            HARDENED: bool = false,
            Reserved10: u2 = 0,
            CLASS: CLASS = @enumFromInt(0),
            /// Create heap with 16 byte alignment (obsolete)
            ALIGN_16: bool = false,
            /// Create heap call tracing enabled (obsolete)
            ENABLE_TRACING: bool = false,
            /// Create heap with executable pages
            ///
            /// All memory blocks that are allocated from this heap allow code execution, if the
            /// hardware enforces data execution prevention. Use this flag heap in applications that
            /// run code from the heap. If `ENABLE_EXECUTE` is not specified and an application
            /// attempts to run code from a protected page, the application receives an exception
            /// with the status code `STATUS_ACCESS_VIOLATION`.
            ENABLE_EXECUTE: bool = false,
            Reserved19: u13 = 0,

            pub const VALID_MASK: CREATE = .{
                .COMMON = .{
                    .NO_SERIALIZE = true,
                    .GROWABLE = true,
                    .GENERATE_EXCEPTIONS = true,
                    .ZERO_MEMORY = true,
                    .REALLOC_IN_PLACE_ONLY = true,
                    .TAIL_CHECKING_ENABLED = true,
                    .FREE_CHECKING_ENABLED = true,
                    .DISABLE_COALESCE_ON_FREE = true,
                },
                .CLASS = .MASK,
                .ALIGN_16 = true,
                .ENABLE_TRACING = true,
                .ENABLE_EXECUTE = true,
                .SEGMENT_HEAP = true,
                .HARDENED = true,
            };
        };

        pub const ALLOCATION = packed struct(ULONG) {
            COMMON: FLAGS = .{},
            SETTABLE_USER: packed struct(u4) {
                VALUE: u1 = 0,
                FLAGS: packed struct(u3) {
                    FLAG1: bool = false,
                    FLAG2: bool = false,
                    FLAG3: bool = false,
                } = .{},
            } = .{},
            CLASS: CLASS = @enumFromInt(0),
            Reserved16: u2 = 0,
            TAG: u12 = 0,
            Reserved30: u2 = 0,
        };
    };

    pub const RTL_PARAMETERS = extern struct {
        Length: ULONG,
        SegmentReserve: SIZE_T,
        SegmentCommit: SIZE_T,
        DeCommitFreeBlockThreshold: SIZE_T,
        DeCommitTotalFreeThreshold: SIZE_T,
        MaximumAllocationSize: SIZE_T,
        VirtualMemoryThreshold: SIZE_T,
        InitialCommit: SIZE_T,
        InitialReserve: SIZE_T,
        CommitRoutine: *const COMMIT_ROUTINE,
        Reserved: [2]SIZE_T = @splat(0),

        pub const COMMIT_ROUTINE = fn (
            Base: PVOID,
            CommitAddress: *PVOID,
            CommitSize: *SIZE_T,
        ) callconv(.winapi) NTSTATUS;

        pub const SEGMENT = extern struct {
            Version: VERSION,
            Size: USHORT,
            Flags: FLG,
            MemorySource: MEMORY_SOURCE,
            Reserved: [4]SIZE_T,

            pub const VERSION = enum(USHORT) {
                CURRENT = 3,
                _,
            };

            pub const FLG = packed struct(ULONG) {
                USE_PAGE_HEAP: bool = false,
                NO_LFH: bool = false,
                Reserved2: u30 = 0,

                pub const VALID_FLAGS: FLG = .{
                    .USE_PAGE_HEAP = true,
                    .NO_LFH = true,
                };
            };

            pub const MEMORY_SOURCE = extern struct {
                Flags: ULONG,
                MemoryTypeMask: TYPE,
                NumaNode: ULONG,
                u: extern union {
                    PartitionHandle: HANDLE,
                    Callbacks: *const VA_CALLBACKS,
                },
                Reserved: [2]SIZE_T = @splat(0),

                pub const TYPE = enum(ULONG) {
                    Paged,
                    NonPaged,
                    @"64KPage",
                    LargePage,
                    HugePage,
                    Custom,
                    _,

                    pub const Max: @typeInfo(@This()).@"enum".tag_type = @typeInfo(@This()).@"enum".fields.len;
                };

                pub const VA_CALLBACKS = extern struct {
                    CallbackContext: HANDLE,
                    AllocateVirtualMemory: *const ALLOCATE_VIRTUAL_MEMORY_EX_CALLBACK,
                    FreeVirtualMemory: *const FREE_VIRTUAL_MEMORY_EX_CALLBACK,
                    QueryVirtualMemory: *const QUERY_VIRTUAL_MEMORY_CALLBACK,

                    pub const ALLOCATE_VIRTUAL_MEMORY_EX_CALLBACK = fn (
                        CallbackContext: HANDLE,
                        BaseAddress: *PVOID,
                        RegionSize: *SIZE_T,
                        AllocationType: ULONG,
                        PageProtection: ULONG,
                        ExtendedParameters: ?[*]MEM.EXTENDED_PARAMETER,
                        ExtendedParameterCount: ULONG,
                    ) callconv(.c) NTSTATUS;

                    pub const FREE_VIRTUAL_MEMORY_EX_CALLBACK = fn (
                        CallbackContext: HANDLE,
                        ProcessHandle: HANDLE,
                        BaseAddress: *PVOID,
                        RegionSize: *SIZE_T,
                        FreeType: ULONG,
                    ) callconv(.c) NTSTATUS;

                    pub const QUERY_VIRTUAL_MEMORY_CALLBACK = fn (
                        CallbackContext: HANDLE,
                        ProcessHandle: HANDLE,
                        BaseAddress: *PVOID,
                        MemoryInformationClass: MEMORY_INFO_CLASS,
                        MemoryInformation: PVOID,
                        MemoryInformationLength: SIZE_T,
                        ReturnLength: ?*SIZE_T,
                    ) callconv(.c) NTSTATUS;

                    pub const MEMORY_INFO_CLASS = enum(c_int) {
                        Basic,
                        _,
                    };
                };
            };
        };
    };
};

pub const CTL_CODE = packed struct(ULONG) {
    Method: METHOD,
    Function: u12,
    Access: FILE_ACCESS,
    DeviceType: FILE_DEVICE,

    pub const METHOD = enum(u2) {
        BUFFERED = 0,
        IN_DIRECT = 1,
        OUT_DIRECT = 2,
        NEITHER = 3,
    };

    pub const FILE_ACCESS = packed struct(u2) {
        READ: bool = false,
        WRITE: bool = false,

        pub const ANY: FILE_ACCESS = .{ .READ = false, .WRITE = false };
        pub const SPECIAL = ANY;
    };

    pub const FILE_DEVICE = enum(u16) {
        BEEP = 0x00000001,
        CD_ROM = 0x00000002,
        CD_ROM_FILE_SYSTEM = 0x00000003,
        CONTROLLER = 0x00000004,
        DATALINK = 0x00000005,
        DFS = 0x00000006,
        DISK = 0x00000007,
        DISK_FILE_SYSTEM = 0x00000008,
        FILE_SYSTEM = 0x00000009,
        INPORT_PORT = 0x0000000a,
        KEYBOARD = 0x0000000b,
        MAILSLOT = 0x0000000c,
        MIDI_IN = 0x0000000d,
        MIDI_OUT = 0x0000000e,
        MOUSE = 0x0000000f,
        MULTI_UNC_PROVIDER = 0x00000010,
        NAMED_PIPE = 0x00000011,
        NETWORK = 0x00000012,
        NETWORK_BROWSER = 0x00000013,
        NETWORK_FILE_SYSTEM = 0x00000014,
        NULL = 0x00000015,
        PARALLEL_PORT = 0x00000016,
        PHYSICAL_NETCARD = 0x00000017,
        PRINTER = 0x00000018,
        SCANNER = 0x00000019,
        SERIAL_MOUSE_PORT = 0x0000001a,
        SERIAL_PORT = 0x0000001b,
        SCREEN = 0x0000001c,
        SOUND = 0x0000001d,
        STREAMS = 0x0000001e,
        TAPE = 0x0000001f,
        TAPE_FILE_SYSTEM = 0x00000020,
        TRANSPORT = 0x00000021,
        UNKNOWN = 0x00000022,
        VIDEO = 0x00000023,
        VIRTUAL_DISK = 0x00000024,
        WAVE_IN = 0x00000025,
        WAVE_OUT = 0x00000026,
        @"8042_PORT" = 0x00000027,
        NETWORK_REDIRECTOR = 0x00000028,
        BATTERY = 0x00000029,
        BUS_EXTENDER = 0x0000002a,
        MODEM = 0x0000002b,
        VDM = 0x0000002c,
        MASS_STORAGE = 0x0000002d,
        SMB = 0x0000002e,
        KS = 0x0000002f,
        CHANGER = 0x00000030,
        SMARTCARD = 0x00000031,
        ACPI = 0x00000032,
        DVD = 0x00000033,
        FULLSCREEN_VIDEO = 0x00000034,
        DFS_FILE_SYSTEM = 0x00000035,
        DFS_VOLUME = 0x00000036,
        SERENUM = 0x00000037,
        TERMSRV = 0x00000038,
        KSEC = 0x00000039,
        FIPS = 0x0000003A,
        INFINIBAND = 0x0000003B,
        VMBUS = 0x0000003E,
        CRYPT_PROVIDER = 0x0000003F,
        WPD = 0x00000040,
        BLUETOOTH = 0x00000041,
        MT_COMPOSITE = 0x00000042,
        MT_TRANSPORT = 0x00000043,
        BIOMETRIC = 0x00000044,
        PMI = 0x00000045,
        EHSTOR = 0x00000046,
        DEVAPI = 0x00000047,
        GPIO = 0x00000048,
        USBEX = 0x00000049,
        CONSOLE = 0x00000050,
        NFP = 0x00000051,
        SYSENV = 0x00000052,
        VIRTUAL_BLOCK = 0x00000053,
        POINT_OF_SERVICE = 0x00000054,
        STORAGE_REPLICATION = 0x00000055,
        TRUST_ENV = 0x00000056,
        UCM = 0x00000057,
        UCMTCPCI = 0x00000058,
        PERSISTENT_MEMORY = 0x00000059,
        NVDIMM = 0x0000005a,
        HOLOGRAPHIC = 0x0000005b,
        SDFXHCI = 0x0000005c,
        UCMUCSI = 0x0000005d,
        PRM = 0x0000005e,
        EVENT_COLLECTOR = 0x0000005f,
        USB4 = 0x00000060,
        SOUNDWIRE = 0x00000061,

        MOUNTMGRCONTROLTYPE = 'm',

        _,
    };

    pub const SET_REPARSE_POINT: CTL_CODE = .{ .DeviceType = .FILE_SYSTEM, .Function = 41, .Method = .BUFFERED, .Access = .SPECIAL };
    pub const GET_REPARSE_POINT: CTL_CODE = .{ .DeviceType = .FILE_SYSTEM, .Function = 42, .Method = .BUFFERED, .Access = .ANY };

    pub const PIPE = struct {
        pub const ASSIGN_EVENT: CTL_CODE = .{ .DeviceType = .NAMED_PIPE, .Function = 0, .Method = .BUFFERED, .Access = .ANY };
        pub const DISCONNECT: CTL_CODE = .{ .DeviceType = .NAMED_PIPE, .Function = 1, .Method = .BUFFERED, .Access = .ANY };
        pub const LISTEN: CTL_CODE = .{ .DeviceType = .NAMED_PIPE, .Function = 2, .Method = .BUFFERED, .Access = .ANY };
        pub const PEEK: CTL_CODE = .{ .DeviceType = .NAMED_PIPE, .Function = 3, .Method = .BUFFERED, .Access = .{ .READ = true } };
        pub const QUERY_EVENT: CTL_CODE = .{ .DeviceType = .NAMED_PIPE, .Function = 4, .Method = .BUFFERED, .Access = .ANY };
        pub const TRANSCEIVE: CTL_CODE = .{ .DeviceType = .NAMED_PIPE, .Function = 5, .Method = .NEITHER, .Access = .{ .READ = true, .WRITE = true } };
        pub const WAIT: CTL_CODE = .{ .DeviceType = .NAMED_PIPE, .Function = 6, .Method = .BUFFERED, .Access = .ANY };
        pub const IMPERSONATE: CTL_CODE = .{ .DeviceType = .NAMED_PIPE, .Function = 7, .Method = .BUFFERED, .Access = .ANY };
        pub const SET_CLIENT_PROCESS: CTL_CODE = .{ .DeviceType = .NAMED_PIPE, .Function = 8, .Method = .BUFFERED, .Access = .ANY };
        pub const QUERY_CLIENT_PROCESS: CTL_CODE = .{ .DeviceType = .NAMED_PIPE, .Function = 9, .Method = .BUFFERED, .Access = .ANY };
        pub const GET_PIPE_ATTRIBUTE: CTL_CODE = .{ .DeviceType = .NAMED_PIPE, .Function = 10, .Method = .BUFFERED, .Access = .ANY };
        pub const SET_PIPE_ATTRIBUTE: CTL_CODE = .{ .DeviceType = .NAMED_PIPE, .Function = 11, .Method = .BUFFERED, .Access = .ANY };
        pub const GET_CONNECTION_ATTRIBUTE: CTL_CODE = .{ .DeviceType = .NAMED_PIPE, .Function = 12, .Method = .BUFFERED, .Access = .ANY };
        pub const SET_CONNECTION_ATTRIBUTE: CTL_CODE = .{ .DeviceType = .NAMED_PIPE, .Function = 13, .Method = .BUFFERED, .Access = .ANY };
        pub const GET_HANDLE_ATTRIBUTE: CTL_CODE = .{ .DeviceType = .NAMED_PIPE, .Function = 14, .Method = .BUFFERED, .Access = .ANY };
        pub const SET_HANDLE_ATTRIBUTE: CTL_CODE = .{ .DeviceType = .NAMED_PIPE, .Function = 15, .Method = .BUFFERED, .Access = .ANY };
        pub const FLUSH: CTL_CODE = .{ .DeviceType = .NAMED_PIPE, .Function = 16, .Method = .BUFFERED, .Access = .{ .WRITE = true } };

        pub const INTERNAL_READ: CTL_CODE = .{ .DeviceType = .NAMED_PIPE, .Function = 2045, .Method = .BUFFERED, .Access = .{ .READ = true } };
        pub const INTERNAL_WRITE: CTL_CODE = .{ .DeviceType = .NAMED_PIPE, .Function = 2046, .Method = .BUFFERED, .Access = .{ .WRITE = true } };
        pub const INTERNAL_TRANSCEIVE: CTL_CODE = .{ .DeviceType = .NAMED_PIPE, .Function = 2047, .Method = .NEITHER, .Access = .{ .READ = true, .WRITE = true } };
        pub const INTERNAL_READ_OVFLOW: CTL_CODE = .{ .DeviceType = .NAMED_PIPE, .Function = 2048, .Method = .BUFFERED, .Access = .{ .READ = true } };
    };
};

pub const IOCTL = struct {
    pub const AFD = struct {
        const CONTROL_CODE = packed struct {
            Method: CTL_CODE.METHOD,
            Function: u10,
            DeviceType: CTL_CODE.FILE_DEVICE,
            Reserved28: u4 = 0,
        };
        pub const BIND: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 0, .Method = .NEITHER });
        pub const CONNECT: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 1, .Method = .NEITHER });
        pub const START_LISTEN: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 2, .Method = .NEITHER });
        pub const WAIT_FOR_LISTEN: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 3, .Method = .BUFFERED });
        pub const ACCEPT: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 4, .Method = .BUFFERED });
        pub const RECEIVE: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 5, .Method = .NEITHER });
        pub const RECEIVE_DATAGRAM: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 6, .Method = .NEITHER });
        pub const SEND: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 7, .Method = .NEITHER });
        pub const SEND_DATAGRAM: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 8, .Method = .NEITHER });
        pub const POLL: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 9, .Method = .BUFFERED });
        pub const PARTIAL_DISCONNECT: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 10, .Method = .NEITHER });

        pub const GET_ADDRESS: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 11, .Method = .NEITHER });
        pub const QUERY_RECEIVE_INFO: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 12, .Method = .NEITHER });
        pub const QUERY_HANDLES: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 13, .Method = .NEITHER });
        pub const SET_INFORMATION: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 14, .Method = .NEITHER });
        pub const GET_CONTEXT_LENGTH: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 15, .Method = .NEITHER });
        pub const GET_CONTEXT: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 16, .Method = .NEITHER });
        pub const SET_CONTEXT: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 17, .Method = .NEITHER });

        pub const SET_CONNECT_DATA: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 18, .Method = .BUFFERED });
        pub const SET_CONNECT_OPTIONS: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 19, .Method = .BUFFERED });
        pub const SET_DISCONNECT_DATA: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 20, .Method = .BUFFERED });
        pub const SET_DISCONNECT_OPTIONS: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 21, .Method = .BUFFERED });
        pub const GET_CONNECT_DATA: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 22, .Method = .BUFFERED });
        pub const GET_CONNECT_OPTIONS: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 23, .Method = .BUFFERED });
        pub const GET_DISCONNECT_DATA: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 24, .Method = .BUFFERED });
        pub const GET_DISCONNECT_OPTIONS: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 25, .Method = .BUFFERED });
        pub const SIZE_CONNECT_DATA: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 26, .Method = .BUFFERED });
        pub const SIZE_CONNECT_OPTIONS: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 27, .Method = .BUFFERED });
        pub const SIZE_DISCONNECT_DATA: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 28, .Method = .BUFFERED });
        pub const SIZE_DISCONNECT_OPTIONS: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 29, .Method = .BUFFERED });

        pub const GET_INFORMATION: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 30, .Method = .NEITHER });
        pub const TRANSMIT_FILE: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 31, .Method = .NEITHER });
        pub const SUPER_ACCEPT: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 32, .Method = .NEITHER });

        pub const EVENT_SELECT: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 33, .Method = .BUFFERED });
        pub const ENUM_NETWORK_EVENTS: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 34, .Method = .BUFFERED });

        pub const DEFER_ACCEPT: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 35, .Method = .BUFFERED });
        pub const WAIT_FOR_LISTEN_LIFO: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 36, .Method = .BUFFERED });
        pub const SET_QOS: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 37, .Method = .BUFFERED });
        pub const GET_QOS: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 38, .Method = .BUFFERED });
        pub const NO_OPERATION: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 39, .Method = .NEITHER });
        pub const VALIDATE_GROUP: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 40, .Method = .BUFFERED });
        pub const GET_UNACCEPTED_CONNECT_DATA: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 41, .Method = .BUFFERED });

        pub const QUEUE_APC: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 42, .Method = .BUFFERED });

        pub const SOCKOPT: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 47, .Method = .NEITHER });
        pub const SUPER_CONNECT: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 49, .Method = .NEITHER });
        pub const RECV_MSG: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 51, .Method = .NEITHER });
        pub const RIO: CTL_CODE = @bitCast(CONTROL_CODE{ .DeviceType = .NETWORK, .Function = 70, .Method = .NEITHER });
    };
    pub const CONDRV = struct {
        pub const READ_IO: CTL_CODE = .{ .DeviceType = .CONSOLE, .Function = 1, .Method = .OUT_DIRECT, .Access = .ANY };
        pub const COMPLETE_IO: CTL_CODE = .{ .DeviceType = .CONSOLE, .Function = 2, .Method = .NEITHER, .Access = .ANY };
        pub const READ_INPUT: CTL_CODE = .{ .DeviceType = .CONSOLE, .Function = 3, .Method = .NEITHER, .Access = .ANY };
        pub const WRITE_OUTPUT: CTL_CODE = .{ .DeviceType = .CONSOLE, .Function = 4, .Method = .NEITHER, .Access = .ANY };
        pub const ISSUE_USER_IO: CTL_CODE = .{ .DeviceType = .CONSOLE, .Function = 5, .Method = .OUT_DIRECT, .Access = .ANY };
        pub const DISCONNECT_PIPE: CTL_CODE = .{ .DeviceType = .CONSOLE, .Function = 6, .Method = .NEITHER, .Access = .ANY };
        pub const SET_SERVER_INFORMATION: CTL_CODE = .{ .DeviceType = .CONSOLE, .Function = 7, .Method = .NEITHER, .Access = .ANY };
        pub const GET_SERVER_PID: CTL_CODE = .{ .DeviceType = .CONSOLE, .Function = 8, .Method = .NEITHER, .Access = .ANY };
        pub const GET_DISPLAY_SIZE: CTL_CODE = .{ .DeviceType = .CONSOLE, .Function = 9, .Method = .NEITHER, .Access = .ANY };
        pub const UPDATE_DISPLAY: CTL_CODE = .{ .DeviceType = .CONSOLE, .Function = 10, .Method = .NEITHER, .Access = .ANY };
        pub const SET_CURSOR: CTL_CODE = .{ .DeviceType = .CONSOLE, .Function = 11, .Method = .NEITHER, .Access = .ANY };
        pub const ALLOW_VIA_UIACCESS: CTL_CODE = .{ .DeviceType = .CONSOLE, .Function = 12, .Method = .NEITHER, .Access = .ANY };
        pub const LAUNCH_SERVER: CTL_CODE = .{ .DeviceType = .CONSOLE, .Function = 13, .Method = .NEITHER, .Access = .ANY };
        pub const GET_FONT_SIZE: CTL_CODE = .{ .DeviceType = .CONSOLE, .Function = 14, .Method = .NEITHER, .Access = .ANY };
    };
    pub const KSEC = struct {
        pub const GEN_RANDOM: CTL_CODE = .{ .DeviceType = .KSEC, .Function = 2, .Method = .BUFFERED, .Access = .ANY };
    };
    pub const MOUNTMGR = struct {
        pub const QUERY_POINTS: CTL_CODE = .{ .DeviceType = .MOUNTMGRCONTROLTYPE, .Function = 2, .Method = .BUFFERED, .Access = .ANY };
        pub const QUERY_DOS_VOLUME_PATH: CTL_CODE = .{ .DeviceType = .MOUNTMGRCONTROLTYPE, .Function = 12, .Method = .BUFFERED, .Access = .ANY };
    };
};

pub const MAXIMUM_REPARSE_DATA_BUFFER_SIZE: ULONG = 16 * 1024;

pub const IO_REPARSE_TAG = packed struct(ULONG) {
    Value: u12,
    Index: u4 = 0,
    ReservedBits: u12 = 0,
    /// Can have children if a directory.
    IsDirectory: bool = false,
    /// Represents another named entity in the system.
    IsSurrogate: bool = false,
    /// Must be `false` for non-Microsoft tags.
    IsReserved: bool = false,
    /// Owned by Microsoft.
    IsMicrosoft: bool = false,

    pub const RESERVED_INVALID: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .IsReserved = true, .Index = 0x8, .Value = 0x000 };
    pub const MOUNT_POINT: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .IsSurrogate = true, .Value = 0x003 };
    pub const HSM: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .IsReserved = true, .Value = 0x004 };
    pub const DRIVE_EXTENDER: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .Value = 0x005 };
    pub const HSM2: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .Value = 0x006 };
    pub const SIS: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .Value = 0x007 };
    pub const WIM: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .Value = 0x008 };
    pub const CSV: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .Value = 0x009 };
    pub const DFS: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .Value = 0x00A };
    pub const FILTER_MANAGER: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .Value = 0x00B };
    pub const SYMLINK: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .IsSurrogate = true, .Value = 0x00C };
    pub const IIS_CACHE: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .IsSurrogate = true, .Value = 0x010 };
    pub const DFSR: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .Value = 0x012 };
    pub const DEDUP: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .Value = 0x013 };
    pub const APPXSTRM: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .IsReserved = true, .Value = 0x014 };
    pub const NFS: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .Value = 0x014 };
    pub const FILE_PLACEHOLDER: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .Value = 0x015 };
    pub const DFM: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .Value = 0x016 };
    pub const WOF: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .Value = 0x017 };
    pub inline fn WCI(index: u1) IO_REPARSE_TAG {
        return .{ .IsMicrosoft = true, .IsDirectory = index == 0x1, .Index = index, .Value = 0x018 };
    }
    pub const GLOBAL_REPARSE: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .IsSurrogate = true, .Value = 0x0019 };
    pub inline fn CLOUD(index: u4) IO_REPARSE_TAG {
        return .{ .IsMicrosoft = true, .IsDirectory = true, .Index = index, .Value = 0x01A };
    }
    pub const APPEXECLINK: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .Value = 0x01B };
    pub const PROJFS: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .IsDirectory = true, .Value = 0x01C };
    pub const LX_SYMLINK: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .IsSurrogate = true, .Value = 0x01D };
    pub const STORAGE_SYNC: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .Value = 0x01E };
    pub const WCI_TOMBSTONE: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .IsSurrogate = true, .Value = 0x01F };
    pub const UNHANDLED: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .Value = 0x020 };
    pub const ONEDRIVE: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .Value = 0x021 };
    pub const PROJFS_TOMBSTONE: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .IsSurrogate = true, .Value = 0x022 };
    pub const AF_UNIX: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .Value = 0x023 };
    pub const LX_FIFO: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .Value = 0x024 };
    pub const LX_CHR: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .Value = 0x025 };
    pub const LX_BLK: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .Value = 0x026 };
    pub const LX_STORAGE_SYNC_FOLDER: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .IsDirectory = true, .Value = 0x027 };
    pub inline fn WCI_LINK(index: u1) IO_REPARSE_TAG {
        return .{ .IsMicrosoft = true, .IsSurrogate = true, .Index = index, .Value = 0x027 };
    }
    pub const DATALESS_CIM: IO_REPARSE_TAG = .{ .IsMicrosoft = true, .IsSurrogate = true, .Value = 0x28 };
};

// ref: km/wdm.h

pub const ACCESS_MASK = packed struct(DWORD) {
    SPECIFIC: Specific = .{ .bits = 0 },
    STANDARD: Standard = .{},
    Reserved21: u3 = 0,
    ACCESS_SYSTEM_SECURITY: bool = false,
    MAXIMUM_ALLOWED: bool = false,
    Reserved26: u2 = 0,
    GENERIC: Generic = .{},

    pub const Specific = packed union {
        bits: u16,

        // ref: km/wdm.h

        /// Define access rights to files and directories
        FILE: File,
        FILE_DIRECTORY: File.Directory,
        FILE_PIPE: File.Pipe,
        /// Registry Specific Access Rights.
        KEY: Key,
        /// Object Manager Object Type Specific Access Rights.
        OBJECT_TYPE: ObjectType,
        /// Object Manager Directory Specific Access Rights.
        DIRECTORY: Directory,
        /// Object Manager Symbolic Link Specific Access Rights.
        SYMBOLIC_LINK: SymbolicLink,
        /// Section Access Rights.
        SECTION: Section,
        /// Session Specific Access Rights.
        SESSION: Session,
        /// Process Specific Access Rights.
        PROCESS: Process,
        /// Thread Specific Access Rights.
        THREAD: Thread,
        /// Partition Specific Access Rights.
        MEMORY_PARTITION: MemoryPartition,
        /// Generic mappings for transaction manager rights.
        TRANSACTIONMANAGER: TransactionManager,
        /// Generic mappings for transaction rights.
        TRANSACTION: Transaction,
        /// Generic mappings for resource manager rights.
        RESOURCEMANAGER: ResourceManager,
        /// Generic mappings for enlistment rights.
        ENLISTMENT: Enlistment,
        /// Event Specific Access Rights.
        EVENT: Event,
        /// Semaphore Specific Access Rights.
        SEMAPHORE: Semaphore,

        // ref: km/ntifs.h

        /// Token Specific Access Rights.
        TOKEN: Token,

        // um/winnt.h

        /// Job Object Specific Access Rights.
        JOB_OBJECT: JobObject,
        /// Mutant Specific Access Rights.
        MUTANT: Mutant,
        /// Timer Specific Access Rights.
        TIMER: Timer,
        /// I/O Completion Specific Access Rights.
        IO_COMPLETION: IoCompletion,

        pub const File = packed struct(u16) {
            READ_DATA: bool = false,
            WRITE_DATA: bool = false,
            APPEND_DATA: bool = false,
            READ_EA: bool = false,
            WRITE_EA: bool = false,
            EXECUTE: bool = false,
            Reserved6: u1 = 0,
            READ_ATTRIBUTES: bool = false,
            WRITE_ATTRIBUTES: bool = false,
            Reserved9: u7 = 0,

            pub const ALL_ACCESS: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .REQUIRED,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .FILE = .{
                    .READ_DATA = true,
                    .WRITE_DATA = true,
                    .APPEND_DATA = true,
                    .READ_EA = true,
                    .WRITE_EA = true,
                    .EXECUTE = true,
                    .Reserved6 = maxInt(@FieldType(File, "Reserved6")),
                    .READ_ATTRIBUTES = true,
                    .WRITE_ATTRIBUTES = true,
                } },
            };

            pub const GENERIC_READ: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .READ,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .FILE = .{
                    .READ_DATA = true,
                    .READ_ATTRIBUTES = true,
                    .READ_EA = true,
                } },
            };

            pub const GENERIC_WRITE: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .WRITE,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .FILE = .{
                    .WRITE_DATA = true,
                    .WRITE_ATTRIBUTES = true,
                    .WRITE_EA = true,
                    .APPEND_DATA = true,
                } },
            };

            pub const GENERIC_EXECUTE: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .EXECUTE,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .FILE = .{
                    .READ_ATTRIBUTES = true,
                    .EXECUTE = true,
                } },
            };

            pub const Directory = packed struct(u16) {
                LIST: bool = false,
                ADD_FILE: bool = false,
                ADD_SUBDIRECTORY: bool = false,
                READ_EA: bool = false,
                WRITE_EA: bool = false,
                TRAVERSE: bool = false,
                DELETE_CHILD: bool = false,
                READ_ATTRIBUTES: bool = false,
                WRITE_ATTRIBUTES: bool = false,
                Reserved9: u7 = 0,
            };

            pub const Pipe = packed struct(u16) {
                READ_DATA: bool = false,
                WRITE_DATA: bool = false,
                CREATE_PIPE_INSTANCE: bool = false,
                Reserved3: u4 = 0,
                READ_ATTRIBUTES: bool = false,
                WRITE_ATTRIBUTES: bool = false,
                Reserved9: u7 = 0,
            };
        };

        pub const Key = packed struct(u16) {
            /// Required to query the values of a registry key.
            QUERY_VALUE: bool = false,
            /// Required to create, delete, or set a registry value.
            SET_VALUE: bool = false,
            /// Required to create a subkey of a registry key.
            CREATE_SUB_KEY: bool = false,
            /// Required to enumerate the subkeys of a registry key.
            ENUMERATE_SUB_KEYS: bool = false,
            /// Required to request change notifications for a registry key or for subkeys of a registry key.
            NOTIFY: bool = false,
            /// Reserved for system use.
            CREATE_LINK: bool = false,
            Reserved6: u2 = 0,
            /// Indicates that an application on 64-bit Windows should operate on the 64-bit registry view.
            /// This flag is ignored by 32-bit Windows.
            WOW64_64KEY: bool = false,
            /// Indicates that an application on 64-bit Windows should operate on the 32-bit registry view.
            /// This flag is ignored by 32-bit Windows.
            WOW64_32KEY: bool = false,
            Reserved10: u6 = 0,

            pub const WOW64_RES: ACCESS_MASK = .{
                .SPECIFIC = .{ .KEY = .{
                    .WOW64_32KEY = true,
                    .WOW64_64KEY = true,
                } },
            };

            /// Combines the STANDARD_RIGHTS_READ, KEY_QUERY_VALUE, KEY_ENUMERATE_SUB_KEYS, and KEY_NOTIFY values.
            pub const READ: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .READ,
                    .SYNCHRONIZE = false,
                },
                .SPECIFIC = .{ .KEY = .{
                    .QUERY_VALUE = true,
                    .ENUMERATE_SUB_KEYS = true,
                    .NOTIFY = true,
                } },
            };

            /// Combines the STANDARD_RIGHTS_WRITE, KEY_SET_VALUE, and KEY_CREATE_SUB_KEY access rights.
            pub const WRITE: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .WRITE,
                    .SYNCHRONIZE = false,
                },
                .SPECIFIC = .{ .KEY = .{
                    .SET_VALUE = true,
                    .CREATE_SUB_KEY = true,
                } },
            };

            /// Equivalent to KEY_READ.
            pub const EXECUTE = READ;

            pub const ALL_ACCESS: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .ALL,
                    .SYNCHRONIZE = false,
                },
                .SPECIFIC = .{ .KEY = .{
                    .QUERY_VALUE = true,
                    .SET_VALUE = true,
                    .CREATE_SUB_KEY = true,
                    .ENUMERATE_SUB_KEYS = true,
                    .NOTIFY = true,
                    .CREATE_LINK = true,
                } },
            };
        };

        pub const ObjectType = packed struct(u16) {
            CREATE: bool = false,
            Reserved1: u15 = 0,

            pub const ALL_ACCESS: ACCESS_MASK = .{
                .STANDARD = .{ .RIGHTS = .REQUIRED },
                .SPECIFIC = .{ .OBJECT_TYPE = .{
                    .CREATE = true,
                } },
            };
        };

        pub const Directory = packed struct(u16) {
            QUERY: bool = false,
            TRAVERSE: bool = false,
            CREATE_OBJECT: bool = false,
            CREATE_SUBDIRECTORY: bool = false,
            Reserved3: u12 = 0,

            pub const ALL_ACCESS: ACCESS_MASK = .{
                .STANDARD = .{ .RIGHTS = .REQUIRED },
                .SPECIFIC = .{ .DIRECTORY = .{
                    .QUERY = true,
                    .TRAVERSE = true,
                    .CREATE_OBJECT = true,
                    .CREATE_SUBDIRECTORY = true,
                } },
            };
        };

        pub const SymbolicLink = packed struct(u16) {
            QUERY: bool = false,
            SET: bool = false,
            Reserved2: u14 = 0,

            pub const ALL_ACCESS: ACCESS_MASK = .{
                .STANDARD = .{ .RIGHTS = .REQUIRED },
                .SPECIFIC = .{ .SYMBOLIC_LINK = .{
                    .QUERY = true,
                } },
            };

            pub const ALL_ACCESS_EX: ACCESS_MASK = .{
                .STANDARD = .{ .RIGHTS = .REQUIRED },
                .SPECIFIC = .{ .SYMBOLIC_LINK = .{
                    .QUERY = true,
                    .SET = true,
                    .Reserved2 = maxInt(@FieldType(SymbolicLink, "Reserved2")),
                } },
            };
        };

        pub const Section = packed struct(u16) {
            QUERY: bool = false,
            MAP_WRITE: bool = false,
            MAP_READ: bool = false,
            MAP_EXECUTE: bool = false,
            EXTEND_SIZE: bool = false,
            /// not included in `ALL_ACCESS`
            MAP_EXECUTE_EXPLICIT: bool = false,
            Reserved6: u10 = 0,

            pub const ALL_ACCESS: ACCESS_MASK = .{
                .STANDARD = .{ .RIGHTS = .REQUIRED },
                .SPECIFIC = .{ .SECTION = .{
                    .QUERY = true,
                    .MAP_WRITE = true,
                    .MAP_READ = true,
                    .MAP_EXECUTE = true,
                    .EXTEND_SIZE = true,
                } },
            };
        };

        pub const Session = packed struct(u16) {
            QUERY_ACCESS: bool = false,
            MODIFY_ACCESS: bool = false,
            Reserved2: u14 = 0,

            pub const ALL_ACCESS: ACCESS_MASK = .{
                .STANDARD = .{ .RIGHTS = .REQUIRED },
                .SPECIFIC = .{ .SESSION = .{
                    .QUERY_ACCESS = true,
                    .MODIFY_ACCESS = true,
                } },
            };
        };

        pub const Process = packed struct(u16) {
            TERMINATE: bool = false,
            CREATE_THREAD: bool = false,
            SET_SESSIONID: bool = false,
            VM_OPERATION: bool = false,
            VM_READ: bool = false,
            VM_WRITE: bool = false,
            DUP_HANDLE: bool = false,
            CREATE_PROCESS: bool = false,
            SET_QUOTA: bool = false,
            SET_INFORMATION: bool = false,
            QUERY_INFORMATION: bool = false,
            SUSPEND_RESUME: bool = false,
            QUERY_LIMITED_INFORMATION: bool = false,
            SET_LIMITED_INFORMATION: bool = false,
            Reserved14: u2 = 0,

            pub const ALL_ACCESS: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .REQUIRED,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .PROCESS = .{
                    .TERMINATE = true,
                    .CREATE_THREAD = true,
                    .SET_SESSIONID = true,
                    .VM_OPERATION = true,
                    .VM_READ = true,
                    .VM_WRITE = true,
                    .DUP_HANDLE = true,
                    .CREATE_PROCESS = true,
                    .SET_QUOTA = true,
                    .SET_INFORMATION = true,
                    .QUERY_INFORMATION = true,
                    .SUSPEND_RESUME = true,
                    .QUERY_LIMITED_INFORMATION = true,
                    .SET_LIMITED_INFORMATION = true,
                    .Reserved14 = maxInt(@FieldType(Process, "Reserved14")),
                } },
            };
        };

        pub const Thread = packed struct(u16) {
            TERMINATE: bool = false,
            SUSPEND_RESUME: bool = false,
            ALERT: bool = false,
            GET_CONTEXT: bool = false,
            SET_CONTEXT: bool = false,
            SET_INFORMATION: bool = false,
            QUERY_INFORMATION: bool = false,
            SET_THREAD_TOKEN: bool = false,
            IMPERSONATE: bool = false,
            DIRECT_IMPERSONATION: bool = false,
            SET_LIMITED_INFORMATION: bool = false,
            QUERY_LIMITED_INFORMATION: bool = false,
            RESUME: bool = false,
            Reserved13: u3 = 0,

            pub const ALL_ACCESS: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .REQUIRED,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .THREAD = .{
                    .TERMINATE = true,
                    .SUSPEND_RESUME = true,
                    .ALERT = true,
                    .GET_CONTEXT = true,
                    .SET_CONTEXT = true,
                    .SET_INFORMATION = true,
                    .QUERY_INFORMATION = true,
                    .SET_THREAD_TOKEN = true,
                    .IMPERSONATE = true,
                    .DIRECT_IMPERSONATION = true,
                    .SET_LIMITED_INFORMATION = true,
                    .QUERY_LIMITED_INFORMATION = true,
                    .RESUME = true,
                    .Reserved13 = maxInt(@FieldType(Thread, "Reserved13")),
                } },
            };
        };

        pub const MemoryPartition = packed struct(u16) {
            QUERY_ACCESS: bool = false,
            MODIFY_ACCESS: bool = false,
            Required2: u14 = 0,

            pub const ALL_ACCESS: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .REQUIRED,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .MEMORY_PARTITION = .{
                    .QUERY_ACCESS = true,
                    .MODIFY_ACCESS = true,
                } },
            };
        };

        pub const TransactionManager = packed struct(u16) {
            QUERY_INFORMATION: bool = false,
            SET_INFORMATION: bool = false,
            RECOVER: bool = false,
            RENAME: bool = false,
            CREATE_RM: bool = false,
            /// The following right is intended for DTC's use only; it will be deprecated, and no one else should take a dependency on it.
            BIND_TRANSACTION: bool = false,
            Reserved6: u10 = 0,

            pub const GENERIC_READ: ACCESS_MASK = .{
                .STANDARD = .{ .RIGHTS = .READ },
                .SPECIFIC = .{ .TRANSACTIONMANAGER = .{
                    .QUERY_INFORMATION = true,
                } },
            };

            pub const GENERIC_WRITE: ACCESS_MASK = .{
                .STANDARD = .{ .RIGHTS = .WRITE },
                .SPECIFIC = .{ .TRANSACTIONMANAGER = .{
                    .SET_INFORMATION = true,
                    .RECOVER = true,
                    .RENAME = true,
                    .CREATE_RM = true,
                } },
            };

            pub const GENERIC_EXECUTE: ACCESS_MASK = .{
                .STANDARD = .{ .RIGHTS = .EXECUTE },
                .SPECIFIC = .{ .TRANSACTIONMANAGER = .{} },
            };

            pub const ALL_ACCESS: ACCESS_MASK = .{
                .STANDARD = .{ .RIGHTS = .REQUIRED },
                .SPECIFIC = .{ .TRANSACTIONMANAGER = .{
                    .QUERY_INFORMATION = true,
                    .SET_INFORMATION = true,
                    .RECOVER = true,
                    .RENAME = true,
                    .CREATE_RM = true,
                    .BIND_TRANSACTION = true,
                } },
            };
        };

        pub const Transaction = packed struct(u16) {
            QUERY_INFORMATION: bool = false,
            SET_INFORMATION: bool = false,
            ENLIST: bool = false,
            COMMIT: bool = false,
            ROLLBACK: bool = false,
            PROPAGATE: bool = false,
            RIGHT_RESERVED1: bool = false,
            Reserved7: u9 = 0,

            pub const GENERIC_READ: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .READ,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .TRANSACTION = .{
                    .QUERY_INFORMATION = true,
                } },
            };

            pub const GENERIC_WRITE: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .WRITE,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .TRANSACTION = .{
                    .SET_INFORMATION = true,
                    .COMMIT = true,
                    .ENLIST = true,
                    .ROLLBACK = true,
                    .PROPAGATE = true,
                } },
            };

            pub const GENERIC_EXECUTE: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .EXECUTE,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .TRANSACTION = .{
                    .COMMIT = true,
                    .ROLLBACK = true,
                } },
            };

            pub const ALL_ACCESS: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .REQUIRED,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .TRANSACTION = .{
                    .QUERY_INFORMATION = true,
                    .SET_INFORMATION = true,
                    .COMMIT = true,
                    .ENLIST = true,
                    .ROLLBACK = true,
                    .PROPAGATE = true,
                } },
            };

            pub const RESOURCE_MANAGER_RIGHTS: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .{
                        .READ_CONTROL = true,
                    },
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .TRANSACTION = .{
                    .QUERY_INFORMATION = true,
                    .SET_INFORMATION = true,
                    .ENLIST = true,
                    .ROLLBACK = true,
                    .PROPAGATE = true,
                } },
            };
        };

        pub const ResourceManager = packed struct(u16) {
            QUERY_INFORMATION: bool = false,
            SET_INFORMATION: bool = false,
            RECOVER: bool = false,
            ENLIST: bool = false,
            GET_NOTIFICATION: bool = false,
            REGISTER_PROTOCOL: bool = false,
            COMPLETE_PROPAGATION: bool = false,
            Reserved7: u9 = 0,

            pub const GENERIC_READ: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .READ,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .RESOURCEMANAGER = .{
                    .QUERY_INFORMATION = true,
                } },
            };

            pub const GENERIC_WRITE: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .WRITE,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .RESOURCEMANAGER = .{
                    .SET_INFORMATION = true,
                    .RECOVER = true,
                    .ENLIST = true,
                    .GET_NOTIFICATION = true,
                    .REGISTER_PROTOCOL = true,
                    .COMPLETE_PROPAGATION = true,
                } },
            };

            pub const GENERIC_EXECUTE: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .EXECUTE,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .RESOURCEMANAGER = .{
                    .RECOVER = true,
                    .ENLIST = true,
                    .GET_NOTIFICATION = true,
                    .COMPLETE_PROPAGATION = true,
                } },
            };

            pub const ALL_ACCESS: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .REQUIRED,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .RESOURCEMANAGER = .{
                    .QUERY_INFORMATION = true,
                    .SET_INFORMATION = true,
                    .RECOVER = true,
                    .ENLIST = true,
                    .GET_NOTIFICATION = true,
                    .REGISTER_PROTOCOL = true,
                    .COMPLETE_PROPAGATION = true,
                } },
            };
        };

        pub const Enlistment = packed struct(u16) {
            QUERY_INFORMATION: bool = false,
            SET_INFORMATION: bool = false,
            RECOVER: bool = false,
            SUBORDINATE_RIGHTS: bool = false,
            SUPERIOR_RIGHTS: bool = false,
            Reserved5: u11 = 0,

            pub const GENERIC_READ: ACCESS_MASK = .{
                .STANDARD = .{ .RIGHTS = .READ },
                .SPECIFIC = .{ .ENLISTMENT = .{
                    .QUERY_INFORMATION = true,
                } },
            };

            pub const GENERIC_WRITE: ACCESS_MASK = .{
                .STANDARD = .{ .RIGHTS = .WRITE },
                .SPECIFIC = .{ .ENLISTMENT = .{
                    .SET_INFORMATION = true,
                    .RECOVER = true,
                    .SUBORDINATE_RIGHTS = true,
                    .SUPERIOR_RIGHTS = true,
                } },
            };

            pub const GENERIC_EXECUTE: ACCESS_MASK = .{
                .STANDARD = .{ .RIGHTS = .EXECUTE },
                .SPECIFIC = .{ .ENLISTMENT = .{
                    .RECOVER = true,
                    .SUBORDINATE_RIGHTS = true,
                    .SUPERIOR_RIGHTS = true,
                } },
            };

            pub const ALL_ACCESS: ACCESS_MASK = .{
                .STANDARD = .{ .RIGHTS = .REQUIRED },
                .SPECIFIC = .{ .ENLISTMENT = .{
                    .QUERY_INFORMATION = true,
                    .SET_INFORMATION = true,
                    .RECOVER = true,
                    .SUBORDINATE_RIGHTS = true,
                    .SUPERIOR_RIGHTS = true,
                } },
            };
        };

        pub const Event = packed struct(u16) {
            QUERY_STATE: bool = false,
            MODIFY_STATE: bool = false,
            Reserved2: u14 = 0,

            pub const ALL_ACCESS: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .REQUIRED,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .EVENT = .{
                    .QUERY_STATE = true,
                    .MODIFY_STATE = true,
                } },
            };
        };

        pub const Semaphore = packed struct(u16) {
            QUERY_STATE: bool = false,
            MODIFY_STATE: bool = false,
            Reserved2: u14 = 0,

            pub const ALL_ACCESS: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .REQUIRED,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .SEMAPHORE = .{
                    .QUERY_STATE = true,
                    .MODIFY_STATE = true,
                } },
            };
        };

        pub const Token = packed struct(u16) {
            ASSIGN_PRIMARY: bool = false,
            DUPLICATE: bool = false,
            IMPERSONATE: bool = false,
            QUERY: bool = false,
            QUERY_SOURCE: bool = false,
            ADJUST_PRIVILEGES: bool = false,
            ADJUST_GROUPS: bool = false,
            ADJUST_DEFAULT: bool = false,
            ADJUST_SESSIONID: bool = false,
            Reserved9: u7 = 0,

            pub const ALL_ACCESS_P: ACCESS_MASK = .{
                .STANDARD = .{ .RIGHTS = .REQUIRED },
                .SPECIFIC = .{ .TOKEN = .{
                    .ASSIGN_PRIMARY = true,
                    .DUPLICATE = true,
                    .IMPERSONATE = true,
                    .QUERY = true,
                    .QUERY_SOURCE = true,
                    .ADJUST_PRIVILEGES = true,
                    .ADJUST_GROUPS = true,
                    .ADJUST_DEFAULT = true,
                } },
            };

            pub const ALL_ACCESS: ACCESS_MASK = .{
                .STANDARD = .{ .RIGHTS = .REQUIRED },
                .SPECIFIC = .{ .TOKEN = .{
                    .ASSIGN_PRIMARY = true,
                    .DUPLICATE = true,
                    .IMPERSONATE = true,
                    .QUERY = true,
                    .QUERY_SOURCE = true,
                    .ADJUST_PRIVILEGES = true,
                    .ADJUST_GROUPS = true,
                    .ADJUST_DEFAULT = true,
                    .ADJUST_SESSIONID = true,
                } },
            };

            pub const READ: ACCESS_MASK = .{
                .STANDARD = .{ .RIGHTS = .READ },
                .SPECIFIC = .{ .TOKEN = .{
                    .QUERY = true,
                } },
            };

            pub const WRITE: ACCESS_MASK = .{
                .STANDARD = .{ .RIGHTS = .WRITE },
                .SPECIFIC = .{ .TOKEN = .{
                    .ADJUST_PRIVILEGES = true,
                    .ADJUST_GROUPS = true,
                    .ADJUST_DEFAULT = true,
                } },
            };

            pub const EXECUTE: ACCESS_MASK = .{
                .STANDARD = .{ .RIGHTS = .EXECUTE },
                .SPECIFIC = .{ .TOKEN = .{} },
            };

            pub const TRUST_CONSTRAINT_MASK: ACCESS_MASK = .{
                .STANDARD = .{ .RIGHTS = .READ },
                .SPECIFIC = .{ .TOKEN = .{
                    .QUERY = true,
                    .QUERY_SOURCE = true,
                } },
            };

            pub const TRUST_ALLOWED_MASK: ACCESS_MASK = .{
                .STANDARD = .{ .RIGHTS = .READ },
                .SPECIFIC = .{ .TOKEN = .{
                    .QUERY = true,
                    .QUERY_SOURCE = true,
                    .DUPLICATE = true,
                    .IMPERSONATE = true,
                } },
            };
        };

        pub const JobObject = packed struct(u16) {
            ASSIGN_PROCESS: bool = false,
            SET_ATTRIBUTES: bool = false,
            QUERY: bool = false,
            TERMINATE: bool = false,
            SET_SECURITY_ATTRIBUTES: bool = false,
            IMPERSONATE: bool = false,
            Reserved6: u10 = 0,

            pub const ALL_ACCESS: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .REQUIRED,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .JOB_OBJECT = .{
                    .ASSIGN_PROCESS = true,
                    .SET_ATTRIBUTES = true,
                    .QUERY = true,
                    .TERMINATE = true,
                    .SET_SECURITY_ATTRIBUTES = true,
                    .IMPERSONATE = true,
                } },
            };
        };

        pub const Mutant = packed struct(u16) {
            QUERY_STATE: bool = false,
            Reserved1: u15 = 0,

            pub const ALL_ACCESS: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .REQUIRED,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .MUTANT = .{
                    .QUERY_STATE = true,
                } },
            };
        };

        pub const Timer = packed struct(u16) {
            QUERY_STATE: bool = false,
            MODIFY_STATE: bool = false,
            Reserved2: u14 = 0,

            pub const ALL_ACCESS: ACCESS_MASK = .{
                .STANDARD = .{
                    .RIGHTS = .REQUIRED,
                    .SYNCHRONIZE = true,
                },
                .SPECIFIC = .{ .TIMER = .{
                    .QUERY_STATE = true,
                    .MODIFY_STATE = true,
                } },
            };
        };

        pub const IoCompletion = packed struct(u16) {
            Reserved0: u1 = 0,
            MODIFY_STATE: bool = false,
            Reserved2: u14 = 0,

            pub const ALL_ACCESS: ACCESS_MASK = .{
                .STANDARD = .{ .RIGHTS = .REQUIRED, .SYNCHRONIZE = true },
                .SPECIFIC = .{ .IO_COMPLETION = .{
                    .Reserved0 = maxInt(@FieldType(IoCompletion, "Reserved0")),
                    .MODIFY_STATE = true,
                } },
            };
        };

        pub const RIGHTS_ALL: Specific = .{ .bits = maxInt(@FieldType(Specific, "bits")) };
    };

    pub const Standard = packed struct(u5) {
        RIGHTS: Rights = .{},
        SYNCHRONIZE: bool = false,

        pub const RIGHTS_ALL: Standard = .{
            .RIGHTS = .ALL,
            .SYNCHRONIZE = true,
        };

        pub const Rights = packed struct(u4) {
            DELETE: bool = false,
            READ_CONTROL: bool = false,
            WRITE_DAC: bool = false,
            WRITE_OWNER: bool = false,

            pub const REQUIRED: Rights = .{
                .DELETE = true,
                .READ_CONTROL = true,
                .WRITE_DAC = true,
                .WRITE_OWNER = true,
            };

            pub const READ: Rights = .{
                .READ_CONTROL = true,
            };
            pub const WRITE: Rights = .{
                .READ_CONTROL = true,
            };
            pub const EXECUTE: Rights = .{
                .READ_CONTROL = true,
            };

            pub const ALL = REQUIRED;
        };
    };

    pub const Generic = packed struct(u4) {
        ALL: bool = false,
        EXECUTE: bool = false,
        WRITE: bool = false,
        READ: bool = false,
    };
};

pub const DEVICE_TYPE = packed struct(ULONG) {
    FileDevice: CTL_CODE.FILE_DEVICE,
    Reserved16: u16 = 0,
};

pub const FS_INFORMATION_CLASS = enum(c_int) {
    Volume = 1,
    Label = 2,
    Size = 3,
    Device = 4,
    Attribute = 5,
    Control = 6,
    FullSize = 7,
    ObjectId = 8,
    DriverPath = 9,
    VolumeFlags = 10,
    SectorSize = 11,
    DataCopy = 12,
    MetadataSize = 13,
    FullSizeEx = 14,
    Guid = 15,
    _,

    pub const Maximum: @typeInfo(@This()).@"enum".tag_type = 1 + @typeInfo(@This()).@"enum".fields.len;
};

pub const SECTION_INHERIT = enum(c_int) {
    Share = 1,
    Unmap = 2,
};

pub const PAGE = packed struct(ULONG) {
    NOACCESS: bool = false,
    READONLY: bool = false,
    READWRITE: bool = false,
    WRITECOPY: bool = false,

    EXECUTE: bool = false,
    EXECUTE_READ: bool = false,
    EXECUTE_READWRITE: bool = false,
    EXECUTE_WRITECOPY: bool = false,

    GUARD: bool = false,
    NOCACHE: bool = false,
    WRITECOMBINE: bool = false,

    GRAPHICS_NOACCESS: bool = false,
    GRAPHICS_READONLY: bool = false,
    GRAPHICS_READWRITE: bool = false,
    GRAPHICS_EXECUTE: bool = false,
    GRAPHICS_EXECUTE_READ: bool = false,
    GRAPHICS_EXECUTE_READWRITE: bool = false,
    GRAPHICS_COHERENT: bool = false,
    GRAPHICS_NOCACHE: bool = false,

    Reserved19: u12 = 0,

    REVERT_TO_FILE_MAP: bool = false,

    pub fn fromProtection(protection: std.process.MemoryProtection) ?PAGE {
        // TODO https://github.com/ziglang/zig/issues/22214
        return switch (@as(u3, @bitCast(protection))) {
            0b000 => .{ .NOACCESS = true },
            0b001 => .{ .READONLY = true },
            0b010 => null,
            0b011 => .{ .READWRITE = true },
            0b100 => .{ .EXECUTE = true },
            0b101 => .{ .EXECUTE_READ = true },
            0b110 => null,
            0b111 => .{ .EXECUTE_READWRITE = true },
        };
    }
};

pub const MEM = struct {
    pub const ALLOCATE = packed struct(ULONG) {
        Reserved0: u12 = 0,
        COMMIT: bool = false,
        RESERVE: bool = false,
        REPLACE_PLACEHOLDER: bool = false,
        Reserved15: u3 = 0,
        RESERVE_PLACEHOLDER: bool = false,
        RESET: bool = false,
        TOP_DOWN: bool = false,
        WRITE_WATCH: bool = false,
        PHYSICAL: bool = false,
        Reserved23: u1 = 0,
        RESET_UNDO: bool = false,
        Reserved25: u4 = 0,
        LARGE_PAGES: bool = false,
        Reserved30: u1 = 0,
        @"4MB_PAGES": bool = false,

        pub const @"64K_PAGES": ALLOCATE = .{
            .LARGE_PAGES = true,
            .PHYSICAL = true,
        };
    };

    pub const FREE = packed struct(ULONG) {
        COALESCE_PLACEHOLDERS: bool = false,
        PRESERVE_PLACEHOLDER: bool = false,
        Reserved2: u12 = 0,
        DECOMMIT: bool = false,
        RELEASE: bool = false,
        FREE: bool = false,
        Reserved17: u15 = 0,
    };

    pub const MAP = packed struct(ULONG) {
        Reserved0: u13 = 0,
        RESERVE: bool = false,
        REPLACE_PLACEHOLDER: bool = false,
        Reserved15: u14 = 0,
        LARGE_PAGES: bool = false,
        Reserved30: u2 = 0,
    };

    pub const UNMAP = packed struct(ULONG) {
        WITH_TRANSIENT_BOOST: bool = false,
        PRESERVE_PLACEHOLDER: bool = false,
        Reserved2: u30 = 0,
    };

    pub const EXTENDED_PARAMETER = extern struct {
        s: packed struct(ULONG64) {
            Type: TYPE,
            Reserved: u56,
        },
        u: extern union {
            ULong64: ULONG64,
            Pointer: PVOID,
            Size: SIZE_T,
            Handle: HANDLE,
            ULong: ULONG,
        },

        pub const TYPE = enum(u8) {
            InvalidType = 0,
            AddressRequirements,
            NumaNode,
            PartitionHandle,
            UserPhysicalHandle,
            AttributeFlags,
            ImageMachine,
            _,

            pub const Max: @typeInfo(@This()).@"enum".tag_type = @typeInfo(@This()).@"enum".fields.len;
        };
    };
};

pub const SEC = packed struct(ULONG) {
    Reserved0: u17 = 0,
    HUGE_PAGES: bool = false,
    PARTITION_OWNER_HANDLE: bool = false,
    @"64K_PAGES": bool = false,
    Reserved19: u3 = 0,
    FILE: bool = false,
    IMAGE: bool = false,
    PROTECTED_IMAGE: bool = false,
    RESERVE: bool = false,
    COMMIT: bool = false,
    NOCACHE: bool = false,
    Reserved29: u1 = 0,
    WRITECOMBINE: bool = false,
    LARGE_PAGES: bool = false,

    pub const IMAGE_NO_EXECUTE: SEC = .{
        .IMAGE = true,
        .NOCACHE = true,
    };
};

pub const ERESOURCE = opaque {};

// ref: shared/ntdef.h

pub const EVENT_TYPE = enum(c_int) {
    Notification,
    Synchronization,
};

pub const TIMER_TYPE = enum(c_int) {
    Notification,
    Synchronization,
};

pub const WAIT_TYPE = enum(c_int) {
    All,
    Any,
};

pub const LOGICAL = ULONG;

pub const NTSTATUS = @import("windows/ntstatus.zig").NTSTATUS;

// ref: um/heapapi.h

pub fn GetProcessHeap() ?*HEAP {
    return peb().ProcessHeap;
}

// ref none

pub fn GetCurrentProcess() HANDLE {
    const process_pseudo_handle: usize = @bitCast(@as(isize, -1));
    return @ptrFromInt(process_pseudo_handle);
}

pub fn GetCurrentProcessId() DWORD {
    return @truncate(@intFromPtr(teb().ClientId.UniqueProcess));
}

pub fn GetCurrentThread() HANDLE {
    const thread_pseudo_handle: usize = @bitCast(@as(isize, -2));
    return @ptrFromInt(thread_pseudo_handle);
}

pub fn GetCurrentThreadId() DWORD {
    return @truncate(@intFromPtr(teb().ClientId.UniqueThread));
}

pub fn GetLastError() Win32Error {
    return teb().LastErrorValue;
}

pub fn CloseHandle(hObject: HANDLE) void {
    switch (ntdll.NtClose(hObject)) {
        .SUCCESS => {},
        else => |status| unexpectedStatus(status) catch {},
    }
}

pub const CreateProcessError = error{
    FileNotFound,
    AccessDenied,
    InvalidName,
    NameTooLong,
    InvalidExe,
    SystemResources,
    FileBusy,
    Unexpected,
};

pub const CreateProcessFlags = packed struct(u32) {
    debug_process: bool = false,
    debug_only_this_process: bool = false,
    create_suspended: bool = false,
    detached_process: bool = false,
    create_new_console: bool = false,
    normal_priority_class: bool = false,
    idle_priority_class: bool = false,
    high_priority_class: bool = false,
    realtime_priority_class: bool = false,
    create_new_process_group: bool = false,
    create_unicode_environment: bool = false,
    create_separate_wow_vdm: bool = false,
    create_shared_wow_vdm: bool = false,
    create_forcedos: bool = false,
    below_normal_priority_class: bool = false,
    above_normal_priority_class: bool = false,
    inherit_parent_affinity: bool = false,
    inherit_caller_priority: bool = false,
    create_protected_process: bool = false,
    extended_startupinfo_present: bool = false,
    process_mode_background_begin: bool = false,
    process_mode_background_end: bool = false,
    create_secure_process: bool = false,
    _reserved: bool = false,
    create_breakaway_from_job: bool = false,
    create_preserve_code_authz_level: bool = false,
    create_default_error_mode: bool = false,
    create_no_window: bool = false,
    profile_user: bool = false,
    profile_kernel: bool = false,
    profile_server: bool = false,
    create_ignore_system_default: bool = false,
};

pub fn teb() *TEB {
    if (builtin.zig_backend == .stage2_c) return @ptrCast(@alignCast(struct {
        /// This is a workaround for the C backend until zig has the ability to put
        /// C code in inline assembly.
        extern fn zig_windows_teb() callconv(.c) *anyopaque;
    }.zig_windows_teb()));
    switch (native_arch) {
        .thumb => return asm (
            \\ mrc p15, 0, %[ptr], c13, c0, 2
            : [ptr] "=r" (-> *TEB),
        ),
        .aarch64 => return asm (
            \\ mov %[ptr], x18
            : [ptr] "=r" (-> *TEB),
        ),
        .x86 => {
            comptime assert(
                @offsetOf(TEB, "NtTib") + @offsetOf(@FieldType(TEB, "NtTib"), "Self") == 0x18,
            );
            return asm (
                \\ movl %%fs:0x18, %[ptr]
                : [ptr] "=r" (-> *TEB),
            );
        },
        .x86_64 => {
            comptime assert(
                @offsetOf(TEB, "NtTib") + @offsetOf(@FieldType(TEB, "NtTib"), "Self") == 0x30,
            );
            return asm (
                \\ movq %%gs:0x30, %[ptr]
                : [ptr] "=r" (-> *TEB),
            );
        },
        else => @compileError("unsupported arch"),
    }
}

pub fn peb() *PEB {
    if (builtin.zig_backend == .stage2_c) switch (native_arch) {
        .x86, .x86_64 => return @ptrCast(@alignCast(struct {
            /// This is a workaround for the C backend until zig has the ability to put
            /// C code in inline assembly.
            extern fn zig_windows_peb() callconv(.c) *anyopaque;
        }.zig_windows_peb())),
        else => {},
    } else switch (native_arch) {
        .aarch64 => {
            comptime assert(@offsetOf(TEB, "ProcessEnvironmentBlock") == 0x60);
            return asm (
                \\ ldr %[ptr], [x18, #0x60]
                : [ptr] "=r" (-> *PEB),
            );
        },
        .x86 => {
            comptime assert(@offsetOf(TEB, "ProcessEnvironmentBlock") == 0x30);
            return asm (
                \\ movl %%fs:0x30, %[ptr]
                : [ptr] "=r" (-> *PEB),
            );
        },
        .x86_64 => {
            comptime assert(@offsetOf(TEB, "ProcessEnvironmentBlock") == 0x60);
            return asm (
                \\ movq %%gs:0x60, %[ptr]
                : [ptr] "=r" (-> *PEB),
            );
        },
        else => {},
    }
    return teb().ProcessEnvironmentBlock;
}

/// A file time is a 64-bit value that represents the number of 100-nanosecond
/// intervals that have elapsed since 12:00 A.M. January 1, 1601 Coordinated
/// Universal Time (UTC).
/// This function returns the number of nanoseconds since the canonical epoch,
/// which is the POSIX one (Jan 01, 1970 AD).
pub fn fromSysTime(hns: i64) Io.Timestamp {
    const adjusted_epoch: i128 = hns + std.time.epoch.windows * (std.time.ns_per_s / 100);
    return .fromNanoseconds(@intCast(adjusted_epoch * 100));
}

pub fn toSysTime(ns: Io.Timestamp) i64 {
    const hns = @divFloor(ns.nanoseconds, 100);
    return @as(i64, @intCast(hns)) - std.time.epoch.windows * (std.time.ns_per_s / 100);
}

/// Use RtlUpcaseUnicodeChar on Windows when not in comptime to avoid including a
/// redundant copy of the uppercase data.
pub inline fn toUpperWtf16(c: u16) u16 {
    return (if (builtin.os.tag != .windows or @inComptime()) nls.upcaseW else ntdll.RtlUpcaseUnicodeChar)(c);
}

/// Compares two WTF16 strings using the equivalent functionality of
/// `RtlEqualUnicodeString` (with case insensitive comparison enabled).
/// This function can be called on any target.
pub fn eqlIgnoreCaseWtf16(a: []const u16, b: []const u16) bool {
    if (@inComptime() or builtin.os.tag != .windows) {
        // This function compares the strings code unit by code unit (aka u16-to-u16),
        // so any length difference implies inequality. In other words, there's no possible
        // conversion that changes the number of WTF-16 code units needed for the uppercase/lowercase
        // version in the conversion table since only codepoints <= max(u16) are eligible
        // for conversion at all.
        if (a.len != b.len) return false;

        for (a, b) |a_c, b_c| {
            // The slices are always WTF-16 LE, so need to convert the elements to native
            // endianness for the uppercasing
            const a_c_native = std.mem.littleToNative(u16, a_c);
            const b_c_native = std.mem.littleToNative(u16, b_c);
            if (a_c != b_c and toUpperWtf16(a_c_native) != toUpperWtf16(b_c_native)) {
                return false;
            }
        }
        return true;
    }
    // Use RtlEqualUnicodeString on Windows when not in comptime to avoid including a
    // redundant copy of the uppercase data.
    return ntdll.RtlEqualUnicodeString(&.init(a), &.init(b), .TRUE).toBool();
}

/// Compares two WTF-8 strings using the equivalent functionality of
/// `RtlEqualUnicodeString` (with case insensitive comparison enabled).
/// This function can be called on any target.
/// Assumes `a` and `b` are valid WTF-8.
pub fn eqlIgnoreCaseWtf8(a: []const u8, b: []const u8) bool {
    // A length equality check is not possible here because there are
    // some codepoints that have a different length uppercase UTF-8 representations
    // than their lowercase counterparts, e.g. U+0250 (2 bytes) <-> U+2C6F (3 bytes).
    // There are 7 such codepoints in the uppercase data used by Windows.

    var a_wtf8_it = std.unicode.Wtf8View.initUnchecked(a).iterator();
    var b_wtf8_it = std.unicode.Wtf8View.initUnchecked(b).iterator();

    while (true) {
        const a_cp = a_wtf8_it.nextCodepoint() orelse break;
        const b_cp = b_wtf8_it.nextCodepoint() orelse return false;

        if (a_cp <= maxInt(u16) and b_cp <= maxInt(u16)) {
            if (a_cp != b_cp and toUpperWtf16(@intCast(a_cp)) != toUpperWtf16(@intCast(b_cp))) {
                return false;
            }
        } else if (a_cp != b_cp) {
            return false;
        }
    }
    // Make sure there are no leftover codepoints in b
    if (b_wtf8_it.nextCodepoint() != null) return false;

    return true;
}

fn testEqlIgnoreCase(comptime expect_eql: bool, comptime a: []const u8, comptime b: []const u8) !void {
    try std.testing.expectEqual(expect_eql, eqlIgnoreCaseWtf8(a, b));
    try std.testing.expectEqual(expect_eql, eqlIgnoreCaseWtf16(
        std.unicode.utf8ToUtf16LeStringLiteral(a),
        std.unicode.utf8ToUtf16LeStringLiteral(b),
    ));

    try comptime std.testing.expect(expect_eql == eqlIgnoreCaseWtf8(a, b));
    try comptime std.testing.expect(expect_eql == eqlIgnoreCaseWtf16(
        std.unicode.utf8ToUtf16LeStringLiteral(a),
        std.unicode.utf8ToUtf16LeStringLiteral(b),
    ));
}

test "eqlIgnoreCaseWtf16/Wtf8" {
    try testEqlIgnoreCase(true, "\x01 a B Λ ɐ", "\x01 A b λ Ɐ");
    // does not do case-insensitive comparison for codepoints >= U+10000
    try testEqlIgnoreCase(false, "𐓏", "𐓷");
}

/// The error type for `removeDotDirsSanitized`
pub const RemoveDotDirsError = error{TooManyParentDirs};

/// Removes '.' and '..' path components from a "sanitized relative path".
/// A "sanitized path" is one where:
///    1) all forward slashes have been replaced with back slashes
///    2) all repeating back slashes have been collapsed
///    3) the path is a relative one (does not start with a back slash)
pub fn removeDotDirsSanitized(comptime T: type, path: []T) RemoveDotDirsError!usize {
    assert(path.len == 0 or path[0] != '\\');

    var write_idx: usize = 0;
    var read_idx: usize = 0;
    while (read_idx < path.len) {
        if (path[read_idx] == '.') {
            if (read_idx + 1 == path.len)
                return write_idx;

            const after_dot = path[read_idx + 1];
            if (after_dot == '\\') {
                read_idx += 2;
                continue;
            }
            if (after_dot == '.' and (read_idx + 2 == path.len or path[read_idx + 2] == '\\')) {
                if (write_idx == 0) return error.TooManyParentDirs;
                assert(write_idx >= 2);
                write_idx -= 1;
                while (true) {
                    write_idx -= 1;
                    if (write_idx == 0) break;
                    if (path[write_idx] == '\\') {
                        write_idx += 1;
                        break;
                    }
                }
                if (read_idx + 2 == path.len)
                    return write_idx;
                read_idx += 3;
                continue;
            }
        }

        // skip to the next path separator
        while (true) : (read_idx += 1) {
            if (read_idx == path.len)
                return write_idx;
            path[write_idx] = path[read_idx];
            write_idx += 1;
            if (path[read_idx] == '\\')
                break;
        }
        read_idx += 1;
    }
    return write_idx;
}

/// Normalizes a Windows path with the following steps:
///     1) convert all forward slashes to back slashes
///     2) collapse duplicate back slashes
///     3) remove '.' and '..' directory parts
/// Returns the length of the new path.
pub fn normalizePath(comptime T: type, path: []T) RemoveDotDirsError!usize {
    mem.replaceScalar(T, path, '/', '\\');
    const new_len = mem.collapseRepeatsLen(T, path, '\\');

    const prefix_len: usize = init: {
        if (new_len >= 1 and path[0] == '\\') break :init 1;
        if (new_len >= 2 and path[1] == ':')
            break :init if (new_len >= 3 and path[2] == '\\') @as(usize, 3) else @as(usize, 2);
        break :init 0;
    };

    return prefix_len + try removeDotDirsSanitized(T, path[prefix_len..new_len]);
}

/// Returns true if the path starts with `\??\`, which is indicative of an NT path
/// but is not enough to fully distinguish between NT paths and Win32 paths, as
/// `\??\` is not actually a distinct prefix but rather the path to a special virtual
/// folder in the Object Manager.
///
/// For example, `\Device\HarddiskVolume2` and `\DosDevices\C:` are also NT paths but
/// cannot be distinguished as such by their prefix.
///
/// So, inferring whether a path is an NT path or a Win32 path is usually a mistake;
/// that information should instead be known ahead-of-time.
///
/// If `T` is `u16`, then `path` should be encoded as WTF-16LE.
pub fn hasCommonNtPrefix(comptime T: type, path: []const T) bool {
    // Must be exactly \??\, forward slashes are not allowed
    const expected_wtf8_prefix = "\\??\\";
    const expected_prefix = switch (T) {
        u8 => expected_wtf8_prefix,
        u16 => std.unicode.wtf8ToWtf16LeStringLiteral(expected_wtf8_prefix),
        else => @compileError("unsupported type: " ++ @typeName(T)),
    };
    return mem.startsWith(T, path, expected_prefix);
}

/// Similar to `RtlNtPathNameToDosPathName` but does not do any heap allocation.
/// The possible transformations are:
///   \??\C:\Some\Path -> C:\Some\Path
///   \??\UNC\server\share\foo -> \\server\share\foo
/// If the path does not have the NT namespace prefix, then `error.NotNtPath` is returned.
///
/// Functionality is based on the ReactOS test cases found here:
/// https://github.com/reactos/reactos/blob/master/modules/rostests/apitests/ntdll/RtlNtPathNameToDosPathName.c
///
/// `path` should be encoded as WTF-16LE.
///
/// Supports in-place modification (`path` and `out` may refer to the same slice).
pub fn ntToWin32Namespace(path: []const u16, out: []u16) error{ NameTooLong, NotNtPath }![]u16 {
    if (path.len > PATH_MAX_WIDE) return error.NameTooLong;
    if (!hasCommonNtPrefix(u16, path)) return error.NotNtPath;

    var dest_index: usize = 0;
    var after_prefix = path[4..]; // after the `\??\`
    // The prefix \??\UNC\ means this is a UNC path, in which case the
    // `\??\UNC\` should be replaced by `\\` (two backslashes)
    const is_unc = after_prefix.len >= 4 and
        eqlIgnoreCaseWtf16(after_prefix[0..3], std.unicode.utf8ToUtf16LeStringLiteral("UNC")) and
        std.fs.path.PathType.windows.isSep(u16, after_prefix[3]);
    const win32_len = path.len - @as(usize, if (is_unc) 6 else 4);
    if (out.len < win32_len) return error.NameTooLong;
    if (is_unc) {
        out[0] = comptime std.mem.nativeToLittle(u16, '\\');
        dest_index += 1;
        // We want to include the last `\` of `\??\UNC\`
        after_prefix = path[7..];
    }
    @memmove(out[dest_index..][0..after_prefix.len], after_prefix);
    return out[0..win32_len];
}

test ntToWin32Namespace {
    const L = std.unicode.utf8ToUtf16LeStringLiteral;

    var mutable_unc_path_buf = L("\\??\\UNC\\path1\\path2").*;
    try std.testing.expectEqualSlices(u16, L("\\\\path1\\path2"), try ntToWin32Namespace(&mutable_unc_path_buf, &mutable_unc_path_buf));

    var mutable_path_buf = L("\\??\\C:\\test\\").*;
    try std.testing.expectEqualSlices(u16, L("C:\\test\\"), try ntToWin32Namespace(&mutable_path_buf, &mutable_path_buf));

    var too_small_buf: [6]u16 = undefined;
    try std.testing.expectError(error.NameTooLong, ntToWin32Namespace(L("\\??\\C:\\test"), &too_small_buf));
}

inline fn MAKELANGID(p: c_ushort, s: c_ushort) LANGID {
    return (s << 10) | p;
}

/// Call this when you made a windows DLL call or something that does SetLastError
/// and you get an unexpected error.
pub fn unexpectedError(err: Win32Error) UnexpectedError {
    @branchHint(.cold);
    if (std.options.unexpected_error_tracing) {
        std.debug.print("error.Unexpected: GetLastError({d}): {t}\n", .{ err, err });
        std.debug.dumpCurrentStackTrace(.{ .first_address = @returnAddress() });
    }
    return error.Unexpected;
}

/// Call this when you made a windows NtDll call
/// and you get an unexpected status.
pub fn unexpectedStatus(status: NTSTATUS) UnexpectedError {
    if (std.options.unexpected_error_tracing) {
        std.debug.print("error.Unexpected NTSTATUS=0x{x} ({s})\n", .{
            @intFromEnum(status),
            std.enums.tagName(NTSTATUS, status) orelse "<unnamed>",
        });
        std.debug.dumpCurrentStackTrace(.{ .first_address = @returnAddress() });
    }
    return error.Unexpected;
}

pub fn statusBug(status: NTSTATUS) UnexpectedError {
    switch (builtin.mode) {
        .Debug => std.debug.panic("programmer bug caused syscall status: 0x{x} ({s})", .{
            @intFromEnum(status),
            std.enums.tagName(NTSTATUS, status) orelse "<unnamed>",
        }),
        else => return error.Unexpected,
    }
}

pub fn errorBug(err: Win32Error) UnexpectedError {
    switch (builtin.mode) {
        .Debug => std.debug.panic("programmer bug caused syscall error: 0x{x} ({s})", .{
            @intFromEnum(err),
            std.enums.tagName(Win32Error, err) orelse "<unnamed>",
        }),
        else => return error.Unexpected,
    }
}

pub const Win32Error = @import("windows/win32error.zig").Win32Error;
pub const LANG = @import("windows/lang.zig");
pub const SUBLANG = @import("windows/sublang.zig");

pub const BOOL = Bool(c_int);
pub const BOOLEAN = Bool(BYTE);
pub const BYTE = u8;
pub const CHAR = u8;
pub const UCHAR = u8;
pub const FLOAT = f32;
pub const HANDLE = *anyopaque;
pub const HCRYPTPROV = ULONG_PTR;
pub const ATOM = u16;
pub const HBRUSH = *opaque {};
pub const HCURSOR = *opaque {};
pub const HICON = *opaque {};
pub const HINSTANCE = *opaque {};
pub const HMENU = *opaque {};
pub const HMODULE = *opaque {};
pub const HWND = *opaque {};
pub const HDC = *opaque {};
pub const HGLRC = *opaque {};
pub const FARPROC = *opaque {};
pub const PROC = *opaque {};
pub const INT = c_int;
pub const LPCSTR = [*:0]const CHAR;
pub const LPCVOID = *const anyopaque;
pub const LPSTR = [*:0]CHAR;
pub const LPVOID = *anyopaque;
pub const LPWSTR = [*:0]WCHAR;
pub const LPCWSTR = [*:0]const WCHAR;
pub const PVOID = *anyopaque;
pub const PWSTR = [*:0]WCHAR;
pub const PCWSTR = [*:0]const WCHAR;
/// Allocated by SysAllocString, freed by SysFreeString
pub const BSTR = [*:0]WCHAR;
pub const SIZE_T = usize;
pub const UINT = c_uint;
pub const ULONG_PTR = usize;
pub const LONG_PTR = isize;
pub const DWORD_PTR = ULONG_PTR;
pub const WCHAR = u16;
pub const WORD = u16;
pub const DWORD = u32;
pub const DWORD64 = u64;
pub const LARGE_INTEGER = i64;
pub const ULARGE_INTEGER = u64;
pub const USHORT = u16;
pub const SHORT = i16;
pub const ULONG = u32;
pub const LONG = i32;
pub const ULONG64 = u64;
pub const ULONGLONG = u64;
pub const LONGLONG = i64;
pub const LANGID = c_ushort;
pub const COLORREF = DWORD;

pub const LPARAM = LONG_PTR;

pub const va_list = *opaque {};

pub const TCHAR = @compileError("Deprecated: choose between `CHAR` or `WCHAR` directly instead.");
pub const LPTSTR = @compileError("Deprecated: choose between `LPSTR` or `LPWSTR` directly instead.");
pub const LPCTSTR = @compileError("Deprecated: choose between `LPCSTR` or `LPCWSTR` directly instead.");
pub const PTSTR = @compileError("Deprecated: choose between `PSTR` or `PWSTR` directly instead.");
pub const PCTSTR = @compileError("Deprecated: choose between `PCSTR` or `PCWSTR` directly instead.");

fn STRING(comptime C: type) type {
    return extern struct {
        Length: USHORT,
        MaximumLength: USHORT,
        Buffer: ?[*]C,

        pub const empty: @This() = .{ .Length = 0, .MaximumLength = 0, .Buffer = null };

        pub fn init(string: []const C) @This() {
            const len: USHORT = @intCast(@sizeOf(C) * string.len);
            return .{
                .Length = len,
                .MaximumLength = len,
                .Buffer = @constCast(string.ptr),
            };
        }

        pub fn initZ(string: [:0]const C) @This() {
            const len: USHORT = @intCast(@sizeOf(C) * string.len);
            return .{
                .Length = len,
                .MaximumLength = len + @sizeOf(C),
                .Buffer = @constCast(string.ptr),
            };
        }

        pub fn isEmpty(string: *const @This()) bool {
            return string.Length == 0;
        }

        pub fn slice(string: *const @This()) []C {
            return if (string.isEmpty()) &.{} else string.Buffer.?[0..@divExact(string.Length, @sizeOf(C))];
        }

        pub fn sliceZ(string: *const @This()) [:0]C {
            assert(string.Length + @sizeOf(C) <= string.MaximumLength);
            return string.Buffer.?[0..@divExact(string.Length, @sizeOf(C)) :0];
        }
    };
}
pub const ANSI_STRING = STRING(CHAR);
pub const UNICODE_STRING = STRING(WCHAR);

fn Bool(comptime BackingInteger: type) type {
    return enum(Backing) {
        /// false
        FALSE = 0,
        /// true
        _,

        /// This is not the only truthy value, comparisons against this value are always a bug.
        pub const TRUE: @This() = @enumFromInt(1);

        pub const Backing = BackingInteger;

        pub fn toBool(b: @This()) bool {
            return b != .FALSE;
        }

        pub fn fromBool(b: bool) @This() {
            return @enumFromInt(@intFromBool(b));
        }
    };
}

pub const INVALID_HANDLE_VALUE: HANDLE = @ptrFromInt(maxInt(usize));

pub const INVALID_FILE_ATTRIBUTES: DWORD = maxInt(DWORD);

pub const IO_STATUS_BLOCK = extern struct {
    // "DUMMYUNIONNAME" expands to "u"
    u: extern union {
        Status: NTSTATUS,
        Pointer: ?*anyopaque,
    },
    Information: ULONG_PTR,
};

pub const MAX_PATH = 260;

pub const SECURITY_ATTRIBUTES = extern struct {
    nLength: DWORD,
    lpSecurityDescriptor: ?*anyopaque,
    bInheritHandle: BOOL,
};

pub const STARTUPINFOW = extern struct {
    cb: DWORD,
    lpReserved: ?LPWSTR,
    lpDesktop: ?LPWSTR,
    lpTitle: ?LPWSTR,
    dwX: DWORD,
    dwY: DWORD,
    dwXSize: DWORD,
    dwYSize: DWORD,
    dwXCountChars: DWORD,
    dwYCountChars: DWORD,
    dwFillAttribute: DWORD,
    dwFlags: DWORD,
    wShowWindow: WORD,
    cbReserved2: WORD,
    lpReserved2: ?*BYTE,
    hStdInput: ?HANDLE,
    hStdOutput: ?HANDLE,
    hStdError: ?HANDLE,
};

pub const STARTF_FORCEONFEEDBACK = 0x00000040;
pub const STARTF_FORCEOFFFEEDBACK = 0x00000080;
pub const STARTF_PREVENTPINNING = 0x00002000;
pub const STARTF_RUNFULLSCREEN = 0x00000020;
pub const STARTF_TITLEISAPPID = 0x00001000;
pub const STARTF_TITLEISLINKNAME = 0x00000800;
pub const STARTF_UNTRUSTEDSOURCE = 0x00008000;
pub const STARTF_USECOUNTCHARS = 0x00000008;
pub const STARTF_USEFILLATTRIBUTE = 0x00000010;
pub const STARTF_USEHOTKEY = 0x00000200;
pub const STARTF_USEPOSITION = 0x00000004;
pub const STARTF_USESHOWWINDOW = 0x00000001;
pub const STARTF_USESIZE = 0x00000002;
pub const STARTF_USESTDHANDLES = 0x00000100;

pub const THREAD_START_ROUTINE = fn (LPVOID) callconv(.winapi) DWORD;
pub const USER_THREAD_START_ROUTINE = fn (LPVOID) callconv(.winapi) NTSTATUS;

pub const FILETIME = extern struct {
    dwLowDateTime: DWORD,
    dwHighDateTime: DWORD,
};

pub const GUID = extern struct {
    Data1: u32,
    Data2: u16,
    Data3: u16,
    Data4: [8]u8,

    const hex_offsets = switch (builtin.target.cpu.arch.endian()) {
        .big => [16]u6{
            0,  2,  4,  6,
            9,  11, 14, 16,
            19, 21, 24, 26,
            28, 30, 32, 34,
        },
        .little => [16]u6{
            6,  4,  2,  0,
            11, 9,  16, 14,
            19, 21, 24, 26,
            28, 30, 32, 34,
        },
    };

    pub fn parse(s: []const u8) GUID {
        assert(s[0] == '{');
        assert(s[37] == '}');
        return parseNoBraces(s[1 .. s.len - 1]) catch @panic("invalid GUID string");
    }

    pub fn parseNoBraces(s: []const u8) !GUID {
        assert(s.len == 36);
        assert(s[8] == '-');
        assert(s[13] == '-');
        assert(s[18] == '-');
        assert(s[23] == '-');
        var bytes: [16]u8 = undefined;
        for (hex_offsets, 0..) |hex_offset, i| {
            bytes[i] = (try std.fmt.charToDigit(s[hex_offset], 16)) << 4 |
                try std.fmt.charToDigit(s[hex_offset + 1], 16);
        }
        return @as(GUID, @bitCast(bytes));
    }

    pub fn format(self: GUID, w: *std.Io.Writer) std.Io.Writer.Error!void {
        return w.print("{{{x:0>8}-{x:0>4}-{x:0>4}-{x}-{x}}}", .{
            self.Data1,
            self.Data2,
            self.Data3,
            self.Data4[0..2],
            self.Data4[2..8],
        });
    }
};

test GUID {
    try std.testing.expectEqual(
        GUID{
            .Data1 = 0x01234567,
            .Data2 = 0x89ab,
            .Data3 = 0xef10,
            .Data4 = "\x32\x54\x76\x98\xba\xdc\xfe\x91".*,
        },
        GUID.parse("{01234567-89AB-EF10-3254-7698badcfe91}"),
    );
    try std.testing.expectFmt(
        "{01234567-89ab-ef10-3254-7698badcfe91}",
        "{f}",
        .{GUID.parse("{01234567-89AB-EF10-3254-7698badcfe91}")},
    );
    try std.testing.expectFmt(
        "{00000001-0001-0001-0001-000000000001}",
        "{f}",
        .{GUID{ .Data1 = 1, .Data2 = 1, .Data3 = 1, .Data4 = [_]u8{ 0, 1, 0, 0, 0, 0, 0, 1 } }},
    );
}

pub const COORD = extern struct {
    X: SHORT,
    Y: SHORT,
};

pub const TLS_OUT_OF_INDEXES = 4294967295;
pub const IMAGE_TLS_DIRECTORY = extern struct {
    StartAddressOfRawData: usize,
    EndAddressOfRawData: usize,
    AddressOfIndex: usize,
    AddressOfCallBacks: usize,
    SizeOfZeroFill: u32,
    Characteristics: u32,
};
pub const IMAGE_TLS_DIRECTORY64 = IMAGE_TLS_DIRECTORY;
pub const IMAGE_TLS_DIRECTORY32 = IMAGE_TLS_DIRECTORY;

pub const PIMAGE_TLS_CALLBACK = ?*const fn (PVOID, DWORD, PVOID) callconv(.winapi) void;

pub const REGSAM = ACCESS_MASK;
pub const LSTATUS = LONG;

pub const HKEY = *opaque {};

pub const HKEY_CLASSES_ROOT: HKEY = @ptrFromInt(0x80000000);
pub const HKEY_CURRENT_USER: HKEY = @ptrFromInt(0x80000001);
pub const HKEY_LOCAL_MACHINE: HKEY = @ptrFromInt(0x80000002);
pub const HKEY_USERS: HKEY = @ptrFromInt(0x80000003);
pub const HKEY_PERFORMANCE_DATA: HKEY = @ptrFromInt(0x80000004);
pub const HKEY_PERFORMANCE_TEXT: HKEY = @ptrFromInt(0x80000050);
pub const HKEY_PERFORMANCE_NLSTEXT: HKEY = @ptrFromInt(0x80000060);
pub const HKEY_CURRENT_CONFIG: HKEY = @ptrFromInt(0x80000005);
pub const HKEY_DYN_DATA: HKEY = @ptrFromInt(0x80000006);
pub const HKEY_CURRENT_USER_LOCAL_SETTINGS: HKEY = @ptrFromInt(0x80000007);

pub const RTL_QUERY_REGISTRY_TABLE = extern struct {
    QueryRoutine: RTL_QUERY_REGISTRY_ROUTINE,
    Flags: ULONG,
    Name: ?PWSTR,
    EntryContext: ?*anyopaque,
    DefaultType: REG.ValueType,
    DefaultData: ?*anyopaque,
    DefaultLength: ULONG,
};

pub const RTL_QUERY_REGISTRY_ROUTINE = ?*const fn (
    PWSTR,
    ULONG,
    ?*anyopaque,
    ULONG,
    ?*anyopaque,
    ?*anyopaque,
) callconv(.winapi) NTSTATUS;

/// Path is a full path
pub const RTL_REGISTRY_ABSOLUTE = 0;
/// \Registry\Machine\System\CurrentControlSet\Services
pub const RTL_REGISTRY_SERVICES = 1;
/// \Registry\Machine\System\CurrentControlSet\Control
pub const RTL_REGISTRY_CONTROL = 2;
/// \Registry\Machine\Software\Microsoft\Windows NT\CurrentVersion
pub const RTL_REGISTRY_WINDOWS_NT = 3;
/// \Registry\Machine\Hardware\DeviceMap
pub const RTL_REGISTRY_DEVICEMAP = 4;
/// \Registry\User\CurrentUser
pub const RTL_REGISTRY_USER = 5;
pub const RTL_REGISTRY_MAXIMUM = 6;

/// Low order bits are registry handle
pub const RTL_REGISTRY_HANDLE = 0x40000000;
/// Indicates the key node is optional
pub const RTL_REGISTRY_OPTIONAL = 0x80000000;

/// Name is a subkey and remainder of table or until next subkey are value
/// names for that subkey to look at.
pub const RTL_QUERY_REGISTRY_SUBKEY = 0x00000001;

/// Reset current key to original key for this and all following table entries.
pub const RTL_QUERY_REGISTRY_TOPKEY = 0x00000002;

/// Fail if no match found for this table entry.
pub const RTL_QUERY_REGISTRY_REQUIRED = 0x00000004;

/// Used to mark a table entry that has no value name, just wants a call out, not
/// an enumeration of all values.
pub const RTL_QUERY_REGISTRY_NOVALUE = 0x00000008;

/// Used to suppress the expansion of REG_MULTI_SZ into multiple callouts or
/// to prevent the expansion of environment variable values in REG_EXPAND_SZ.
pub const RTL_QUERY_REGISTRY_NOEXPAND = 0x00000010;

/// QueryRoutine field ignored.  EntryContext field points to location to store value.
/// For null terminated strings, EntryContext points to UNICODE_STRING structure that
/// that describes maximum size of buffer. If .Buffer field is NULL then a buffer is
/// allocated.
pub const RTL_QUERY_REGISTRY_DIRECT = 0x00000020;

/// Used to delete value keys after they are queried.
pub const RTL_QUERY_REGISTRY_DELETE = 0x00000040;

/// Use this flag with the RTL_QUERY_REGISTRY_DIRECT flag to verify that the REG_XXX type
/// of the stored registry value matches the type expected by the caller.
/// If the types do not match, the call fails.
pub const RTL_QUERY_REGISTRY_TYPECHECK = 0x00000100;

/// REG_ is a crowded namespace with a lot of overlapping and unrelated
/// defines in the Windows headers, so instead of strictly following the
/// Windows headers names, extra namespaces are added here for clarity.
pub const REG = struct {
    pub const ValueType = enum(ULONG) {
        /// No value type
        NONE = 0,
        /// Unicode nul terminated string
        SZ = 1,
        /// Unicode nul terminated string (with environment variable references)
        EXPAND_SZ = 2,
        /// Free form binary
        BINARY = 3,
        /// 32-bit number
        DWORD = 4,
        /// 32-bit number
        DWORD_BIG_ENDIAN = 5,
        /// Symbolic Link (unicode)
        LINK = 6,
        /// Multiple Unicode strings
        MULTI_SZ = 7,
        /// Resource list in the resource map
        RESOURCE_LIST = 8,
        /// Resource list in the hardware description
        FULL_RESOURCE_DESCRIPTOR = 9,
        RESOURCE_REQUIREMENTS_LIST = 10,
        /// 64-bit number
        QWORD = 11,
        _,

        /// 32-bit number (same as REG_DWORD)
        pub const DWORD_LITTLE_ENDIAN: ValueType = .DWORD;
        /// 64-bit number (same as REG_QWORD)
        pub const QWORD_LITTLE_ENDIAN: ValueType = .QWORD;
    };

    /// Used with NtOpenKeyEx, maybe others
    pub const OpenOptions = packed struct(ULONG) {
        Reserved0: u2 = 0,
        /// Open for backup or restore
        /// special access rules privilege required
        BACKUP_RESTORE: bool = false,
        /// Open symbolic link
        OPEN_LINK: bool = false,
        Reserved3: u28 = 0,
    };

    /// Used with NtLoadKeyEx, maybe others
    pub const LoadOptions = packed struct(ULONG) {
        /// Restore whole hive volatile
        WHOLE_HIVE_VOLATILE: bool = false,
        /// Unwind changes to last flush
        REFRESH_HIVE: bool = false,
        /// Never lazy flush this hive
        NO_LAZY_FLUSH: bool = false,
        /// Force the restore process even when we have open handles on subkeys
        FORCE_RESTORE: bool = false,
        /// Loads the hive visible to the calling process
        APP_HIVE: bool = false,
        /// Hive cannot be mounted by any other process while in use
        PROCESS_PRIVATE: bool = false,
        /// Starts Hive Journal
        START_JOURNAL: bool = false,
        /// Grow hive file in exact 4k increments
        HIVE_EXACT_FILE_GROWTH: bool = false,
        /// No RM is started for this hive (no transactions)
        HIVE_NO_RM: bool = false,
        /// Legacy single logging is used for this hive
        HIVE_SINGLE_LOG: bool = false,
        /// This hive might be used by the OS loader
        BOOT_HIVE: bool = false,
        /// Load the hive and return a handle to its root kcb
        LOAD_HIVE_OPEN_HANDLE: bool = false,
        /// Flush changes to primary hive file size as part of all flushes
        FLUSH_HIVE_FILE_GROWTH: bool = false,
        /// Open a hive's files in read-only mode
        /// The same flag is used for REG_APP_HIVE_OPEN_READ_ONLY:
        /// Open an app hive's files in read-only mode (if the hive was not previously loaded).
        OPEN_READ_ONLY: bool = false,
        /// Load the hive, but don't allow any modification of it
        IMMUTABLE: bool = false,
        /// Do not fall back to impersonating the caller if hive file access fails
        NO_IMPERSONATION_FALLBACK: bool = false,
        Reserved16: u16 = 0,
    };
};

pub const KEY = struct {
    pub const VALUE = struct {
        /// https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/wdm/ne-wdm-_key_value_information_class
        pub const INFORMATION_CLASS = enum(c_int) {
            Basic = 0,
            Full = 1,
            Partial = 2,
            FullAlign64 = 3,
            PartialAlign64 = 4,
            Layer = 5,
            _,

            pub const Max: @typeInfo(@This()).@"enum".tag_type = @typeInfo(@This()).@"enum".fields.len;
        };

        pub const PARTIAL_INFORMATION = extern struct {
            TitleIndex: ULONG,
            Type: REG.ValueType,
            DataLength: ULONG,
            Data: [0]UCHAR,

            pub fn data(info: *const PARTIAL_INFORMATION) []const UCHAR {
                const ptr: [*]const UCHAR = @ptrCast(&info.Data);
                return ptr[0..info.DataLength];
            }
        };
    };
};

pub const ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x4;
pub const DISABLE_NEWLINE_AUTO_RETURN = 0x8;

pub const FOREGROUND_BLUE = 0x0001;
pub const FOREGROUND_GREEN = 0x0002;
pub const FOREGROUND_RED = 0x0004;
pub const FOREGROUND_INTENSITY = 0x0008;
pub const BACKGROUND_BLUE = 0x0010;
pub const BACKGROUND_GREEN = 0x0020;
pub const BACKGROUND_RED = 0x0040;
pub const BACKGROUND_INTENSITY = 0x0080;

pub const LIST_ENTRY = extern struct {
    Flink: *LIST_ENTRY,
    Blink: *LIST_ENTRY,
};

pub const RTL_CRITICAL_SECTION_DEBUG = extern struct {
    Type: WORD,
    CreatorBackTraceIndex: WORD,
    CriticalSection: *RTL_CRITICAL_SECTION,
    ProcessLocksList: LIST_ENTRY,
    EntryCount: DWORD,
    ContentionCount: DWORD,
    Flags: DWORD,
    CreatorBackTraceIndexHigh: WORD,
    SpareWORD: WORD,
};

pub const RTL_CRITICAL_SECTION = extern struct {
    DebugInfo: *RTL_CRITICAL_SECTION_DEBUG,
    LockCount: LONG,
    RecursionCount: LONG,
    OwningThread: HANDLE,
    LockSemaphore: HANDLE,
    SpinCount: ULONG_PTR,
};

pub const CRITICAL_SECTION = RTL_CRITICAL_SECTION;
pub const INIT_ONCE = RTL_RUN_ONCE;
pub const INIT_ONCE_STATIC_INIT = RTL_RUN_ONCE_INIT;
pub const INIT_ONCE_FN = *const fn (InitOnce: *INIT_ONCE, Parameter: ?*anyopaque, Context: ?*anyopaque) callconv(.winapi) BOOL;

pub const RTL_RUN_ONCE = extern struct {
    Ptr: ?*anyopaque,
};

pub const RTL_RUN_ONCE_INIT = RTL_RUN_ONCE{ .Ptr = null };

/// > The maximum path of 32,767 characters is approximate, because the "\\?\"
/// > prefix may be expanded to a longer string by the system at run time, and
/// > this expansion applies to the total length.
/// from https://docs.microsoft.com/en-us/windows/desktop/FileIO/naming-a-file#maximum-path-length-limitation
pub const PATH_MAX_WIDE = 32767;

/// > [Each file name component can be] up to the value returned in the
/// > lpMaximumComponentLength parameter of the GetVolumeInformation function
/// > (this value is commonly 255 characters)
/// from https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation
///
/// > The value that is stored in the variable that *lpMaximumComponentLength points to is
/// > used to indicate that a specified file system supports long names. For example, for
/// > a FAT file system that supports long names, the function stores the value 255, rather
/// > than the previous 8.3 indicator. Long names can also be supported on systems that use
/// > the NTFS file system.
/// from https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getvolumeinformationw
///
/// The assumption being made here is that while lpMaximumComponentLength may vary, it will never
/// be larger than 255.
///
/// TODO: More verification of this assumption.
pub const NAME_MAX = 255;

pub const EXCEPTION_DATATYPE_MISALIGNMENT = 0x80000002;
pub const EXCEPTION_ACCESS_VIOLATION = 0xc0000005;
pub const EXCEPTION_ILLEGAL_INSTRUCTION = 0xc000001d;
pub const EXCEPTION_STACK_OVERFLOW = 0xc00000fd;
pub const EXCEPTION_CONTINUE_SEARCH = 0;

pub const EXCEPTION_RECORD = extern struct {
    ExceptionCode: u32,
    ExceptionFlags: u32,
    ExceptionRecord: *EXCEPTION_RECORD,
    ExceptionAddress: *anyopaque,
    NumberParameters: u32,
    ExceptionInformation: [15]usize,
};

pub const FLOATING_SAVE_AREA = switch (native_arch) {
    .x86 => extern struct {
        ControlWord: DWORD,
        StatusWord: DWORD,
        TagWord: DWORD,
        ErrorOffset: DWORD,
        ErrorSelector: DWORD,
        DataOffset: DWORD,
        DataSelector: DWORD,
        RegisterArea: [80]BYTE,
        Cr0NpxState: DWORD,
    },
    else => @compileError("FLOATING_SAVE_AREA only defined on x86"),
};

pub const M128A = switch (native_arch) {
    .x86_64 => extern struct {
        Low: ULONGLONG,
        High: LONGLONG,
    },
    else => @compileError("M128A only defined on x86_64"),
};

pub const XMM_SAVE_AREA32 = switch (native_arch) {
    .x86_64 => extern struct {
        ControlWord: WORD,
        StatusWord: WORD,
        TagWord: BYTE,
        Reserved1: BYTE,
        ErrorOpcode: WORD,
        ErrorOffset: DWORD,
        ErrorSelector: WORD,
        Reserved2: WORD,
        DataOffset: DWORD,
        DataSelector: WORD,
        Reserved3: WORD,
        MxCsr: DWORD,
        MxCsr_Mask: DWORD,
        FloatRegisters: [8]M128A,
        XmmRegisters: [16]M128A,
        Reserved4: [96]BYTE,
    },
    else => @compileError("XMM_SAVE_AREA32 only defined on x86_64"),
};

pub const NEON128 = switch (native_arch) {
    .thumb => extern struct {
        Low: ULONGLONG,
        High: LONGLONG,
    },
    .aarch64 => extern union {
        DUMMYSTRUCTNAME: extern struct {
            Low: ULONGLONG,
            High: LONGLONG,
        },
        D: [2]f64,
        S: [4]f32,
        H: [8]WORD,
        B: [16]BYTE,
    },
    else => @compileError("NEON128 only defined on aarch64"),
};

pub const CONTEXT = switch (native_arch) {
    .x86 => extern struct {
        ContextFlags: DWORD,
        Dr0: DWORD,
        Dr1: DWORD,
        Dr2: DWORD,
        Dr3: DWORD,
        Dr6: DWORD,
        Dr7: DWORD,
        FloatSave: FLOATING_SAVE_AREA,
        SegGs: DWORD,
        SegFs: DWORD,
        SegEs: DWORD,
        SegDs: DWORD,
        Edi: DWORD,
        Esi: DWORD,
        Ebx: DWORD,
        Edx: DWORD,
        Ecx: DWORD,
        Eax: DWORD,
        Ebp: DWORD,
        Eip: DWORD,
        SegCs: DWORD,
        EFlags: DWORD,
        Esp: DWORD,
        SegSs: DWORD,
        ExtendedRegisters: [512]BYTE,

        pub fn getRegs(ctx: *const CONTEXT) struct { bp: usize, ip: usize, sp: usize } {
            return .{ .bp = ctx.Ebp, .ip = ctx.Eip, .sp = ctx.Esp };
        }
    },
    .x86_64 => extern struct {
        P1Home: DWORD64 align(16),
        P2Home: DWORD64,
        P3Home: DWORD64,
        P4Home: DWORD64,
        P5Home: DWORD64,
        P6Home: DWORD64,
        ContextFlags: DWORD,
        MxCsr: DWORD,
        SegCs: WORD,
        SegDs: WORD,
        SegEs: WORD,
        SegFs: WORD,
        SegGs: WORD,
        SegSs: WORD,
        EFlags: DWORD,
        Dr0: DWORD64,
        Dr1: DWORD64,
        Dr2: DWORD64,
        Dr3: DWORD64,
        Dr6: DWORD64,
        Dr7: DWORD64,
        Rax: DWORD64,
        Rcx: DWORD64,
        Rdx: DWORD64,
        Rbx: DWORD64,
        Rsp: DWORD64,
        Rbp: DWORD64,
        Rsi: DWORD64,
        Rdi: DWORD64,
        R8: DWORD64,
        R9: DWORD64,
        R10: DWORD64,
        R11: DWORD64,
        R12: DWORD64,
        R13: DWORD64,
        R14: DWORD64,
        R15: DWORD64,
        Rip: DWORD64,
        DUMMYUNIONNAME: extern union {
            FltSave: XMM_SAVE_AREA32,
            FloatSave: XMM_SAVE_AREA32,
            DUMMYSTRUCTNAME: extern struct {
                Header: [2]M128A,
                Legacy: [8]M128A,
                Xmm0: M128A,
                Xmm1: M128A,
                Xmm2: M128A,
                Xmm3: M128A,
                Xmm4: M128A,
                Xmm5: M128A,
                Xmm6: M128A,
                Xmm7: M128A,
                Xmm8: M128A,
                Xmm9: M128A,
                Xmm10: M128A,
                Xmm11: M128A,
                Xmm12: M128A,
                Xmm13: M128A,
                Xmm14: M128A,
                Xmm15: M128A,
            },
        },
        VectorRegister: [26]M128A,
        VectorControl: DWORD64,
        DebugControl: DWORD64,
        LastBranchToRip: DWORD64,
        LastBranchFromRip: DWORD64,
        LastExceptionToRip: DWORD64,
        LastExceptionFromRip: DWORD64,

        pub fn getRegs(ctx: *const CONTEXT) struct { bp: usize, ip: usize, sp: usize } {
            return .{ .bp = ctx.Rbp, .ip = ctx.Rip, .sp = ctx.Rsp };
        }

        pub fn setIp(ctx: *CONTEXT, ip: usize) void {
            ctx.Rip = ip;
        }

        pub fn setSp(ctx: *CONTEXT, sp: usize) void {
            ctx.Rsp = sp;
        }
    },
    .thumb => extern struct {
        ContextFlags: ULONG,
        R0: ULONG,
        R1: ULONG,
        R2: ULONG,
        R3: ULONG,
        R4: ULONG,
        R5: ULONG,
        R6: ULONG,
        R7: ULONG,
        R8: ULONG,
        R9: ULONG,
        R10: ULONG,
        R11: ULONG,
        R12: ULONG,
        Sp: ULONG,
        Lr: ULONG,
        Pc: ULONG,
        Cpsr: ULONG,
        Fpcsr: ULONG,
        Padding: ULONG,
        DUMMYUNIONNAME: extern union {
            Q: [16]NEON128,
            D: [32]ULONGLONG,
            S: [32]ULONG,
        },
        Bvr: [8]ULONG,
        Bcr: [8]ULONG,
        Wvr: [1]ULONG,
        Wcr: [1]ULONG,
        Padding2: [2]ULONG,

        pub fn getRegs(ctx: *const CONTEXT) struct { bp: usize, ip: usize, sp: usize } {
            return .{
                .bp = ctx.DUMMYUNIONNAME.S[11],
                .ip = ctx.Pc,
                .sp = ctx.Sp,
            };
        }

        pub fn setIp(ctx: *CONTEXT, ip: usize) void {
            ctx.Pc = ip;
        }

        pub fn setSp(ctx: *CONTEXT, sp: usize) void {
            ctx.Sp = sp;
        }
    },
    .aarch64 => extern struct {
        ContextFlags: ULONG align(16),
        Cpsr: ULONG,
        DUMMYUNIONNAME: extern union {
            DUMMYSTRUCTNAME: extern struct {
                X0: DWORD64,
                X1: DWORD64,
                X2: DWORD64,
                X3: DWORD64,
                X4: DWORD64,
                X5: DWORD64,
                X6: DWORD64,
                X7: DWORD64,
                X8: DWORD64,
                X9: DWORD64,
                X10: DWORD64,
                X11: DWORD64,
                X12: DWORD64,
                X13: DWORD64,
                X14: DWORD64,
                X15: DWORD64,
                X16: DWORD64,
                X17: DWORD64,
                X18: DWORD64,
                X19: DWORD64,
                X20: DWORD64,
                X21: DWORD64,
                X22: DWORD64,
                X23: DWORD64,
                X24: DWORD64,
                X25: DWORD64,
                X26: DWORD64,
                X27: DWORD64,
                X28: DWORD64,
                Fp: DWORD64,
                Lr: DWORD64,
            },
            X: [31]DWORD64,
        },
        Sp: DWORD64,
        Pc: DWORD64,
        V: [32]NEON128,
        Fpcr: DWORD,
        Fpsr: DWORD,
        Bcr: [8]DWORD,
        Bvr: [8]DWORD64,
        Wcr: [2]DWORD,
        Wvr: [2]DWORD64,

        pub fn getRegs(ctx: *const CONTEXT) struct { bp: usize, ip: usize, sp: usize } {
            return .{
                .bp = ctx.DUMMYUNIONNAME.DUMMYSTRUCTNAME.Fp,
                .ip = ctx.Pc,
                .sp = ctx.Sp,
            };
        }

        pub fn setIp(ctx: *CONTEXT, ip: usize) void {
            ctx.Pc = ip;
        }

        pub fn setSp(ctx: *CONTEXT, sp: usize) void {
            ctx.Sp = sp;
        }
    },
    else => @compileError("CONTEXT is not defined for this architecture"),
};

pub const RUNTIME_FUNCTION = switch (native_arch) {
    .x86_64 => extern struct {
        BeginAddress: DWORD,
        EndAddress: DWORD,
        UnwindData: DWORD,
    },
    .thumb => extern struct {
        BeginAddress: DWORD,
        DUMMYUNIONNAME: extern union {
            UnwindData: DWORD,
            DUMMYSTRUCTNAME: packed struct(u32) {
                Flag: u2,
                FunctionLength: u11,
                Ret: u2,
                H: u1,
                Reg: u3,
                R: u1,
                L: u1,
                C: u1,
                StackAdjust: u10,
            },
        },
    },
    .aarch64 => extern struct {
        BeginAddress: DWORD,
        DUMMYUNIONNAME: extern union {
            UnwindData: DWORD,
            DUMMYSTRUCTNAME: packed struct(u32) {
                Flag: u2,
                FunctionLength: u11,
                RegF: u3,
                RegI: u4,
                H: u1,
                CR: u2,
                FrameSize: u9,
            },
        },
    },
    else => @compileError("RUNTIME_FUNCTION is not defined for this architecture"),
};

pub const KNONVOLATILE_CONTEXT_POINTERS = switch (native_arch) {
    .x86_64 => extern struct {
        FloatingContext: [16]?*M128A,
        IntegerContext: [16]?*ULONG64,
    },
    .thumb => extern struct {
        R4: ?*DWORD,
        R5: ?*DWORD,
        R6: ?*DWORD,
        R7: ?*DWORD,
        R8: ?*DWORD,
        R9: ?*DWORD,
        R10: ?*DWORD,
        R11: ?*DWORD,
        Lr: ?*DWORD,
        D8: ?*ULONGLONG,
        D9: ?*ULONGLONG,
        D10: ?*ULONGLONG,
        D11: ?*ULONGLONG,
        D12: ?*ULONGLONG,
        D13: ?*ULONGLONG,
        D14: ?*ULONGLONG,
        D15: ?*ULONGLONG,
    },
    .aarch64 => extern struct {
        X19: ?*DWORD64,
        X20: ?*DWORD64,
        X21: ?*DWORD64,
        X22: ?*DWORD64,
        X23: ?*DWORD64,
        X24: ?*DWORD64,
        X25: ?*DWORD64,
        X26: ?*DWORD64,
        X27: ?*DWORD64,
        X28: ?*DWORD64,
        Fp: ?*DWORD64,
        Lr: ?*DWORD64,
        D8: ?*DWORD64,
        D9: ?*DWORD64,
        D10: ?*DWORD64,
        D11: ?*DWORD64,
        D12: ?*DWORD64,
        D13: ?*DWORD64,
        D14: ?*DWORD64,
        D15: ?*DWORD64,
    },
    else => @compileError("KNONVOLATILE_CONTEXT_POINTERS is not defined for this architecture"),
};

pub const EXCEPTION_POINTERS = extern struct {
    ExceptionRecord: *EXCEPTION_RECORD,
    ContextRecord: *CONTEXT,
};

pub const VECTORED_EXCEPTION_HANDLER = *const fn (ExceptionInfo: *EXCEPTION_POINTERS) callconv(.winapi) c_long;

pub const EXCEPTION_DISPOSITION = i32;
pub const EXCEPTION_ROUTINE = *const fn (
    ExceptionRecord: ?*EXCEPTION_RECORD,
    EstablisherFrame: PVOID,
    ContextRecord: *CONTEXT,
    DispatcherContext: PVOID,
) callconv(.winapi) EXCEPTION_DISPOSITION;

pub const UNWIND_HISTORY_TABLE_SIZE = 12;
pub const UNWIND_HISTORY_TABLE_ENTRY = extern struct {
    ImageBase: ULONG64,
    FunctionEntry: *RUNTIME_FUNCTION,
};

pub const UNWIND_HISTORY_TABLE = extern struct {
    Count: ULONG,
    LocalHint: BYTE,
    GlobalHint: BYTE,
    Search: BYTE,
    Once: BYTE,
    LowAddress: ULONG64,
    HighAddress: ULONG64,
    Entry: [UNWIND_HISTORY_TABLE_SIZE]UNWIND_HISTORY_TABLE_ENTRY,
};

pub const UNW_FLAG_NHANDLER = 0x0;
pub const UNW_FLAG_EHANDLER = 0x1;
pub const UNW_FLAG_UHANDLER = 0x2;
pub const UNW_FLAG_CHAININFO = 0x4;

pub const ACTIVATION_CONTEXT_DATA = opaque {};
pub const ASSEMBLY_STORAGE_MAP = opaque {};
pub const FLS_CALLBACK_INFO = opaque {};
pub const RTL_BITMAP = opaque {};
pub const KAFFINITY = usize;
pub const KPRIORITY = i32;

pub const CLIENT_ID = extern struct {
    UniqueProcess: HANDLE,
    UniqueThread: HANDLE,
};

pub const TEB = extern struct {
    NtTib: NT_TIB,
    EnvironmentPointer: PVOID,
    ClientId: CLIENT_ID,
    ActiveRpcHandle: PVOID,
    ThreadLocalStoragePointer: PVOID,
    ProcessEnvironmentBlock: *PEB,
    LastErrorValue: Win32Error,
    Reserved2: [399 * @sizeOf(PVOID) - @sizeOf(ULONG)]u8,
    Reserved3: [1952]u8,
    TlsSlots: [64]PVOID,
    Reserved4: [8]u8,
    Reserved5: [26]PVOID,
    ReservedForOle: PVOID,
    Reserved6: [4]PVOID,
    TlsExpansionSlots: PVOID,
};

comptime {
    // XXX: Without this check we cannot use `std.Io.Writer` on 16-bit platforms. `std.fmt.bufPrint` will hit the unreachable in `PEB.GdiHandleBuffer` without this guard.
    if (builtin.os.tag == .windows) {
        // Offsets taken from WinDbg info and Geoff Chappell[1] (RIP)
        // [1]: https://www.geoffchappell.com/studies/windows/km/ntoskrnl/inc/api/pebteb/teb/index.htm
        assert(@offsetOf(TEB, "NtTib") == 0x00);
        if (@sizeOf(usize) == 4) {
            assert(@offsetOf(TEB, "EnvironmentPointer") == 0x1C);
            assert(@offsetOf(TEB, "ClientId") == 0x20);
            assert(@offsetOf(TEB, "ActiveRpcHandle") == 0x28);
            assert(@offsetOf(TEB, "ThreadLocalStoragePointer") == 0x2C);
            assert(@offsetOf(TEB, "ProcessEnvironmentBlock") == 0x30);
            assert(@offsetOf(TEB, "LastErrorValue") == 0x34);
            assert(@offsetOf(TEB, "TlsSlots") == 0xe10);
        } else if (@sizeOf(usize) == 8) {
            assert(@offsetOf(TEB, "EnvironmentPointer") == 0x38);
            assert(@offsetOf(TEB, "ClientId") == 0x40);
            assert(@offsetOf(TEB, "ActiveRpcHandle") == 0x50);
            assert(@offsetOf(TEB, "ThreadLocalStoragePointer") == 0x58);
            assert(@offsetOf(TEB, "ProcessEnvironmentBlock") == 0x60);
            assert(@offsetOf(TEB, "LastErrorValue") == 0x68);
            assert(@offsetOf(TEB, "TlsSlots") == 0x1480);
        }
    }
}

pub const EXCEPTION_REGISTRATION_RECORD = extern struct {
    Next: ?*EXCEPTION_REGISTRATION_RECORD,
    Handler: ?*EXCEPTION_DISPOSITION,
};

pub const NT_TIB = extern struct {
    ExceptionList: ?*EXCEPTION_REGISTRATION_RECORD,
    StackBase: PVOID,
    StackLimit: PVOID,
    SubSystemTib: PVOID,
    DUMMYUNIONNAME: extern union { FiberData: PVOID, Version: DWORD },
    ArbitraryUserPointer: PVOID,
    Self: ?*@This(),
};

/// Process Environment Block
/// Microsoft documentation of this is incomplete, the fields here are taken from various resources including:
///  - https://github.com/wine-mirror/wine/blob/1aff1e6a370ee8c0213a0fd4b220d121da8527aa/include/winternl.h#L269
///  - https://www.geoffchappell.com/studies/windows/win32/ntdll/structs/peb/index.htm
pub const PEB = extern struct {
    // Versions: All
    InheritedAddressSpace: BOOLEAN,

    // Versions: 3.51+
    ReadImageFileExecOptions: BOOLEAN,
    BeingDebugged: BOOLEAN,

    // Versions: 5.2+ (previously was padding)
    BitField: UCHAR,

    // Versions: all
    Mutant: HANDLE,
    ImageBaseAddress: HMODULE,
    Ldr: *PEB_LDR_DATA,
    ProcessParameters: *RTL_USER_PROCESS_PARAMETERS,
    SubSystemData: PVOID,
    ProcessHeap: ?*HEAP,

    // Versions: 5.1+
    FastPebLock: *RTL_CRITICAL_SECTION,

    // Versions: 5.2+
    AtlThunkSListPtr: PVOID,
    IFEOKey: PVOID,

    // Versions: 6.0+

    /// https://www.geoffchappell.com/studies/windows/win32/ntdll/structs/peb/crossprocessflags.htm
    CrossProcessFlags: ULONG,

    // Versions: 6.0+
    union1: extern union {
        KernelCallbackTable: PVOID,
        UserSharedInfoPtr: PVOID,
    },

    // Versions: 5.1+
    SystemReserved: ULONG,

    // Versions: 5.1, (not 5.2, not 6.0), 6.1+
    AtlThunkSListPtr32: ULONG,

    // Versions: 6.1+
    ApiSetMap: PVOID,

    // Versions: all
    TlsExpansionCounter: ULONG,
    // note: there is padding here on 64 bit
    TlsBitmap: *RTL_BITMAP,
    TlsBitmapBits: [2]ULONG,
    /// Our base address of the memory region shared with the CSR server.
    ReadOnlySharedMemoryBase: PVOID,

    // Versions: 1703+
    SharedData: PVOID,

    // Versions: all
    ReadOnlyStaticServerData: *UnknownStaticServerDataIndirection,
    AnsiCodePageData: PVOID,
    OemCodePageData: PVOID,
    UnicodeCaseTableData: PVOID,

    // Versions: 3.51+
    NumberOfProcessors: ULONG,
    NtGlobalFlag: ULONG,

    // Versions: all
    CriticalSectionTimeout: LARGE_INTEGER,

    // End of Original PEB size

    // Fields appended in 3.51:
    HeapSegmentReserve: ULONG_PTR,
    HeapSegmentCommit: ULONG_PTR,
    HeapDeCommitTotalFreeThreshold: ULONG_PTR,
    HeapDeCommitFreeBlockThreshold: ULONG_PTR,
    NumberOfHeaps: ULONG,
    MaximumNumberOfHeaps: ULONG,
    ProcessHeaps: *PVOID,

    // Fields appended in 4.0:
    GdiSharedHandleTable: PVOID,
    ProcessStarterHelper: PVOID,
    GdiDCAttributeList: ULONG,
    // note: there is padding here on 64 bit
    LoaderLock: *RTL_CRITICAL_SECTION,
    OSMajorVersion: ULONG,
    OSMinorVersion: ULONG,
    OSBuildNumber: USHORT,
    OSCSDVersion: USHORT,
    OSPlatformId: ULONG,
    ImageSubSystem: ULONG,
    ImageSubSystemMajorVersion: ULONG,
    ImageSubSystemMinorVersion: ULONG,
    // note: there is padding here on 64 bit
    ActiveProcessAffinityMask: KAFFINITY,
    GdiHandleBuffer: [
        switch (@sizeOf(usize)) {
            4 => 0x22,
            8 => 0x3C,
            else => unreachable,
        }
    ]ULONG,

    // Fields appended in 5.0 (Windows 2000):
    PostProcessInitRoutine: PVOID,
    TlsExpansionBitmap: *RTL_BITMAP,
    TlsExpansionBitmapBits: [32]ULONG,
    SessionId: ULONG,
    // note: there is padding here on 64 bit
    // Versions: 5.1+
    AppCompatFlags: ULARGE_INTEGER,
    AppCompatFlagsUser: ULARGE_INTEGER,
    ShimData: PVOID,
    // Versions: 5.0+
    AppCompatInfo: PVOID,
    CSDVersion: UNICODE_STRING,

    // Fields appended in 5.1 (Windows XP):
    ActivationContextData: *const ACTIVATION_CONTEXT_DATA,
    ProcessAssemblyStorageMap: *ASSEMBLY_STORAGE_MAP,
    SystemDefaultActivationData: *const ACTIVATION_CONTEXT_DATA,
    SystemAssemblyStorageMap: *ASSEMBLY_STORAGE_MAP,
    MinimumStackCommit: ULONG_PTR,

    // Fields appended in 5.2 (Windows Server 2003):
    FlsCallback: *FLS_CALLBACK_INFO,
    FlsListHead: LIST_ENTRY,
    FlsBitmap: *RTL_BITMAP,
    FlsBitmapBits: [4]ULONG,
    FlsHighIndex: ULONG,

    // Fields appended in 6.0 (Windows Vista):
    WerRegistrationData: PVOID,
    WerShipAssertPtr: PVOID,

    // Fields appended in 6.1 (Windows 7):
    pUnused: PVOID, // previously pContextData
    pImageHeaderHash: PVOID,

    /// TODO: https://www.geoffchappell.com/studies/windows/win32/ntdll/structs/peb/tracingflags.htm
    TracingFlags: ULONG,

    // Fields appended in 6.2 (Windows 8):
    /// Base address in the CSRSS address space of the memory region shared with the CSR server.
    CsrServerReadOnlySharedMemoryBase: ULONGLONG,

    // Fields appended in 1511:
    TppWorkerpListLock: ULONG,
    TppWorkerpList: LIST_ENTRY,
    WaitOnAddressHashTable: [0x80]PVOID,

    // Fields appended in 1709:
    TelemetryCoverageHeader: PVOID,
    CloudFileFlags: ULONG,

    /// Details of this structure are unknown, but the existence of the field at offset 8 is known
    /// from experimentation and from reverse-engineering kernelbase.dll.
    const UnknownStaticServerDataIndirection = extern struct {
        unknown: u64,
        /// In the CSRSS address space.
        base_static_server_data_addr: u64,
    };
};

/// The `PEB_LDR_DATA` structure is the main record of what modules are loaded in a process.
/// It is essentially the head of three double-linked lists of `LDR.DATA_TABLE_ENTRY` structures which each represent one loaded module.
///
/// Microsoft documentation of this is incomplete, the fields here are taken from various resources including:
///  - https://www.geoffchappell.com/studies/windows/win32/ntdll/structs/peb_ldr_data.htm
pub const PEB_LDR_DATA = extern struct {
    // Versions: 3.51 and higher
    /// The size in bytes of the structure
    Length: ULONG,

    /// TRUE if the structure is prepared.
    Initialized: BOOLEAN,

    SsHandle: PVOID,
    InLoadOrderModuleList: LIST_ENTRY,
    InMemoryOrderModuleList: LIST_ENTRY,
    InInitializationOrderModuleList: LIST_ENTRY,

    // Versions: 5.1 and higher

    /// No known use of this field is known in Windows 8 and higher.
    EntryInProgress: PVOID,

    // Versions: 6.0 from Windows Vista SP1, and higher
    ShutdownInProgress: BOOLEAN,

    /// Though ShutdownThreadId is declared as a HANDLE,
    /// it is indeed the thread ID as suggested by its name.
    /// It is picked up from the UniqueThread member of the CLIENT_ID in the
    /// TEB of the thread that asks to terminate the process.
    ShutdownThreadId: HANDLE,
};

pub const LDR = struct {
    /// Microsoft documentation of this is incomplete, the fields here are taken from various resources including:
    ///  - https://docs.microsoft.com/en-us/windows/win32/api/winternl/ns-winternl-peb_ldr_data
    ///  - https://www.geoffchappell.com/studies/windows/km/ntoskrnl/inc/api/ntldr/ldr_data_table_entry.htm
    pub const DATA_TABLE_ENTRY = extern struct {
        InLoadOrderLinks: LIST_ENTRY,
        InMemoryOrderLinks: LIST_ENTRY,
        InInitializationOrderLinks: LIST_ENTRY,
        DllBase: PVOID,
        EntryPoint: PVOID,
        SizeOfImage: ULONG,
        FullDllName: UNICODE_STRING,
        BaseDllName: UNICODE_STRING,
        Reserved5: [3]PVOID,
        DUMMYUNIONNAME: extern union {
            CheckSum: ULONG,
            Reserved6: PVOID,
        },
        TimeDateStamp: ULONG,
    };

    pub const DLL_NOTIFICATION = struct {
        pub const REASON = enum(ULONG) { LOADED = 1, UNLOADED = 2 };

        pub const DATA = extern union {
            Loaded: LOADED,
            Unloaded: UNLOADED,

            pub const LOADED = extern struct {
                Flags: REGISTER,
                FullDllName: *const UNICODE_STRING,
                BaseDllName: *const UNICODE_STRING,
                DllBase: PVOID,
                SizeOfImage: ULONG,
            };

            pub const UNLOADED = extern struct {
                Flags: REGISTER,
                FullDllName: *const UNICODE_STRING,
                BaseDllName: *const UNICODE_STRING,
                DllBase: PVOID,
                SizeOfImage: ULONG,
            };
        };

        pub const COOKIE = *opaque {};

        pub const FUNCTION = fn (
            NotificationReason: REASON,
            NotificationData: *const DATA,
            Context: ?PVOID,
        ) callconv(.winapi) void;

        pub const REGISTER = packed struct(ULONG) {
            Reserved0: u32 = 0,
        };
    };

    pub const GET_DLL_HANDLE_EX = packed struct(ULONG) {
        UNCHANGED_REFCOUNT: bool = false,
        PIN: bool = false,
        Reserved2: u30 = 0,
    };

    pub const GET_PROCEDURE_ADDRESS = packed struct(ULONG) {
        DONT_RECORD_FORWARDER: bool = false,
        Reserved1: u31 = 0,
    };

    pub const LOAD = packed struct(ULONG) {
        DONT_RESOLVE_DLL_REFERENCES: bool = false,
        LIBRARY_AS_DATAFILE: bool = false,
        PACKAGED_LIBRARY: bool = false,
        WITH_ALTERED_SEARCH_PATH: bool = false,
        IGNORE_CODE_AUTHZ_LEVEL: bool = false,
        LIBRARY_AS_IMAGE_RESOURCE: bool = false,
        LIBRARY_AS_DATAFILE_EXCLUSIVE: bool = false,
        LIBRARY_REQUERE_SIGNED_TARGET: bool = false,
        LIBRARY_SEARCH_DLL_LOAD_DIR: bool = false,
        LIBRARY_SEARCH_USER_DIRS: bool = false,
        LIBRARY_SEARCH_SYSTEM32: bool = false,
        LIBRARY_SEARCH_DEFAULT_DIRS: bool = false,
    };
};

pub const RTL_USER_PROCESS_PARAMETERS = extern struct {
    AllocationSize: ULONG,
    Size: ULONG,
    Flags: ULONG,
    DebugFlags: ULONG,
    ConsoleHandle: HANDLE,
    ConsoleFlags: ULONG,
    hStdInput: HANDLE,
    hStdOutput: HANDLE,
    hStdError: HANDLE,
    CurrentDirectory: CURDIR,
    DllPath: UNICODE_STRING,
    ImagePathName: UNICODE_STRING,
    CommandLine: UNICODE_STRING,
    /// Points to a NUL-terminated sequence of NUL-terminated
    /// WTF-16 LE encoded `name=value` sequences.
    /// Example using string literal syntax:
    /// `"NAME=value\x00foo=bar\x00\x00"`
    Environment: [*:0]WCHAR,
    dwX: ULONG,
    dwY: ULONG,
    dwXSize: ULONG,
    dwYSize: ULONG,
    dwXCountChars: ULONG,
    dwYCountChars: ULONG,
    dwFillAttribute: ULONG,
    dwFlags: ULONG,
    dwShowWindow: ULONG,
    WindowTitle: UNICODE_STRING,
    Desktop: UNICODE_STRING,
    ShellInfo: UNICODE_STRING,
    RuntimeInfo: UNICODE_STRING,
    DLCurrentDirectory: [0x20]RTL_DRIVE_LETTER_CURDIR,
};

pub const RTL_DRIVE_LETTER_CURDIR = extern struct {
    Flags: c_ushort,
    Length: c_ushort,
    TimeStamp: ULONG,
    DosPath: UNICODE_STRING,
};

pub const PPS_POST_PROCESS_INIT_ROUTINE = ?*const fn () callconv(.winapi) void;

pub const FILE_DIRECTORY_INFORMATION = extern struct {
    NextEntryOffset: ULONG,
    FileIndex: ULONG,
    CreationTime: LARGE_INTEGER,
    LastAccessTime: LARGE_INTEGER,
    LastWriteTime: LARGE_INTEGER,
    ChangeTime: LARGE_INTEGER,
    EndOfFile: LARGE_INTEGER,
    AllocationSize: LARGE_INTEGER,
    FileAttributes: FILE.ATTRIBUTE,
    FileNameLength: ULONG,
    FileName: [1]WCHAR,
};

pub const FILE_BOTH_DIR_INFORMATION = extern struct {
    NextEntryOffset: ULONG,
    FileIndex: ULONG,
    CreationTime: LARGE_INTEGER,
    LastAccessTime: LARGE_INTEGER,
    LastWriteTime: LARGE_INTEGER,
    ChangeTime: LARGE_INTEGER,
    EndOfFile: LARGE_INTEGER,
    AllocationSize: LARGE_INTEGER,
    FileAttributes: FILE.ATTRIBUTE,
    FileNameLength: ULONG,
    EaSize: ULONG,
    ShortNameLength: CHAR,
    ShortName: [12]WCHAR,
    FileName: [1]WCHAR,
};
pub const FILE_BOTH_DIRECTORY_INFORMATION = FILE_BOTH_DIR_INFORMATION;

/// Helper for iterating a byte buffer of FILE_*_INFORMATION structures (from
/// things like NtQueryDirectoryFile calls).
pub fn FileInformationIterator(comptime FileInformationType: type) type {
    return struct {
        byte_offset: usize = 0,
        buf: []u8 align(@alignOf(FileInformationType)),

        pub fn next(self: *@This()) ?*FileInformationType {
            if (self.byte_offset >= self.buf.len) return null;
            const cur: *FileInformationType = @ptrCast(@alignCast(&self.buf[self.byte_offset]));
            if (cur.NextEntryOffset == 0) {
                self.byte_offset = self.buf.len;
            } else {
                self.byte_offset += cur.NextEntryOffset;
            }
            return cur;
        }
    };
}

pub const IO_APC_ROUTINE = fn (?*anyopaque, *IO_STATUS_BLOCK, ULONG) callconv(.winapi) void;

pub const CURDIR = extern struct {
    DosPath: UNICODE_STRING,
    Handle: HANDLE,
};

pub const DUPLICATE_SAME_ACCESS = 2;

pub const MODULEINFO = extern struct {
    lpBaseOfDll: LPVOID,
    SizeOfImage: DWORD,
    EntryPoint: LPVOID,
};

pub const OSVERSIONINFOW = extern struct {
    dwOSVersionInfoSize: ULONG,
    dwMajorVersion: ULONG,
    dwMinorVersion: ULONG,
    dwBuildNumber: ULONG,
    dwPlatformId: ULONG,
    szCSDVersion: [128]WCHAR,
};
pub const RTL_OSVERSIONINFOW = OSVERSIONINFOW;

pub const REPARSE_DATA_BUFFER = extern struct {
    ReparseTag: IO_REPARSE_TAG,
    ReparseDataLength: USHORT,
    Reserved: USHORT,
    DataBuffer: [1]UCHAR,
};
pub const SYMBOLIC_LINK_REPARSE_BUFFER = extern struct {
    SubstituteNameOffset: USHORT,
    SubstituteNameLength: USHORT,
    PrintNameOffset: USHORT,
    PrintNameLength: USHORT,
    Flags: ULONG,
    PathBuffer: [1]WCHAR,
};
pub const MOUNT_POINT_REPARSE_BUFFER = extern struct {
    SubstituteNameOffset: USHORT,
    SubstituteNameLength: USHORT,
    PrintNameOffset: USHORT,
    PrintNameLength: USHORT,
    PathBuffer: [1]WCHAR,
};
pub const SYMLINK_FLAG_RELATIVE: ULONG = 0x1;

pub const SYMBOLIC_LINK_FLAG_DIRECTORY: DWORD = 0x1;
pub const SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE: DWORD = 0x2;

pub const MOUNTMGR_MOUNT_POINT = extern struct {
    SymbolicLinkNameOffset: ULONG,
    SymbolicLinkNameLength: USHORT,
    Reserved1: USHORT,
    UniqueIdOffset: ULONG,
    UniqueIdLength: USHORT,
    Reserved2: USHORT,
    DeviceNameOffset: ULONG,
    DeviceNameLength: USHORT,
    Reserved3: USHORT,
};
pub const MOUNTMGR_MOUNT_POINTS = extern struct {
    Size: ULONG,
    NumberOfMountPoints: ULONG,
    MountPoints: [1]MOUNTMGR_MOUNT_POINT,
};

pub const MOUNTMGR_TARGET_NAME = extern struct {
    DeviceNameLength: USHORT,
    DeviceName: [1]WCHAR,
};
pub const MOUNTMGR_VOLUME_PATHS = extern struct {
    MultiSzLength: ULONG,
    MultiSz: [1]WCHAR,
};

pub const SRWLOCK_INIT = SRWLOCK{};
pub const SRWLOCK = extern struct {
    Ptr: ?PVOID = null,
};

pub const CONDITION_VARIABLE_INIT = CONDITION_VARIABLE{};
pub const CONDITION_VARIABLE = extern struct {
    Ptr: ?PVOID = null,
};

/// Processor feature enumeration.
pub const PF = enum(DWORD) {
    /// On a Pentium, a floating-point precision error can occur in rare circumstances.
    FLOATING_POINT_PRECISION_ERRATA = 0,

    /// Floating-point operations are emulated using software emulator.
    /// This function returns a nonzero value if floating-point operations are emulated; otherwise, it returns zero.
    FLOATING_POINT_EMULATED = 1,

    /// The atomic compare and exchange operation (cmpxchg) is available.
    COMPARE_EXCHANGE_DOUBLE = 2,

    /// The MMX instruction set is available.
    MMX_INSTRUCTIONS_AVAILABLE = 3,

    PPC_MOVEMEM_64BIT_OK = 4,
    ALPHA_BYTE_INSTRUCTIONS = 5,

    /// The SSE instruction set is available.
    XMMI_INSTRUCTIONS_AVAILABLE = 6,

    /// The 3D-Now instruction is available.
    @"3DNOW_INSTRUCTIONS_AVAILABLE" = 7,

    /// The RDTSC instruction is available.
    RDTSC_INSTRUCTION_AVAILABLE = 8,

    /// The processor is PAE-enabled.
    PAE_ENABLED = 9,

    /// The SSE2 instruction set is available.
    XMMI64_INSTRUCTIONS_AVAILABLE = 10,

    SSE_DAZ_MODE_AVAILABLE = 11,

    /// Data execution prevention is enabled.
    NX_ENABLED = 12,

    /// The SSE3 instruction set is available.
    SSE3_INSTRUCTIONS_AVAILABLE = 13,

    /// The atomic compare and exchange 128-bit operation (cmpxchg16b) is available.
    COMPARE_EXCHANGE128 = 14,

    /// The atomic compare 64 and exchange 128-bit operation (cmp8xchg16) is available.
    COMPARE64_EXCHANGE128 = 15,

    /// The processor channels are enabled.
    CHANNELS_ENABLED = 16,

    /// The processor implements the XSAVI and XRSTOR instructions.
    XSAVE_ENABLED = 17,

    /// The VFP/Neon: 32 x 64bit register bank is present.
    /// This flag has the same meaning as PF_ARM_VFP_EXTENDED_REGISTERS.
    ARM_VFP_32_REGISTERS_AVAILABLE = 18,

    /// This ARM processor implements the ARM v8 NEON instruction set.
    ARM_NEON_INSTRUCTIONS_AVAILABLE = 19,

    /// Second Level Address Translation is supported by the hardware.
    SECOND_LEVEL_ADDRESS_TRANSLATION = 20,

    /// Virtualization is enabled in the firmware and made available by the operating system.
    VIRT_FIRMWARE_ENABLED = 21,

    /// RDFSBASE, RDGSBASE, WRFSBASE, and WRGSBASE instructions are available.
    RDWRFSGBASE_AVAILABLE = 22,

    /// _fastfail() is available.
    FASTFAIL_AVAILABLE = 23,

    /// The divide instruction_available.
    ARM_DIVIDE_INSTRUCTION_AVAILABLE = 24,

    /// The 64-bit load/store atomic instructions are available.
    ARM_64BIT_LOADSTORE_ATOMIC = 25,

    /// The external cache is available.
    ARM_EXTERNAL_CACHE_AVAILABLE = 26,

    /// The floating-point multiply-accumulate instruction is available.
    ARM_FMAC_INSTRUCTIONS_AVAILABLE = 27,

    RDRAND_INSTRUCTION_AVAILABLE = 28,

    /// This ARM processor implements the ARM v8 instructions set.
    ARM_V8_INSTRUCTIONS_AVAILABLE = 29,

    /// This ARM processor implements the ARM v8 extra cryptographic instructions (i.e., AES, SHA1 and SHA2).
    ARM_V8_CRYPTO_INSTRUCTIONS_AVAILABLE = 30,

    /// This ARM processor implements the ARM v8 extra CRC32 instructions.
    ARM_V8_CRC32_INSTRUCTIONS_AVAILABLE = 31,

    RDTSCP_INSTRUCTION_AVAILABLE = 32,
    RDPID_INSTRUCTION_AVAILABLE = 33,

    /// This ARM processor implements the ARM v8.1 atomic instructions (e.g., CAS, SWP).
    ARM_V81_ATOMIC_INSTRUCTIONS_AVAILABLE = 34,

    MONITORX_INSTRUCTION_AVAILABLE = 35,

    /// The SSSE3 instruction set is available.
    SSSE3_INSTRUCTIONS_AVAILABLE = 36,

    /// The SSE4_1 instruction set is available.
    SSE4_1_INSTRUCTIONS_AVAILABLE = 37,

    /// The SSE4_2 instruction set is available.
    SSE4_2_INSTRUCTIONS_AVAILABLE = 38,

    /// The AVX instruction set is available.
    AVX_INSTRUCTIONS_AVAILABLE = 39,

    /// The AVX2 instruction set is available.
    AVX2_INSTRUCTIONS_AVAILABLE = 40,

    /// The AVX512F instruction set is available.
    AVX512F_INSTRUCTIONS_AVAILABLE = 41,

    ERMS_AVAILABLE = 42,

    /// This ARM processor implements the ARM v8.2 Dot Product (DP) instructions.
    ARM_V82_DP_INSTRUCTIONS_AVAILABLE = 43,

    /// This ARM processor implements the ARM v8.3 JavaScript conversion (JSCVT) instructions.
    ARM_V83_JSCVT_INSTRUCTIONS_AVAILABLE = 44,

    /// This Arm processor implements the Arm v8.3 LRCPC instructions (for example, LDAPR). Note that certain Arm v8.2 CPUs may optionally support the LRCPC instructions.
    ARM_V83_LRCPC_INSTRUCTIONS_AVAILABLE,
};

pub const MAX_WOW64_SHARED_ENTRIES = 16;
pub const PROCESSOR_FEATURE_MAX = 64;
pub const MAXIMUM_XSTATE_FEATURES = 64;

pub const KSYSTEM_TIME = extern struct {
    LowPart: ULONG,
    High1Time: LONG,
    High2Time: LONG,
};

pub const NT_PRODUCT_TYPE = enum(INT) {
    NtProductWinNt = 1,
    NtProductLanManNt,
    NtProductServer,
};

pub const ALTERNATIVE_ARCHITECTURE_TYPE = enum(INT) {
    StandardDesign,
    NEC98x86,
    EndAlternatives,
};

pub const XSTATE_FEATURE = extern struct {
    Offset: ULONG,
    Size: ULONG,
};

pub const XSTATE_CONFIGURATION = extern struct {
    EnabledFeatures: ULONG64,
    Size: ULONG,
    OptimizedSave: ULONG,
    Features: [MAXIMUM_XSTATE_FEATURES]XSTATE_FEATURE,
};

/// Shared Kernel User Data
pub const KUSER_SHARED_DATA = extern struct {
    TickCountLowDeprecated: ULONG,
    TickCountMultiplier: ULONG,
    InterruptTime: KSYSTEM_TIME,
    SystemTime: KSYSTEM_TIME,
    TimeZoneBias: KSYSTEM_TIME,
    ImageNumberLow: USHORT,
    ImageNumberHigh: USHORT,
    NtSystemRoot: [260]WCHAR,
    MaxStackTraceDepth: ULONG,
    CryptoExponent: ULONG,
    TimeZoneId: ULONG,
    LargePageMinimum: ULONG,
    AitSamplingValue: ULONG,
    AppCompatFlag: ULONG,
    RNGSeedVersion: ULONGLONG,
    GlobalValidationRunlevel: ULONG,
    TimeZoneBiasStamp: LONG,
    NtBuildNumber: ULONG,
    NtProductType: NT_PRODUCT_TYPE,
    ProductTypeIsValid: BOOLEAN,
    Reserved0: [1]BOOLEAN,
    NativeProcessorArchitecture: USHORT,
    NtMajorVersion: ULONG,
    NtMinorVersion: ULONG,
    ProcessorFeatures: [PROCESSOR_FEATURE_MAX]BOOLEAN,
    Reserved1: ULONG,
    Reserved3: ULONG,
    TimeSlip: ULONG,
    AlternativeArchitecture: ALTERNATIVE_ARCHITECTURE_TYPE,
    BootId: ULONG,
    SystemExpirationDate: LARGE_INTEGER,
    SuiteMaskY: ULONG,
    KdDebuggerEnabled: BOOLEAN,
    DummyUnion1: extern union {
        MitigationPolicies: UCHAR,
        Alt: packed struct(u8) {
            NXSupportPolicy: u2,
            SEHValidationPolicy: u2,
            CurDirDevicesSkippedForDlls: u2,
            Reserved: u2,
        },
    },
    CyclesPerYield: USHORT,
    ActiveConsoleId: ULONG,
    DismountCount: ULONG,
    ComPlusPackage: ULONG,
    LastSystemRITEventTickCount: ULONG,
    NumberOfPhysicalPages: ULONG,
    SafeBootMode: BOOLEAN,
    DummyUnion2: extern union {
        VirtualizationFlags: UCHAR,
        Alt: packed struct(u8) {
            ArchStartedInEl2: u1,
            QcSlIsSupported: u1,
            SpareBits: u6,
        },
    },
    Reserved12: [2]UCHAR,
    DummyUnion3: extern union {
        SharedDataFlags: ULONG,
        Alt: packed struct(u32) {
            DbgErrorPortPresent: u1,
            DbgElevationEnabled: u1,
            DbgVirtEnabled: u1,
            DbgInstallerDetectEnabled: u1,
            DbgLkgEnabled: u1,
            DbgDynProcessorEnabled: u1,
            DbgConsoleBrokerEnabled: u1,
            DbgSecureBootEnabled: u1,
            DbgMultiSessionSku: u1,
            DbgMultiUsersInSessionSku: u1,
            DbgStateSeparationEnabled: u1,
            SpareBits: u21,
        },
    },
    DataFlagsPad: [1]ULONG,
    TestRetInstruction: ULONGLONG,
    QpcFrequency: LONGLONG,
    SystemCall: ULONG,
    Reserved2: ULONG,
    SystemCallPad: [2]ULONGLONG,
    DummyUnion4: extern union {
        TickCount: KSYSTEM_TIME,
        TickCountQuad: ULONG64,
        Alt: extern struct {
            ReservedTickCountOverlay: [3]ULONG,
            TickCountPad: [1]ULONG,
        },
    },
    Cookie: ULONG,
    CookiePad: [1]ULONG,
    ConsoleSessionForegroundProcessId: LONGLONG,
    TimeUpdateLock: ULONGLONG,
    BaselineSystemTimeQpc: ULONGLONG,
    BaselineInterruptTimeQpc: ULONGLONG,
    QpcSystemTimeIncrement: ULONGLONG,
    QpcInterruptTimeIncrement: ULONGLONG,
    QpcSystemTimeIncrementShift: UCHAR,
    QpcInterruptTimeIncrementShift: UCHAR,
    UnparkedProcessorCount: USHORT,
    EnclaveFeatureMask: [4]ULONG,
    TelemetryCoverageRound: ULONG,
    UserModeGlobalLogger: [16]USHORT,
    ImageFileExecutionOptions: ULONG,
    LangGenerationCount: ULONG,
    Reserved4: ULONGLONG,
    InterruptTimeBias: ULONGLONG,
    QpcBias: ULONGLONG,
    ActiveProcessorCount: ULONG,
    ActiveGroupCount: UCHAR,
    Reserved9: UCHAR,
    DummyUnion5: extern union {
        QpcData: USHORT,
        Alt: extern struct {
            QpcBypassEnabled: UCHAR,
            QpcShift: UCHAR,
        },
    },
    TimeZoneBiasEffectiveStart: LARGE_INTEGER,
    TimeZoneBiasEffectiveEnd: LARGE_INTEGER,
    XState: XSTATE_CONFIGURATION,
    FeatureConfigurationChangeStamp: KSYSTEM_TIME,
    Spare: ULONG,
    UserPointerAuthMask: ULONG64,
};

/// Read-only user-mode address for the shared data.
/// https://www.geoffchappell.com/studies/windows/km/ntoskrnl/inc/api/ntexapi_x/kuser_shared_data/index.htm
/// https://msrc-blog.microsoft.com/2022/04/05/randomizing-the-kuser_shared_data-structure-on-windows/
pub const SharedUserData: *const KUSER_SHARED_DATA = @ptrFromInt(0x7FFE0000);

pub fn IsProcessorFeaturePresent(feature: PF) bool {
    if (@intFromEnum(feature) >= PROCESSOR_FEATURE_MAX) return false;
    return SharedUserData.ProcessorFeatures[@intFromEnum(feature)].toBool();
}

// https://github.com/reactos/reactos/blob/master/sdk/include/ndk/pstypes.h#L977-L983
pub const KERNEL_USER_TIMES = extern struct {
    CreationTime: LARGE_INTEGER,
    ExitTime: LARGE_INTEGER,
    KernelTime: LARGE_INTEGER,
    UserTime: LARGE_INTEGER,
};

pub fn wtf8ToWtf16Le(wtf16le: []u16, wtf8: []const u8) error{ BadPathName, NameTooLong }!usize {
    // Each u8 in UTF-8/WTF-8 correlates to at most one u16 in UTF-16LE/WTF-16LE.
    if (wtf16le.len < wtf8.len) {
        const utf16_len = std.unicode.calcUtf16LeLenImpl(wtf8, .can_encode_surrogate_half) catch
            return error.BadPathName;
        if (utf16_len > wtf16le.len)
            return error.NameTooLong;
    }
    return std.unicode.wtf8ToWtf16Le(wtf16le, wtf8) catch |err| switch (err) {
        error.InvalidWtf8 => return error.BadPathName,
    };
}

/// Returns the path to the system directory, typically "C:\\WINDOWS\\System32".
///
/// Equivalent to `GetSystemDirectoryW` in kernel32.
pub fn getSystemDirectoryWtf16Le() [:0]const u16 {
    const ssd: *const BASE_STATIC_SERVER_DATA = @ptrCast(@alignCast(relocateCsrssAddress(
        peb().ReadOnlyStaticServerData.base_static_server_data_addr,
    )));
    return ssd.windows_system_directory.relocate().sliceZ();
}
// https://github.com/reactos/reactos/blob/4b75ec5508d47b726d1210e24f5a849dae4e3bda/sdk/include/reactos/subsys/win/base.h#L119
const BASE_STATIC_SERVER_DATA = extern struct {
    windows_directory: ForeignString,
    windows_system_directory: ForeignString,
    named_object_directory: ForeignString,
    /// This matches the 64-bit version of `UNICODE_STRING`---even on 32-bit targets, this string is
    /// from 64-bit code (since it comes from CSRSS which is running outside of WOW64).
    const ForeignString = extern struct {
        length: u16,
        maximum_length: u16,
        /// Address in the CSRSS address space. To convert this to a valid pointer in *our* address
        /// space, see `relocateCsrssAddress` (or the `ForeignString.relocate` wrapper function).
        buffer_address: u64,
        fn relocate(str: ForeignString) UNICODE_STRING {
            return .{
                .Length = str.length,
                .MaximumLength = str.maximum_length,
                .Buffer = @ptrCast(@alignCast(@constCast(relocateCsrssAddress(str.buffer_address)))),
            };
        }
    };
};
/// Takes an address in the CSRSS address space's mapped view of the shared memory region, and
/// returns the corresponding address in *our* mapped view of the shared memory region.
fn relocateCsrssAddress(addr: u64) *const anyopaque {
    const base: [*]const u8 = @ptrCast(peb().ReadOnlySharedMemoryBase);
    const offset: usize = @intCast(addr - peb().CsrServerReadOnlySharedMemoryBase);
    return base + offset;
}
