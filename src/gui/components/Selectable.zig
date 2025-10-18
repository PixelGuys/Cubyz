const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;

const Selectable = @This();

pos: Vec2f,
size: Vec2f,
child: ?GuiComponent = null,
onSelect: gui.Callback = .{},
selected: bool = false,
hovered: bool = false,
pressed: bool = false,

const normalColor: u32 = 0x00000000;
const hoveredColor: u32 = 0x40ffffff;
const selectedColor: u32 = 0x50000000;

pub fn init(pos: Vec2f, size: Vec2f, onSelect: gui.Callback) *Selectable {
	const self = main.globalAllocator.create(Selectable);
	self.* = Selectable{.pos = pos, .size = size, .onSelect = onSelect};
	return self;
}

pub fn deinit(self: *const Selectable) void {
	if(self.child) |child| {
		child.deinit();
	}
	main.globalAllocator.destroy(self);
}

pub fn select(self: *Selectable) void {
	if(!self.selected) {
		self.selected = true;
		self.onSelect.run();
	}
}

pub fn deselect(self: *Selectable) void {
	self.selected = false;
}

pub fn setChild(self: *Selectable, _child: anytype) void {
	var child: GuiComponent = undefined;
	if(@TypeOf(_child) == GuiComponent) {
		child = _child;
	} else {
		child = _child.toComponent();
	}
	self.child = child;
	self.size[1] = @max(self.size[1], child.pos()[1] + child.size()[1]);
	self.size[0] = @max(self.size[0], child.pos()[0] + child.size()[0]);
}

pub fn finish(self: *Selectable, alignment: graphics.TextBuffer.Alignment) void {
	const child = self.child orelse return;

	const mutPos = child.mutPos();
	const size = child.size();
	switch(alignment) {
		.left => {},
		.center => {
			mutPos.*[0] = mutPos.*[0]/2 + self.size[0]/2 - size[0]/2;
			mutPos.*[1] = mutPos.*[1]/2 + self.size[1]/2 - size[1]/2;
		},
		.right => {
			mutPos.*[1] = self.size[1] - size[1];
		},
	}
}

pub fn toComponent(self: *Selectable) GuiComponent {
	return .{.selectable = self};
}

pub fn mainButtonPressed(self: *Selectable, mousePosition: Vec2f) void {
	if(self.child) |child| {
		if(GuiComponent.contains(child.pos() + self.pos, child.size(), mousePosition)) {
			child.mainButtonPressed(mousePosition - self.pos);
		}
	}

	self.pressed = true;
}

pub fn mainButtonReleased(self: *Selectable, mousePosition: Vec2f) void {
	if(self.pressed) {
		self.select();
		self.pressed = false;
	}

	if(self.child) |child| {
		child.mainButtonReleased(mousePosition);
	}
}

pub fn updateSelected(self: *Selectable) void {
	if(self.child) |child| {
		child.updateSelected();
	}
}

pub fn updateHovered(self: *Selectable, mousePosition: Vec2f) void {
	if(self.child) |child| {
		if(GuiComponent.contains(child.pos() + self.pos, child.size(), mousePosition)) {
			child.updateHovered(mousePosition - self.pos);
		}
	}

	self.hovered = true;
}

pub fn render(self: *Selectable, mousePosition: Vec2f) void {
	const color = if(self.selected)
		selectedColor
	else if(self.hovered)
		hoveredColor
	else
		normalColor;

	draw.setColor(color);
	draw.rect(self.pos, self.size);

	const oldTranslation = draw.setTranslation(self.pos);
	if(self.child) |child| {
		child.render(mousePosition - self.pos);
	}
	draw.restoreTranslation(oldTranslation);

	self.hovered = false;
}
