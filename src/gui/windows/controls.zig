const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const Label = @import("../components/Label.zig");
const VerticalList = @import("../components/VerticalList.zig");

var window: GuiWindow = undefined;
var components: [1]GuiComponent = undefined;
pub fn init() !void {
	window = GuiWindow{
		.contentSize = Vec2f{128, 256},
		.id = "cubyz:controls",
		.title = "Controls",
		.onOpenFn = &onOpen,
		.onCloseFn = &onClose,
		.renderFn = &render,
		.components = &components,
	};
	try gui.addWindow(&window, true);
}

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
	var list = try VerticalList.init(main.globalAllocator);
	list.currentOffset = 8;
	inline for(comptime std.meta.fieldNames(@TypeOf(main.keyboard))) |field| {
		var label = try Label.init(main.globalAllocator, .{0, 8}, 128, field);
		var button = if(&@field(main.keyboard, field) == selectedKey) (
			try Button.init(main.globalAllocator, .{128 + 16, 8}, 128, "...", null)
		) else (
			try Button.init(main.globalAllocator, .{128 + 16, 8}, 128, @field(main.keyboard, field).getName(), &functionBuilder(field))
		);
		if(label.size[1] > button.size[1]) {
			button.pos[1] += (label.size[1] - button.size[1])/2;
			try list.add(button);
			label.pos[1] -= button.size[1] + button.pos[1];
			try list.add(label);
		} else {
			label.pos[1] += (button.size[1] - label.size[1])/2;
			try list.add(label);
			button.pos[1] -= label.size[1] + label.pos[1];
			try list.add(button);
		}
	}
	components[0] = list.toComponent(.{padding, padding});
	window.contentSize = components[0].size + @splat(2, @as(f32, 2*padding));
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