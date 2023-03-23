const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const HorizontalList = @import("../components/HorizontalList.zig");
const Label = @import("../components/Label.zig");
const VerticalList = @import("../components/VerticalList.zig");

var components: [1]GuiComponent = undefined;
pub var window = GuiWindow {
	.contentSize = Vec2f{128, 256},
	.id = "cubyz:controls",
	.title = "Controls",
	.components = &components,
};

const padding: f32 = 8;
var selectedKey: ?*main.Key = null;
var needsUpdate: bool = false;

fn functionBuilder(comptime name: []const u8) fn() void {
	return struct {
		fn function() void {
			main.setNextKeypressListener(&keypressListener) catch return;
			selectedKey = &@field(main.keyboard, name);
			needsUpdate = true;
		}
	}.function;
}

fn keypressListener(key: c_int, mouseButton: c_int, scancode: c_int) void {
	selectedKey.?.key = key;
	selectedKey.?.mouseButton = mouseButton;
	selectedKey.?.scancode = scancode;
	selectedKey = null;
	needsUpdate = true;
}

pub fn onOpen() Allocator.Error!void {
	var list = try VerticalList.init(.{padding, 16 + padding}, 300, 8);
	inline for(comptime std.meta.fieldNames(@TypeOf(main.keyboard))) |field| {
		var label = try Label.init(.{0, 0}, 128, field, .left);
		var button = if(&@field(main.keyboard, field) == selectedKey) (
			try Button.init(.{16, 0}, 128, "...", null)
		) else (
			try Button.init(.{16, 0}, 128, @field(main.keyboard, field).getName(), &functionBuilder(field))
		);
		var row = try HorizontalList.init();
		try row.add(label);
		try row.add(button);
		row.finish(.{0, 0}, .center);
		try list.add(row);
	}
	list.finish(.center);
	components[0] = list.toComponent();
	window.contentSize = components[0].pos() + components[0].size() + @splat(2, @as(f32, padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	for(&components) |*comp| {
		comp.deinit();
	}
}

pub fn render() Allocator.Error!void {
	if(needsUpdate) {
		needsUpdate = false;
		onClose();
		onOpen() catch {
			std.log.err("Received out of memory error while rebuilding the controls GUI. This behavior is not handled.", .{});
		};
	}
}