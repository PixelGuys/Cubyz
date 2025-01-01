const std = @import("std");

const ZonElement = @import("zon.zig").ZonElement;
const main = @import("main.zig");

pub const defaultPort: u16 = 47649;
pub const connectionTimeout = 60_000_000_000;

pub const entityLookback: i16 = 100;

pub const version = "Cubyz α 0.12.0";

pub const highestSupportedLod: u3 = 5;


pub var simulationDistance: u16 = 4;

pub var cpuThreads: ?u64 = null;

pub var anisotropicFiltering: u8 = 4.0;


pub var fpsCap: ?u32 = null;

pub var fov: f32 = 70;

pub var mouseSensitivity: f32 = 1;
pub var controllerSensitivity: f32 = 1;

pub var renderDistance: u16 = 7;

pub var highestLod: u3 = highestSupportedLod;

pub var resolutionScale: f32 = 1;

pub var bloom: bool = true;

pub var vsync: bool = true;

pub var playerName: []const u8 = "";

pub var lastUsedIPAddress: []const u8 = "";

pub var guiScale: ?f32 = null;

pub var musicVolume: f32 = 1;

pub var leavesQuality: u16 = 2;

pub var @"lod0.5Distance": f32 = 200;


pub var storageTime: i64 = 5000;


pub var updateRepeatSpeed: u31 = 200;

pub var updateRepeatDelay: u31 = 500;

pub var developerAutoEnterWorld: []const u8 = "";

pub var developerGPUInfiniteLoopDetection: bool = false;

pub var controllerAxisDeadzone: f32 = 0.0;

pub fn init() void {
	const zon: ZonElement = main.files.cubyzDir().readToZon(main.stackAllocator, "settings.zig.zon") catch |err| blk: {
		if(err != error.FileNotFound) {
			std.log.err("Could not read settings file: {s}", .{@errorName(err)});
		}
		break :blk .null;
	};
	defer zon.deinit(main.stackAllocator);

	inline for(@typeInfo(@This()).@"struct".decls) |decl| {
		const is_const = @typeInfo(@TypeOf(&@field(@This(), decl.name))).pointer.is_const; // Sadly there is no direct way to check if a declaration is const.
		if(!is_const) {
			const declType = @TypeOf(@field(@This(), decl.name));
			if(@typeInfo(declType) == .@"struct") {
				@compileError("Not implemented yet.");
			}
			@field(@This(), decl.name) = zon.get(declType, decl.name, @field(@This(), decl.name));
			if(@typeInfo(declType) == .pointer) {
				if(@typeInfo(declType).pointer.size == .Slice) {
					@field(@This(), decl.name) = main.globalAllocator.dupe(@typeInfo(declType).pointer.child, @field(@This(), decl.name));
				} else {
					@compileError("Not implemented yet.");
				}
			}
		}
	}

	if(resolutionScale != 1 and resolutionScale != 0.5 and resolutionScale != 0.25) resolutionScale = 1;

	// keyboard settings:
	const keyboard = zon.getChild("keyboard");
	for(&main.KeyBoard.keys) |*key| {
		const keyZon = keyboard.getChild(key.name);
		key.key = keyZon.get(c_int, "key", key.key);
		key.mouseButton = keyZon.get(c_int, "mouseButton", key.mouseButton);
		key.scancode = keyZon.get(c_int, "scancode", key.scancode);
	}
}

pub fn deinit() void {
	save();
	inline for(@typeInfo(@This()).@"struct".decls) |decl| {
		const is_const = @typeInfo(@TypeOf(&@field(@This(), decl.name))).pointer.is_const; // Sadly there is no direct way to check if a declaration is const.
		if(!is_const) {
			const declType = @TypeOf(@field(@This(), decl.name));
			if(@typeInfo(declType) == .@"struct") {
				@compileError("Not implemented yet.");
			}
			if(@typeInfo(declType) == .pointer) {
				if(@typeInfo(declType).pointer.size == .Slice) {
					main.globalAllocator.free(@field(@This(), decl.name));
				} else {
					@compileError("Not implemented yet.");
				}
			}
		}
	}
}

pub fn save() void {
	const zonObject = ZonElement.initObject(main.stackAllocator);
	defer zonObject.deinit(main.stackAllocator);

	inline for(@typeInfo(@This()).@"struct".decls) |decl| {
		const is_const = @typeInfo(@TypeOf(&@field(@This(), decl.name))).pointer.is_const; // Sadly there is no direct way to check if a declaration is const.
		if(!is_const) {
			const declType = @TypeOf(@field(@This(), decl.name));
			if(@typeInfo(declType) == .@"struct") {
				@compileError("Not implemented yet.");
			}
			if(declType == []const u8) {
				zonObject.putOwnedString(decl.name, @field(@This(), decl.name));
			} else {
				zonObject.put(decl.name, @field(@This(), decl.name));
			}
		}
	}

	// keyboard settings:
	const keyboard = ZonElement.initObject(main.stackAllocator);
	for(&main.KeyBoard.keys) |key| {
		const keyZon = ZonElement.initObject(main.stackAllocator);
		keyZon.put("key", key.key);
		keyZon.put("mouseButton", key.mouseButton);
		keyZon.put("scancode", key.scancode);
		keyboard.put(key.name, keyZon);
	}
	zonObject.put("keyboard", keyboard);

	// Write to file:
	main.files.cubyzDir().writeZon("settings.zig.zon", zonObject) catch |err| {
		std.log.err("Couldn't write settings to file: {s}", .{@errorName(err)});
	};
}
