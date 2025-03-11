const std = @import("std");

const main = @import("root");
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const Label = @import("../components/Label.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
};

const padding: f32 = 8;

var deleteWorldName: []const u8 = "";

pub fn init() void {
	deleteWorldName = "";
}

pub fn deinit() void {
	main.globalAllocator.free(deleteWorldName);
}

pub fn setDeleteWorldName(name: []const u8) void {
	main.globalAllocator.free(deleteWorldName);
	deleteWorldName = main.globalAllocator.dupe(u8, name);
}

fn flawedDeleteWorld(name: []const u8) !void {
	try main.files.deleteDir("saves", name);
	gui.windowlist.save_selection.needsUpdate = true;
}

fn deleteWorld(_: usize) void {
	flawedDeleteWorld(deleteWorldName) catch |err| {
		std.log.err("Encountered error while deleting world \"{s}\": {s}", .{deleteWorldName, @errorName(err)});
	};
	gui.closeWindowFromRef(&window);
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	const text = std.fmt.allocPrint(main.stackAllocator.allocator, "Are you sure you want to delete the world **{s}**", .{deleteWorldName}) catch unreachable;
	defer main.stackAllocator.free(text);
	list.add(Label.init(.{0, 0}, 128, text, .center));
	list.add(Button.initText(.{0, 0}, 128, "Yes", .{.callback = &deleteWorld}));
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
