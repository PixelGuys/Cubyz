const std = @import("std");
const builtin = @import("builtin");
const main = @import("main");

// We use this variable to check if some time has passed since last detectLowRam() call
// to avoid requesting the OS for available RAM every frame.
var detectLowRamLastCheck: f64 = 0;

var detectLowRamDisabled: bool = false;

var lastAvailableRam: ?usize = null;

fn getAvailableRamLinux() error{GettingAvailableRamFailed}!usize {
	const meminfoFile = main.files.cwd().openFile("/proc/meminfo") catch |err| {
		std.log.err("Failed to read /proc/meminfo: {s}", .{@errorName(err)});
		return error.GettingAvailableRamFailed;
	};
	defer meminfoFile.close(main.io);

	var buf: [1024]u8 = undefined;
	var reader: std.Io.File.Reader = meminfoFile.reader(main.io, &buf);

	while (reader.interface.takeDelimiter('\n') catch |err| {
		std.log.err("Failed to parse /proc/meminfo: {s}", .{@errorName(err)});
		return error.GettingAvailableRamFailed;
	}) |line| {
		if (std.mem.startsWith(u8, line, "MemAvailable")) {
			var iter = std.mem.tokenizeScalar(u8, line, ' ');
			_ = iter.next();
			const mem = iter.next() orelse {
				std.log.err("Failed to parse /proc/meminfo: missing memory amount", .{});
				return error.GettingAvailableRamFailed;
			};
			const unit = iter.next() orelse {
				std.log.err("Failed to parse /proc/meminfo: missing memory unit", .{});
				return error.GettingAvailableRamFailed;
			};

			if (std.fmt.parseInt(usize, mem, 10)) |memInt| {
				if (std.mem.eql(u8, unit, "kB")) {
					return memInt*1024;
				} else {
					std.log.err("Failed to parse /proc/meminfo: unexpected memory unit", .{});
					return error.GettingAvailableRamFailed;
				}
			} else |err| {
				std.log.err("Failed to parse /proc/meminfo: parsing memory amount failed: {s}", .{@errorName(err)});
				return error.GettingAvailableRamFailed;
			}
		}
	}

	return error.GettingAvailableRamFailed;
}

pub fn detectLowRam(deltaTime: f64) void {
	if (detectLowRamDisabled) return;

	detectLowRamLastCheck += deltaTime;

	// Make 1 second pause between each update
	if (detectLowRamLastCheck > 1.0) {
		detectLowRamLastCheck = 0.0;

		const availableRam = switch (builtin.os.tag) {
			.linux => getAvailableRamLinux(),
			else => |os| {
				detectLowRamDisabled = true;
				std.log.warn("Low RAM detector has not been implemented for your platform: {s}", .{@tagName(os)});
				return;
			},
		} catch |err| {
			detectLowRamDisabled = true;
			std.log.err("Failed to detect available RAM amount: {s}", .{@errorName(err)});
			return;
		};

		lastAvailableRam = availableRam;
	}

	if (lastAvailableRam) |ram| {
		if (ram < main.settings.alertLowRamBytes) {
			const oldScale = main.graphics.draw.setScale(main.gui.scale);
			defer main.graphics.draw.restoreScale(oldScale);
			const oldColor = main.graphics.draw.setColor(0xffff0000);
			defer main.graphics.draw.restoreColor(oldColor);
			main.graphics.draw.print("Warning: Only {d} MiB of RAM available!", .{ram/(1024*1024)}, 4, 4, 16);
		}
	}
}
