const std = @import("std");

const main = @import("root");
const NeverFailingAllocator = main.utils.NeverFailingAllocator;
const JsonElement = main.JsonElement;

pub fn read(allocator: NeverFailingAllocator, path: []const u8) ![]u8 {
	return cwd().read(allocator, path);
}

pub fn readToJson(allocator: NeverFailingAllocator, path: []const u8) !JsonElement {
	return cwd().readToJson(allocator, path);
}

pub fn write(path: []const u8, data: []const u8) !void {
	try cwd().write(path, data);
}

pub fn writeJson(path: []const u8, json: JsonElement) !void {
	try cwd().writeJson(path, json);
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

	pub fn readToJson(self: Dir, allocator: NeverFailingAllocator, path: []const u8) !JsonElement {
		const string = try self.read(main.stackAllocator, path);
		defer main.stackAllocator.free(string);
		return JsonElement.parseFromString(allocator, string);
	}

	pub fn write(self: Dir, path: []const u8, data: []const u8) !void {
		const file = try self.dir.createFile(path, .{});
		defer file.close();
		try file.writeAll(data);
	}

	pub fn writeJson(self: Dir, path: []const u8, json: JsonElement) !void {
		const string = json.toString(main.stackAllocator);
		defer main.stackAllocator.free(string);
		try self.write(path, string);
	}

	pub fn hasFile(self: Dir, path: []const u8) bool {
		const file = self.dir.openFile(path, .{}) catch return false;
		file.close();
		return true;
	}
};