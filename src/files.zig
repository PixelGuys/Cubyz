const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const JsonElement = main.JsonElement;

pub fn read(allocator: Allocator, path: []const u8) ![]u8 {
	const file = try std.fs.cwd().openFile(path, .{});
	defer file.close();
	return try file.readToEndAlloc(allocator, std.math.maxInt(usize));
}

pub fn readToJson(allocator: Allocator, path: []const u8) !JsonElement {
	const string = try read(main.threadAllocator, path);
	defer main.threadAllocator.free(string);
	return JsonElement.parseFromString(allocator, string);
}

pub fn write(path: []const u8, data: []const u8) !void {
	const file = try std.fs.cwd().createFile(path, .{});
	defer file.close();
	try file.writeAll(data);
}

pub fn writeJson(path: []const u8, json: JsonElement) !void {
	const string = try json.toString(main.threadAllocator);
	defer main.threadAllocator.free(string);
	try write(path, string);
}