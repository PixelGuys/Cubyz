const std = @import("std");

// a different runmode than normal allows you to open the game faster
const runSettings = @This();
const runType = union(enum) {
	normal: void,
	first: void,
	world: []const u8,
};

//pub const runMode: runType = .normal;
pub const runMode: runType = .first;
//pub const runMode: runType = .{.world = "insert world name here"};