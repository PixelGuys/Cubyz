const std = @import("std");

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
children: main.List(GuiComponent),

pub fn init() *HorizontalList {
	const self = main.globalAllocator.create(HorizontalList);
	self.* = HorizontalList {
		.children = main.List(GuiComponent).init(main.globalAllocator),
		.pos = .{0, 0},
		.size = .{0, 0},
	};
	return self;
}

pub fn deinit(self: *const HorizontalList) void {
	for(self.children.items) |*child| {
		child.deinit();
	}
	self.children.deinit();
	main.globalAllocator.destroy(self);
}

pub fn toComponent(self: *HorizontalList) GuiComponent {
	return GuiComponent {
		.horizontalList = self
	};
}

pub fn add(self: *HorizontalList, _other: anytype) void {
	var other: GuiComponent = undefined;
	if(@TypeOf(_other) == GuiComponent) {
		other = _other;
	} else {
		other = _other.toComponent();
	}
	other.mutPos().*[0] += self.size[0];
	self.size[0] = other.pos()[0] + other.size()[0];
	self.size[1] = @max(self.size[1], other.pos()[1] + other.size()[1]);
	self.children.append(other);
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

pub fn render(self: *HorizontalList, mousePosition: Vec2f) void {
	const oldTranslation = draw.setTranslation(self.pos);
	for(self.children.items) |*child| {
		child.render(mousePosition - self.pos);
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