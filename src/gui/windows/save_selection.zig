const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const ConnectionManager = main.network.ConnectionManager;
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const HorizontalList = @import("../components/HorizontalList.zig");
const Label = @import("../components/Label.zig");
const TextInput = @import("../components/TextInput.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow {
	.contentSize = Vec2f{128, 256},
	.id = "save_selection",
};

const padding: f32 = 8;
const width: f32 = 128;
var buttonNameArena: std.heap.ArenaAllocator = undefined;

fn openWorld(namePtr: usize) void {
	const nullTerminatedName = @intToPtr([*:0]const u8, namePtr);
	const name = std.mem.span(nullTerminatedName);
	std.log.info("TODO: Open world {s}", .{name});
//	new Thread(() -> Server.main(new String[] {name}), "Server Thread").start();
//	Cubyz.gameUI.setMenu(null, false); // hide from UISystem.back()
//	while(Server.world == null) {
//		try {
//			Thread.sleep(10);
//		} catch(InterruptedException e) {}
//	}
//	try {
//		GameLauncher.logic.loadWorld(new ClientWorld("127.0.0.1", new UDPConnectionManager(Constants.DEFAULT_PORT+1, false))); // TODO: Don't go over the local network in singleplayer.
//	} catch(InterruptedException e) {}
}

fn flawedDeleteWorld(name: []const u8) !void {
	var saveDir = try std.fs.cwd().openDir("saves", .{});
	defer saveDir.close();
	try saveDir.deleteTree(name);

	onClose();
	try onOpen();
}

fn deleteWorld(namePtr: usize) void {
	const nullTerminatedName = @intToPtr([*:0]const u8, namePtr);
	const name = std.mem.span(nullTerminatedName);
	flawedDeleteWorld(name) catch |err| {
		std.log.err("Encountered error while deleting world \"{s}\": {s}", .{name, @errorName(err)});
	};
}

fn parseEscapedFolderName(name: []const u8) ![]const u8 {
	var result = std.ArrayList(u8).init(main.threadAllocator);
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
			try result.appendSlice(buf[0..std.unicode.utf8Encode(val, &buf) catch 0]); // TODO: Change this to full unicode rather than using this broken utf-16 converter.
		} else {
			try result.append(name[i]);
		}
	}
	return try result.toOwnedSlice();
}

pub fn onOpen() Allocator.Error!void {
	buttonNameArena = std.heap.ArenaAllocator.init(main.globalAllocator);
	var list = try VerticalList.init(.{padding, 16 + padding}, 300, 8);
	// TODO: try list.add(try Button.initText(.{0, 0}, 128, "Create World", gui.openWindowCallback("save_creation")));

	var dir: std.fs.IterableDir = std.fs.cwd().makeOpenPathIterable("saves", .{}) catch |err| {
		std.log.err("Encountered error while trying to open folder \"saves\": {s}", .{@errorName(err)});
		return;
	};
	defer dir.close();

	var iterator = dir.iterate();
	while(iterator.next() catch |err| {
		std.log.err("Encountered error while iterating over folder \"saves\": {s}", .{@errorName(err)});
		return;
	}) |entry| {
		if(entry.kind == .Directory) {
			var row = try HorizontalList.init();

			const decodedName = try parseEscapedFolderName(entry.name);
			defer main.threadAllocator.free(decodedName);
			const name = try buttonNameArena.allocator().dupeZ(u8, entry.name); // Null terminate, so we can later recover the string from jsut the pointer.
			const buttonName = try std.fmt.allocPrint(buttonNameArena.allocator(), "Play {s}", .{decodedName});
			
			try row.add(try Button.initText(.{0, 0}, 128, buttonName, .{.callback = &openWorld, .arg = @ptrToInt(name.ptr)}));
			try row.add(try Button.initText(.{8, 0}, 64, "delete", .{.callback = &deleteWorld, .arg = @ptrToInt(name.ptr)}));
			row.finish(.{0, 0}, .center);
			try list.add(row);
		}
	}

	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @splat(2, @as(f32, padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	buttonNameArena.deinit();
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}