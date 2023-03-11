const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const TextInput = @import("../components/TextInput.zig");
const VerticalList = @import("../components/VerticalList.zig");

var window: GuiWindow = undefined;
var components: [1]GuiComponent = undefined;
pub fn init() !void {
	window = GuiWindow{
		.contentSize = Vec2f{128, 256},
		.id = "cubyz:change_name",
		.title = "Change Name",
		.onOpenFn = &onOpen,
		.onCloseFn = &onClose,
		.components = &components,
	};
	try gui.addWindow(&window, true);
}

const padding: f32 = 8;

pub fn onOpen() Allocator.Error!void {
	var list = try VerticalList.init();
	// TODO Please change your name bla bla
	try list.add(try TextInput.init(.{0, 16}, 128, 256, "gr da jkwa hfeka fuei   \n ofuiewo\natg78o4ea74e8t\nz57 t4738qa0 47a80 t47803a t478aqv t487 5t478a0 tg478a09 t748ao t7489a rt4e5 okv5895 678v54vgvo6r z8or z578v rox74et8ys9otv 4z3789so z4oa9t z489saoyt z"));
	// TODO: Done button.
	components[0] = list.toComponent(.{padding, padding});
	window.contentSize = components[0].size + @splat(2, @as(f32, 2*padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	for(&components) |*comp| {
		comp.deinit();
	}
}