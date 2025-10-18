const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const VerticalList = @import("VerticalList.zig");

const SelectableList = @This();

const Callback = struct {
	callback: ?*const fn(itemIdx: usize, arg: usize) void = null,
	arg: usize = 0,

	pub fn run(self: Callback, itemIdx: usize) void {
		if(self.callback) |callback| {
			callback(itemIdx, self.arg);
		}
	}
};

pos: Vec2f = .{0, 0},
size: Vec2f = .{0, 0},
list: *VerticalList,
onSelect: Callback,
selectedIdx: ?u32 = null,
hoveredIdx: ?u32 = null,
pressedIdx: ?u32 = null,

upPressed: bool = false,
downPressed: bool = false,

const normalColor: u32 = 0x00000000;
const hoveredColor: u32 = 0x40ffffff;
const selectedColor: u32 = 0x50000000;

pub fn init(pos: Vec2f, maxHeight: f32, padding: f32, onSelect: Callback) *SelectableList {
	const self = main.globalAllocator.create(SelectableList);
	self.* = SelectableList{.list = VerticalList.init(pos, maxHeight, padding), .onSelect = onSelect};
	return self;
}

pub fn deinit(self: *const SelectableList) void {
	self.list.deinit();
	main.globalAllocator.destroy(self);
}

pub fn select(self: *SelectableList, itemIdx: usize) void {
	const idx: u32 = @intCast(itemIdx);
	if(self.selectedIdx != idx) {
		const child = self.list.children.items[idx];
		const childPosY = child.pos()[1] + self.list.getShiftedPos()[1] - self.list.pos[1];
		const childLowerBound = childPosY + child.size()[1];
		if(childLowerBound > self.list.size[1]) {
			self.list.scrollBar.scroll(childLowerBound/self.list.size[1] - 1);
		} else if(childPosY < 0) {
			self.list.scrollBar.scroll(childPosY/self.list.size[1]);
		}

		self.selectedIdx = idx;
		self.hoveredIdx = if(self.hoveredIdx == idx) null else self.hoveredIdx;
		self.onSelect.run(idx);
	}
}

pub fn deselect(self: *SelectableList) void {
	self.selectedIdx = null;
}

pub inline fn add(self: *SelectableList, _other: anytype) void {
	self.list.add(_other);
}

pub inline fn finish(self: *SelectableList, alignment: graphics.TextBuffer.Alignment) void {
	self.list.finish(alignment);
	self.pos = self.list.pos;
	self.size = self.list.size;
}

pub fn toComponent(self: *SelectableList) GuiComponent {
	return .{.selectableList = self};
}

fn itemToIndex(self: *const SelectableList, item: GuiComponent) u32 {
	for(self.list.children.items, 0..) |other, i| {
		if(std.meta.eql(item, other)) {
			return @intCast(i);
		}
	}
	unreachable;
}

pub fn mainButtonPressed(self: *SelectableList, mousePosition: Vec2f) void {
	const item = self.list.mousePosToItem(mousePosition) orelse return;
	if(item == .scrollBar and item.scrollBar == self.list.scrollBar) {
		self.list.scrollBar.mainButtonPressed(mousePosition - self.list.pos);
	} else {
		self.pressedIdx = self.itemToIndex(item);
		item.mainButtonPressed(mousePosition - self.list.getShiftedPos());
	}
}

pub fn mainButtonReleased(self: *SelectableList, mousePosition: Vec2f) void {
	const shiftedPos = self.list.getShiftedPos();
	if(self.pressedIdx) |idx| {
		self.pressedIdx = null;
		const item = &self.list.children.items[idx];
		if(gui.GuiComponent.contains(item.pos() + shiftedPos, item.size(), mousePosition)) {
			self.select(idx);
		}
	}

	self.list.mainButtonReleased(mousePosition - shiftedPos);
}

pub fn updateSelected(self: *SelectableList) void {
	self.list.updateSelected();

	if(self.list.children.items.len == 0) return;

	if(main.KeyBoard.key("textCursorUp").pressed) {
		if(!self.upPressed and self.selectedIdx != null) {
			self.select(if(self.selectedIdx.? != 0) self.selectedIdx.? - 1 else 0);
		}
		self.upPressed = true;
	} else {
		self.upPressed = false;
	}
	if(main.KeyBoard.key("textCursorDown").pressed) {
		if(!self.downPressed and self.selectedIdx != null) {
			const maxIdx = @as(u32, @intCast(self.list.children.items.len - 1));
			self.select(@min(self.selectedIdx.? + 1, maxIdx));
		}
		self.downPressed = true;
	} else {
		self.downPressed = false;
	}
}

pub fn updateHovered(self: *SelectableList, mousePosition: Vec2f) void {
	if(self.list.scrollBarEnabled) {
		const diff = self.list.childrenHeight - self.list.maxHeight;
		self.list.scrollBar.scroll(-main.Window.scrollOffset*32/diff);
		main.Window.scrollOffset = 0;
	}

	const item = self.list.mousePosToItem(mousePosition) orelse return;
	if(item == .scrollBar and item.scrollBar == self.list.scrollBar) {
		self.list.scrollBar.updateHovered(mousePosition - self.list.pos);
	} else {
		item.updateHovered(mousePosition - self.list.getShiftedPos());
		const idx = self.itemToIndex(item);
		if(idx != self.selectedIdx)
			self.hoveredIdx = idx;
	}
}

pub fn render(self: *SelectableList, mousePosition: Vec2f) void {
	self.list.pos = self.pos;
	self.list.size = self.size;

	if(self.hoveredIdx != null or self.selectedIdx != null) {
		const shiftedPos = self.list.getShiftedPos();
		const oldTranslation = draw.setTranslation(self.list.pos);
		defer draw.restoreTranslation(oldTranslation);
		const oldClip = draw.setClip(self.list.size);
		defer draw.restoreClip(oldClip);
		_ = draw.setTranslation(shiftedPos - self.list.pos);

		if(self.selectedIdx) |idx| {
			const child = self.list.children.items[idx];
			draw.setColor(selectedColor);
			draw.rect(child.pos(), child.size());
		}
		if(self.hoveredIdx) |idx| {
			const child = self.list.children.items[idx];
			draw.setColor(hoveredColor);
			draw.rect(child.pos(), child.size());
		}
	}

	self.hoveredIdx = null;
	self.list.render(mousePosition);
}
