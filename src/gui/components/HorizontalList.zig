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

const HorizontalList = @This();

pos: Vec2f,
size: Vec2f,
children: std.ArrayList(GuiComponent),

pub fn init() Allocator.Error!*HorizontalList {
	const self = try gui.allocator.create(HorizontalList);
	self.* = HorizontalList {
		.children = std.ArrayList(GuiComponent).init(gui.allocator),
		.pos = undefined,
		.size = .{0, 0},
	};
	return self;
}

pub fn deinit(self: *const HorizontalList) void {
	for(self.children.items) |*child| {
		child.deinit();
	}
	self.children.deinit();
	gui.allocator.destroy(self);
}

pub fn toComponent(self: *HorizontalList) GuiComponent {
	return GuiComponent {
		.horizontalList = self
	};
}

pub fn add(self: *HorizontalList, _other: anytype) Allocator.Error!void {
	var other: GuiComponent = undefined;
	if(@TypeOf(_other) == GuiComponent) {
		other = _other;
	} else {
		other = _other.toComponent();
	}
	const added = try self.children.addOne();
	added.* = other;
	added.mutPos().*[0] += self.size[0];
	self.size[0] = added.pos()[0] + added.size()[0];
	self.size[1] = @max(self.size[1], added.pos()[1] + added.size()[1]);
}

pub fn finish(self: *HorizontalList, pos: Vec2f, alignment: graphics.TextBuffer.Alignment) void {
	self.pos = pos;
	self.children.shrinkAndFree(self.children.items.len);
	for(self.children.items) |_child| {
		const child: GuiComponent = _child;
		const mutPos = child.mutPos();
		const size = child.size();
		switch(alignment) {
			.left => {},
			.center => {
				mutPos.*[1] = mutPos.*[1]/2 + self.size[1]/2 - size[1]/2;
			},
			.right => {
				mutPos.*[1] = self.size[1] - size[1];
			},
		}
	}
}

pub fn updateSelected(self: *HorizontalList) void {
	for(self.children.items) |*child| {
		child.updateSelected();
	}
}

pub fn updateHovered(self: *HorizontalList, mousePosition: Vec2f) void {
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

pub fn render(self: *HorizontalList, mousePosition: Vec2f) anyerror!void { // TODO: Remove anyerror once error union inference works in recursive loops.
	const oldTranslation = draw.setTranslation(self.pos);
	for(self.children.items) |*child| {
		try child.render(mousePosition - self.pos);
	}
	draw.restoreTranslation(oldTranslation);
}

pub fn mainButtonPressed(self: *HorizontalList, mousePosition: Vec2f) void {
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

pub fn mainButtonReleased(self: *HorizontalList, mousePosition: Vec2f) void {
	for(self.children.items) |*child| {
		child.mainButtonReleased(mousePosition - self.pos);
	}
}