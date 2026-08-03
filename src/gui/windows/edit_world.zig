const std = @import("std");

const main = @import("main");
const Vec2f = main.vec.Vec2f;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ZonElement = main.ZonElement;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const Label = @import("../components/Label.zig");
const TextInput = @import("../components/TextInput.zig");
const HorizontalList = @import("../components/HorizontalList.zig");
const VerticalList = @import("../components/VerticalList.zig");
const CheckBox = @import("../components/CheckBox.zig");

const Gamemode = main.game.Gamemode;

const WorldSettings = struct {
	name: []const u8,
	seed: i128,
	defaultgameMode: Gamemode,
	allowCheats: bool,
	testingMode: bool,
	localPlayerIndex: usize,

	pub fn init(name: []const u8, seed: i128, defaultgameMode: ?[]const u8, allowCheats: bool, testingMode: bool, localPlayerIndex: usize) WorldSettings {
		return .{
			.name = name,
			.seed = seed,
			.defaultgameMode = toEnum(defaultgameMode),
			.allowCheats = allowCheats,
			.testingMode = testingMode,
			.localPlayerIndex = localPlayerIndex,
		};
	}

	fn toEnum(gamemode: ?[]const u8) Gamemode {
		_ = gamemode;
	}

	pub fn print(self: WorldSettings) void {
		std.debug.print("name: {s}\nseed: {d}\n defaultGameMode: {s}\nallowCheats: {}\ntestingMode: {}\n", .{self.name, self.seed, self.defaultGameMode, self.allowCheats, self.testingMode});
	}
};

const WorldZonElement = struct {
	worldInfo: ZonElement,
	worldInfoSettings: ZonElement,

	fn check(worldInfoPath: []const u8) ZonElement {
		if (main.files.cubyzDir().readToZon(main.stackAllocator, worldInfoPath)) |data| {
			return data;
		} else |err| {
			std.log.err("Couldn't open save {s}: {s}", .{worldInfoPath, @errorName(err)});
			return ZonElement.initObject(main.stackAllocator);
		}
	}

	pub fn init(worldInfoPath: []const u8) *WorldZonElement {
		const self = main.globalAllocator.create(WorldZonElement);
		self.* = WorldZonElement{
			.worldInfo = WorldZonElement.check(worldInfoPath),
			.worldInfoSettings = undefined,
		};
		return self;
	}

	pub fn initSettings(self: *WorldZonElement) void {
		self.worldInfoSettings = self.worldInfo.getChild("settings");
	}

	pub fn deinit(self: @This()) void {
		// self.worldInfoSettings.deinit(main.stackAllocator);
		self.worldInfo.deinit(main.stackAllocator);
	}
};

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
};

const padding: f32 = 8;

var editWorldName: []const u8 = "";

var worldZonElement: *WorldZonElement = undefined;
var worldSettings: WorldSettings = undefined;

var nameInput: *TextInput = undefined;
var gamemodeInput: *Button = undefined;

fn pass() void {}

fn pass2(allow: bool) void {
	_ = allow;
}

fn gameModeCallback() void {
	worldSettings.defaultGameMode = std.enums.fromInt(Gamemode, @intFromEnum(worldSettings.defaultGameMode) + 1) orelse @enumFromInt(0);
}

pub fn init() void {
	editWorldName = "";
}

pub fn deinit() void {
	main.globalAllocator.free(editWorldName);
}

pub fn setEditWorldName(name: []const u8) void {
	main.globalAllocator.free(editWorldName);
	editWorldName = main.globalAllocator.dupe(u8, name);
}

pub fn onOpen() void {
	const worldInfoPath = main.stackAllocator.print("saves/{s}/world.zig.zon", .{editWorldName});
	defer main.stackAllocator.free(worldInfoPath);

	worldZonElement = WorldZonElement.init(worldInfoPath);
	defer worldZonElement.deinit();
	worldZonElement.initSettings();

	worldSettings = WorldSettings.init(
		worldZonElement.worldInfo.get([]const u8, "name") orelse "",
		worldZonElement.worldInfoSettings.get(i128, "seed") orelse 0,
		worldZonElement.worldInfoSettings.get([]const u8, "defaultGamemode") orelse "",
		worldZonElement.worldInfoSettings.get(bool, "allowCheats") orelse false,
		worldZonElement.worldInfoSettings.get(bool, "testingMode") orelse false,
		worldZonElement.worldInfo.get(usize, "localPlayer") orelse 0,
	);
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 8);

	nameInput = TextInput.init(.{0, 0}, 128, 22, editWorldName, .{.onNewline = .init(pass)});
	list.add(nameInput);

	list.add(CheckBox.init(.{0, 0}, 128, "Allow Cheats", worldSettings.allowCheats, &pass2));

	list.add(CheckBox.init(.{0, 0}, 128, "Testing Mode", worldSettings.testingMode, &pass2));

	const seed = main.stackAllocator.print("{d}", .{worldSettings.seed});
	defer main.stackAllocator.free(seed);
	const seedLabel = Label.init(.{0, 0}, 48, "Seed:", .left);
	const seedInput = TextInput.init(.{0, 0}, 128 - 48, 22, seed, .{.disabled = true});
	const seedRow = HorizontalList.init();
	seedRow.add(seedLabel);
	seedRow.add(seedInput);
	list.add(seedRow);

	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}
