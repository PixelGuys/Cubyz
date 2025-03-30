const std = @import("std");

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

fn gamemodeCallback(_: usize) void {
	gamemode = std.meta.intToEnum(main.game.Gamemode, @intFromEnum(gamemode) + 1) catch @enumFromInt(0);
	gamemodeInput.child.label.updateText(@tagName(gamemode));
}

fn allowCheatsCallback(allow: bool) void {
	allowCheats = allow;
}

fn createWorld(_: usize) void {
	flawedCreateWorld() catch |err| {
		std.log.err("Error while creating new world: {s}", .{@errorName(err)});
	};
}

fn flawedCreateWorld() !void {
	const worldName = textInput.currentString.items;
	const saveFolder = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}", .{worldName}) catch unreachable;
	defer main.stackAllocator.free(saveFolder);
	if(std.fs.cwd().openDir(saveFolder, .{})) |_dir| {
		var dir = _dir;
		dir.close();
		return error.AlreadyExists;
	} else |_| {}
	try main.files.makeDir(saveFolder);
	{
		const generatorSettingsPath = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/generatorSettings.zig.zon", .{worldName}) catch unreachable;
		defer main.stackAllocator.free(generatorSettingsPath);
		const generatorSettings = main.ZonElement.initObject(main.stackAllocator);
		defer generatorSettings.deinit(main.stackAllocator);
		const climateGenerator = main.ZonElement.initObject(main.stackAllocator);
		climateGenerator.put("id", "cubyz:noise_based_voronoi"); // TODO: Make this configurable
		generatorSettings.put("climateGenerator", climateGenerator);
		const mapGenerator = main.ZonElement.initObject(main.stackAllocator);
		mapGenerator.put("id", "cubyz:mapgen_v1"); // TODO: Make this configurable
		generatorSettings.put("mapGenerator", mapGenerator);
		const climateWavelengths = main.ZonElement.initObject(main.stackAllocator);
		climateWavelengths.put("hot_cold", 2400);
		climateWavelengths.put("land_ocean", 3200);
		climateWavelengths.put("wet_dry", 1800);
		climateWavelengths.put("vegetation", 1600);
		climateWavelengths.put("mountain", 512);
		generatorSettings.put("climateWavelengths", climateWavelengths);
		try main.files.writeZon(generatorSettingsPath, generatorSettings);
	}
	{
		const gamerulePath = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/gamerules.zig.zon", .{worldName}) catch unreachable;
		defer main.stackAllocator.free(gamerulePath);
		const gamerules = main.ZonElement.initObject(main.stackAllocator);
		defer gamerules.deinit(main.stackAllocator);

		gamerules.put("default_gamemode", @tagName(gamemode));
		gamerules.put("cheats", allowCheats);

		try main.files.writeZon(gamerulePath, gamerules);
	}
	{ // Make assets subfolder
		const assetsPath = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/assets", .{worldName}) catch unreachable;
		defer main.stackAllocator.free(assetsPath);
		try main.files.makeDir(assetsPath);
	}
	// TODO: Make the seed configurable
	gui.closeWindowFromRef(&window);
	gui.windowlist.save_selection.needsUpdate = true;
	gui.openWindow("save_selection");
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 8);

	var num: usize = 1;
	var buf: [32]u8 = undefined;
	while(true) {
		var dir = std.fs.cwd().openDir(std.fmt.bufPrint(&buf, "saves/Save{}", .{num}) catch unreachable, .{}) catch break;
		dir.close();
		num += 1;
	}
	const name = std.fmt.bufPrint(&buf, "Save{}", .{num}) catch unreachable;
	textInput = TextInput.init(.{0, 0}, 128, 22, name, .{.callback = &createWorld});
	list.add(textInput);

	gamemodeInput = Button.initText(.{0, 0}, 128, @tagName(gamemode), .{.callback = &gamemodeCallback});
	list.add(gamemodeInput);

	list.add(CheckBox.init(.{0, 0}, 128, "Allow Cheats", true, &allowCheatsCallback));

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
