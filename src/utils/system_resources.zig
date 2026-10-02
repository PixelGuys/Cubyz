const std = @import("std");
const builtin = @import("builtin");
const main = @import("main");

pub var notifiedAboutLowRam: bool = false;

var detectLowRamLastCheck: i64 = 0;

pub fn detectLowRam() void {
	const now = main.timestamp().toMilliseconds();

	// Make 1000 millisecond pause between each check
	if ((detectLowRamLastCheck + 1000) < now) {
		detectLowRamLastCheck = now;
	} else return;

	const memLeftOrNull: ?usize = blk: switch (builtin.os.tag) {
		.linux => {
			const meminfoFile = main.files.cwd().openFile("/proc/meminfo") catch |err| {
				std.log.err("Failed to read /proc/meminfo: {s}", .{@errorName(err)});
				return;
			};
			defer meminfoFile.close(main.io);

			var buf: [1024]u8 = undefined;
			var reader: std.Io.File.Reader = meminfoFile.reader(main.io, &buf);

			while (reader.interface.takeDelimiter('\n') catch |err| {
				std.log.err("Failed to parse /proc/meminfo: {s}", .{@errorName(err)});
				return;
			}) |line| {
				if (std.mem.startsWith(u8, line, "MemAvailable")) {
					var iter = std.mem.tokenizeScalar(u8, line, ' ');
					_ = iter.next();
					const mem = iter.next() orelse {
						std.log.err("Failed to parse /proc/meminfo: missing memory amount", .{});
						return;
					};
					const unit = iter.next() orelse {
						std.log.err("Failed to parse /proc/meminfo: missing memory unit", .{});
						return;
					};

					if (std.fmt.parseInt(usize, mem, 10)) |memInt| {
						if (std.mem.eql(u8, unit, "kB")) {
							break :blk memInt;
						} else {
							std.log.err("Failed to parse /proc/meminfo: unexpected memory unit", .{});
							return;
						}
					} else |err| {
						std.log.err("Failed to parse /proc/meminfo: parsing memory amount failed: {s}", .{@errorName(err)});
						return;
					}
					break;
				}
			}
			break :blk null;
		},
		else => null,
	};

	if (memLeftOrNull) |memLeft| {
		if (memLeft < main.settings.alertLowRamKiB) {
			if (!notifiedAboutLowRam) {
				main.gui.windowlist.notification.raiseNotification(
					"Warning!\nSystem has less than {d} MiB RAM memory left!",
					.{main.settings.alertLowRamKiB/1024},
				);
				notifiedAboutLowRam = true;
			}
		} else {
			// Reset when value dropped a bit below alert value to avoid constant popups
			if (memLeft > main.settings.alertLowRamKiB + (main.settings.alertLowRamKiB/20)) {
				notifiedAboutLowRam = false;
			}
		}
	}
}
