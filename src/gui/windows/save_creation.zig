const std = @import("std");

const build_options = @import("build_options");

const main = @import("main");
const ConnectionManager = main.network.ConnectionManager;
const settings = main.settings;
const Vec2f = main.vec.Vec2f;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
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

var gamemode: main.game.Gamemode = .creative;
var gamemodeInput: *Button = undefined;

var allowCheats: bool = true;

var testingMode: bool = false;

const ZonMapEntry = std.StringHashMapUnmanaged(ZonElement).Entry;
var worldPresets: []ZonMapEntry = &.{};
var selectedPreset: usize = undefined;
var defaultPreset: usize = 0;
var presetButton: *Button = undefined;

fn chooseSeed(seedStr: []const u8) u64 {
	if(seedStr.len == 0) {
		return main.random.nextInt(u64, &main.seed);
	} else {
		return std.fmt.parseInt(u64, seedStr, 0) catch {
			return std.hash.Wyhash.hash(0, seedStr);
		};
	}
}

fn gamemodeCallback() void {
	gamemode = std.meta.intToEnum(main.game.Gamemode, @intFromEnum(gamemode) + 1) catch @enumFromInt(0);
	gamemodeInput.child.label.updateText(@tagName(gamemode));
}

fn worldPresetCallback() void {
	selectedPreset += 1;
	if(selectedPreset == worldPresets.len) selectedPreset = 0;
	presetButton.child.label.updateText(worldPresets[selectedPreset].key_ptr.*);
}

fn allowCheatsCallback(allow: bool) void {
	allowCheats = allow;
}

fn testingModeCallback(enabled: bool) void {
	testingMode = enabled;
}

fn createWorld() void {
	const worldName = nameInput.currentString.items;
	const worldSeed = chooseSeed(seedInput.currentString.items);

	const worldSettings: main.server.world_zig.Settings = .{
		.defaultGamemode = gamemode,
		.allowCheats = allowCheats,
		.testingMode = testingMode,
		.seed = worldSeed,
	};

	main.server.world_zig.tryCreateWorld(worldName, worldSettings, worldPresets[selectedPreset].value_ptr.*) catch |err| {
		std.log.err("Error while creating new world: {s}", .{@errorName(err)});
	};
	gui.closeWindowFromRef(&window);
	gui.windowlist.save_selection.needsUpdate = true;
	gui.openWindow("save_selection");
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 8);

	if(worldPresets.len == 0) {
		var presetMap = main.assets.worldPresets();
		var entryList: main.ListUnmanaged(ZonMapEntry) = .initCapacity(main.globalArena, presetMap.count());
		var iterator = presetMap.iterator();
		while(iterator.next()) |entry| {
			entryList.appendAssumeCapacity(entry);
		}

		std.sort.insertion(ZonMapEntry, entryList.items, {}, struct{
			fn lessThanFn(_: void, lhs: ZonMapEntry, rhs: ZonMapEntry) bool {
				return std.ascii.lessThanIgnoreCase(lhs.key_ptr.*, rhs.key_ptr.*);
			}
		}.lessThanFn);
		worldPresets = entryList.items;
		for(worldPresets, 0..) |entry, i| {
			if(std.mem.eql(u8, entry.key_ptr.*, "cubyz:default")) {
				defaultPreset = i;
			}
		}
	}
	selectedPreset = defaultPreset;

	var num: usize = 1;
	while(true) {
		const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/Save{}", .{num}) catch unreachable;
		defer main.stackAllocator.free(path);
		if(!main.files.cubyzDir().hasDir(path)) break;
		num += 1;
	}
	const name = std.fmt.allocPrint(main.stackAllocator.allocator, "Save{}", .{num}) catch unreachable;
	defer main.stackAllocator.free(name);
	nameInput = TextInput.init(.{0, 0}, 128, 22, name, .{.onNewline = .init(createWorld)});
	list.add(nameInput);

	gamemodeInput = Button.initText(.{0, 0}, 128, @tagName(gamemode), .init(gamemodeCallback));
	list.add(gamemodeInput);

	list.add(CheckBox.init(.{0, 0}, 128, "Allow Cheats", allowCheats, &allowCheatsCallback));

	if(!build_options.isTaggedRelease) {
		list.add(CheckBox.init(.{0, 0}, 128, "Testing mode (for developers)", testingMode, &testingModeCallback));
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
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}
