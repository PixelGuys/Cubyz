const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const TextBuffer = graphics.TextBuffer;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const ScrollBar = GuiComponent.ScrollBar;

const VerticalList = @This();

const scrollBarWidth = 10;
const border: f32 = 3;

pos: Vec2f,
size: Vec2f,
children: main.List(GuiComponent),
padding: f32,
maxHeight: f32,
childrenHeight: f32 = 0,
scrollBar: *ScrollBar,
scrollBarEnabled: bool = false,

pub fn init(pos: Vec2f, maxHeight: f32, padding: f32) *VerticalList {
	const scrollBar = ScrollBar.init(undefined, scrollBarWidth, maxHeight - 2*border, 0);
	const self = main.globalAllocator.create(VerticalList);
	self.* = VerticalList{
		.children = .init(main.globalAllocator),
		.pos = pos,
		.size = .{0, 0},
		.padding = padding,
		.maxHeight = maxHeight,
		.scrollBar = scrollBar,
	};
	return self;
}

pub fn deinit(self: *const VerticalList) void {
	for(self.children.items) |*child| {
		child.deinit();
	}
	self.scrollBar.deinit();
	self.children.deinit();
	main.globalAllocator.destroy(self);
}

pub fn toComponent(self: *VerticalList) GuiComponent {
	return .{.verticalList = self};
}

pub fn add(self: *VerticalList, _other: anytype) void {
	var other: GuiComponent = undefined;
	if(@TypeOf(_other) == GuiComponent) {
		other = _other;
	} else {
		other = _other.toComponent();
	}
	other.mutPos().*[1] += self.size[1];
	if(self.size[1] != 0) other.mutPos().*[1] += self.padding;
	self.size[1] = other.pos()[1] + other.size()[1];
	self.size[0] = @max(self.size[0], other.pos()[0] + other.size()[0]);
	self.children.append(other);
}

pub fn finish(self: *VerticalList, alignment: graphics.TextBuffer.Alignment) void {
	self.children.shrinkAndFree(self.children.items.len);
	for(self.children.items) |_child| {
		const child: GuiComponent = _child;
		const mutPos = child.mutPos();
		const size = child.size();
		switch(alignment) {
			.left => {},
			.center => {
				mutPos.*[0] = mutPos.*[0]/2 + self.size[0]/2 - size[0]/2;
			},
			.right => {
				mutPos.*[0] = self.size[0] - size[0];
			},
		}
	}
	if(self.size[1] > self.maxHeight) {
		self.scrollBarEnabled = true;
		self.childrenHeight = self.size[1];
		self.size[1] = self.maxHeight;
		self.scrollBar.pos = .{self.size[0] + border, border};
		self.size[0] += 2*border + scrollBarWidth;
	}
}

pub fn updateSelected(self: *VerticalList) void {
	for(self.children.items) |*child| {
		child.updateSelected();
	}
}

pub fn updateHovered(self: *VerticalList, mousePosition: Vec2f) void {
	var shiftedPos = self.pos;
	if(self.scrollBarEnabled) {
		const diff = self.childrenHeight - self.maxHeight;
		shiftedPos[1] -= diff*self.scrollBar.currentState;
	}
	var i: usize = self.children.items.len;
	while(i != 0) {
		i -= 1;
		const child = &self.children.items[i];
		if(GuiComponent.contains(child.pos() + shiftedPos, child.size(), mousePosition)) {
			child.updateHovered(mousePosition - shiftedPos);
			break;
		}
	}
	if(self.scrollBarEnabled) {
		const diff = self.childrenHeight - self.maxHeight;
		self.scrollBar.scroll(-main.Window.scrollOffset*32/diff);
		main.Window.scrollOffset = 0;
		if(GuiComponent.contains(self.scrollBar.pos, self.scrollBar.size, mousePosition - self.pos)) {
			self.scrollBar.updateHovered(mousePosition - self.pos);
		}
	}
}

pub fn render(self: *VerticalList, mousePosition: Vec2f) void {
	const oldTranslation = draw.setTranslation(self.pos);
	defer draw.restoreTranslation(oldTranslation);
	const oldClip = draw.setClip(self.size);
	defer draw.restoreClip(oldClip);
	var shiftedPos = self.pos;
	if(self.scrollBarEnabled) {
		const diff = self.childrenHeight - self.maxHeight;
		shiftedPos[1] -= diff*self.scrollBar.currentState;
		self.scrollBar.render(mousePosition - self.pos);
	}
	_ = draw.setTranslation(shiftedPos - self.pos);

	for(self.children.items) |*child| {
		const itemYPos = child.pos()[1];
		const adjustedYPos = itemYPos + shiftedPos[1];

		if(adjustedYPos + child.size()[1] < 0 or adjustedYPos - child.size()[1] > self.maxHeight + child.size()[1]) {
			continue;
		}
		child.render(mousePosition - shiftedPos);
	}
}

pub fn mainButtonPressed(self: *VerticalList, mousePosition: Vec2f) void {
	var shiftedPos = self.pos;
	if(self.scrollBarEnabled) {
		const diff = self.childrenHeight - self.maxHeight;
		shiftedPos[1] -= diff*self.scrollBar.currentState;
		if(GuiComponent.contains(self.scrollBar.pos, self.scrollBar.size, mousePosition - self.pos)) {
			self.scrollBar.mainButtonPressed(mousePosition - self.pos);
			return;
		}
	}
	var selectedChild: ?*GuiComponent = null;
	for(self.children.items) |*child| {
		if(GuiComponent.contains(child.pos() + shiftedPos, child.size(), mousePosition)) {
			selectedChild = child;
		}
	}
	if(selectedChild) |child| {
		child.mainButtonPressed(mousePosition - shiftedPos);
	}
}

pub fn mainButtonReleased(self: *VerticalList, mousePosition: Vec2f) void {
	var shiftedPos = self.pos;
	if(self.scrollBarEnabled) {
		const diff = self.childrenHeight - self.maxHeight;
		shiftedPos[1] -= diff*self.scrollBar.currentState;
		self.scrollBar.mainButtonReleased(mousePosition - self.pos);
	}
	for(self.children.items) |*child| {
		child.mainButtonReleased(mousePosition - shiftedPos);
	}
}
