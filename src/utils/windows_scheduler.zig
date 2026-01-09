const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;
const main = @import("main");

// Resolution is in 100ns units
var initialResolution: windows.ULONG = undefined;
var minResolution: windows.ULONG = undefined;
var maxResolution: windows.ULONG = undefined;
var currentResolution: windows.ULONG = undefined;

pub fn increaseTimerResolution() void {
	std.debug.assert(builtin.os.tag == .windows);

	_ = NtQueryTimerResolution(&minResolution, &maxResolution, &initialResolution);
	_ = NtSetTimerResolution(maxResolution, 1, &currentResolution);

	std.log.info("Set system timer resolution: {d} -> {d}.", .{initialResolution, currentResolution});
}

pub fn resetTimerResolution() void {
	std.debug.assert(builtin.os.tag == .windows);

	_ = NtSetTimerResolution(initialResolution, 1, &currentResolution);

	std.log.info("Reset system timer resolution: {d}.", .{initialResolution});
}

pub fn preciseSleep(sleepDuration: std.Io.Duration) void {
	std.debug.assert(builtin.os.tag == .windows);

	const start = main.timestamp();
	const targetTime = start.addDuration(sleepDuration);

	// Update currentResolution because it can change
	_ = NtQueryTimerResolution(&minResolution, &maxResolution, &currentResolution);

	// Negative value for relative time
	var delayInterval = -(@divFloor(@as(windows.LARGE_INTEGER, @intCast(sleepDuration.nanoseconds)), 100) - currentResolution);
	if(delayInterval < 0) {
		_ = NtDelayExecution(windows.FALSE, &delayInterval);
	}

	const end = main.timestamp();
	if(targetTime.durationTo(end).nanoseconds > currentResolution*100) {
		const desired = @as(f64, @floatFromInt(sleepDuration.nanoseconds))/1_000_000;
		const actual = @as(f64, @floatFromInt(start.durationTo(end).nanoseconds))/1_000_000;
		std.log.warn("Overslept: Desired duration: {d:.2}ms, Actual duration: {d:.2}ms, Timer resolution: {d}", .{desired, actual, currentResolution});
	}

	while(main.timestamp().durationTo(targetTime).nanoseconds > 0) {
		std.atomic.spinLoopHint();
	}
}

pub const PriorityClass = enum(u32) {
	idle = 0x00000040,
	below_normal = 0x00004000,
	normal = 0x00000020,
	above_normal = 0x00008000,
	high = 0x00000080,
	realtime = 0x00000100,

	pub fn displayName(self: PriorityClass) []const u8 {
		return switch(self) {
			.idle => "Idle",
			.below_normal => "Below Normal",
			.normal => "Normal",
			.above_normal => "Above Normal",
			.high => "High",
			.realtime => "Realtime",
		};
	}
};

pub fn setPriorityClass(priority: PriorityClass) void {
	if(SetPriorityClass(windows.GetCurrentProcess(), @intFromEnum(priority)) == 0) {
		std.log.warn("Failed to set process priority class: {s}'", .{priority.displayName()});
	} else {
		std.log.info("Set process priority class: {s}", .{priority.displayName()});
	}
}

extern "ntdll" fn NtQueryTimerResolution(MinimumResolution: *windows.ULONG, MaximumResolution: *windows.ULONG, CurrentResolution: *windows.ULONG) callconv(.winapi) windows.NTSTATUS;

extern "ntdll" fn NtSetTimerResolution(
	DesiredResolution: windows.ULONG,
	SetResolution: windows.BOOLEAN,
	CurrentResolution: *windows.ULONG,
) callconv(.winapi) windows.NTSTATUS;

extern "ntdll" fn NtDelayExecution(
	Alertable: windows.BOOLEAN,
	DelayInterval: *windows.LARGE_INTEGER,
) callconv(.winapi) windows.NTSTATUS;

extern "kernel32" fn SetPriorityClass(hProcess: windows.HANDLE, dwPriorityClass: windows.DWORD) callconv(.winapi) c_int;
