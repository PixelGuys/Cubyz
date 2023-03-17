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

pos: Vec2f,
size: Vec2f,
children: std.ArrayList(GuiComponent),

pub fn init() Allocator.Error!*VerticalList {
	const self = try gui.allocator.create(VerticalList);
	self.* = VerticalList {
		.children = std.ArrayList(GuiComponent).init(gui.allocator),
		.pos = undefined,
		.size = .{0, 0},
	};
	return self;
}

pub fn deinit(self: *const VerticalList) void {
	for(self.children.items) |*child| {
		child.deinit();
	}
	self.children.deinit();
	gui.allocator.destroy(self);
}

pub fn toComponent(self: *VerticalList, pos: Vec2f) GuiComponent {
	self.pos = pos;
	return GuiComponent {
		.verticalList = self
	};
}

pub fn add(self: *VerticalList, _other: anytype) Allocator.Error!void {
	var other: GuiComponent = undefined;
	if(@TypeOf(_other) == GuiComponent) {
		other = _other;
	} else {
		other = _other.toComponent();
	}
	const added = try self.children.addOne();
	added.* = other;
	added.mutPos().*[1] += self.size[1];
	self.size[1] = added.pos()[1] + added.size()[1];
	self.size[0] = @max(self.size[0], added.pos()[0] + added.size()[0]);
}

pub fn updateSelected(self: *VerticalList) void {
	for(self.children.items) |*child| {
		child.updateSelected();
	}
}

pub fn updateHovered(self: *VerticalList, mousePosition: Vec2f) void {
	var i: usize = self.children.items.len;
	while(i != 0) {
		i -= 1;
		const child = &self.children.items[i];
		if(GuiComponent.contains(child.pos() + self.pos, child.size(), mousePosition)) {
			child.updateHovered(mousePosition - self.pos);
			break;
		}
	}
}

pub fn render(self: *VerticalList, mousePosition: Vec2f) anyerror!void { // TODO: Remove anyerror once error union inference works in recursive loops.
	const oldTranslation = draw.setTranslation(self.pos);
	for(self.children.items) |*child| {
		try child.render(mousePosition - self.pos);
	}
	draw.restoreTranslation(oldTranslation);
}

pub fn mainButtonPressed(self: *VerticalList, mousePosition: Vec2f) void {
	var selectedChild: ?*GuiComponent = null;
	for(self.children.items) |*child| {
		if(GuiComponent.contains(child.pos() + self.pos, child.size(), mousePosition)) {
			selectedChild = child;
		}
	}
	if(selectedChild) |child| {
		child.mainButtonPressed(mousePosition - self.pos);
	}
}

pub fn mainButtonReleased(self: *VerticalList, mousePosition: Vec2f) void {
	for(self.children.items) |*child| {
		child.mainButtonReleased(mousePosition - self.pos);
	}
}