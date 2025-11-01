const std = @import("std");

const build_options = @import("build_options");

//const main = @import("main");
const main = @import("../../main.zig");
const ConnectionManager = main.network.ConnectionManager;
const settings = main.settings;
const Vec2f = main.vec.Vec2f;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const Texture = main.graphics.Texture;
const assets = main.assets;

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

var deleteIcon: Texture = undefined;
var fileExplorerIcon: Texture = undefined;

var addonPathList: main.ListUnmanaged([]const u8) = .{};

var page: Page = .generation;
const numPages: usize = std.meta.fields(Page).len;

const Page = enum(u8) {
	generation = 0,
	gameRules = 1,
	addons = 2,

	pub fn fillSubmenu(self: Page, submenu: *VerticalList) void {
		switch(self) {
			.generation => {
				submenu.add(Label.init(.{0, 0}, 256 - 64, "this is the first page", .center));
			},
			.gameRules => {
				submenu.add(Label.init(.{0, 0}, 256 - 64, "this is the second page", .center));
			},
			.addons => {
				if(addonPathList.items.len > 0) {
					const addonsList = VerticalList.init(.{0, 0}, 256, padding);
					for(addonPathList.items, 0..) |addonPath, i| {
						const addonName = nameFromPath(main.stackAllocator, addonPath) catch unreachable;
						defer main.stackAllocator.free(addonName);

						const nameLabel = Label.init(.{0, 0}, 192 - 8 - 26 - 8 - 26, addonName, .left);
						const folderButton = Button.initIcon(.{8, 0}, .{16, 16}, fileExplorerIcon, false, .{.callback = &openFolder, .arg = i});
						const deleteButton = Button.initIcon(.{8, 0}, .{16, 16}, deleteIcon, false, .{.callback = &removeAddon, .arg = i});
						const row = HorizontalList.init();
						row.add(nameLabel);
						row.add(folderButton);
						row.add(deleteButton);
						row.finish(.{0, 0}, .center);
						addonsList.add(row);
					}
					addonsList.finish(.center);
					submenu.add(addonsList);
				} else {
					submenu.add(Label.init(.{0, 0}, 192, "*No addons yet*", .center));
				}

				const buttonRow = HorizontalList.init();
				if(addonPathList.items.len > 0)
				{
					buttonRow.add(Label.init(.{0, 0}, 192 - 120, "", .left));
					buttonRow.add(Button.initText(.{0, 0}, 120, "Add More...", .{.callback = &addAddon}));
				} else {
					buttonRow.add(Button.initText(.{0, 0}, 80, "Add...", .{.callback = &addAddon}));
				}
				buttonRow.finish(.{0, 0}, .center);
				submenu.add(buttonRow);

				// TODO: add global addons folder button and information dialog explaining what global addons are
			},
		}
	}

	pub fn label(self: Page) []const u8 {
		switch(self) {
			.generation => {
				return "Generation";
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

pub fn init() void {
	deleteIcon = Texture.initFromFile("assets/cubyz/ui/delete_icon.png");
	fileExplorerIcon = Texture.initFromFile("assets/cubyz/ui/file_explorer_icon.png");
}

pub fn deinit() void {
	deleteIcon.deinit();
	fileExplorerIcon.deinit();
}

fn openFolder(index: usize) void {
	main.files.openDirInWindow(addonPathList.items[index]);
}

fn removeAddon(index: usize) void {
	main.globalAllocator.free(addonPathList.orderedRemove(index));
	needsUpdate = true;
}

fn addAddon(_: usize) void {
	const newAddonPathOptional = main.files.folderQuery(main.globalAllocator) catch return;
	if(newAddonPathOptional) |newAddonPath| {

		for(addonPathList.items) |addonPath|{
			const addonName = nameFromPath(main.stackAllocator, addonPath) catch unreachable;
			const newAddonName = nameFromPath(main.stackAllocator, newAddonPath) catch unreachable;
			defer {
				main.stackAllocator.free(addonName);
				main.stackAllocator.free(newAddonName);
			}
			if(std.mem.eql(u8, addonName, newAddonName)) {
				main.globalAllocator.free(newAddonPath);
				return;
			}
		}

		addonPathList.append(main.globalAllocator, newAddonPath);
		needsUpdate = true;
	}
}

fn nameFromPath(allocator: main.heap.NeverFailingAllocator, path: []const u8) ![]const u8 {
	if(std.mem.lastIndexOf(u8, path, "/")) |lastSlash| {
		return std.fmt.allocPrint(allocator.allocator, "{s}", .{path[(lastSlash + 1)..]}) catch unreachable;
	} else {
		std.log.err("Could not find / in {s}", .{path});
		return error.NeedleNotFound;
	}
}

fn prevPage(_: usize) void {
	const oldPageInt = @intFromEnum(page);
	const newPageInt = (oldPageInt -% 1);
	page = std.meta.intToEnum(Page, newPageInt) catch .addons;
	needsUpdate = true;
}

fn nextPage(_: usize) void {
	const oldPageInt = @intFromEnum(page);
	const newPageInt = (oldPageInt + 1);
	page = std.meta.intToEnum(Page, newPageInt) catch .generation;
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

	{ // name field
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

	{ // page title and switch buttons
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

	const submenu = VerticalList.init(.{0, 8}, 384, 8);
	page.fillSubmenu(submenu);
	submenu.finish(.center);
	list.add(submenu);

	list.add(Button.initText(.{0, 8}, 128, "Create World", .{.callback = &createWorld}));

	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
	page = .generation;
	
	for (addonPathList.items) |addonPath| {
		main.globalAllocator.free(addonPath);
	}
	addonPathList.clearAndFree(main.globalAllocator);
}

pub fn render() void {
	if(needsUpdate) {
		needsUpdate = false;
		var oldWorldName = window.rootComponent.?.verticalList.children.items[0].horizontalList.children.items[1].textInput.currentString.items;
		oldWorldName = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}", .{oldWorldName}) catch unreachable;
		defer main.stackAllocator.free(oldWorldName);

		const oldScroll = window.rootComponent.?.verticalList.children.items[2].verticalList.scrollBar.currentState;
		const oldPage = page;
		var oldAddonPathList: main.ListUnmanaged([]const u8) = .{};
		defer oldAddonPathList.clearAndFree(main.stackAllocator);
		
		for (addonPathList.items) |path| {
			oldAddonPathList.append(main.stackAllocator, main.globalAllocator.dupe(u8, path));
		}

		onClose();
		page = oldPage;
		for (oldAddonPathList.items) |oldPath| {
			addonPathList.append(main.globalAllocator, oldPath);
		}

		onOpen();
		window.rootComponent.?.verticalList.children.items[0].horizontalList.children.items[1].textInput.setString(oldWorldName);
		window.rootComponent.?.verticalList.children.items[2].verticalList.scrollBar.currentState = oldScroll;
	}
}