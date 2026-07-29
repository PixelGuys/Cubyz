const std = @import("std");

const build_options = @import("build_options");

const main = @import("../../main.zig");
const files = main.files;
const ConnnectionManager = main.network.ConnectionManager;
const settings = main.settings;
const Vec2f = main.vec.Vec2f;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ZonElement = main.ZonElement;
const Gamemode = main.game.Gamemode;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const HorizontalList = @import("../components/HorizontalList.zig");
const Label = @import("../components/Label.zig");
const TextInput = @import("../components/TextInput.zig");
const CheckBox = @import("../components/CheckBox.zig");
const VerticalList = @import("../components/VerticalList.zig");
const DiscreteSlider = @import("../components/DiscreteSlider.zig");

const WorldConfig = struct {
	worldName: []const u8,
	worldSeed: i128,
	worldTickSpeed: u16,
	gameMode: Gamemode,
	isCheatsAllowed: bool,
	isTimeCycleAllowed: bool,
	isTestingAllowed: bool,

	isUpdated: bool = false,

	pub fn init(worldName: []const u8, worldSeed: i128, worldTickSpeed: u16, gameMode: Gamemode, isCheatsAllowed: bool, isTimeCycleAllowed: bool, isTestingAllowed: bool) @This() {
		return .{
			.worldName = worldName,
			.worldSeed = worldSeed,
			.worldTickSpeed = worldTickSpeed,
			.gameMode = gameMode,
			.isCheatsAllowed = isCheatsAllowed,
			.isTimeCycleAllowed = isTimeCycleAllowed,
			.isTestingAllowed = isTestingAllowed,
		};
	}

	pub fn setWorldName() void {}

	pub fn getGameMode(config: ZonElement) Gamemode {
		const mode = config.get([]const u8, "defaultGamemode") orelse @tagName(defaultSettings.defaultGamemode);
		return std.meta.stringToEnum(Gamemode, mode).?;
	}
};

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
};

const padding: f32 = 8;

const tickSpeeds = [_]u8{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20};

var editWorldName: []const u8 = undefined;

var defaultSettings = main.server.world_zig.Settings.defaults;

var gameModeInput: *Button = undefined;
var worldNameInput: *TextInput = undefined;

var worldConfig: WorldConfig = undefined;

fn gamemodeCallback() void {}
fn pass() void {}

fn pass2(in: bool) void {
	_ = in;
}

fn pass3(in: u16) void {
	_ = in;
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
	const worldInfo = main.files.cubyzDir().readToZon(main.stackAllocator, worldInfoPath) catch |err| {
		std.log.err("Couldn't open save {s}: {s}", .{worldInfoPath, @errorName(err)});
		return;
	};
	defer worldInfo.deinit(main.stackAllocator);

	const worldSettings = worldInfo.getChild("settings");

	worldConfig = WorldConfig.init(
		worldInfo.get([]const u8, "name") orelse "",
		worldSettings.get(i128, "seed") orelse 0,
		worldSettings.get(u16, "tickSpeed") orelse 12,
		WorldConfig.getGameMode(worldSettings),
		worldSettings.get(bool, "allowCheats") orelse defaultSettings.allowCheats,
		worldInfo.get(bool, "doGameTimeCycle") orelse true,
		worldSettings.get(bool, "testingMode") orelse defaultSettings.testingMode,
	);

	const list = VerticalList.init(.{padding, 16 + padding}, 300, 8);

	worldNameInput = TextInput.init(.{0, 0}, 128, 22, worldConfig.worldName, .{.onNewline = .init(pass)});
	list.add(worldNameInput);

	gameModeInput = Button.initText(.{0, 0}, 128, @tagName(worldConfig.gameMode), .{.onAction = .init(gamemodeCallback)});
	list.add(gameModeInput);

	list.add(CheckBox.init(.{0, 0}, 128, "Allow Cheats", worldConfig.isCheatsAllowed, &pass2));

	if (!build_options.isTaggedRelease) {
		list.add(CheckBox.init(.{0, 0}, 128, "Developer Options", worldConfig.isTestingAllowed, &pass2));
	}

	const seedRow = HorizontalList.init();
	const seedLabel = Label.init(.{0, 0}, 48, "Seed: ", .left);

	const worldSeedText = main.stackAllocator.print("{d}", .{worldConfig.worldSeed});
	defer main.stackAllocator.free(worldSeedText);
	const seedInput = TextInput.init(.{0, 0}, 128 - 48, 22, worldSeedText, .{.onNewline = .init(pass)});
	seedRow.add(seedLabel);
	seedRow.add(seedInput);
	seedRow.finish(.{0, 0}, .center);

	list.add(seedRow);

	list.add(CheckBox.init(.{0, 0}, 128, "Time Cycle", worldConfig.isTimeCycleAllowed, &pass2));

	list.add(DiscreteSlider.init(.{0, 0}, 128, "Tick Speed", ": {}", &tickSpeeds, worldConfig.worldTickSpeed, &pass3));

	list.add(Button.initText(.{0, 0}, 128, "Save Changes", .{.disabled = worldConfig.isUpdated}));

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
