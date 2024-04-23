const std = @import("std");

const main = @import("root");
const graphics = main.graphics;
const draw = graphics.draw;
const TextBuffer = graphics.TextBuffer;
const Texture = graphics.Texture;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const Button = GuiComponent.Button;
const ScrollBar = GuiComponent.ScrollBar;

const TextInput = @This();

const scrollBarWidth = 5;
const border: f32 = 3;
const fontSize: f32 = 16;

var texture: Texture = undefined;

pos: Vec2f,
size: Vec2f,
pressed: bool = false,
cursor: ?u32 = null,
selectionStart: ?u32 = null,
currentString: main.List(u8),
textBuffer: TextBuffer,
maxWidth: f32,
maxHeight: f32,
textSize: Vec2f = undefined,
scrollBar: *ScrollBar,
onNewline: gui.Callback,

pub fn __init() void {
	texture = Texture.initFromFile("assets/cubyz/ui/text_input.png");
}

pub fn __deinit() void {
	texture.deinit();
}

pub fn init(pos: Vec2f, maxWidth: f32, maxHeight: f32, text: []const u8, onNewline: gui.Callback) *TextInput {
	const scrollBar = ScrollBar.init(undefined, scrollBarWidth, maxHeight - 2*border, 0);
	const self = main.globalAllocator.create(TextInput);
	self.* = TextInput {
		.pos = pos,
		.size = .{maxWidth, maxHeight},
		.currentString = main.List(u8).init(main.globalAllocator),
		.textBuffer = TextBuffer.init(main.globalAllocator, text, .{}, true, .left),
		.maxWidth = maxWidth,
		.maxHeight = maxHeight,
		.scrollBar = scrollBar,
		.onNewline = onNewline,
	};
	self.currentString.appendSlice(text);
	self.textSize = self.textBuffer.calculateLineBreaks(fontSize, maxWidth - 2*border - scrollBarWidth);
	return self;
}

pub fn deinit(self: *const TextInput) void {
	self.textBuffer.deinit();
	self.currentString.deinit();
	self.scrollBar.deinit();
	main.globalAllocator.destroy(self);
}

pub fn clear(self: *TextInput) void {
	if(self.cursor != null) {
		self.cursor = 0;
		self.selectionStart = null;
	}
	self.currentString.clearRetainingCapacity();
	self.reloadText();
}

pub fn toComponent(self: *TextInput) GuiComponent {
	return GuiComponent {
		.textInput = self
	};
}

pub fn updateHovered(self: *TextInput, mousePosition: Vec2f) void {
	if(self.textSize[1] > self.maxHeight - 2*border) {
		const diff = self.textSize[1] - (self.maxHeight - 2*border);
		self.scrollBar.scroll(-main.Window.scrollOffset*32/diff);
		main.Window.scrollOffset = 0;
	}
	if(self.textSize[1] > self.maxHeight - 2*border) {
		self.scrollBar.pos = Vec2f{self.size[0] - border - scrollBarWidth, border};
		if(GuiComponent.contains(self.scrollBar.pos, self.scrollBar.size, mousePosition - self.pos)) {
			self.scrollBar.updateHovered(mousePosition - self.pos);
		}
	}
}

pub fn mainButtonPressed(self: *TextInput, mousePosition: Vec2f) void {
	if(self.textSize[1] > self.maxHeight - 2*border) {
		self.scrollBar.pos = Vec2f{self.size[0] - border - scrollBarWidth, border};
		if(GuiComponent.contains(self.scrollBar.pos, self.scrollBar.size, mousePosition - self.pos)) {
			self.scrollBar.mainButtonPressed(mousePosition - self.pos);
			return;
		}
	}
	self.cursor = null;
	var textPos = Vec2f{border, border};
	if(self.textSize[1] > self.maxHeight - 2*border) {
		const diff = self.textSize[1] - (self.maxHeight - 2*border);
		textPos[1] -= diff*self.scrollBar.currentState;
	}
	self.selectionStart = self.textBuffer.mousePosToIndex(mousePosition - textPos - self.pos, self.currentString.items.len);
	self.pressed = true;
}

pub fn mainButtonReleased(self: *TextInput, mousePosition: Vec2f) void {
	if(self.pressed) {
		var textPos = Vec2f{border, border};
		if(self.textSize[1] > self.maxHeight - 2*border) {
			const diff = self.textSize[1] - (self.maxHeight - 2*border);
			textPos[1] -= diff*self.scrollBar.currentState;
		}
		self.cursor = self.textBuffer.mousePosToIndex(mousePosition - textPos - self.pos, self.currentString.items.len);
		if(self.cursor == self.selectionStart) {
			self.selectionStart = null;
		}
		self.pressed = false;
		gui.setSelectedTextInput(self);
	} else if(self.textSize[1] > self.maxHeight - 2*border) {
		self.scrollBar.pos = .{self.size[0] - border - scrollBarWidth, border};
		self.scrollBar.mainButtonReleased(mousePosition - self.pos);
		gui.setSelectedTextInput(self);
	}
}

pub fn deselect(self: *TextInput) void {
	self.cursor = null;
	self.selectionStart = null;
}

fn reloadText(self: *TextInput) void {
	self.textBuffer.deinit();
	self.textBuffer = TextBuffer.init(main.globalAllocator, self.currentString.items, .{}, true, .left);
	self.textSize = self.textBuffer.calculateLineBreaks(fontSize, self.maxWidth - 2*border - scrollBarWidth);
}

fn moveCursorLeft(self: *TextInput, mods: main.Window.Key.Modifiers) void {
	if(mods.control) {
		const text = self.currentString.items;
		if(self.cursor.? == 0) return;
		self.cursor.? -= 1;
		// Find end of previous "word":
		while(!std.ascii.isAlphabetic(text[self.cursor.?]) and std.ascii.isASCII(text[self.cursor.?])) {
			if(self.cursor.? == 0) return;
			self.cursor.? -= 1;
		}
		// Find the start of the previous "word":
		while(std.ascii.isAlphabetic(text[self.cursor.?]) or !std.ascii.isASCII(text[self.cursor.?])) {
			if(self.cursor.? == 0) return;
			self.cursor.? -= 1;
		}
		self.cursor.? += 1;
	} else {
		while(self.cursor.? > 0) {
			self.cursor.? -= 1;
			if((std.unicode.utf8ByteSequenceLength(self.currentString.items[self.cursor.?]) catch 0) != 0) break; // Ugly hack to check if we found a valid start byte.
		}
	}
}

pub fn left(self: *TextInput, mods: main.Window.Key.Modifiers) void {
	if(self.cursor) |*cursor| {
		if(mods.shift) {
			if(self.selectionStart == null) {
				self.selectionStart = cursor.*;
			}
			self.moveCursorLeft(mods);
			if(self.selectionStart == self.cursor) {
				self.selectionStart = null;
			}
		} else {
			if(self.selectionStart) |selectionStart| {
				cursor.* = @min(cursor.*, selectionStart);
				self.selectionStart = null;
			} else {
				self.moveCursorLeft(mods);
			}
		}
		self.ensureCursorVisibility();
	}
}

fn moveCursorRight(self: *TextInput, mods: main.Window.Key.Modifiers) void {
	if(self.cursor.? < self.currentString.items.len) {
		if(mods.control) {
			const text = self.currentString.items;
			// Find start of next "word":
			while(!std.ascii.isAlphabetic(text[self.cursor.?]) and std.ascii.isASCII(text[self.cursor.?])) {
				self.cursor.? += 1;
				if(self.cursor.? >= self.currentString.items.len) return;
			}
			// Find the end of the next "word":
			while(std.ascii.isAlphabetic(text[self.cursor.?]) or !std.ascii.isASCII(text[self.cursor.?])) {
				self.cursor.? += 1;
				if(self.cursor.? >= self.currentString.items.len) return;
			}
		} else {
			self.cursor.? += std.unicode.utf8ByteSequenceLength(self.currentString.items[self.cursor.?]) catch 0;
		}
	}
}

pub fn right(self: *TextInput, mods: main.Window.Key.Modifiers) void {
	if(self.cursor) |*cursor| {
		if(mods.shift) {
			if(self.selectionStart == null) {
				self.selectionStart = cursor.*;
			}
			self.moveCursorRight(mods);
			if(self.selectionStart == self.cursor) {
				self.selectionStart = null;
			}
		} else {
			if(self.selectionStart) |selectionStart| {
				cursor.* = @max(cursor.*, selectionStart);
				self.selectionStart = null;
			} else {
				self.moveCursorRight(mods);
			}
		}
		self.ensureCursorVisibility();
	}
}

fn moveCursorVertically(self: *TextInput, relativeLines: f32) void {
	self.cursor = self.textBuffer.mousePosToIndex(self.textBuffer.indexToCursorPos(self.cursor.?) + Vec2f{0, 16*relativeLines}, self.currentString.items.len);
}

pub fn down(self: *TextInput, mods: main.Window.Key.Modifiers) void {
	if(self.cursor) |*cursor| {
		if(mods.shift) {
			if(self.selectionStart == null) {
				self.selectionStart = cursor.*;
			}
			self.moveCursorVertically(1);
			if(self.selectionStart == self.cursor) {
				self.selectionStart = null;
			}
		} else {
			if(self.selectionStart) |selectionStart| {
				cursor.* = @max(cursor.*, selectionStart);
				self.selectionStart = null;
			} else {
				self.moveCursorVertically(1);
			}
		}
		self.ensureCursorVisibility();
	}
}

pub fn up(self: *TextInput, mods: main.Window.Key.Modifiers) void {
	if(self.cursor) |*cursor| {
		if(mods.shift) {
			if(self.selectionStart == null) {
				self.selectionStart = cursor.*;
			}
			self.moveCursorVertically(-1);
			if(self.selectionStart == self.cursor) {
				self.selectionStart = null;
			}
		} else {
			if(self.selectionStart) |selectionStart| {
				cursor.* = @min(cursor.*, selectionStart);
				self.selectionStart = null;
			} else {
				self.moveCursorVertically(-1);
			}
		}
		self.ensureCursorVisibility();
	}
}

fn moveCursorToStart(self: *TextInput, mods: main.Window.Key.Modifiers) void {
	if(mods.control) {
		self.cursor.? = 0;
	} else {
		self.cursor.? = @intCast(if(std.mem.lastIndexOf(u8, self.currentString.items[0..self.cursor.?], "\n")) |nextPos| nextPos + 1 else 0);
	}
}

pub fn gotoStart(self: *TextInput, mods: main.Window.Key.Modifiers) void {
	if(self.cursor) |*cursor| {
		if(mods.shift) {
			if(self.selectionStart == null) {
				self.selectionStart = cursor.*;
			}
			self.moveCursorToStart(mods);
			if(self.selectionStart == self.cursor) {
				self.selectionStart = null;
			}
		} else {
			if(self.selectionStart) |selectionStart| {
				cursor.* = @min(cursor.*, selectionStart);
				self.selectionStart = null;
			} else {
				self.moveCursorToStart(mods);
			}
		}
		self.ensureCursorVisibility();
	}
}

fn moveCursorToEnd(self: *TextInput, mods: main.Window.Key.Modifiers) void {
	if(mods.control) {
		self.cursor.? = @intCast(self.currentString.items.len);
	} else {
		self.cursor.? += @intCast(std.mem.indexOf(u8, self.currentString.items[self.cursor.?..], "\n") orelse self.currentString.items.len - self.cursor.?);
	}
}

pub fn gotoEnd(self: *TextInput, mods: main.Window.Key.Modifiers) void {
	if(self.cursor) |*cursor| {
		if(mods.shift) {
			if(self.selectionStart == null) {
				self.selectionStart = cursor.*;
			}
			self.moveCursorToEnd(mods);
			if(self.selectionStart == self.cursor) {
				self.selectionStart = null;
			}
		} else {
			if(self.selectionStart) |selectionStart| {
				cursor.* = @min(cursor.*, selectionStart);
				self.selectionStart = null;
			} else {
				self.moveCursorToEnd(mods);
			}
		}
		self.ensureCursorVisibility();
	}
}

fn deleteSelection(self: *TextInput) void {
	if(self.selectionStart) |selectionStart| {
		const start = @min(selectionStart, self.cursor.?);
		const end = @max(selectionStart, self.cursor.?);

		self.currentString.replaceRange(start, end - start, &[0]u8{});
		self.cursor.? = start;
		self.selectionStart = null;
		self.ensureCursorVisibility();
	}
}

pub fn deleteLeft(self: *TextInput, _: main.Window.Key.Modifiers) void {
	if(self.cursor == null) return;
	if(self.selectionStart == null) {
		self.selectionStart = self.cursor;
		self.moveCursorLeft(.{});
	}
	self.deleteSelection();
	self.reloadText();
	self.ensureCursorVisibility();
}

pub fn deleteRight(self: *TextInput, _: main.Window.Key.Modifiers) void {
	if(self.cursor == null) return;
	if(self.selectionStart == null) {
		self.selectionStart = self.cursor;
		self.moveCursorRight(.{});
	}
	self.deleteSelection();
	self.reloadText();
	self.ensureCursorVisibility();
}

pub fn inputCharacter(self: *TextInput, character: u21) void {
	if(self.cursor) |*cursor| {
		self.deleteSelection();
		var buf: [4]u8 = undefined;
		const utf8 = buf[0..std.unicode.utf8Encode(character, &buf) catch return];
		self.currentString.insertSlice(cursor.*, utf8);
		self.reloadText();
		cursor.* += @intCast(utf8.len);
		self.ensureCursorVisibility();
	}
}

pub fn copy(self: *TextInput, mods: main.Window.Key.Modifiers) void {
	if(mods.control) {
		if(self.cursor) |cursor| {
			if(self.selectionStart) |selectionStart| {
				const start = @min(cursor, selectionStart);
				const end = @max(cursor, selectionStart);
				main.Window.setClipboardString(self.currentString.items[start..end]);
			}
		}
		self.ensureCursorVisibility();
	}
}

pub fn paste(self: *TextInput, mods: main.Window.Key.Modifiers) void {
	if(mods.control) {
		const string = main.Window.getClipboardString();
		self.deleteSelection();
		self.currentString.insertSlice(self.cursor.?, string);
		self.cursor.? += @intCast(string.len);
		self.reloadText();
		self.ensureCursorVisibility();
	}
}

pub fn cut(self: *TextInput, mods: main.Window.Key.Modifiers) void {
	if(mods.control) {
		self.copy(mods);
		self.deleteSelection();
		self.reloadText();
		self.ensureCursorVisibility();
	}
}

pub fn newline(self: *TextInput, mods: main.Window.Key.Modifiers) void {
	if(!mods.shift and self.onNewline.callback != null) {
		self.onNewline.run();
		return;
	}
	self.inputCharacter('\n');
	self.ensureCursorVisibility();
}

fn ensureCursorVisibility(self: *TextInput) void {
	if(self.textSize[1] > self.maxHeight - 2*border) {
		var y: f32 = 0;
		const diff = self.textSize[1] - (self.maxHeight - 2*border);
		y -= diff*self.scrollBar.currentState;
		if(self.cursor) |cursor| {
			const cursorPos = y + self.textBuffer.indexToCursorPos(cursor)[1];
			if(cursorPos < 0) {
				self.scrollBar.currentState += cursorPos/diff;
			} else if(cursorPos + 16 >= self.maxHeight - 2*border) {
				self.scrollBar.currentState += (cursorPos + 16 - (self.maxHeight - 2*border))/diff;
			}
		}
	}
}

pub fn render(self: *TextInput, mousePosition: Vec2f) void {
	texture.bindTo(0);
	Button.shader.bind();
	draw.setColor(0xff000000);
	draw.customShadedRect(Button.buttonUniforms, self.pos, self.size);
	const oldTranslation = draw.setTranslation(self.pos);
	defer draw.restoreTranslation(oldTranslation);
	const oldClip = draw.setClip(self.size);
	defer draw.restoreClip(oldClip);

	var textPos = Vec2f{border, border};
	if(self.textSize[1] > self.maxHeight - 2*border) {
		const diff = self.textSize[1] - (self.maxHeight - 2*border);
		textPos[1] -= diff*self.scrollBar.currentState;
		self.scrollBar.pos = .{self.size[0] - self.scrollBar.size[0] - border, border};
		self.scrollBar.render(mousePosition - self.pos);
	}
	self.textBuffer.render(textPos[0], textPos[1], fontSize);
	if(self.pressed) {
		self.cursor = self.textBuffer.mousePosToIndex(mousePosition - textPos - self.pos, self.currentString.items.len);
	}
	if(self.cursor) |cursor| {
		const cursorPos = textPos + self.textBuffer.indexToCursorPos(cursor);
		if(self.selectionStart) |selectionStart| {
			draw.setColor(0x440000ff);
			self.textBuffer.drawSelection(textPos, @min(selectionStart, cursor), @max(selectionStart, cursor));
		}
		draw.setColor(0xff000000);
		draw.line(cursorPos, cursorPos + Vec2f{0, 16});
	}
}