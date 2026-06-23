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
	.closeable = true,
};

const padding: f32 = 8;

fn apply(modelIndex: usize) void {
	const emi: main.entityModel.EntityModelIndex = .{.index = @intCast(modelIndex)};
	std.log.debug("picked model {s}", .{emi.get().entityModelId});

	const command = std.fmt.allocPrint(main.globalAllocator.allocator, "avatar {s}", .{emi.get().entityModelId}) catch unreachable;
	main.sync.client.executeCommand(.{.chatCommand = .{.message = command}});
	gui.closeWindowFromRef(&window);
}

pub fn onOpen() void { 
	const rows = VerticalList.init(.{0,0}, 400, padding);
	var row = HorizontalList.init();


	for (main.entityModel.playerEntityModels.items) |index| {
		const verticalList = VerticalList.init(.{padding, padding}, 300, padding);
		verticalList.add(Label.init(.{0,0}, 100, index.get().entityModelId, .center));
		verticalList.add(EntityModelFrame.init(.{0, 0}, .{100, 100}, index));
		verticalList.add(Button.initText(.{0, 0}, 100, "Use", .{.onAction = .initWithInt(apply, index.index)}));
		verticalList.finish(.center);
		row.add(verticalList);
		if(row.children.items.len >= 5){
			row.finish(.{padding, 16 + padding}, .left);
			rows.add(row);
 			row = HorizontalList.init();
		}
	}
	row.finish(.{padding, 16 + padding}, .left);
	if(row.children.items.len != 0)	rows.add(row);
	rows.finish(.center);
	
	window.rootComponent = rows.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}
