const std = @import("std");

const JsonElement = @import("json.zig").JsonElement;
const main = @import("main.zig");

pub const defaultPort: u16 = 47649;
pub const connectionTimeout = 60000;

pub const entityLookback: i16 = 100;

pub const version = "Cubyz α 0.12.0";

pub const highestLOD: u5 = 5;


pub var entityDistance: u16 = 2;

pub var anisotropicFiltering: bool = true;


pub var fov: f32 = 70;

pub var mouseSensitivity: f32 = 1;

pub var renderDistance: u16 = 7;

pub var bloom: bool = true;

pub var vsync: bool = true;

pub var playerName: []const u8 = "";

pub var lastUsedIPAddress: []const u8 = "127.0.0.1";

pub var guiScale: ?f32 = null;

pub var musicVolume: f32 = 1;


pub var developerAutoEnterWorld: []const u8 = "";


pub fn init() !void {
	const json: JsonElement = main.files.readToJson(main.globalAllocator, "settings.json") catch |err| blk: {
		if(err == error.FileNotFound) break :blk JsonElement{.JsonNull={}};
		return err;
	};
	defer json.free(main.globalAllocator);

	inline for(@typeInfo(@This()).Struct.decls) |decl| {
		const is_const = @typeInfo(@TypeOf(&@field(@This(), decl.name))).Pointer.is_const; // Sadly there is no direct way to check if a declaration is const.
		if(!is_const) {
			const declType = @TypeOf(@field(@This(), decl.name));
			if(@typeInfo(declType) == .Struct) {
				@compileError("Not implemented yet.");
			}
			@field(@This(), decl.name) = json.get(declType, decl.name, @field(@This(), decl.name));
			if(@typeInfo(declType) == .Pointer) {
				if(@typeInfo(declType).Pointer.size == .Slice) {
					@field(@This(), decl.name) = try main.globalAllocator.dupe(@typeInfo(declType).Pointer.child, @field(@This(), decl.name));
				} else {
					@compileError("Not implemented yet.");
				}
			}
		}
	}

	// keyboard settings:
	const keyboard = json.getChild("keyboard");
	for(&main.KeyBoard.keys) |*key| {
		const keyJson = keyboard.getChild(key.name);
		key.key = keyJson.get(c_int, "key", key.key);
		key.mouseButton = keyJson.get(c_int, "mouseButton", key.mouseButton);
		key.scancode = keyJson.get(c_int, "scancode", key.scancode);
	}
}

fn flawedDeinit() !void {
	const jsonObject = try JsonElement.initObject(main.globalAllocator);
	defer jsonObject.free(main.globalAllocator);

	inline for(@typeInfo(@This()).Struct.decls) |decl| {
		const is_const = @typeInfo(@TypeOf(&@field(@This(), decl.name))).Pointer.is_const; // Sadly there is no direct way to check if a declaration is const.
		if(!is_const) {
			const declType = @TypeOf(@field(@This(), decl.name));
			if(@typeInfo(declType) == .Struct) {
				@compileError("Not implemented yet.");
			}
			if(declType == []const u8) {
				try jsonObject.putOwnedString(decl.name, @field(@This(), decl.name));
			} else {
				try jsonObject.put(decl.name, @field(@This(), decl.name));
			}
			if(@typeInfo(declType) == .Pointer) {
				if(@typeInfo(declType).Pointer.size == .Slice) {
					main.globalAllocator.free(@field(@This(), decl.name));
				} else {
					@compileError("Not implemented yet.");
				}
			}
		}
	}

	// keyboard settings:
	const keyboard = try JsonElement.initObject(main.globalAllocator);
	for(&main.KeyBoard.keys) |key| {
		const keyJson = try JsonElement.initObject(main.globalAllocator);
		try keyJson.put("key", key.key);
		try keyJson.put("mouseButton", key.mouseButton);
		try keyJson.put("scancode", key.scancode);
		try keyboard.put(key.name, keyJson);
	}
	try jsonObject.put("keyboard", keyboard);

	// Write to file:
	try main.files.writeJson("settings.json", jsonObject);
}

pub fn deinit() void {
	flawedDeinit() catch |err| {
		std.log.err("Error in settings.deinit(): {s}", .{@errorName(err)});
		return;
	};
}