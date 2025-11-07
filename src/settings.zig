const std = @import("std");
const builtin = @import("builtin");

const ZonElement = @import("zon.zig").ZonElement;
const main = @import("main");
const Window = @import("graphics/Window.zig");

pub const version = @import("utils/version.zig");

pub const defaultPort: u16 = 47649;
pub const connectionTimeout = 60_000_000;

pub const entityLookback: i16 = 100;

pub const highestSupportedLod: u3 = 5;

pub var lastVersionString: []const u8 = "";

pub var simulationDistance: u16 = 4;

pub var cpuThreads: ?u64 = null;

pub var anisotropicFiltering: u8 = 4.0;

pub var fpsCap: ?u32 = null;

pub var fov: f32 = 70;

pub var vulkanTestingWindow: bool = false;

pub var mouseSensitivity: f32 = 1;
pub var controllerSensitivity: f32 = 1;

pub var invertMouseY: bool = false;

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

pub var blockContrast: f32 = 0;

pub var storageTime: i64 = 5000;

pub var updateRepeatSpeed: u31 = 200;

pub var updateRepeatDelay: u31 = 500;

pub var developerGPUInfiniteLoopDetection: bool = false;

pub var controllerAxisDeadzone: f32 = 0.0;

const settingsFile = if(builtin.mode == .Debug) "debug_settings.zig.zon" else "settings.zig.zon";

pub fn init() void {
	const zon: ZonElement = main.files.cubyzDir().readToZon(main.stackAllocator, settingsFile) catch |err| blk: {
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
				if(@typeInfo(declType).pointer.size == .slice) {
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
		if(key.isToggling != .never) {
			key.isToggling = std.meta.stringToEnum(Window.Key.IsToggling, keyZon.get([]const u8, "isToggling", "")) orelse key.isToggling;
		}
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
				if(@typeInfo(declType).pointer.size == .slice) {
					main.globalAllocator.free(@field(@This(), decl.name));
				} else {
					@compileError("Not implemented yet.");
				}
			}
		}
	}
}

pub fn save() void {
	var zonObject = ZonElement.initObject(main.stackAllocator);
	defer zonObject.deinit(main.stackAllocator);

	inline for(@typeInfo(@This()).@"struct".decls) |decl| {
		if(comptime std.mem.eql(u8, decl.name, "lastVersionString")) {
			zonObject.put(decl.name, version.version);
			continue;
		}
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
		if(key.isToggling != .never) {
			keyZon.put("isToggling", @tagName(key.isToggling));
		}
		keyboard.put(key.name, keyZon);
	}
	zonObject.put("keyboard", keyboard);

	// Merge with the old settings file to preserve unknown settings.
	var oldZonObject: ZonElement = main.files.cubyzDir().readToZon(main.stackAllocator, settingsFile) catch |err| blk: {
		if(err != error.FileNotFound) {
			std.log.err("Could not read settings file: {s}", .{@errorName(err)});
		}
		break :blk .null;
	};
	defer oldZonObject.deinit(main.stackAllocator);

	if(oldZonObject == .object) {
		zonObject.join(.preferLeft, oldZonObject);
	}

	main.files.cubyzDir().writeZon(settingsFile, zonObject) catch |err| {
		std.log.err("Couldn't write settings to file: {s}", .{@errorName(err)});
	};
}

pub const launchConfig = struct {
	pub var cubyzDir: []const u8 = "";
	pub var autoEnterWorld: []const u8 = "";

	pub fn init() void {
		const zon: ZonElement = main.files.cwd().readToZon(main.stackAllocator, "launchConfig.zon") catch |err| blk: {
			std.log.err("Could not read launchConfig.zon: {s}", .{@errorName(err)});
			break :blk .null;
		};
		defer zon.deinit(main.stackAllocator);

		cubyzDir = main.globalAllocator.dupe(u8, zon.get([]const u8, "cubyzDir", cubyzDir));
		autoEnterWorld = main.globalAllocator.dupe(u8, zon.get([]const u8, "autoEnterWorld", autoEnterWorld));
	}

	pub fn deinit() void {
		main.globalAllocator.free(cubyzDir);
	}
};
