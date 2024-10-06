const std = @import("std");

const main = @import("root");
const NeverFailingAllocator = main.utils.NeverFailingAllocator;
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

pub fn openDir(path: []const u8) !Dir {
	return Dir {
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

fn cwd() Dir {
	return Dir {
		.dir = std.fs.cwd(),
	};
}

pub const Dir = struct {
	dir: std.fs.Dir,

	pub fn close(self: *Dir) void {
		self.dir.close();
	}

	pub fn read(self: Dir, allocator: NeverFailingAllocator, path: []const u8) ![]u8 {
		const file = try self.dir.openFile(path, .{});
		defer file.close();
		return file.readToEndAlloc(allocator.allocator, std.math.maxInt(usize)) catch unreachable;
	}

	pub fn readToZon(self: Dir, allocator: NeverFailingAllocator, path: []const u8) !ZonElement {
		const string = try self.read(main.stackAllocator, path);
		defer main.stackAllocator.free(string);
		return ZonElement.parseFromString(allocator, string);
	}

	pub fn write(self: Dir, path: []const u8, data: []const u8) !void {
		const file = try self.dir.createFile(path, .{});
		defer file.close();
		try file.writeAll(data);
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