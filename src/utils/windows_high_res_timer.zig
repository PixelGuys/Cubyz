const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;
const main = @import("main");

var initialResolution: windows.ULONG = undefined;
var minResolution: windows.ULONG = undefined;
var maxResolution: windows.ULONG = undefined;
var currentResolution: windows.ULONG = undefined;

pub fn init() void {
    std.debug.assert(builtin.os.tag == .windows);

	_ = NtQueryTimerResolution(&minResolution, &maxResolution, &initialResolution);
	_ = NtSetTimerResolution(10000,  1, &currentResolution);
	
    if(initialResolution != currentResolution) {
		const initialMs = @as(f32, @floatFromInt(initialResolution))/10_000;
		const currentMs = @as(f32, @floatFromInt(currentResolution))/10_000;
    	std.log.info("Changed system timer resolution from {d:.1}ms to {d:.1}ms.", .{initialMs, currentMs});
	}
	
    //const highPriorityClass = 0x00000080;
	//if (SetPriorityClass(windows.GetCurrentProcess(), highPriorityClass) == 0) {
    //    std.log.warn("Failed to set process priority to High", .{});
    //} else {
    //    std.log.debug("Process priority set to High", .{});
   // }
}

pub fn deinit() void {
    std.debug.assert(builtin.os.tag == .windows);

	_ = NtSetTimerResolution(initialResolution, 1, &currentResolution);
}

pub fn sleep(sleepDuration: std.Io.Duration) void {
    std.debug.assert(builtin.os.tag == .windows);

    const start = main.timestamp();

	var delayInterval = -(@divFloor(@as(windows.LARGE_INTEGER, @intCast(sleepDuration.nanoseconds)), 100) - currentResolution);
	if(delayInterval < 0) {
		_ = NtDelayExecution(windows.FALSE, &delayInterval);
	}

    const end = main.timestamp();
    if(start.durationTo(end).nanoseconds - sleepDuration.nanoseconds > 1_000_000) {
		const desired = @as(f64, @floatFromInt(sleepDuration.nanoseconds)) / 1_000_000;
		const actual = @as(f64, @floatFromInt(start.durationTo(end).nanoseconds)) / 1_000_000;
		_ = NtQueryTimerResolution(&minResolution, &maxResolution, &currentResolution);
        std.log.debug("Desired sleep: {d:.1}ms, Actual sleep: {d:.1}ms, Timer resolution: {d}", .{desired, actual, currentResolution});
    }

    const targetTime = start.addDuration(sleepDuration);
	while(main.timestamp().durationTo(targetTime).nanoseconds > 0) {
		std.atomic.spinLoopHint();
	}
}

extern "ntdll" fn NtQueryTimerResolution(
	MinimumResolution: *windows.ULONG,
	MaximumResolution: *windows.ULONG,
	CurrentResolution: *windows.ULONG
) callconv(.winapi) windows.NTSTATUS;

extern "ntdll" fn NtSetTimerResolution(
	DesiredResolution: windows.ULONG,
	SetResolution: windows.BOOLEAN,
	CurrentResolution: *windows.ULONG,	
) callconv(.winapi) windows.NTSTATUS;

extern "ntdll" fn NtDelayExecution(
	Alertable: windows.BOOLEAN,
	DelayInterval: *windows.LARGE_INTEGER,
) callconv(.winapi) windows.NTSTATUS;

extern "kernel32" fn SetPriorityClass(
	hProcess: windows.HANDLE,
	dwPriorityClass: windows.DWORD
) callconv(.winapi) c_int;
