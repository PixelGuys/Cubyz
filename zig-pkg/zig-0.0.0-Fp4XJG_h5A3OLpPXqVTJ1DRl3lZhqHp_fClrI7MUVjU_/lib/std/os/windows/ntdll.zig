const std = @import("../../std.zig");
const windows = std.os.windows;

const ACCESS_MASK = windows.ACCESS_MASK;
const ANSI_STRING = windows.ANSI_STRING;
const BOOL = windows.BOOL;
const BOOLEAN = windows.BOOLEAN;
const CONDITION_VARIABLE = windows.CONDITION_VARIABLE;
const CONTEXT = windows.CONTEXT;
const CRITICAL_SECTION = windows.CRITICAL_SECTION;
const CTL_CODE = windows.CTL_CODE;
const CURDIR = windows.CURDIR;
const DIRECTORY = windows.DIRECTORY;
const DWORD = windows.DWORD;
const DWORD64 = windows.DWORD64;
const ERESOURCE = windows.ERESOURCE;
const EVENT_TYPE = windows.EVENT_TYPE;
const EXCEPTION_ROUTINE = windows.EXCEPTION_ROUTINE;
const FILE = windows.FILE;
const FS_INFORMATION_CLASS = windows.FS_INFORMATION_CLASS;
const HANDLE = windows.HANDLE;
const HEAP = windows.HEAP;
const IO_APC_ROUTINE = windows.IO_APC_ROUTINE;
const IO_STATUS_BLOCK = windows.IO_STATUS_BLOCK;
const KEY = windows.KEY;
const KNONVOLATILE_CONTEXT_POINTERS = windows.KNONVOLATILE_CONTEXT_POINTERS;
const LARGE_INTEGER = windows.LARGE_INTEGER;
const LDR = windows.LDR;
const LOGICAL = windows.LOGICAL;
const LONG = windows.LONG;
const LPCVOID = windows.LPCVOID;
const LPVOID = windows.LPVOID;
const MEM = windows.MEM;
const NTSTATUS = windows.NTSTATUS;
const OBJECT = windows.OBJECT;
const PAGE = windows.PAGE;
const PCWSTR = windows.PCWSTR;
const PROCESS = windows.PROCESS;
const PVOID = windows.PVOID;
const PWSTR = windows.PWSTR;
const REG = windows.REG;
const RTL_OSVERSIONINFOW = windows.RTL_OSVERSIONINFOW;
const RTL_QUERY_REGISTRY_TABLE = windows.RTL_QUERY_REGISTRY_TABLE;
const RUNTIME_FUNCTION = windows.RUNTIME_FUNCTION;
const SEC = windows.SEC;
const SECTION_INHERIT = windows.SECTION_INHERIT;
const SIZE_T = windows.SIZE_T;
const SRWLOCK = windows.SRWLOCK;
const SYSTEM = windows.SYSTEM;
const THREAD = windows.THREAD;
const ULONG = windows.ULONG;
const ULONG_PTR = windows.ULONG_PTR;
const UNICODE_STRING = windows.UNICODE_STRING;
const UNWIND_HISTORY_TABLE = windows.UNWIND_HISTORY_TABLE;
const USHORT = windows.USHORT;
const VECTORED_EXCEPTION_HANDLER = windows.VECTORED_EXCEPTION_HANDLER;
const WORD = windows.WORD;
const USER_THREAD_START_ROUTINE = windows.USER_THREAD_START_ROUTINE;
const PS = windows.PS;
const TEB = windows.TEB;

// ref: km/ntifs.h

pub extern "ntdll" fn RtlCreateHeap(
    Flags: HEAP.FLAGS.CREATE,
    HeapBase: ?PVOID,
    ReserveSize: SIZE_T,
    CommitSize: SIZE_T,
    Lock: ?*ERESOURCE,
    Parameters: ?*const HEAP.RTL_PARAMETERS,
) callconv(.winapi) ?*HEAP;

pub extern "ntdll" fn RtlDestroyHeap(
    HeapHandle: *HEAP,
) callconv(.winapi) ?*HEAP;

pub extern "ntdll" fn RtlAllocateHeap(
    HeapHandle: *HEAP,
    Flags: HEAP.FLAGS.ALLOCATION,
    Size: SIZE_T,
) callconv(.winapi) ?PVOID;

pub extern "ntdll" fn RtlFreeHeap(
    HeapHandle: *HEAP,
    Flags: HEAP.FLAGS.ALLOCATION,
    BaseAddress: ?PVOID,
) callconv(.winapi) LOGICAL;

pub extern "ntdll" fn RtlCaptureStackBackTrace(
    FramesToSkip: ULONG,
    FramesToCapture: ULONG,
    BackTrace: **anyopaque,
    BackTraceHash: ?*ULONG,
) callconv(.winapi) USHORT;

pub extern "ntdll" fn RtlCaptureContext(
    ContextRecord: *CONTEXT,
) callconv(.winapi) void;

pub extern "ntdll" fn NtSetInformationThread(
    ThreadHandle: HANDLE,
    ThreadInformationClass: THREAD.INFOCLASS,
    ThreadInformation: *const anyopaque,
    ThreadInformationLength: ULONG,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtCreateFile(
    FileHandle: *HANDLE,
    DesiredAccess: ACCESS_MASK,
    ObjectAttributes: *const OBJECT.ATTRIBUTES,
    IoStatusBlock: *IO_STATUS_BLOCK,
    AllocationSize: ?*const LARGE_INTEGER,
    FileAttributes: FILE.ATTRIBUTE,
    ShareAccess: FILE.SHARE,
    CreateDisposition: FILE.CREATE_DISPOSITION,
    CreateOptions: FILE.MODE,
    EaBuffer: ?*const anyopaque,
    EaLength: ULONG,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtDeviceIoControlFile(
    FileHandle: HANDLE,
    Event: ?HANDLE,
    ApcRoutine: ?*align(2) const IO_APC_ROUTINE,
    ApcContext: ?*anyopaque,
    IoStatusBlock: *IO_STATUS_BLOCK,
    IoControlCode: CTL_CODE,
    InputBuffer: ?*const anyopaque,
    InputBufferLength: ULONG,
    OutputBuffer: ?PVOID,
    OutputBufferLength: ULONG,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtFsControlFile(
    FileHandle: HANDLE,
    Event: ?HANDLE,
    ApcRoutine: ?*align(2) const IO_APC_ROUTINE,
    ApcContext: ?*anyopaque,
    IoStatusBlock: *IO_STATUS_BLOCK,
    FsControlCode: CTL_CODE,
    InputBuffer: ?*const anyopaque,
    InputBufferLength: ULONG,
    OutputBuffer: ?PVOID,
    OutputBufferLength: ULONG,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtLockFile(
    FileHandle: HANDLE,
    Event: ?HANDLE,
    ApcRoutine: ?*align(2) const IO_APC_ROUTINE,
    ApcContext: ?*anyopaque,
    IoStatusBlock: *IO_STATUS_BLOCK,
    ByteOffset: *const LARGE_INTEGER,
    Length: *const LARGE_INTEGER,
    Key: ?*const ULONG,
    FailImmediately: BOOLEAN,
    ExclusiveLock: BOOLEAN,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtOpenFile(
    FileHandle: *HANDLE,
    DesiredAccess: ACCESS_MASK,
    ObjectAttributes: *const OBJECT.ATTRIBUTES,
    IoStatusBlock: *IO_STATUS_BLOCK,
    ShareAccess: FILE.SHARE,
    OpenOptions: FILE.MODE,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtQueryDirectoryFile(
    FileHandle: HANDLE,
    Event: ?HANDLE,
    ApcRoutine: ?*align(2) const IO_APC_ROUTINE,
    ApcContext: ?*anyopaque,
    IoStatusBlock: *IO_STATUS_BLOCK,
    FileInformation: *anyopaque,
    Length: ULONG,
    FileInformationClass: FILE.INFORMATION_CLASS,
    ReturnSingleEntry: BOOLEAN,
    FileName: ?*const UNICODE_STRING,
    RestartScan: BOOLEAN,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtQueryInformationFile(
    FileHandle: HANDLE,
    IoStatusBlock: *IO_STATUS_BLOCK,
    FileInformation: *anyopaque,
    Length: ULONG,
    FileInformationClass: FILE.INFORMATION_CLASS,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtQueryVolumeInformationFile(
    FileHandle: HANDLE,
    IoStatusBlock: *IO_STATUS_BLOCK,
    FsInformation: *anyopaque,
    Length: ULONG,
    FsInformationClass: FS_INFORMATION_CLASS,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtReadFile(
    FileHandle: HANDLE,
    Event: ?HANDLE,
    ApcRoutine: ?*align(2) const IO_APC_ROUTINE,
    ApcContext: ?*anyopaque,
    IoStatusBlock: *IO_STATUS_BLOCK,
    Buffer: *anyopaque,
    Length: ULONG,
    ByteOffset: ?*const LARGE_INTEGER,
    Key: ?*const ULONG,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtSetInformationFile(
    FileHandle: HANDLE,
    IoStatusBlock: *IO_STATUS_BLOCK,
    /// This can't be const as providing read-only memory could result in ACCESS_VIOLATION
    /// in certain scenarios. This has been seen when using FILE_DISPOSITION_INFORMATION_EX
    /// and targeting x86-windows.
    FileInformation: *anyopaque,
    Length: ULONG,
    FileInformationClass: FILE.INFORMATION_CLASS,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtWriteFile(
    FileHandle: HANDLE,
    Event: ?HANDLE,
    ApcRoutine: ?*align(2) const IO_APC_ROUTINE,
    ApcContext: ?*anyopaque,
    IoStatusBlock: *IO_STATUS_BLOCK,
    Buffer: *const anyopaque,
    Length: ULONG,
    ByteOffset: ?*const LARGE_INTEGER,
    Key: ?*const ULONG,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtUnlockFile(
    FileHandle: HANDLE,
    IoStatusBlock: *IO_STATUS_BLOCK,
    ByteOffset: *const LARGE_INTEGER,
    Length: *const LARGE_INTEGER,
    Key: ULONG,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtQueryObject(
    Handle: HANDLE,
    ObjectInformationClass: OBJECT.INFORMATION_CLASS,
    ObjectInformation: ?PVOID,
    ObjectInformationLength: ULONG,
    ReturnLength: ?*ULONG,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtClose(
    Handle: HANDLE,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtCreateSection(
    SectionHandle: *HANDLE,
    DesiredAccess: ACCESS_MASK,
    ObjectAttributes: ?*const OBJECT.ATTRIBUTES,
    MaximumSize: ?*const LARGE_INTEGER,
    SectionPageProtection: PAGE,
    AllocationAttributes: SEC,
    FileHandle: ?HANDLE,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtExtendSection(
    SectionHandle: HANDLE,
    NewSectionSize: *LARGE_INTEGER,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtAllocateVirtualMemory(
    ProcessHandle: HANDLE,
    BaseAddress: *PVOID,
    ZeroBits: ULONG_PTR,
    RegionSize: *SIZE_T,
    AllocationType: MEM.ALLOCATE,
    Protect: PAGE,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtFreeVirtualMemory(
    ProcessHandle: HANDLE,
    BaseAddress: *PVOID,
    RegionSize: *SIZE_T,
    FreeType: MEM.FREE,
) callconv(.winapi) NTSTATUS;

// ref: km/wdm.h

pub extern "ntdll" fn RtlQueryRegistryValues(
    RelativeTo: ULONG,
    Path: PCWSTR,
    QueryTable: [*]RTL_QUERY_REGISTRY_TABLE,
    Context: ?*const anyopaque,
    Environment: ?*const anyopaque,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn RtlEqualUnicodeString(
    String1: *const UNICODE_STRING,
    String2: *const UNICODE_STRING,
    CaseInSensitive: BOOLEAN,
) callconv(.winapi) BOOLEAN;

pub extern "ntdll" fn RtlUpcaseUnicodeChar(
    SourceCharacter: u16,
) callconv(.winapi) u16;

pub extern "ntdll" fn RtlFreeUnicodeString(
    UnicodeString: *UNICODE_STRING,
) callconv(.winapi) void;

pub extern "ntdll" fn RtlGetVersion(
    lpVersionInformation: *RTL_OSVERSIONINFOW,
) callconv(.winapi) NTSTATUS;

// ref: um/winnt.h

pub extern "ntdll" fn RtlLookupFunctionEntry(
    ControlPc: usize,
    ImageBase: *usize,
    HistoryTable: *UNWIND_HISTORY_TABLE,
) callconv(.winapi) ?*RUNTIME_FUNCTION;

pub extern "ntdll" fn RtlVirtualUnwind(
    HandlerType: DWORD,
    ImageBase: usize,
    ControlPc: usize,
    FunctionEntry: *RUNTIME_FUNCTION,
    ContextRecord: *CONTEXT,
    HandlerData: *?PVOID,
    EstablisherFrame: *usize,
    ContextPointers: ?*KNONVOLATILE_CONTEXT_POINTERS,
) callconv(.winapi) *EXCEPTION_ROUTINE;

// ref: um/winternl.h

pub extern "ntdll" fn NtWaitForSingleObject(
    Handle: HANDLE,
    Alertable: BOOLEAN,
    Timeout: ?*const LARGE_INTEGER,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtQueryInformationProcess(
    ProcessHandle: HANDLE,
    ProcessInformationClass: PROCESS.INFOCLASS,
    ProcessInformation: *anyopaque,
    ProcessInformationLength: ULONG,
    ReturnLength: ?*ULONG,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtQueryInformationThread(
    ThreadHandle: HANDLE,
    ThreadInformationClass: THREAD.INFOCLASS,
    ThreadInformation: *anyopaque,
    ThreadInformationLength: ULONG,
    ReturnLength: ?*ULONG,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtQuerySystemInformation(
    SystemInformationClass: SYSTEM.INFORMATION_CLASS,
    SystemInformation: PVOID,
    SystemInformationLength: ULONG,
    ReturnLength: ?*ULONG,
) callconv(.winapi) NTSTATUS;

// ref none

pub extern "ntdll" fn RtlGetActiveActivationContext(
    ActivationContext: *?HANDLE,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn RtlActivateActivationContextEx(
    Flags: ULONG,
    Teb: *TEB,
    ActivationContext: HANDLE,
    Cookie: *ULONG,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn RtlReleaseActivationContext(
    ActivationContext: HANDLE,
) callconv(.winapi) void;

pub extern "ntdll" fn LdrAddRefDll(
    Flags: ULONG,
    DllHandle: PVOID,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn LdrLoadDll(
    DllPath: ?PCWSTR,
    DllCharacteristics: ?*const ULONG,
    DllName: *const UNICODE_STRING,
    DllHandle: *PVOID,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn LdrUnloadDll(
    DllHandle: PVOID,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn LdrFindEntryForAddress(
    DllHandle: PVOID,
    Entry: **LDR.DATA_TABLE_ENTRY,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn LdrGetDllFullName(
    DllHandle: ?PVOID,
    FullDllName: *UNICODE_STRING,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn LdrGetDllPath(
    DllName: PCWSTR,
    Flags: LDR.LOAD,
    DllPath: *PWSTR,
    SearchPaths: *PWSTR,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn LdrGetDllHandle(
    DllPath: ?PCWSTR,
    DllCharacteristics: ?*const ULONG,
    DllName: *const UNICODE_STRING,
    DllHandle: *PVOID,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn LdrGetDllHandleByMapping(
    BaseAddress: PVOID,
    DllHandle: *PVOID,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn LdrGetDllHandleByName(
    BaseDllName: *const UNICODE_STRING,
    FullDllName: *const UNICODE_STRING,
    DllHandle: *PVOID,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn LdrGetDllHandleEx(
    Flags: LDR.GET_DLL_HANDLE_EX,
    DllPath: ?PCWSTR,
    DllCharacteristics: ?*const ULONG,
    DllName: *const UNICODE_STRING,
    DllHandle: *PVOID,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn LdrGetProcedureAddress(
    DllHandle: PVOID,
    ProcedureName: *const ANSI_STRING,
    ProcedureNumber: ULONG,
    ProcedureAddress: *PVOID,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn LdrGetProcedureAddressEx(
    DllHandle: PVOID,
    ProcedureName: *const ANSI_STRING,
    ProcedureNumber: ULONG,
    ProcedureAddress: *PVOID,
    Flags: LDR.GET_PROCEDURE_ADDRESS,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn LdrGetProcedureAddressForCaller(
    DllHandle: PVOID,
    ProcedureName: *const ANSI_STRING,
    ProcedureNumber: ULONG,
    ProcedureAddress: *PVOID,
    Flags: LDR.GET_PROCEDURE_ADDRESS,
    CallerAddress: PVOID,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn LdrRegisterDllNotification(
    Flags: LDR.DLL_NOTIFICATION.REGISTER,
    NotificationFunction: *const LDR.DLL_NOTIFICATION.FUNCTION,
    Context: ?PVOID,
    Cookie: *LDR.DLL_NOTIFICATION.COOKIE,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn LdrUnregisterDllNotification(
    Cookie: LDR.DLL_NOTIFICATION.COOKIE,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtQueryAttributesFile(
    ObjectAttributes: *const OBJECT.ATTRIBUTES,
    FileAttributes: *FILE.BASIC_INFORMATION,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtCreateEvent(
    EventHandle: *HANDLE,
    DesiredAccess: ACCESS_MASK,
    ObjectAttributes: ?*const OBJECT.ATTRIBUTES,
    EventType: EVENT_TYPE,
    InitialState: BOOLEAN,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtSetEvent(
    EventHandle: HANDLE,
    PreviousState: ?*LONG,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtCreateKeyedEvent(
    KeyedEventHandle: *HANDLE,
    DesiredAccess: ACCESS_MASK,
    ObjectAttributes: ?*const OBJECT.ATTRIBUTES,
    Flags: ULONG,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtReleaseKeyedEvent(
    EventHandle: ?HANDLE,
    Key: ?*const anyopaque,
    Alertable: BOOLEAN,
    Timeout: ?*const LARGE_INTEGER,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtWaitForKeyedEvent(
    EventHandle: ?HANDLE,
    Key: ?*const anyopaque,
    Alertable: BOOLEAN,
    Timeout: ?*const LARGE_INTEGER,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtCancelSynchronousIoFile(
    ThreadHandle: HANDLE,
    IoRequestToCancel: ?*IO_STATUS_BLOCK,
    IoStatusBlock: *IO_STATUS_BLOCK,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtCancelIoFile(
    FileHandle: HANDLE,
    IoStatusBlock: *IO_STATUS_BLOCK,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtCancelIoFileEx(
    FileHandle: HANDLE,
    IoRequestToCancel: *const IO_STATUS_BLOCK,
    IoStatusBlock: *IO_STATUS_BLOCK,
) callconv(.winapi) NTSTATUS;

/// This function has been observed to return SUCCESS on timeout on Windows 10
/// and TIMEOUT on Wine 10.0.
///
/// This function has been observed on Windows 11 such that positive interval
/// is real time, which can cause waits to be interrupted by changing system
/// time, however negative intervals are not affected by changes to system
/// time.
pub extern "ntdll" fn NtDelayExecution(
    Alertable: BOOLEAN,
    DelayInterval: *const LARGE_INTEGER,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtNotifyChangeDirectoryFileEx(
    FileHandle: HANDLE,
    Event: ?HANDLE,
    ApcRoutine: ?*align(2) const IO_APC_ROUTINE,
    ApcContext: ?*anyopaque,
    IoStatusBlock: *IO_STATUS_BLOCK,
    Buffer: *anyopaque,
    Length: ULONG,
    CompletionFilter: FILE.NOTIFY.CHANGE,
    WatchTree: BOOLEAN,
    DirectoryNotifyInformationClass: DIRECTORY.NOTIFY_INFORMATION_CLASS,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtOpenThread(
    ThreadHandle: *HANDLE,
    DesiredAccess: ACCESS_MASK,
    ObjectAttributes: *const OBJECT.ATTRIBUTES,
    ClientId: *const windows.CLIENT_ID,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtCreateNamedPipeFile(
    FileHandle: *HANDLE,
    DesiredAccess: ACCESS_MASK,
    ObjectAttributes: *const OBJECT.ATTRIBUTES,
    IoStatusBlock: *IO_STATUS_BLOCK,
    ShareAccess: FILE.SHARE,
    CreateDisposition: FILE.CREATE_DISPOSITION,
    CreateOptions: FILE.MODE,
    NamedPipeType: FILE.PIPE.TYPE,
    ReadMode: FILE.PIPE.READ_MODE,
    CompletionMode: FILE.PIPE.COMPLETION_MODE,
    MaximumInstances: ULONG,
    InboundQuota: ULONG,
    OutboundQuota: ULONG,
    DefaultTimeout: ?*const LARGE_INTEGER,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtFlushBuffersFile(
    FileHandle: HANDLE,
    IoStatusBlock: *IO_STATUS_BLOCK,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtMapViewOfSection(
    SectionHandle: HANDLE,
    ProcessHandle: HANDLE,
    BaseAddress: ?*PVOID,
    ZeroBits: ?*const ULONG,
    CommitSize: SIZE_T,
    SectionOffset: ?*LARGE_INTEGER,
    ViewSize: *SIZE_T,
    InheritDispostion: SECTION_INHERIT,
    AllocationType: MEM.MAP,
    PageProtection: PAGE,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtUnmapViewOfSection(
    ProcessHandle: HANDLE,
    BaseAddress: PVOID,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtUnmapViewOfSectionEx(
    ProcessHandle: HANDLE,
    BaseAddress: PVOID,
    UnmapFlags: MEM.UNMAP,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtOpenKey(
    KeyHandle: *HANDLE,
    DesiredAccess: ACCESS_MASK,
    ObjectAttributes: *const OBJECT.ATTRIBUTES,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtQueueApcThread(
    ThreadHandle: HANDLE,
    ApcRoutine: *const IO_APC_ROUTINE,
    ApcArgument1: ?*anyopaque,
    ApcArgument2: ?*anyopaque,
    ApcArgument3: ?*anyopaque,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtReadVirtualMemory(
    ProcessHandle: HANDLE,
    BaseAddress: ?PVOID,
    Buffer: LPVOID,
    NumberOfBytesToRead: SIZE_T,
    NumberOfBytesRead: ?*SIZE_T,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtWriteVirtualMemory(
    ProcessHandle: HANDLE,
    BaseAddress: ?PVOID,
    Buffer: LPCVOID,
    NumberOfBytesToWrite: SIZE_T,
    NumberOfBytesWritten: ?*SIZE_T,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtProtectVirtualMemory(
    ProcessHandle: HANDLE,
    BaseAddress: *?PVOID,
    NumberOfBytesToProtect: *SIZE_T,
    NewAccessProtection: PAGE,
    OldAccessProtection: *PAGE,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtWaitForAlertByThreadId(
    Address: ?*const anyopaque,
    Timeout: ?*const LARGE_INTEGER,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtAlertThreadByThreadId(ThreadId: DWORD) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtAlertThread(ThreadHandle: HANDLE) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtAlertMultipleThreadByThreadId(
    ThreadIds: [*]const ULONG_PTR,
    ThreadCount: ULONG,
    Unknown1: ?*const anyopaque,
    Unknown2: ?*const anyopaque,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtYieldExecution() callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn RtlAddVectoredExceptionHandler(
    First: ULONG,
    Handler: ?VECTORED_EXCEPTION_HANDLER,
) callconv(.winapi) ?LPVOID;
pub extern "ntdll" fn RtlRemoveVectoredExceptionHandler(
    Handle: HANDLE,
) callconv(.winapi) ULONG;

pub extern "ntdll" fn RtlDosPathNameToNtPathName_U(
    DosPathName: [*:0]const u16,
    NtPathName: *UNICODE_STRING,
    NtFileNamePart: ?*?[*:0]const u16,
    DirectoryInfo: ?*CURDIR,
) callconv(.winapi) BOOL;

pub extern "ntdll" fn RtlExitUserProcess(
    ExitStatus: u32,
) callconv(.winapi) noreturn;

/// Returns the number of bytes written to `Buffer`.
/// If the returned count is larger than `BufferByteLength`, the buffer was too small.
/// If the returned count is zero, an error occurred.
pub extern "ntdll" fn RtlGetFullPathName_U(
    FileName: [*:0]const u16,
    BufferByteLength: ULONG,
    Buffer: [*]u16,
    ShortName: ?*[*:0]const u16,
) callconv(.winapi) ULONG;

pub extern "ntdll" fn RtlGetCurrentDirectory_U(
    BufferByteLength: ULONG,
    Buffer: [*]u16,
) callconv(.winapi) ULONG;

pub extern "ntdll" fn RtlGetSystemTimePrecise() callconv(.winapi) LARGE_INTEGER;

pub extern "ntdll" fn RtlInitializeCriticalSection(
    lpCriticalSection: *CRITICAL_SECTION,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn RtlEnterCriticalSection(
    lpCriticalSection: *CRITICAL_SECTION,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn RtlLeaveCriticalSection(
    lpCriticalSection: *CRITICAL_SECTION,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn RtlDeleteCriticalSection(
    lpCriticalSection: *CRITICAL_SECTION,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn RtlQueryPerformanceCounter(
    PerformanceCounter: *LARGE_INTEGER,
) callconv(.winapi) BOOL;
pub extern "ntdll" fn RtlQueryPerformanceFrequency(
    PerformanceFrequency: *LARGE_INTEGER,
) callconv(.winapi) BOOL;

pub extern "ntdll" fn RtlReAllocateHeap(
    HeapHandle: *HEAP,
    Flags: HEAP.FLAGS.ALLOCATION,
    BaseAddress: ?PVOID,
    Size: SIZE_T,
) callconv(.winapi) ?PVOID;

pub extern "ntdll" fn RtlReportSilentProcessExit(
    ProcessHandle: HANDLE,
    ExitStatus: NTSTATUS,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtTerminateProcess(
    ProcessHandle: ?HANDLE,
    ExitStatus: NTSTATUS,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn RtlSetCurrentDirectory_U(
    PathName: *const UNICODE_STRING,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn RtlTryAcquireSRWLockExclusive(
    SRWLock: *SRWLOCK,
) callconv(.winapi) BOOLEAN;
pub extern "ntdll" fn RtlAcquireSRWLockExclusive(
    SRWLock: *SRWLOCK,
) callconv(.winapi) void;
pub extern "ntdll" fn RtlReleaseSRWLockExclusive(
    SRWLock: *SRWLOCK,
) callconv(.winapi) void;

pub extern "ntdll" fn RtlWakeAddressAll(
    Address: ?*const anyopaque,
) callconv(.winapi) void;
pub extern "ntdll" fn RtlWakeAddressSingle(
    Address: ?*const anyopaque,
) callconv(.winapi) void;
pub extern "ntdll" fn RtlWaitOnAddress(
    Address: ?*const anyopaque,
    CompareAddress: ?*const anyopaque,
    AddressSize: SIZE_T,
    Timeout: ?*const LARGE_INTEGER,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn RtlWakeConditionVariable(
    ConditionVariable: *CONDITION_VARIABLE,
) callconv(.winapi) void;
pub extern "ntdll" fn RtlWakeAllConditionVariable(
    ConditionVariable: *CONDITION_VARIABLE,
) callconv(.winapi) void;

pub extern "ntdll" fn NtOpenKeyEx(
    KeyHandle: *HANDLE,
    DesiredAccess: ACCESS_MASK,
    ObjectAttributes: *const OBJECT.ATTRIBUTES,
    OpenOptions: REG.OpenOptions,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn RtlOpenCurrentUser(
    DesiredAccess: ACCESS_MASK,
    CurrentUserKey: *HANDLE,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtQueryValueKey(
    KeyHandle: HANDLE,
    ValueName: *const UNICODE_STRING,
    KeyValueInformationClass: KEY.VALUE.INFORMATION_CLASS,
    KeyValueInformation: *anyopaque,
    /// Length of KeyValueInformation buffer in bytes
    Length: ULONG,
    /// On STATUS_SUCCESS, contains the length of the populated portion of the
    /// provided buffer. On STATUS_BUFFER_OVERFLOW or STATUS_BUFFER_TOO_SMALL,
    /// contains the minimum `Length` value that would be required to hold the information.
    ResultLength: *ULONG,
) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtLoadKeyEx(
    TargetKey: *const OBJECT.ATTRIBUTES,
    SourceFile: *const OBJECT.ATTRIBUTES,
    Flags: REG.LoadOptions,
    TrustClassKey: ?HANDLE,
    Event: ?HANDLE,
    DesiredAccess: ACCESS_MASK,
    RootHandle: ?*HANDLE,
    Reserved: ?*anyopaque,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtCreateThreadEx(
    ThreadHandle: *HANDLE,
    DesiredAccess: ACCESS_MASK,
    ObjectAttributes: *const OBJECT.ATTRIBUTES,
    ProcessHandle: HANDLE,
    StartRoutine: *const USER_THREAD_START_ROUTINE,
    Argument: ?PVOID,
    CreateFlags: THREAD.CREATE_FLAGS,
    ZeroBits: SIZE_T,
    /// This value is rounded up to the nearest page.
    /// If this value is larger than `StackReserve`, the reserved stack
    /// size will be the rounded value of this parameter.
    /// https://learn.microsoft.com/en-us/windows/win32/procthread/thread-stack-size
    StackCommit: THREAD.StackSize,
    StackReserve: THREAD.StackSize,
    AttributeList: ?*PS.ATTRIBUTE.LIST,
) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn NtResumeThread(
    ThreadHandle: HANDLE,
    PreviousSuspendCount: ?*ULONG,
) callconv(.winapi) NTSTATUS;
