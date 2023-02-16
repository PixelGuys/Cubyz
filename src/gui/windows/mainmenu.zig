const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const VerticalList = @import("../components/VerticalList.zig");

var mainmenuWindow: GuiWindow = undefined;
var components: [1]GuiComponent = undefined;
var hotbarWindow2: GuiWindow = undefined;
var hotbarWindow3: GuiWindow = undefined;
pub fn init() !void {
	mainmenuWindow = GuiWindow{
		.contentSize = Vec2f{128, 256},
		.id = "cubyz:mainmenu",
		.onOpenFn = &onOpen,
		.onCloseFn = &onClose,
		.components = &components,
	};
	try gui.addWindow(&mainmenuWindow, true);
}

pub fn buttonCallbackTest() void {
	std.log.info("Clicked!", .{});
}

pub fn onOpen() Allocator.Error!void {
	var list = try VerticalList.init(main.globalAllocator);
	try list.add(try Button.init(.{0, 16}, .{128, 32}, main.globalAllocator, "Singleplayer player player", &buttonCallbackTest));
	try list.add(try Button.init(.{0, 16}, .{128, 32}, main.globalAllocator, "Multiplayer", &buttonCallbackTest));
	try list.add(try Button.init(.{0, 16}, .{128, 32}, main.globalAllocator, "Settings", &buttonCallbackTest));
	try list.add(try Button.init(.{0, 16}, .{128, 32}, main.globalAllocator, "Exit", &buttonCallbackTest));
	components[0] = list.toComponent(.{0, 0});
	mainmenuWindow.contentSize = components[0].size;
	gui.updateWindowPositions();
}

pub fn onClose() void {
	for(components) |*comp| {
		comp.deinit();
	}
}