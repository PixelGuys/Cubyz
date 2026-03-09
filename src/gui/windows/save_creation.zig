const std = @import("std");

const build_options = @import("build_options");

const main = @import("main");
const ConnectionManager = main.network.ConnectionManager;
const settings = main.settings;
const Vec2f = main.vec.Vec2f;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const Texture = main.graphics.Texture;
const ZonElement = main.ZonElement;

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

var gamemodeInput: *Button = undefined;

var worldSettings = main.server.world_zig.Settings.defaults;

const ZonMapEntry = std.StringHashMapUnmanaged(ZonElement).Entry;
var worldPresets: []ZonMapEntry = &.{};
var selectedPreset: usize = undefined;
var defaultPreset: usize = 0;
var presetButton: *Button = undefined;

var needsUpdate: bool = false;

var deleteIcon: Texture = undefined;
var fileExplorerIcon: Texture = undefined;

var page: Page = .generation;
const numPages: usize = std.meta.fields(Page).len;

const Page = enum(u8) {
	generation = 0,
	gameRules = 1,

	pub fn fillSubmenu(self: Page, submenu: *VerticalList) void {
		switch (self) {
			.generation => {
				submenu.add(Label.init(.{0, 0}, 256 - 64, "this is the first page", .center));
			},
			.gameRules => {
				submenu.add(Label.init(.{0, 0}, 256 - 64, "this is the second page", .center));
			},
		}
	}

	pub fn label(self: Page) []const u8 {
		switch (self) {
			.generation => {
				return "Generation";
			},
			.gameRules => {
				return "Game Rules";
			},
		}
	}
};

fn prevPage() void {
	const oldPageInt = @intFromEnum(page);
	const newPageInt = (oldPageInt -% 1);
	page = std.meta.intToEnum(Page, newPageInt) catch .gameRules;
	needsUpdate = true;
}

fn nextPage() void {
	const oldPageInt = @intFromEnum(page);
	const newPageInt = (oldPageInt + 1);
	page = std.meta.intToEnum(Page, newPageInt) catch .generation;
	needsUpdate = true;
}

fn chooseSeed(seedStr: []const u8) u64 {
	if (seedStr.len == 0) {
		return main.random.nextInt(u64, &main.seed);
	} else {
		return std.fmt.parseInt(u64, seedStr, 0) catch {
			return std.hash.Wyhash.hash(0, seedStr);
		};
	}
}

fn gamemodeCallback() void {
	worldSettings.defaultGamemode = std.meta.intToEnum(main.game.Gamemode, @intFromEnum(worldSettings.defaultGamemode) + 1) catch @enumFromInt(0);
	gamemodeInput.child.label.updateText(@tagName(worldSettings.defaultGamemode));
}

fn worldPresetCallback() void {
	selectedPreset += 1;
	if (selectedPreset == worldPresets.len) selectedPreset = 0;
	presetButton.child.label.updateText(worldPresets[selectedPreset].key_ptr.*);
}

fn allowCheatsCallback(allow: bool) void {
	worldSettings.allowCheats = allow;
}

fn testingModeCallback(enabled: bool) void {
	worldSettings.testingMode = enabled;
}

fn createWorld() void {
	const worldName = nameInput.currentString.items;
	worldSettings.seed = chooseSeed(seedInput.currentString.items);

	main.server.world_zig.tryCreateWorld(worldName, worldSettings, worldPresets[selectedPreset].value_ptr.*) catch |err| {
		std.log.err("Error while creating new world: {s}", .{@errorName(err)});
	};
	gui.closeWindowFromRef(&window);
	gui.windowlist.save_selection.needsUpdate = true;
	gui.openWindow("save_selection");
}

fn none() void {}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 500, 8);

	{ // name field
		const label = Label.init(.{0, 0}, 96, "World Name:", .center);
		var num: usize = 1;
		while (true) {
			const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/Save{}", .{num}) catch unreachable;
			defer main.stackAllocator.free(path);
			if (!main.files.cubyzDir().hasDir(path)) break;
			num += 1;
		}
		const name = std.fmt.allocPrint(main.stackAllocator.allocator, "Save{}", .{num}) catch unreachable;
		defer main.stackAllocator.free(name);
		const textInput = TextInput.init(.{0, 0}, 256 - 96, 22, name, .{.onNewline = .init(none)});
		const nameRow = HorizontalList.init();
		nameRow.add(label);
		nameRow.add(textInput);
		nameRow.finish(.{0, 0}, .center);
		list.add(nameRow);
	}

	{ // page title and switch buttons
		const leftArrow = Button.initText(.{0, 0}, 24, "<", .init(prevPage));
		const label = Label.init(.{0, 0}, 224 - 48, page.label(), .center);
		const rightArrow = Button.initText(.{0, 0}, 24, ">", .init(nextPage));
		const header = HorizontalList.init();
		header.add(leftArrow);
		header.add(label);
		header.add(rightArrow);
		header.finish(.{0, 0}, .center);
		list.add(header);
	}

	const submenu = VerticalList.init(.{0, 8}, 384, 8);
	page.fillSubmenu(submenu);
	submenu.finish(.center);
	list.add(submenu);

	list.add(Button.initText(.{0, 8}, 128, "Create World", .init(createWorld)));

	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();

	if (worldPresets.len == 0) {
		var presetMap = main.assets.worldPresets();
		var entryList: main.ListUnmanaged(ZonMapEntry) = .initCapacity(main.globalArena, presetMap.count());
		var iterator = presetMap.iterator();
		while (iterator.next()) |entry| {
			entryList.appendAssumeCapacity(entry);
		}

		std.sort.insertion(ZonMapEntry, entryList.items, {}, struct {
			fn lessThanFn(_: void, lhs: ZonMapEntry, rhs: ZonMapEntry) bool {
				return std.ascii.lessThanIgnoreCase(lhs.key_ptr.*, rhs.key_ptr.*);
			}
		}.lessThanFn);
		worldPresets = entryList.items;
		for (worldPresets, 0..) |entry, i| {
			if (std.mem.eql(u8, entry.key_ptr.*, "cubyz:default")) {
				defaultPreset = i;
			}
		}
	}
	selectedPreset = defaultPreset;

	gamemodeInput = Button.initText(.{0, 0}, 128, @tagName(worldSettings.defaultGamemode), .init(gamemodeCallback));
	list.add(gamemodeInput);

	list.add(CheckBox.init(.{0, 0}, 128, "Allow Cheats", worldSettings.allowCheats, &allowCheatsCallback));

	if (!build_options.isTaggedRelease) {
		list.add(CheckBox.init(.{0, 0}, 128, "Testing mode (for developers)", worldSettings.testingMode, &testingModeCallback));
	}

	presetButton = Button.initText(.{0, 0}, 128, worldPresets[selectedPreset].key_ptr.*, .init(worldPresetCallback));
	list.add(presetButton);

	const seedLabel = Label.init(.{0, 0}, 48, "Seed:", .left);
	seedInput = TextInput.init(.{0, 0}, 128 - 48, 22, "", .{.onNewline = .init(createWorld)});
	const seedRow = HorizontalList.init();
	seedRow.add(seedLabel);
	seedRow.add(seedInput);
	seedRow.finish(.{0, 0}, .center);
	list.add(seedRow);

	list.add(Button.initText(.{0, 0}, 128, "Create World", .init(createWorld)));

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

pub fn render() void {
	if(needsUpdate) {
		needsUpdate = false;
		var oldWorldName = window.rootComponent.?.verticalList.children.items[0].horizontalList.children.items[1].textInput.currentString.items;
		oldWorldName = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}", .{oldWorldName}) catch unreachable;
		defer main.stackAllocator.free(oldWorldName);

		const oldScroll = window.rootComponent.?.verticalList.children.items[2].verticalList.scrollBar.currentState;
		const oldPage = page;

		onClose();
		page = oldPage;

		onOpen();
		window.rootComponent.?.verticalList.children.items[0].horizontalList.children.items[1].textInput.setString(oldWorldName);
		window.rootComponent.?.verticalList.children.items[2].verticalList.scrollBar.currentState = oldScroll;
	}
}