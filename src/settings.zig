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

pub var playerName: []const u8 = "quanturmdoelvloper";

pub var lastUsedIPAddress: []const u8 = "127.0.0.1";

pub var guiScale: ?f32 = null;

pub var musicVolume: f32 = 1;


pub var storageTime: i64 = 5000;


pub var developerAutoEnterWorld: []const u8 = "";

pub var developerGPUInfiniteLoopDetection: bool = false;


pub fn init() void {
	const json: JsonElement = main.files.readToJson(main.stackAllocator, "settings.json") catch |err| {
		if(err != error.FileNotFound) {
			std.log.err("Could not read settings file: {s}", .{@errorName(err)});
		}
		return;
	};
	defer json.free(main.stackAllocator);

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
					@field(@This(), decl.name) = main.globalAllocator.dupe(@typeInfo(declType).Pointer.child, @field(@This(), decl.name));
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

pub fn deinit() void {
	const jsonObject = JsonElement.initObject(main.stackAllocator);
	defer jsonObject.free(main.stackAllocator);

	inline for(@typeInfo(@This()).Struct.decls) |decl| {
		const is_const = @typeInfo(@TypeOf(&@field(@This(), decl.name))).Pointer.is_const; // Sadly there is no direct way to check if a declaration is const.
		if(!is_const) {
			const declType = @TypeOf(@field(@This(), decl.name));
			if(@typeInfo(declType) == .Struct) {
				@compileError("Not implemented yet.");
			}
			if(declType == []const u8) {
				jsonObject.putOwnedString(decl.name, @field(@This(), decl.name));
			} else {
				jsonObject.put(decl.name, @field(@This(), decl.name));
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
	const keyboard = JsonElement.initObject(main.stackAllocator);
	for(&main.KeyBoard.keys) |key| {
		const keyJson = JsonElement.initObject(main.stackAllocator);
		keyJson.put("key", key.key);
		keyJson.put("mouseButton", key.mouseButton);
		keyJson.put("scancode", key.scancode);
		keyboard.put(key.name, keyJson);
	}
	jsonObject.put("keyboard", keyboard);

	// Write to file:
	main.files.writeJson("settings.json", jsonObject) catch |err| {
		std.log.err("Couldn't write settings to file: {s}", .{@errorName(err)});
	};
}