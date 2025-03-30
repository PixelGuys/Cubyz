const std = @import("std");
const builtin = @import("builtin");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ZonElement = main.ZonElement;

pub fn read(allocator: NeverFailingAllocator, path: []const u8) ![]u8 {
	return cwd().read(allocator, path);
}

pub fn readToZon(allocator: NeverFailingAllocator, path: []const u8) !ZonElement {
	return cwd().readToZon(allocator, path);
}

pub fn write(path: []const u8, data: []const u8) !void {
	try cwd().write(path, data);
}

pub fn writeZon(path: []const u8, zon: ZonElement) !void {
	try cwd().writeZon(path, zon);
}

pub fn openDirInWindow(path: []const u8) void {
	const newPath = main.stackAllocator.dupe(u8, path);
	defer main.stackAllocator.free(newPath);

	if(builtin.os.tag == .windows) {
		std.mem.replaceScalar(u8, newPath, '/', '\\');
	}

	const command = if(builtin.os.tag == .windows) .{"explorer", newPath} else .{"open", newPath};

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

pub fn openDir(path: []const u8) !Dir {
	return Dir{
		.dir = try std.fs.cwd().makeOpenPath(path, .{}),
	};
}

pub fn makeDir(path: []const u8) !void {
	try std.fs.cwd().makePath(path);
}

pub fn deleteDir(path: []const u8, dirName: []const u8) !void {
	var saveDir = try std.fs.cwd().openDir(path, .{});
	defer saveDir.close();
	try saveDir.deleteTree(dirName);
}

pub fn hasFile(path: []const u8) bool {
	return cwd().hasFile(path);
}

fn cwd() Dir {
	return Dir{
		.dir = std.fs.cwd(),
	};
}

var cubyzDir_: ?std.fs.Dir = null;

pub fn cubyzDir() Dir {
	return .{
		.dir = cubyzDir_ orelse std.fs.cwd(),
	};
}

fn flawedInit() !void {
	const homePath = try std.process.getEnvVarOwned(main.stackAllocator.allocator, if(builtin.os.tag == .windows) "USERPROFILE" else "HOME");
	defer main.stackAllocator.free(homePath);
	var homeDir = try std.fs.openDirAbsolute(homePath, .{});
	defer homeDir.close();
	if(builtin.os.tag == .windows) {
		cubyzDir_ = try homeDir.makeOpenPath("Saved Games/Cubyz", .{});
	} else {
		cubyzDir_ = try homeDir.makeOpenPath(".cubyz", .{});
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
		const realPath = try self.dir.realpathAlloc(main.stackAllocator.allocator, path);
		defer main.stackAllocator.free(realPath);
		return ZonElement.parseFromString(allocator, realPath, string);
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
};
