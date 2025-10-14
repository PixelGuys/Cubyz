const std = @import("std");
const main = @import("main");
const Pattern = main.blueprint.Pattern;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub fn parsePatternWithDefault(allocator: NeverFailingAllocator, source: ?[]const u8, replacement: []const u8) Pattern {
	if(source) |string| {
		return Pattern.initFromString(allocator, string) catch |err| {
			std.log.err("Error encountered while parsing pattern \"{s}\": {}", .{string, err});
			return Pattern.initFromString(allocator, replacement) catch unreachable;
		};
	} else {
		return Pattern.initFromString(allocator, replacement) catch unreachable;
	}
}
