const std = @import("std");

const main = @import("main");
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const EntityModelFrame = @import("../components/EntityModelFrame.zig");
const Label = @import("../components/Label.zig");
const TextInput = @import("../components/TextInput.zig");
const VerticalList = @import("../components/VerticalList.zig");
const HorizontalList = @import("../components/HorizontalList.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{64*10, 64*3},
	.scale = 0.75,
	.isHud = true,
	.closeable = false,
};

const padding: f32 = 8;

fn apply(pIndex:usize) void {
	std.log.debug("picked model {}\n", .{pIndex});
	//const index = main.entityModel.EntityModelIndex{.index = pIndex};
	gui.closeWindowFromRef(&window);
}

pub fn onOpen() void {
    const list = HorizontalList.init();
    //TODO: use scrollbar
    for (main.entityModel.playerEntityModels.items) |index| { 
	    const verticalList = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	    verticalList.add(EntityModelFrame.init(.{0, 0}, .{100, 100},index));
	    verticalList.add(Button.initText(.{0, 0}, 100, "Use", .initWithInt(apply,index.index)));
	    verticalList.finish(.center);
        list.add(verticalList);
    }
    list.finish(.{padding, 16 + padding}, .left);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}
