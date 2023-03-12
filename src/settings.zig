const std = @import("std");

const JsonElement = @import("json.zig").JsonElement;
const main = @import("main.zig");

pub const defaultPort: u16 = 47649;
pub const connectionTimeout = 60000;

pub const entityLookback: i16 = 100;

pub const version = "Cubyz α 0.12.0";

pub const highestLOD: u5 = 5;


pub var entityDistance: u16 = 2;


pub var fov: f32 = 70;

pub var mouseSensitivity: f32 = 1;

pub var fogCoefficient: f32 = 15;

pub var renderDistance: u16 = 4;
pub var LODFactor: f32 = 2.0;

pub var bloom: bool = true;

pub var vsync: bool = true;

pub var playerName: []const u8 = "";

pub var lastUsedIPAddress: []const u8 = "127.0.0.1";

pub var guiScale: ?f32 = null;


pub fn init() !void {
	const json: JsonElement = blk: {
		var file = std.fs.cwd().openFile("settings.json", .{}) catch break :blk JsonElement{.JsonNull={}};
		defer file.close();
		const fileString = try file.readToEndAlloc(main.threadAllocator, std.math.maxInt(usize));
		defer main.threadAllocator.free(fileString);
		break :blk JsonElement.parseFromString(main.threadAllocator, fileString);
	};
	defer json.free(main.threadAllocator);

	inline for(@typeInfo(@This()).Struct.decls) |decl| {
		const is_const = @typeInfo(@TypeOf(&@field(@This(), decl.name))).Pointer.is_const; // Sadly there is no direct way to check if a declaration is const.
		if(!is_const and decl.is_pub) {
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
	inline for(comptime std.meta.fieldNames(@TypeOf(main.keyboard))) |keyName| {
		const keyJson = keyboard.getChild(keyName);
		const key = &@field(main.keyboard, keyName);
		key.key = keyJson.get(c_int, "key", key.key);
		key.mouseButton = keyJson.get(c_int, "mouseButton", key.mouseButton);
		key.scancode = keyJson.get(c_int, "scancode", key.scancode);
	}
}

pub fn deinit() void {
	const jsonObject = JsonElement.initObject(main.threadAllocator) catch |err| {
		std.log.err("Error in settings.deinit(): {s}", .{@errorName(err)});
		return;
	};
	defer jsonObject.free(main.threadAllocator);

	inline for(@typeInfo(@This()).Struct.decls) |decl| {
		const is_const = @typeInfo(@TypeOf(&@field(@This(), decl.name))).Pointer.is_const; // Sadly there is no direct way to check if a declaration is const.
		if(!is_const and decl.is_pub) {
			const declType = @TypeOf(@field(@This(), decl.name));
			if(@typeInfo(declType) == .Struct) {
				@compileError("Not implemented yet.");
			}
			if(declType == []const u8) {
				jsonObject.putOwnedString(decl.name, @field(@This(), decl.name)) catch |err| {
					std.log.err("Error in settings.deinit(): {s}", .{@errorName(err)});
				};
			} else {
				jsonObject.put(decl.name, @field(@This(), decl.name)) catch |err| {
					std.log.err("Error in settings.deinit(): {s}", .{@errorName(err)});
				};
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
	const keyboard = JsonElement.initObject(main.threadAllocator) catch |err| {
		std.log.err("Error in settings.deinit(): {s}", .{@errorName(err)});
		return;
	};
	inline for(comptime std.meta.fieldNames(@TypeOf(main.keyboard))) |keyName| {
		const keyJson = JsonElement.initObject(main.threadAllocator) catch |err| {
			std.log.err("Error in settings.deinit(): {s}", .{@errorName(err)});
			return;
		};
		const key = &@field(main.keyboard, keyName);
		keyJson.put("key", key.key) catch |err| {
			std.log.err("Error in settings.deinit(): {s}", .{@errorName(err)});
		};
		keyJson.put("mouseButton", key.mouseButton) catch |err| {
			std.log.err("Error in settings.deinit(): {s}", .{@errorName(err)});
		};
		keyJson.put("scancode", key.scancode) catch |err| {
			std.log.err("Error in settings.deinit(): {s}", .{@errorName(err)});
		};
		keyboard.put(keyName, keyJson) catch |err| {
			std.log.err("Error in settings.deinit(): {s}", .{@errorName(err)});
		};
	}
	jsonObject.put("keyboard", keyboard) catch |err| {
		std.log.err("Error in settings.deinit(): {s}", .{@errorName(err)});
	};

	// Write to file:
	
	const string = jsonObject.toStringEfficient(main.threadAllocator, "") catch |err| {
		std.log.err("Error in settings.deinit(): {s}", .{@errorName(err)});
		return;
	};
	defer main.threadAllocator.free(string);

	var file = std.fs.cwd().createFile("settings.json", .{}) catch |err| {
		std.log.err("Error in settings.deinit(): {s}", .{@errorName(err)});
		return;
	};
	defer file.close();

	file.writeAll(string) catch |err| {
		std.log.err("Error in settings.deinit(): {s}", .{@errorName(err)});
		return;
	};
}

// TODO: Check if/how these are needed:
//	static Side currentSide = null;
//
//	private static Language currentLanguage = null;
//
//	public static boolean musicOnOff = true; //Turn on or off the music
//
//	/**Not actually a setting, but stored here anyways.*/
//	public static int EFFECTIVE_RENDER_DISTANCE = calculatedEffectiveRenderDistance();
//	
//	public static int calculatedEffectiveRenderDistance() {
//		return RENDER_DISTANCE + (((int)(RENDER_DISTANCE*LOD_FACTOR) & ~1) << Constants.HIGHEST_LOD);
//	}