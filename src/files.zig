const std = @import("std");
const builtin = @import("builtin");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ZonElement = main.ZonElement;

pub fn openDirInWindow(path: []const u8) void {
	const newPath = main.stackAllocator.dupe(u8, path);
	defer main.stackAllocator.free(newPath);

	if(builtin.os.tag == .windows) {
		std.mem.replaceScalar(u8, newPath, '/', '\\');
	}

	const command = switch(builtin.os.tag) {
		.windows => .{"explorer", newPath},
		.macos => .{"open", newPath},
		else => .{"xdg-open", newPath},
	};
	const result = std.process.Child.run(.{
		.allocator = main.stackAllocator.allocator,
		.argv = &command,
	}) catch |err| {
		std.log.err("Got error while trying to open file explorer: {s}", .{@errorName(err)});
		return;
	};
	defer {
		main.stackAllocator.free(result.stderr);
		main.stackAllocator.free(result.stdout);
	}
	if(result.stderr.len != 0) {
		std.log.err("Got error while trying to open file explorer: {s}", .{result.stderr});
	}
}

pub fn cwd() Dir {
	return Dir{
		.dir = std.fs.cwd(),
	};
}

var cubyzDir_: ?std.fs.Dir = null;
var cubyzDirStr_: []const u8 = ".";

pub fn cubyzDir() Dir {
	return .{
		.dir = cubyzDir_ orelse std.fs.cwd(),
	};
}

pub fn cubyzDirStr() []const u8 {
	return cubyzDirStr_;
}

fn flawedInit() !void {
	if(main.settings.launchConfig.cubyzDir.len != 0) {
		cubyzDir_ = try std.fs.cwd().makeOpenPath(main.settings.launchConfig.cubyzDir, .{});
		cubyzDirStr_ = main.globalAllocator.dupe(u8, main.settings.launchConfig.cubyzDir);
		return;
	}
	const homePath = try std.process.getEnvVarOwned(main.stackAllocator.allocator, if(builtin.os.tag == .windows) "USERPROFILE" else "HOME");
	defer main.stackAllocator.free(homePath);
	var homeDir = try std.fs.openDirAbsolute(homePath, .{});
	defer homeDir.close();
	if(builtin.os.tag == .windows) {
		cubyzDir_ = try homeDir.makeOpenPath("Saved Games/Cubyz", .{});
		cubyzDirStr_ = std.mem.concat(main.globalAllocator.allocator, u8, &.{homePath, "/Saved Games/Cubyz"}) catch unreachable;
	} else {
		cubyzDir_ = try homeDir.makeOpenPath(".cubyz", .{});
		cubyzDirStr_ = std.mem.concat(main.globalAllocator.allocator, u8, &.{homePath, "/.cubyz"}) catch unreachable;
	}
}

pub fn init() void {
	flawedInit() catch |err| {
		std.log.err("Error {s} while opening global Cubyz directory. Using working directory instead.", .{@errorName(err)});
	};
}

pub fn deinit() void {
	if(cubyzDir_ != null) {
		cubyzDir_.?.close();
	}
	if(cubyzDirStr_.ptr != ".".ptr) {
		main.globalAllocator.free(cubyzDirStr_);
	}
}

pub const Dir = struct {
	dir: std.fs.Dir,

	pub fn init(dir: std.fs.Dir) Dir {
		return .{.dir = dir};
	}

	pub fn close(self: *Dir) void {
		self.dir.close();
	}

	pub fn read(self: Dir, allocator: NeverFailingAllocator, path: []const u8) ![]u8 {
		return self.dir.readFileAlloc(allocator.allocator, path, std.math.maxInt(usize));
	}

	pub fn readToZon(self: Dir, allocator: NeverFailingAllocator, path: []const u8) !ZonElement {
		const string = try self.read(main.stackAllocator, path);
		defer main.stackAllocator.free(string);
		const realPath: ?[]const u8 = self.dir.realpathAlloc(main.stackAllocator.allocator, path) catch null;
		defer if(realPath) |p| main.stackAllocator.free(p);
		return ZonElement.parseFromString(allocator, realPath orelse path, string);
	}

	pub fn write(self: Dir, path: []const u8, data: []const u8) !void {
		return self.dir.writeFile(.{.data = data, .sub_path = path});
	}

	pub fn writeZon(self: Dir, path: []const u8, zon: ZonElement) !void {
		const string = zon.toString(main.stackAllocator);
		defer main.stackAllocator.free(string);
		try self.write(path, string);
	}

	pub fn hasFile(self: Dir, path: []const u8) bool {
		const file = self.dir.openFile(path, .{}) catch return false;
		file.close();
		return true;
	}

	pub fn hasDir(self: Dir, path: []const u8) bool {
		var dir = self.dir.openDir(path, .{.iterate = false}) catch return false;
		dir.close();
		return true;
	}

	pub fn openDir(self: Dir, path: []const u8) !Dir {
		return .{.dir = try self.dir.makeOpenPath(path, .{})};
	}

	pub fn openIterableDir(self: Dir, path: []const u8) !Dir {
		return .{.dir = try self.dir.makeOpenPath(path, .{.iterate = true})};
	}

	pub fn openFile(self: Dir, path: []const u8) !std.fs.File {
		return self.dir.openFile(path, .{});
	}

	pub fn deleteTree(self: Dir, path: []const u8) !void {
		try self.dir.deleteTree(path);
	}

	pub fn deleteFile(self: Dir, path: []const u8) !void {
		try self.dir.deleteFile(path);
	}

	pub fn makePath(self: Dir, path: []const u8) !void {
		try self.dir.makePath(path);
	}

	pub fn walk(self: Dir, allocator: NeverFailingAllocator) std.fs.Dir.Walker {
		return self.dir.walk(allocator.allocator) catch unreachable;
	}

	pub fn iterate(self: Dir) std.fs.Dir.Iterator {
		return self.dir.iterate();
	}
};
