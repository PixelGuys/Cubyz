const std = @import("std");

const main = @import("main");
const vec = main.vec;
const Vec2f = vec.Vec2f;

pub const GuiComponent = union(enum) {
	pub const Button = @import("components/Button.zig");
	pub const CheckBox = @import("components/CheckBox.zig");
	pub const HorizontalList = @import("components/HorizontalList.zig");
	pub const Icon = @import("components/Icon.zig");
	pub const ItemSlot = @import("components/ItemSlot.zig");
	pub const Label = @import("components/Label.zig");
	pub const MutexComponent = @import("components/MutexComponent.zig");
	pub const ScrollBar = @import("components/ScrollBar.zig");
	pub const ContinuousSlider = @import("components/ContinuousSlider.zig");
	pub const DiscreteSlider = @import("components/DiscreteSlider.zig");
	pub const TextInput = @import("components/TextInput.zig");
	pub const VerticalList = @import("components/VerticalList.zig");

	button: *Button,
	checkBox: *CheckBox,
	horizontalList: *HorizontalList,
	icon: *Icon,
	itemSlot: *ItemSlot,
	label: *Label,
	mutexComponent: *MutexComponent,
	scrollBar: *ScrollBar,
	continuousSlider: *ContinuousSlider,
	discreteSlider: *DiscreteSlider,
	textInput: *TextInput,
	verticalList: *VerticalList,

	pub fn deinit(self: GuiComponent) void {
		switch(self) {
			inline else => |impl| {
				if(@hasDecl(@TypeOf(impl.*), "deinit")) {
					impl.deinit();
				}
			},
		}
	}

	pub fn mutPos(self: GuiComponent) *Vec2f {
		switch(self) {
			inline else => |impl| {
				return &impl.pos;
			},
		}
	}

	pub fn mutSize(self: GuiComponent) *Vec2f {
		switch(self) {
			inline else => |impl| {
				return &impl.size;
			},
		}
	}

	pub fn pos(self: GuiComponent) Vec2f {
		switch(self) {
			inline else => |impl| {
				return impl.pos;
			},
		}
	}

	pub fn size(self: GuiComponent) Vec2f {
		switch(self) {
			inline else => |impl| {
				return impl.size;
			},
		}
	}

	pub fn updateSelected(self: GuiComponent) void {
		switch(self) {
			inline else => |impl| {
				if(@hasDecl(@TypeOf(impl.*), "updateSelected")) {
					impl.updateSelected();
				}
			},
		}
	}

	pub fn updateHovered(self: GuiComponent, mousePosition: Vec2f) void {
		switch(self) {
			inline else => |impl| {
				if(@hasDecl(@TypeOf(impl.*), "updateHovered")) {
					impl.updateHovered(mousePosition);
				}
			},
		}
	}

	pub fn render(self: GuiComponent, mousePosition: Vec2f) void {
		switch(self) {
			inline else => |impl| {
				if(@hasDecl(@TypeOf(impl.*), "render")) {
					impl.render(mousePosition);
				}
			},
		}
	}

	pub fn mainButtonPressed(self: GuiComponent, mousePosition: Vec2f) void {
		switch(self) {
			inline else => |impl| {
				if(@hasDecl(@TypeOf(impl.*), "mainButtonPressed")) {
					impl.mainButtonPressed(mousePosition);
				}
			},
		}
	}

	pub fn mainButtonReleased(self: GuiComponent, mousePosition: Vec2f) void {
		switch(self) {
			inline else => |impl| {
				if(@hasDecl(@TypeOf(impl.*), "mainButtonReleased")) {
					impl.mainButtonReleased(mousePosition);
				}
			},
		}
	}

	pub fn contains(_pos: Vec2f, _size: Vec2f, point: Vec2f) bool {
		return @reduce(.And, point >= _pos) and @reduce(.And, point < _pos + _size);
	}
};
