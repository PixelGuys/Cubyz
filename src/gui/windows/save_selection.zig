const std = @import("std");

const main = @import("main");
const ConnectionManager = main.network.ConnectionManager;
const settings = main.settings;
const Vec2f = main.vec.Vec2f;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const Texture = main.graphics.Texture;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const HorizontalList = @import("../components/HorizontalList.zig");
const Label = @import("../components/Label.zig");
const TextInput = @import("../components/TextInput.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
};

const padding: f32 = 8;
const width: f32 = 128;
var buttonNameArena: main.heap.NeverFailingArenaAllocator = undefined;

pub var needsUpdate: bool = false;

var deleteIcon: Texture = undefined;
var fileExplorerIcon: Texture = undefined;

const WorldInfo = struct {
	lastUsedTime: i64,
	name: []const u8,
	fileName: []const u8,
};
var worldList: main.ListUnmanaged(WorldInfo) = .{};

pub fn init() void {
	deleteIcon = Texture.initFromFile("assets/cubyz/ui/delete_icon.png");
	fileExplorerIcon = Texture.initFromFile("assets/cubyz/ui/file_explorer_icon.png");
}

pub fn deinit() void {
	deleteIcon.deinit();
	fileExplorerIcon.deinit();
}

pub fn openWorld(name: []const u8) void {
	const clientConnection = ConnectionManager.init(0, false) catch |err| {
		std.log.err("Encountered error while opening connection: {s}", .{@errorName(err)});
		return;
	};

	std.log.info("Opening world {s}", .{name});
	main.server.thread = std.Thread.spawn(.{}, main.server.start, .{name, clientConnection.localPort}) catch |err| {
		std.log.err("Encountered error while starting server thread: {s}", .{@errorName(err)});
		return;
	};
	main.server.thread.?.setName("Server") catch |err| {
		std.log.err("Failed to rename Server thread: {s}", .{@errorName(err)});
	};

	while(!main.server.running.load(.acquire)) {
		std.Thread.sleep(1_000_000);
		main.heap.GarbageCollection.syncPoint();
	}
	clientConnection.world = &main.game.testWorld;
	const ipPort = std.fmt.allocPrint(main.stackAllocator.allocator, "127.0.0.1:{}", .{main.server.connectionManager.localPort}) catch unreachable;
	defer main.stackAllocator.free(ipPort);
	main.game.world = &main.game.testWorld;
	main.game.testWorld.init(ipPort, clientConnection) catch |err| {
		std.log.err("Encountered error while opening world: {s}", .{@errorName(err)});
	};
	for(gui.openWindows.items) |openWindow| {
		gui.closeWindowFromRef(openWindow);
	}
	gui.openHud();
}

fn openWorldWrap(index: usize) void { // TODO: Improve this situation. Maybe it makes sense to always use 2 arguments in the Callback.
	openWorld(worldList.items[index].fileName);
}

fn deleteWorld(index: usize) void {
	main.gui.closeWindow("delete_world_confirmation");
	main.gui.windowlist.delete_world_confirmation.setDeleteWorldName(worldList.items[index].fileName);
	main.gui.openWindow("delete_world_confirmation");
}

fn openFolder(index: usize) void {
	const path = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/saves/{s}", .{main.files.cubyzDirStr(), worldList.items[index].fileName}) catch unreachable;
	defer main.stackAllocator.free(path);

	main.files.openDirInWindow(path);
}

pub fn update() void {
	if(needsUpdate) {
		needsUpdate = false;
		onClose();
		onOpen();
	}
}

pub fn onOpen() void {
	buttonNameArena = main.heap.NeverFailingArenaAllocator.init(main.globalAllocator);
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 8);
	list.add(Label.init(.{0, 0}, width, "**Select World**", .center));
	list.add(Button.initText(.{0, 0}, 128, "Create New World", gui.openWindowCallback("save_creation")));
	readingSaves: {
		var dir = main.files.cubyzDir().openIterableDir("saves") catch |err| {
			list.add(Label.init(.{0, 0}, 128, "Encountered error while trying to open saves folder:", .center));
			list.add(Label.init(.{0, 0}, 128, @errorName(err), .center));
			break :readingSaves;
		};
		defer dir.close();

		var iterator = dir.iterate();
		while(iterator.next() catch |err| {
			list.add(Label.init(.{0, 0}, 128, "Encountered error while iterating over saves folder:", .center));
			list.add(Label.init(.{0, 0}, 128, @errorName(err), .center));
			break :readingSaves;
		}) |entry| {
			if(entry.kind == .directory) {
				const worldInfoPath = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/world.zig.zon", .{entry.name}) catch unreachable;
				defer main.stackAllocator.free(worldInfoPath);
				const worldInfo = main.files.cubyzDir().readToZon(main.stackAllocator, worldInfoPath) catch |err| {
					std.log.err("Couldn't open save {s}: {s}", .{worldInfoPath, @errorName(err)});
					continue;
				};
				defer worldInfo.deinit(main.stackAllocator);

				worldList.append(main.globalAllocator, .{
					.fileName = main.globalAllocator.dupe(u8, entry.name),
					.lastUsedTime = worldInfo.get(i64, "lastUsedTime", 0),
					.name = main.globalAllocator.dupe(u8, worldInfo.get([]const u8, "name", entry.name)),
				});
			}
		}
	}

	std.sort.insertion(WorldInfo, worldList.items, {}, struct {
		fn lessThan(_: void, lhs: WorldInfo, rhs: WorldInfo) bool {
			return rhs.lastUsedTime -% lhs.lastUsedTime < 0;
		}
	}.lessThan);

	for(worldList.items, 0..) |worldInfo, i| {
		const row = HorizontalList.init();
		row.add(Button.initText(.{0, 0}, 128, worldInfo.name, .{.callback = &openWorldWrap, .arg = i}));
		row.add(Button.initIcon(.{8, 0}, .{16, 16}, fileExplorerIcon, false, .{.callback = &openFolder, .arg = i}));
		row.add(Button.initIcon(.{8, 0}, .{16, 16}, deleteIcon, false, .{.callback = &deleteWorld, .arg = i}));
		row.finish(.{0, 0}, .center);
		list.add(row);
	}

	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	for(worldList.items) |worldInfo| {
		main.globalAllocator.free(worldInfo.fileName);
		main.globalAllocator.free(worldInfo.name);
	}
	worldList.clearAndFree(main.globalAllocator);
	buttonNameArena.deinit();
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}
