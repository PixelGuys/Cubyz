const std = @import("std");

const build_options = @import("build_options");

const main = @import("main");
const ConnectionManager = main.network.ConnectionManager;
const settings = main.settings;
const Vec2f = main.vec.Vec2f;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const HorizontalList = @import("../components/HorizontalList.zig");
const Label = @import("../components/Label.zig");
const TextInput = @import("../components/TextInput.zig");
const CheckBox = @import("../components/CheckBox.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
};

const padding: f32 = 8;

var nameInput: *TextInput = undefined;
var seedInput: *TextInput = undefined;

var gamemode: main.game.Gamemode = .creative;
var gamemodeInput: *Button = undefined;

var allowCheats: bool = true;

var testingMode: bool = false;

fn gamemodeCallback(_: usize) void {
	gamemode = std.meta.intToEnum(main.game.Gamemode, @intFromEnum(gamemode) + 1) catch @enumFromInt(0);
	gamemodeInput.child.label.updateText(@tagName(gamemode));
}

fn allowCheatsCallback(allow: bool) void {
	allowCheats = allow;
}

fn testingModeCallback(enabled: bool) void {
	testingMode = enabled;
}

fn getWorldSeed(seedStr: []const u8) u64 {
	if(seedStr.len == 0)
	{
		return std.crypto.random.int(u64);
	} else
	{
		return std.fmt.parseInt(u64, seedStr, 0) catch {
			return std.hash.Wyhash.hash(0, seedStr);
		};
	}
}

fn createWorld(_: usize) void {
	const worldName = nameInput.currentString.items;
	const worldSeedStr = seedInput.currentString.items;

	const worldSeed = getWorldSeed(worldSeedStr);

	const worldSettings: main.server.world_zig.WorldSettings = .{.gamemode = gamemode, .allowCheats = allowCheats, .testingMode = testingMode, .seed = worldSeed};
	main.server.world_zig.tryCreateWorld(worldName, worldSettings) catch |err| {
		std.log.err("Error while creating new world: {s}", .{@errorName(err)});
	};
	gui.closeWindowFromRef(&window);
	gui.windowlist.save_selection.needsUpdate = true;
	gui.openWindow("save_selection");
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 8);

	const headerTexts: [3][]const u8 = .{"Page 1", "Page 2", "Page 3"};
	const page = 1;
	{
		const leftArrow = Button.initText(.{16, 0}, 24, "<", .{.callback = null});
		const label = Label.init(.{0, 0}, 256 - 64, headerTexts[page], .center);
		const rightArrow = Button.initText(.{16, 0}, 24, ">", .{.callback = null});
		const header = HorizontalList.init();
		header.add(leftArrow);
		header.add(label);
		header.add(rightArrow);
		header.finish(.{0, 0}, .center);
		list.add(header);
	}

	list.add(Button.initText(.{0, 0}, 128, "Create World", .{.callback = &createWorld}));

	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}
