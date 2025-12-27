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
	_ = NtSetTimerResolution(@max(10000, maxResolution), 1, &currentResolution);
	
    if(initialResolution != currentResolution) {
		const initialMs = @as(f32, @floatFromInt(initialResolution))/10000;
		const currentMs = @as(f32, @floatFromInt(currentResolution))/10000;
    	std.log.info("Changed system timer resolution from {d:.1} to {d:.1}ms.", .{initialMs, currentMs});
	}
}

pub fn deinit() void {
    std.debug.assert(builtin.os.tag == .windows);

	_ = NtSetTimerResolution(initialResolution, 1, &currentResolution);
}

pub fn sleep(sleepDuration: std.Io.Duration) void {
    std.debug.assert(builtin.os.tag == .windows);

    const start = main.timestamp();
    const targetTime = main.timestamp().addDuration(sleepDuration);

	// The timer uses 100ns units
	const sleepTime = @divFloor(@as(windows.LARGE_INTEGER, @intCast(sleepDuration.nanoseconds)), 10000);
	_ = NtDelayExecution(windows.FALSE, -sleepTime); // Negative for relative time

    const end = main.timestamp();
    if(main.timestamp().durationTo(targetTime).nanoseconds < 0) {
        std.log.warn("Desired sleep: {d}, Actual sleep: {d}", .{sleepDuration.nanoseconds, start.durationTo(end).nanoseconds});
    }
	while(main.timestamp().durationTo(targetTime).nanoseconds > 0) {}
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
	DelayInterval: std.os.windows.LARGE_INTEGER,
) callconv(.winapi) windows.NTSTATUS;

