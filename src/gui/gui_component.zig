const std = @import("std");

const main = @import("root");
const vec = main.vec;
const Vec2f = vec.Vec2f;

pub const GuiComponent = union(enum) {

	pub const Button = @import("components/Button.zig");
	pub const CheckBox = @import("components/CheckBox.zig");
	pub const Label = @import("components/Label.zig");
	pub const Slider = @import("components/Slider.zig");
	pub const ScrollBar = @import("components/ScrollBar.zig");
	pub const TextInput = @import("components/TextInput.zig");
	pub const VerticalList = @import("components/VerticalList.zig");


	button: *Button,
	checkBox: *CheckBox,
	label: *Label,
	scrollBar: *ScrollBar,
	slider: *Slider,
	textInput: *TextInput,
	verticalList: *VerticalList,

	pub fn deinit(self: *GuiComponent) void {
		switch(self.*) {
			inline else => |impl| {
				// Only call the function if it exists:
				inline for(@typeInfo(@TypeOf(impl.*)).Struct.decls) |decl| {
					if(comptime std.mem.eql(u8, decl.name, "deinit")) {
						impl.deinit();
					}
				}
			}
		}
	}

	pub fn mutPos(self: *GuiComponent) *Vec2f {
		switch(self.*) {
			inline else => |impl| {
				return &impl.pos;
			}
		}
	}

	pub fn mutSize(self: *GuiComponent) *Vec2f {
		switch(self.*) {
			inline else => |impl| {
				return &impl.size;
			}
		}
	}

	pub fn pos(self: *GuiComponent) Vec2f {
		switch(self.*) {
			inline else => |impl| {
				return impl.pos;
			}
		}
	}

	pub fn size(self: *GuiComponent) Vec2f {
		switch(self.*) {
			inline else => |impl| {
				return impl.size;
			}
		}
	}

	pub fn updateSelected(self: *GuiComponent) void {
		switch(self.*) {
			inline else => |impl| {
				// Only call the function if it exists:
				inline for(@typeInfo(@TypeOf(impl.*)).Struct.decls) |decl| {
					if(comptime std.mem.eql(u8, decl.name, "updateSelected")) {
						impl.updateSelected();
					}
				}
			}
		}
	}

	pub fn updateHovered(self: *GuiComponent, mousePosition: Vec2f) void {
		switch(self.*) {
			inline else => |impl| {
				// Only call the function if it exists:
				inline for(@typeInfo(@TypeOf(impl.*)).Struct.decls) |decl| {
					if(comptime std.mem.eql(u8, decl.name, "updateHovered")) {
						impl.updateHovered(mousePosition);
					}
				}
			}
		}
	}

	pub fn render(self: *GuiComponent, mousePosition: Vec2f) !void {
		switch(self.*) {
			inline else => |impl| {
				// Only call the function if it exists:
				inline for(@typeInfo(@TypeOf(impl.*)).Struct.decls) |decl| {
					if(comptime std.mem.eql(u8, decl.name, "render")) {
						try impl.render(mousePosition);
					}
				}
			}
		}
	}

	pub fn mainButtonPressed(self: *GuiComponent, mousePosition: Vec2f) void {
		switch(self.*) {
			inline else => |impl| {
				// Only call the function if it exists:
				inline for(@typeInfo(@TypeOf(impl.*)).Struct.decls) |decl| {
					if(comptime std.mem.eql(u8, decl.name, "mainButtonPressed")) {
						impl.mainButtonPressed(mousePosition);
					}
				}
			}
		}
	}

	pub fn mainButtonReleased(self: *GuiComponent, mousePosition: Vec2f) void {
		switch(self.*) {
			inline else => |impl| {
				// Only call the function if it exists:
				inline for(@typeInfo(@TypeOf(impl.*)).Struct.decls) |decl| {
					if(comptime std.mem.eql(u8, decl.name, "mainButtonReleased")) {
						impl.mainButtonReleased(mousePosition);
					}
				}
			}
		}
	}

	pub fn contains(_pos: Vec2f, _size: Vec2f, point: Vec2f) bool {
		return @reduce(.And, point >= _pos) and @reduce(.And, point < _pos + _size);
	}
};