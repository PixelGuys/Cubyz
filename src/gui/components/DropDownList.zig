const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const SelectableList = @import("SelectableList.zig");

const DropDownList = @This();

pos: Vec2f = .{0, 0},
size: Vec2f = .{0, 0},
list: *SelectableList,
selectedItemIdx: usize = 0,
open: bool = false,

pub fn init(pos: Vec2f, maxHeight: f32, padding: f32) *DropDownList {
	const self = main.globalAllocator.create(DropDownList);
	self.* = DropDownList{.list = SelectableList.init(pos, maxHeight, padding, .{.callback = &onSelectCallback, .arg = @intFromPtr(self)})};
	return self;
}

pub fn deinit(self: *const DropDownList) void {
	self.list.deinit();
	main.globalAllocator.destroy(self);
}

pub fn onSelectCallback(itemIdx: usize, DropDownListPtr: usize) void {
	onSelect(@ptrFromInt(DropDownListPtr), itemIdx);
}

pub fn onSelect(self: *DropDownList, itemIdx: usize) void {
	self.selectedItemIdx = itemIdx;
	self.open = false;
}

pub inline fn add(self: *DropDownList, _other: anytype) void {
	self.list.add(_other);
	if(self.list.list.children.items.len == 1) {
		self.onSelect(0);
	}
}

pub inline fn finish(self: *DropDownList, alignment: graphics.TextBuffer.Alignment) void {
	self.list.finish(alignment);
	self.pos = self.list.pos;
	self.size = self.list.size;
}

pub fn toComponent(self: *DropDownList) GuiComponent {
	return .{.dropDownList = self};
}

pub fn updateSelected(self: *DropDownList) void {
	if(self.open) {
		self.list.updateSelected();
	} else {
		self.list.list.children.items[self.selectedItemIdx].updateSelected();
	}
}

pub fn mainButtonPressed(self: *DropDownList, mousePosition: Vec2f) void {
	if(self.open) {
		self.list.mainButtonPressed(mousePosition);
	}
}

pub fn mainButtonReleased(self: *DropDownList, mousePosition: Vec2f) void {
	if(!self.open) {
		self.open = true;
	} else {
		self.list.mainButtonReleased(mousePosition);
	}
}

pub fn updateHovered(self: *DropDownList, mousePosition: Vec2f) void {
	if(self.open) {
		self.list.updateHovered(mousePosition);
	}
}

pub fn render(self: *DropDownList, mousePosition: Vec2f) void {
	if(self.list.list.children.items.len > 0) {
		if(self.open) {
			self.list.render(mousePosition);
		} else {
			const item = self.list.list.children.items[self.selectedItemIdx];
			const shiftedPos = Vec2f{0, -item.pos()[1]};
			const oldTranslation = draw.setTranslation(shiftedPos);
			defer draw.restoreTranslation(oldTranslation);
			item.render(mousePosition + shiftedPos);
		}
	}
}
