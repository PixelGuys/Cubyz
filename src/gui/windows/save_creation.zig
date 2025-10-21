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

var textInput: *TextInput = undefined;

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

fn createWorld(_: usize) void {
	const worldName = textInput.currentString.items;
	const worldSettings: main.server.world_zig.WorldSettings = .{.gamemode = gamemode, .allowCheats = allowCheats, .testingMode = testingMode};
	main.server.world_zig.tryCreateWorld(worldName, worldSettings) catch |err| {
		std.log.err("Error while creating new world: {s}", .{@errorName(err)});
	};
	gui.closeWindowFromRef(&window);
	gui.windowlist.save_selection.needsUpdate = true;
	gui.openWindow("save_selection");
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 8);

	var num: usize = 1;
	while(true) {
		const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/Save{}", .{num}) catch unreachable;
		defer main.stackAllocator.free(path);
		if(!main.files.cubyzDir().hasDir(path)) break;
		num += 1;
	}
	const name = std.fmt.allocPrint(main.stackAllocator.allocator, "Save{}", .{num}) catch unreachable;
	defer main.stackAllocator.free(name);
	textInput = TextInput.init(.{0, 0}, 128, 22, name, .{.callback = &createWorld}, .{});
	list.add(textInput);

	gamemodeInput = Button.initText(.{0, 0}, 128, @tagName(gamemode), .{.callback = &gamemodeCallback});
	list.add(gamemodeInput);

	list.add(CheckBox.init(.{0, 0}, 128, "Allow Cheats", true, &allowCheatsCallback));

	if(!build_options.isTaggedRelease) {
		list.add(CheckBox.init(.{0, 0}, 128, "Testing mode (for developers)", false, &testingModeCallback));
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
