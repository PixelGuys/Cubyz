const std = @import("std");
const builtin = @import("builtin");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ZonElement = main.ZonElement;

pub fn openDirInWindow(path: []const u8) void {
	const newPath = main.stackAllocator.dupe(u8, path);
	defer main.stackAllocator.free(newPath);

	if (builtin.os.tag == .windows) {
		std.mem.replaceScalar(u8, newPath, '/', '\\');
	}

	const command = switch (builtin.os.tag) {
		.windows => .{"explorer", newPath},
		.macos => .{"open", newPath},
		else => .{"xdg-open", newPath},
	};
	var envMap = main.settings.environment.env.createMap(main.stackAllocator.allocator) catch |err| blk: {
		std.log.err("Failed to get environment map: {s}", .{@errorName(err)});
		break :blk std.process.Environ.Map.init(main.stackAllocator.allocator);
	};
	defer envMap.deinit();
	const result = std.process.run(main.stackAllocator.allocator, main.io, .{
		.argv = &command,
		.environ_map = &envMap,
	}) catch |err| {
		std.log.err("Got error while trying to open file explorer: {s}", .{@errorName(err)});
		return;
	};
	defer {
		main.stackAllocator.free(result.stderr);
		main.stackAllocator.free(result.stdout);
	}
	if (result.stderr.len != 0) {
		std.log.err("Got error while trying to open file explorer: {s}", .{result.stderr});
	}
}

pub fn cwd() Dir {
	return Dir{
		.dir = std.Io.Dir.cwd(),
	};
}

var cubyzDir_: ?std.Io.Dir = null;
var cubyzDirStr_: []const u8 = ".";

pub fn cubyzDir() Dir {
	return .{
		.dir = cubyzDir_ orelse std.Io.Dir.cwd(),
	};
}

pub fn cubyzDirStr() []const u8 {
	return cubyzDirStr_;
}

fn flawedInit(homePath: []const u8) !void {
	if (main.settings.launchConfig.cubyzDir.len != 0) {
		cubyzDir_ = try std.Io.Dir.cwd().createDirPathOpen(main.io, main.settings.launchConfig.cubyzDir, .{});
		cubyzDirStr_ = main.globalAllocator.dupe(u8, main.settings.launchConfig.cubyzDir);
		return;
	}
	var homeDir = try std.Io.Dir.openDirAbsolute(main.io, homePath, .{});
	defer homeDir.close(main.io);
	if (builtin.os.tag == .windows) {
		cubyzDir_ = try homeDir.createDirPathOpen(main.io, "Saved Games/Cubyz", .{});
		cubyzDirStr_ = std.mem.concat(main.globalAllocator.allocator, u8, &.{homePath, "/Saved Games/Cubyz"}) catch unreachable;
	} else {
		cubyzDir_ = try homeDir.createDirPathOpen(main.io, ".cubyz", .{});
		cubyzDirStr_ = std.mem.concat(main.globalAllocator.allocator, u8, &.{homePath, "/.cubyz"}) catch unreachable;
	}
}

pub fn init(homePath: []const u8) void {
	flawedInit(homePath) catch |err| {
		std.log.err("Error {s} while opening global Cubyz directory. Using working directory instead.", .{@errorName(err)});
	};
}

pub fn deinit() void {
	if (cubyzDir_ != null) {
		cubyzDir_.?.close(main.io);
	}
	if (cubyzDirStr_.ptr != ".".ptr) {
		main.globalAllocator.free(cubyzDirStr_);
	}
}

pub const Dir = struct {
	dir: std.Io.Dir,

	pub fn init(dir: std.Io.Dir) Dir {
		return .{.dir = dir};
	}

	pub fn close(self: *Dir) void {
		self.dir.close(main.io);
	}

	pub fn read(self: Dir, allocator: NeverFailingAllocator, subPath: []const u8) ![]u8 {
		return self.dir.readFileAlloc(main.io, subPath, allocator.allocator, .unlimited);
	}

	pub fn readToZon(self: Dir, allocator: NeverFailingAllocator, subPath: []const u8) !ZonElement {
		const string = try self.read(main.stackAllocator, subPath);
		defer main.stackAllocator.free(string);
		const realPath: ?[:0]const u8 = self.dir.realPathFileAlloc(main.io, subPath, main.stackAllocator.allocator) catch null;
		defer if (realPath) |p| main.stackAllocator.free(p);
		return ZonElement.parseFromString(allocator, realPath orelse subPath, string);
	}

	pub fn write(self: Dir, path: []const u8, data: []const u8) !void {
		const tempPath = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}.tmp0", .{path}) catch unreachable;
		defer main.stackAllocator.free(tempPath);

		try self.dir.writeFile(main.io, .{.data = data, .sub_path = tempPath});

		return self.dir.rename(tempPath, self.dir, path, main.io);
	}

	pub fn writeZon(self: Dir, path: []const u8, zon: ZonElement) !void {
		const string = zon.toString(main.stackAllocator);
		defer main.stackAllocator.free(string);
		try self.write(path, string);
	}

	pub fn hasFile(self: Dir, subPath: []const u8) bool {
		const file = self.dir.openFile(main.io, subPath, .{}) catch return false;
		file.close(main.io);
		return true;
	}

	pub fn hasDir(self: Dir, subPath: []const u8) bool {
		var dir = self.dir.openDir(main.io, subPath, .{.iterate = false}) catch return false;
		dir.close(main.io);
		return true;
	}

	pub fn openDir(self: Dir, subPath: []const u8) !Dir {
		return .{.dir = try self.dir.createDirPathOpen(main.io, subPath, .{})};
	}

	pub fn openIterableDir(self: Dir, subPath: []const u8) !Dir {
		return .{.dir = try self.dir.createDirPathOpen(main.io, subPath, .{.open_options = .{.iterate = true}})};
	}

	pub fn openFile(self: Dir, subPath: []const u8) !std.Io.File {
		return self.dir.openFile(main.io, subPath, .{});
	}

	pub fn deleteTree(self: Dir, subPath: []const u8) !void {
		try self.dir.deleteTree(main.io, subPath);
	}

	pub fn deleteFile(self: Dir, subPath: []const u8) !void {
		try self.dir.deleteFile(main.io, subPath);
	}

	pub fn makePath(self: Dir, subPath: []const u8) !void {
		try self.dir.createDirPath(main.io, subPath);
	}

	pub fn walk(self: Dir, allocator: NeverFailingAllocator) std.Io.Dir.Walker {
		return self.dir.walk(allocator.allocator) catch unreachable;
	}

	pub fn iterate(self: Dir) std.Io.Dir.Iterator {
		return self.dir.iterate();
	}
};
