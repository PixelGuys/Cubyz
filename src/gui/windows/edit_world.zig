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
const DefaultSettings = main.server.world_zig.Settings.defaults;

const WorldSettings = struct {
	name: []const u8 = &.{},
	seed: i128,
	defaultGamemode: Gamemode,
	allowCheats: bool,
	testingMode: bool,
	localPlayerIndex: usize,

	isUpated: bool = false,

	pub fn init(name: []const u8, seed: i128, defaultgameMode: ?[]const u8, allowCheats: bool, testingMode: bool, localPlayerIndex: usize) WorldSettings {
		return .{
			.name = name,
			.seed = seed,
			.defaultGamemode = toEnum(defaultgameMode),
			.allowCheats = allowCheats,
			.testingMode = testingMode,
			.localPlayerIndex = localPlayerIndex,
		};
	}

	fn toEnum(gamemode: ?[]const u8) Gamemode {
		const mode = gamemode orelse @tagName(DefaultSettings.defaultGamemode);
		return std.meta.stringToEnum(Gamemode, mode).?;
	}

	pub fn print(self: WorldSettings) void {
		std.debug.print("name: {s}\nseed: {d}\n defaultGameMode: {s}\nallowCheats: {}\ntestingMode: {}\n", .{
			nameInput.currentString.items,
			self.seed,
			@tagName(self.defaultGamemode),
			self.allowCheats,
			self.testingMode,
		});
	}

	pub fn update(self: *WorldSettings, value: bool) void {
		self.isUpated = value;
		saveChanges.disabled = !value;
	}
};

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
};

const padding: f32 = 8;

var editWorldName: []const u8 = "";

var worldInfo: ZonElement = undefined;
var worldSettings: WorldSettings = undefined;

var nameInput: *TextInput = undefined;
var gamemodeInput: *Button = undefined;
var saveChanges: *Button = undefined;

fn nameCallback() void {
	const newName = nameInput.currentString.items;
	worldSettings.name = newName;
	worldSettings.update(true);
}

fn gameModeCallback() void {
	worldSettings.defaultGamemode = std.enums.fromInt(Gamemode, @intFromEnum(worldSettings.defaultGamemode) + 1) orelse @enumFromInt(0);
	gamemodeInput.child.label.updateText(@tagName(worldSettings.defaultGamemode));
	worldSettings.update(true);
}

fn allowCheatsCallback(allow: bool) void {
	worldSettings.allowCheats = allow;
	worldSettings.update(true);
}

fn testingModeCallback(enabled: bool) void {
	worldSettings.testingMode = enabled;
	worldSettings.update(true);
}

fn saveChangesCallback() void {
	worldSettings.print();

	const path = main.stackAllocator.print("saves/{s}/world.zig.zon", .{editWorldName});
	defer main.stackAllocator.free(path);

	const worldInfoSettings = worldInfo.getChild("settings");

	worldInfoSettings.put("defaultGamemode", @tagName(worldSettings.defaultGamemode));
	worldInfoSettings.put("allowCheats", worldSettings.allowCheats);
	worldInfoSettings.put("testingMode", worldSettings.testingMode);

	worldInfo.put("localPlayer", worldSettings.localPlayerIndex);
	worldInfo.put("name", nameInput.currentString.items);
	worldInfo.put("settings", worldInfoSettings.clone(main.stackAllocator));
	main.files.cubyzDir().writeZon(path, worldInfo) catch |err| {
		std.log.err("Error while creating new world: {s}", .{@errorName(err)});
		return;
	};
	worldSettings.update(false);
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

	worldInfo = main.files.cubyzDir().readToZon(main.globalAllocator, worldInfoPath) catch |err| {
		std.log.err("Error while creating new world: {s}", .{@errorName(err)});
		return;
	};

	const worldInfoSettings = worldInfo.getChild("settings");

	worldSettings = WorldSettings.init(
		worldInfo.get([]const u8, "name") orelse "",
		worldInfoSettings.get(i128, "seed") orelse 0,
		worldInfoSettings.get([]const u8, "defaultGamemode"),
		worldInfoSettings.get(bool, "allowCheats") orelse DefaultSettings.allowCheats,
		worldInfoSettings.get(bool, "testingMode") orelse DefaultSettings.testingMode,
		worldInfo.get(usize, "localPlayer") orelse 0,
	);

	const list = VerticalList.init(.{padding, 16 + padding}, 300, 8);

	nameInput = TextInput.init(.{0, 0}, 128, 22, worldSettings.name, .{.onNewline = .init(nameCallback)});
	list.add(nameInput);

	gamemodeInput = Button.initText(.{0, 0}, 128, @tagName(worldSettings.defaultGamemode), .{.onAction = .init(gameModeCallback)});
	list.add(gamemodeInput);

	list.add(CheckBox.init(.{0, 0}, 128, "Allow Cheats", worldSettings.allowCheats, &allowCheatsCallback));

	list.add(CheckBox.init(.{0, 0}, 128, "Testing Mode", worldSettings.testingMode, &testingModeCallback));

	const seed = main.stackAllocator.print("{d}", .{worldSettings.seed});
	defer main.stackAllocator.free(seed);
	const seedLabel = Label.init(.{0, 0}, 48, "Seed:", .left);
	const seedInput = TextInput.init(.{0, 0}, 128 - 48, 22, seed, .{.disabled = true});
	const seedRow = HorizontalList.init();
	seedRow.add(seedLabel);
	seedRow.add(seedInput);
	list.add(seedRow);

	const indexLabel = Label.init(.{0, 0}, 128, "Local Player Indiex", .left);
	list.add(indexLabel);

	saveChanges = Button.initText(.{0, 0}, 128, "Save Changes", .{.disabled = !worldSettings.isUpated, .onAction = .init(saveChangesCallback)});
	list.add(saveChanges);

	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
	worldInfo.deinit(main.globalAllocator);
}
