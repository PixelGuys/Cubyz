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

	while(!main.server.running.load(.acquire)) {
		std.time.sleep(1_000_000);
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

fn openWorldWrap(namePtr: usize) void { // TODO: Improve this situation. Maybe it makes sense to always use 2 arguments in the Callback.
	const nullTerminatedName: [*:0]const u8 = @ptrFromInt(namePtr);
	const name = std.mem.span(nullTerminatedName);
	openWorld(name);
}

fn deleteWorld(namePtr: usize) void {
	const nullTerminatedName: [*:0]const u8 = @ptrFromInt(namePtr);
	const name = std.mem.span(nullTerminatedName);
	main.gui.closeWindow("delete_world_confirmation");
	main.gui.windowlist.delete_world_confirmation.setDeleteWorldName(name);
	main.gui.openWindow("delete_world_confirmation");
}

fn openFolder(namePtr: usize) void {
	const nullTerminatedName: [*:0]const u8 = @ptrFromInt(namePtr);
	const name = std.mem.span(nullTerminatedName);

	const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}", .{name}) catch unreachable;
	defer main.stackAllocator.free(path);

	main.files.openDirInWindow(path);
}

fn parseEscapedFolderName(allocator: NeverFailingAllocator, name: []const u8) []const u8 {
	var result = main.List(u8).init(allocator);
	defer result.deinit();
	var i: u32 = 0;
	while(i < name.len) : (i += 1) {
		if(name[i] == '_') {
			var val: u21 = 0;
			for(0..4) |_| {
				i += 1;
				if(i < name.len) {
					val = val*16 + switch(name[i]) {
						'0'...'9' => name[i] - '0',
						'a'...'f' => name[i] - 'a' + 10,
						'A'...'F' => name[i] - 'A' + 10,
						else => 0,
					};
				}
			}
			var buf: [4]u8 = undefined;
			result.appendSlice(buf[0 .. std.unicode.utf8Encode(val, &buf) catch 0]); // TODO: Change this to full unicode rather than using this broken utf-16 converter.
		} else {
			result.append(name[i]);
		}
	}
	return result.toOwnedSlice();
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
		var dir = std.fs.cwd().makeOpenPath("saves", .{.iterate = true}) catch |err| {
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
				const row = HorizontalList.init();

				const decodedName = parseEscapedFolderName(main.stackAllocator, entry.name);
				defer main.stackAllocator.free(decodedName);
				const name = buttonNameArena.allocator().dupeZ(u8, entry.name); // Null terminate, so we can later recover the string from just the pointer.
				const buttonName = std.fmt.allocPrint(buttonNameArena.allocator().allocator, "{s}", .{decodedName}) catch unreachable;

				row.add(Button.initText(.{0, 0}, 128, buttonName, .{.callback = &openWorldWrap, .arg = @intFromPtr(name.ptr)}));
				row.add(Button.initIcon(.{8, 0}, .{16, 16}, fileExplorerIcon, false, .{.callback = &openFolder, .arg = @intFromPtr(name.ptr)}));
				row.add(Button.initIcon(.{8, 0}, .{16, 16}, deleteIcon, false, .{.callback = &deleteWorld, .arg = @intFromPtr(name.ptr)}));
				row.finish(.{0, 0}, .center);
				list.add(row);
			}
		}
	}

	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	buttonNameArena.deinit();
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}
