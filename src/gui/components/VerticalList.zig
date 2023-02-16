const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const graphics = main.graphics;
const draw = graphics.draw;
const TextBuffer = graphics.TextBuffer;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;

const VerticalList = @This();

children: std.ArrayList(GuiComponent),
currentOffset: f32 = 0,
maxWidth: f32 = 0,

pub fn init(allocator: Allocator) Allocator.Error!VerticalList {
	const self = VerticalList {
		.children = std.ArrayList(GuiComponent).init(allocator),
	};
	return self;
}

pub fn deinit(self: VerticalList) void {
	for(self.children.items) |*child| {
		child.deinit();
	}
	self.children.deinit();
}

pub fn toComponent(self: *VerticalList, pos: Vec2f) GuiComponent {
	for(self.children.items) |*child| {
		child.pos += pos;
	}
	return GuiComponent {
		.pos = pos,
		.size = .{self.maxWidth, self.currentOffset},
		.impl = .{.verticalList = self.*}
	};
}

pub fn add(self: *VerticalList, other: GuiComponent) Allocator.Error!void {
	const added = try self.children.addOne();
	added.* = other;
	added.pos[1] += self.currentOffset;
	self.currentOffset = added.pos[1] + added.size[1];
	self.maxWidth = @max(self.maxWidth, added.pos[0] + added.size[0]);
}

pub fn update(self: *VerticalList, _: *const GuiComponent) void {
	for(self.children.items) |*child| {
		child.update();
	}
}

pub fn render(self: *VerticalList, _: *const GuiComponent, mousePosition: Vec2f) anyerror!void { // TODO: Remove anyerror once error union inference works in recursive loops.
	for(self.children.items) |*child| {
		try child.render(mousePosition);
	}
}

pub fn mainButtonPressed(self: *VerticalList, _: *const GuiComponent, mousePosition: Vec2f) void {
	var selectedChild: ?*GuiComponent = null;
	for(self.children.items) |*child| {
		if(child.contains(mousePosition)) {
			selectedChild = child;
		}
	}
	if(selectedChild) |child| {
		child.mainButtonPressed(mousePosition);
	}
}

pub fn mainButtonReleased(self: *VerticalList, _: *const GuiComponent, mousePosition: Vec2f) void {
	for(self.children.items) |*child| {
		child.mainButtonReleased(mousePosition);
	}
}