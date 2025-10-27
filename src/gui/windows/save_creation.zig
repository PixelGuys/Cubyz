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

var needsUpdate: bool = false;

const Page = enum(u8) {
	generationSettings = 0,
	gameRules = 1,
	addons = 2,

	pub fn fillSubmenu(self: Page, submenu: *VerticalList) void {
		switch(self) {
			.generationSettings => {
				submenu.add(Label.init(.{0, 0}, 256 - 64, "this is the first page", .center));
			},
			.gameRules => {
				submenu.add(Label.init(.{0, 0}, 256 - 64, "this is the second page", .center));
			},
			.addons => {
				submenu.add(Label.init(.{0, 0}, 256 - 64, "this is the third page", .center));
			},
		}
	}

	pub fn label(self: Page) []const u8 {
		switch(self) {
			.generationSettings => {
				return "Generation Settings";
			},
			.gameRules => {
				return "Game Rules";
			},
			.addons => {
				return "Addons";
			},
		}
	}
};

var page: Page = .generationSettings;

const numPages: usize = std.meta.fields(Page).len;

fn prevPage(_: usize) void {
	const oldPageInt = @intFromEnum(page);
	const newPageInt = (oldPageInt -% 1);
	page = std.meta.intToEnum(Page, newPageInt) catch .addons;
	needsUpdate = true;
}

fn nextPage(_: usize) void {
	const oldPageInt = @intFromEnum(page);
	const newPageInt = (oldPageInt + 1);
	page = std.meta.intToEnum(Page, newPageInt) catch .generationSettings;
	needsUpdate = true;
}

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
	const list = VerticalList.init(.{padding, 16 + padding}, 500, 8);

	{
		const label = Label.init(.{0, 0}, 96, "World Name:", .center);
		var num: usize = 1;
		while(true) {
			const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/Save{}", .{num}) catch unreachable;
			defer main.stackAllocator.free(path);
			if(!main.files.cubyzDir().hasDir(path)) break;
			num += 1;
		}
		const name = std.fmt.allocPrint(main.stackAllocator.allocator, "Save{}", .{num}) catch unreachable;
		defer main.stackAllocator.free(name);
		const textInput = TextInput.init(.{0, 0}, 256 - 96, 22, name, .{.callback = null}, .{});
		const nameRow = HorizontalList.init();
		nameRow.add(label);
		nameRow.add(textInput);
		nameRow.finish(.{0, 0}, .center);
		list.add(nameRow);
	}

	{
		const leftArrow = Button.initText(.{0, 0}, 24, "<", .{.callback = &prevPage});
		const label = Label.init(.{0, 0}, 224 - 48, page.label(), .center);
		const rightArrow = Button.initText(.{0, 0}, 24, ">", .{.callback = &nextPage});
		const header = HorizontalList.init();
		header.add(leftArrow);
		header.add(label);
		header.add(rightArrow);
		header.finish(.{0, 0}, .center);
		list.add(header);
	}

	const submenu = VerticalList.init(.{0, 0}, 384, 8);
	page.fillSubmenu(submenu);
	list.add(submenu);

	list.add(Button.initText(.{0, 0}, 128, "Create World", .{.callback = &createWorld}));

	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if(window.rootComponent) |*comp| {
		comp.deinit();
		page = .generationSettings;
	}
}

pub fn render() void {
	if(needsUpdate) {
		needsUpdate = false;
		var oldName = window.rootComponent.?.verticalList.children.items[0].horizontalList.children.items[1].textInput.currentString.items;
		oldName = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}", .{oldName}) catch unreachable;
		defer main.stackAllocator.free(oldName);
		const oldScroll = window.rootComponent.?.verticalList.children.items[2].verticalList.scrollBar.currentState;
		const oldPage = page;
		onClose();
		page = oldPage;
		onOpen();
		window.rootComponent.?.verticalList.children.items[0].horizontalList.children.items[1].textInput.setString(oldName);
		window.rootComponent.?.verticalList.children.items[2].verticalList.scrollBar.currentState = oldScroll;
	}
}