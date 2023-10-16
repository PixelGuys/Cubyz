/// A collection of things that should make dealing with opengl easier.
/// Also contains some basic 2d drawing stuff.

const std = @import("std");

const freetype = @import("freetype");
const harfbuzz = @import("harfbuzz");

const vec =  @import("vec.zig");
const Mat4f = vec.Mat4f;
const Vec4i = vec.Vec4i;
const Vec4f = vec.Vec4f;
const Vec2f = vec.Vec2f;
const Vec2i = vec.Vec2i;
const Vec3f = vec.Vec3f;

const main = @import("main.zig");
const Window = main.Window;

const Allocator = std.mem.Allocator;

pub const c = @cImport ({
	@cInclude("glad/glad.h");
});

pub const stb_image = @cImport ({
	@cInclude("stb/stb_image.h");
	@cInclude("stb/stb_image_write.h");
});

pub const draw = struct {
	var color: u32 = 0;
	var clip: ?Vec4i = null;
	var translation: Vec2f = Vec2f{0, 0};
	var scale: f32 = 1;

	pub fn setColor(newColor: u32) void {
		color = newColor;
	}

	/// Returns the previous translation.
	pub fn setTranslation(newTranslation: Vec2f) Vec2f {
		const oldTranslation = translation;
		translation += newTranslation*@as(Vec2f, @splat(scale));
		return oldTranslation;
	}

	pub fn restoreTranslation(previousTranslation: Vec2f) void {
		translation = previousTranslation;
	}

	/// Returns the previous scale.
	pub fn setScale(newScale: f32) f32 {
		std.debug.assert(newScale >= 0);
		const oldScale = scale;
		scale *= newScale;
		return oldScale;
	}

	pub fn restoreScale(previousScale: f32) void {
		scale = previousScale;
	}

	/// Returns the previous clip.
	pub fn setClip(clipRect: Vec2f) ?Vec4i {
		std.debug.assert(@reduce(.And, clipRect >= Vec2f{0, 0}));
		var newClip = Vec4i {
			std.math.lossyCast(i32, translation[0]),
			main.Window.height - std.math.lossyCast(i32, translation[1] + clipRect[1]*scale),
			std.math.lossyCast(i32, clipRect[0]*scale),
			std.math.lossyCast(i32, clipRect[1]*scale),
		};
		if(clip) |oldClip| {
			if (newClip[0] < oldClip[0]) {
				newClip[2] -= oldClip[0] - newClip[0];
				newClip[0] += oldClip[0] - newClip[0];
			}
			if (newClip[1] < oldClip[1]) {
				newClip[3] -= oldClip[1] - newClip[1];
				newClip[1] += oldClip[1] - newClip[1];
			}
			if (newClip[0] + newClip[2] > oldClip[0] + oldClip[2]) {
				newClip[2] -= (newClip[0] + newClip[2]) - (oldClip[0] + oldClip[2]);
			}
			if (newClip[1] + newClip[3] > oldClip[1] + oldClip[3]) {
				newClip[3] -= (newClip[1] + newClip[3]) - (oldClip[1] + oldClip[3]);
			}
			newClip[2] = @max(newClip[2], 0);
			newClip[3] = @max(newClip[3], 0);
		} else {
			c.glEnable(c.GL_SCISSOR_TEST);
		}
		c.glScissor(newClip[0], newClip[1], newClip[2], newClip[3]);
		const oldClip = clip;
		clip = newClip;
		return oldClip;
	}

	/// Should be used to restore the old clip when leaving the render function.
	pub fn restoreClip(previousClip: ?Vec4i) void {
		clip = previousClip;
		if (clip) |clipRef| {
			c.glScissor(clipRef[0], clipRef[1], clipRef[2], clipRef[3]);
		} else {
			c.glDisable(c.GL_SCISSOR_TEST);
		}
	}

	// ----------------------------------------------------------------------------
	// Stuff for fillRect:
	var rectUniforms: struct {
		screen: c_int,
		start: c_int,
		size: c_int,
		rectColor: c_int,
	} = undefined;
	var rectShader: Shader = undefined;
	pub var rectVAO: c_uint = undefined;
	var rectVBO: c_uint = undefined;

	fn initRect() void {
		rectShader = Shader.initAndGetUniforms("assets/cubyz/shaders/graphics/Rect.vs", "assets/cubyz/shaders/graphics/Rect.fs", &rectUniforms) catch Shader{.id = 0};
		var rawData = [_]f32 {
			0, 0,
			0, 1,
			1, 0,
			1, 1,
		};

		c.glGenVertexArrays(1, &rectVAO);
		c.glBindVertexArray(rectVAO);
		c.glGenBuffers(1, &rectVBO);
		c.glBindBuffer(c.GL_ARRAY_BUFFER, rectVBO);
		c.glBufferData(c.GL_ARRAY_BUFFER, rawData.len*@sizeOf(f32), &rawData, c.GL_STATIC_DRAW);
		c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, 2*@sizeOf(f32), null);
		c.glEnableVertexAttribArray(0);
	}

	fn deinitRect() void {
		rectShader.deinit();
		c.glDeleteVertexArrays(1, &rectVAO);
		c.glDeleteBuffers(1, &rectVBO);
	}

	pub fn rect(_pos: Vec2f, _dim: Vec2f) void {
		var pos = _pos;
		var dim = _dim;
		pos *= @splat(scale);
		pos += translation;
		dim *= @splat(scale);

		rectShader.bind();

		c.glUniform2f(rectUniforms.screen, @floatFromInt(Window.width), @floatFromInt(Window.height));
		c.glUniform2f(rectUniforms.start, pos[0], pos[1]);
		c.glUniform2f(rectUniforms.size, dim[0], dim[1]);
		c.glUniform1i(rectUniforms.rectColor,  @bitCast(color));

		c.glBindVertexArray(rectVAO);
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}

	// ----------------------------------------------------------------------------
	// Stuff for drawLine:
	var lineUniforms: struct {
		screen: c_int,
		start: c_int,
		direction: c_int,
		lineColor: c_int,
	} = undefined;
	var lineShader: Shader = undefined;
	var lineVAO: c_uint = undefined;
	var lineVBO: c_uint = undefined;

	fn initLine() void {
		lineShader = Shader.initAndGetUniforms("assets/cubyz/shaders/graphics/Line.vs", "assets/cubyz/shaders/graphics/Line.fs", &lineUniforms) catch Shader{.id = 0};
		var rawData = [_]f32 {
			0, 0,
			1, 1,
		};

		c.glGenVertexArrays(1, &lineVAO);
		c.glBindVertexArray(lineVAO);
		c.glGenBuffers(1, &lineVBO);
		c.glBindBuffer(c.GL_ARRAY_BUFFER, lineVBO);
		c.glBufferData(c.GL_ARRAY_BUFFER, rawData.len*@sizeOf(f32), &rawData, c.GL_STATIC_DRAW);
		c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, 2*@sizeOf(f32), null);
		c.glEnableVertexAttribArray(0);
	}

	fn deinitLine() void {
		lineShader.deinit();
		c.glDeleteVertexArrays(1, &lineVAO);
		c.glDeleteBuffers(1, &lineVBO);
	}

	pub fn line(_pos1: Vec2f, _pos2: Vec2f) void {
		var pos1 = _pos1;
		var pos2 = _pos2;
		pos1 *= @splat(scale);
		pos1 += translation;
		pos2 *= @splat(scale);
		pos2 += translation;

		lineShader.bind();

		c.glUniform2f(lineUniforms.screen, @floatFromInt(Window.width), @floatFromInt(Window.height));
		c.glUniform2f(lineUniforms.start, pos1[0], pos1[1]);
		c.glUniform2f(lineUniforms.direction, pos2[0] - pos1[0], pos2[1] - pos1[1]);
		c.glUniform1i(lineUniforms.lineColor,  @bitCast(color));

		c.glBindVertexArray(lineVAO);
		c.glDrawArrays(c.GL_LINE_STRIP, 0, 2);
	}
	
	// ----------------------------------------------------------------------------
	// Stuff for drawRect:
	// Draw rect can use the same shader as drawline, because it essentially draws lines.
	var drawRectVAO: c_uint = undefined;
	var drawRectVBO: c_uint = undefined;

	fn initDrawRect() void {
		var rawData = [_]f32 {
			0, 0,
			0, 1,
			1, 1,
			1, 0,
		};

		c.glGenVertexArrays(1, &drawRectVAO);
		c.glBindVertexArray(drawRectVAO);
		c.glGenBuffers(1, &drawRectVBO);
		c.glBindBuffer(c.GL_ARRAY_BUFFER, drawRectVBO);
		c.glBufferData(c.GL_ARRAY_BUFFER, rawData.len*@sizeOf(f32), &rawData, c.GL_STATIC_DRAW);
		c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, 2*@sizeOf(f32), null);
		c.glEnableVertexAttribArray(0);
	}

	fn deinitDrawRect() void {
		c.glDeleteVertexArrays(1, &drawRectVAO);
		c.glDeleteBuffers(1, &drawRectVBO);
	}

	pub fn rectOutline(_pos: Vec2f, _dim: Vec2f) void {
		var pos = _pos;
		var dim = _dim;
		pos *= @splat(scale);
		pos += translation;
		dim *= @splat(scale);

		lineShader.bind();

		c.glUniform2f(lineUniforms.screen, @floatFromInt(Window.width), @floatFromInt(Window.height));
		c.glUniform2f(lineUniforms.start, pos[0], pos[1]); // Move the coordinates, so they are in the center of a pixel.
		c.glUniform2f(lineUniforms.direction, dim[0] - 1, dim[1] - 1); // The height is a lot smaller because the inner edge of the rect is drawn.
		c.glUniform1i(lineUniforms.lineColor,  @bitCast(color));

		c.glBindVertexArray(lineVAO);
		c.glDrawArrays(c.GL_LINE_LOOP, 0, 5);
	}
	
	// ----------------------------------------------------------------------------
	// Stuff for fillCircle:
	var circleUniforms: struct {
		screen: c_int,
		center: c_int,
		radius: c_int,
		circleColor: c_int,
	} = undefined;
	var circleShader: Shader = undefined;
	var circleVAO: c_uint = undefined;
	var circleVBO: c_uint = undefined;

	fn initCircle() void {
		circleShader = Shader.initAndGetUniforms("assets/cubyz/shaders/graphics/Circle.vs", "assets/cubyz/shaders/graphics/Circle.fs", &circleUniforms) catch Shader{.id = 0};
		var rawData = [_]f32 {
			-1, -1,
			-1, 1,
			1, -1,
			1, 1,
		};

		c.glGenVertexArrays(1, &circleVAO);
		c.glBindVertexArray(circleVAO);
		c.glGenBuffers(1, &circleVBO);
		c.glBindBuffer(c.GL_ARRAY_BUFFER, circleVBO);
		c.glBufferData(c.GL_ARRAY_BUFFER, rawData.len*@sizeOf(f32), &rawData, c.GL_STATIC_DRAW);
		c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, 2*@sizeOf(f32), null);
		c.glEnableVertexAttribArray(0);
	}

	fn deinitCircle() void {
		circleShader.deinit();
		c.glDeleteVertexArrays(1, &circleVAO);
		c.glDeleteBuffers(1, &circleVBO);
	}

	pub fn circle(_center: Vec2f, _radius: f32) void {
		var center = _center;
		var radius = _radius;
		_center *= @splat(scale);
		_center += translation;
		radius *= scale;
		circleShader.bind();

		c.glUniform2f(circleUniforms.screen, @floatFromInt(Window.width), @floatFromInt(Window.height));
		c.glUniform2f(circleUniforms.center, center[0], center[1]); // Move the coordinates, so they are in the center of a pixel.
		c.glUniform1f(circleUniforms.radius, radius); // The height is a lot smaller because the inner edge of the rect is drawn.
		c.glUniform1i(circleUniforms.circleColor,  @bitCast(color));

		c.glBindVertexArray(circleVAO);
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}
	
	// ----------------------------------------------------------------------------
	// Stuff for drawImage:
	// Luckily the vao of the regular rect can used.
	var imageUniforms: struct {
		screen: c_int,
		start: c_int,
		size: c_int,
		image: c_int,
		color: c_int,
	} = undefined;
	var imageShader: Shader = undefined;

	fn initImage() void {
		imageShader = Shader.initAndGetUniforms("assets/cubyz/shaders/graphics/Image.vs", "assets/cubyz/shaders/graphics/Image.fs", &imageUniforms) catch Shader{.id = 0};
	}

	fn deinitImage() void {
		imageShader.deinit();
	}

	pub fn boundImage(_pos: Vec2f, _dim: Vec2f) void {
		var pos = _pos;
		var dim = _dim;
		pos *= @splat(scale);
		pos += translation;
		dim *= @splat(scale);
		pos = @floor(pos);
		dim = @ceil(dim);

		imageShader.bind();

		c.glUniform2f(imageUniforms.screen, @floatFromInt(Window.width), @floatFromInt(Window.height));
		c.glUniform2f(imageUniforms.start, pos[0], pos[1]);
		c.glUniform2f(imageUniforms.size, dim[0], dim[1]);
		c.glUniform1i(imageUniforms.color, @bitCast(color));

		c.glBindVertexArray(rectVAO);
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}

	// ----------------------------------------------------------------------------

	pub fn customShadedRect(uniforms: anytype, _pos: Vec2f, _dim: Vec2f) void {
		var pos = _pos;
		var dim = _dim;
		pos *= @splat(scale);
		pos += translation;
		dim *= @splat(scale);
		pos = @floor(pos);
		dim = @ceil(dim);

		c.glUniform2f(uniforms.screen, @floatFromInt(Window.width), @floatFromInt(Window.height));
		c.glUniform2f(uniforms.start, pos[0], pos[1]);
		c.glUniform2f(uniforms.size, dim[0], dim[1]);
		c.glUniform1i(uniforms.color,  @bitCast(color));
		c.glUniform1f(uniforms.scale, scale);

		c.glBindVertexArray(rectVAO);
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}

	// ----------------------------------------------------------------------------
	
	pub fn text(_text: []const u8, x: f32, y: f32, fontSize: f32, alignment: TextBuffer.Alignment) !void {
		try TextRendering.renderText(_text, x, y, fontSize, .{.color = @truncate(@as(u32, @bitCast(color)))}, alignment);
	}

	pub inline fn print(comptime format: []const u8, args: anytype, x: f32, y: f32, fontSize: f32, alignment: TextBuffer.Alignment) !void {
		var stackFallback = std.heap.stackFallback(4096, main.threadAllocator);
		const allocator = stackFallback.get();
		const string = try std.fmt.allocPrint(allocator, format, args);
		defer allocator.free(string);
		try text(string, x, y ,fontSize, alignment);
	}
};

pub const TextBuffer = struct {

	pub const Alignment = enum {
		left,
		center,
		right,
	};

	pub const FontEffect = packed struct(u28) {
		color: u24 = 0xffffff,
		bold: bool = false,
		italic: bool = false,
		underline: bool = false,
		strikethrough: bool = false,

		fn hasLine(self: FontEffect, comptime isUnderline: bool) bool {
			if(isUnderline) return self.underline;
			return self.strikethrough;
		}
	};

	const Line = struct {
		start: f32,
		end: f32,
		color: u24,
		isUnderline: bool,
	};

	const LineBreak = struct {
		index: u32,
		width: f32,
	};

	const GlyphData = struct {
		x_advance: f32,
		y_advance: f32,
		x_offset: f32,
		y_offset: f32,
		character: u21,
		index: u32,
		cluster: u32,
		fontEffect: FontEffect,
		characterIndex: u32,
	};

	alignment: Alignment,
	width: f32,
	buffer: harfbuzz.Buffer,
	glyphs: []GlyphData,
	lines: std.ArrayList(Line),
	lineBreaks: std.ArrayList(LineBreak),

	fn addLine(self: *TextBuffer, line: Line) !void {
		if(line.start != line.end) {
			try self.lines.append(line);
		}
	}

	fn initLines(self: *TextBuffer, comptime isUnderline: bool) !void {
		var line: Line = Line {.start = 0, .end = 0, .color = 0, .isUnderline = isUnderline};
		var lastFontEffect: FontEffect = .{};
		for(self.glyphs) |glyph| {
			const fontEffect = glyph.fontEffect;
			if(lastFontEffect.hasLine(isUnderline)) {
				if(fontEffect.color != lastFontEffect.color) {
					try self.addLine(line);
					line.color = fontEffect.color;
					line.start = line.end;
				} else if(!fontEffect.hasLine(isUnderline)) {
					try self.addLine(line);
				}
			} else if(fontEffect.hasLine(isUnderline)) {
				line.start = line.end;
				line.color = fontEffect.color;
			}
			lastFontEffect = fontEffect;
			line.end += glyph.x_advance;
		}
		if(lastFontEffect.hasLine(isUnderline)) {
			try self.addLine(line);
		}
	}

	const Parser = struct {
		unicodeIterator: std.unicode.Utf8Iterator,
		currentFontEffect: FontEffect,
		parsedText: std.ArrayList(u32),
		fontEffects: std.ArrayList(FontEffect),
		characterIndex: std.ArrayList(u32),
		showControlCharacters: bool,
		curChar: u21 = undefined,
		curIndex: u32 = 0,

		fn appendControlGetNext(self: *Parser) !?void {
			if(self.showControlCharacters) {
				try self.fontEffects.append(.{.color = 0x808080});
				try self.parsedText.append(self.curChar);
				try self.characterIndex.append(self.curIndex);
			}
			self.curIndex = @intCast(self.unicodeIterator.i);
			self.curChar = self.unicodeIterator.nextCodepoint() orelse return null;
		}

		fn appendGetNext(self: *Parser) !?void {
			try self.fontEffects.append(self.currentFontEffect);
			try self.parsedText.append(self.curChar);
			try self.characterIndex.append(self.curIndex);
			self.curIndex = @intCast(self.unicodeIterator.i);
			self.curChar = self.unicodeIterator.nextCodepoint() orelse return null;
		}

		fn parse(self: *Parser) !void {
			self.curIndex = @intCast(self.unicodeIterator.i);
			self.curChar = self.unicodeIterator.nextCodepoint() orelse return;
			while(true) switch(self.curChar) {
				'*' => {
					try self.appendControlGetNext() orelse return;
					if(self.curChar == '*') {
						try self.appendControlGetNext() orelse return;
						self.currentFontEffect.bold = !self.currentFontEffect.bold;
					} else {
						self.currentFontEffect.italic = !self.currentFontEffect.italic;
					}
				},
				'_' => {
					try self.appendControlGetNext() orelse return;
					if(self.curChar == '_') {
						try self.appendControlGetNext() orelse return;
						self.currentFontEffect.strikethrough = !self.currentFontEffect.strikethrough;
					} else {
						self.currentFontEffect.underline = !self.currentFontEffect.underline;
					}
				},
				'\\' => {
					try self.appendControlGetNext() orelse return;
					try self.appendGetNext() orelse return;
				},
				'#' => {
					try self.appendControlGetNext() orelse return;
					var shift: u5 = 20;
					while(true) : (shift -= 4) {
						self.currentFontEffect.color = (self.currentFontEffect.color & ~(@as(u24, 0xf) << shift)) | @as(u24, switch(self.curChar) {
							'0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => self.curChar - '0',
							'a', 'b', 'c', 'd', 'e', 'f' => self.curChar - 'a' + 10,
							'A', 'B', 'C', 'D', 'E', 'F' => self.curChar - 'A' + 10,
							else => 0,
						}) << shift;
						try self.appendControlGetNext() orelse return;
						if(shift == 0) break;
					}
				},
				else => {
					try self.appendGetNext() orelse return;
				}
			};
		}
	};

	pub fn init(allocator: Allocator, text: []const u8, initialFontEffect: FontEffect, showControlCharacters: bool, alignment: Alignment) Allocator.Error!TextBuffer {
		var self: TextBuffer = undefined;
		self.alignment = alignment;
		var stackFallback = std.heap.stackFallback(4096, main.threadAllocator);
		const stackFallbackAllocator = stackFallback.get();
		// Parse the input text:
		var parser = Parser {
			.unicodeIterator = std.unicode.Utf8Iterator{.bytes = text, .i = 0},
			.currentFontEffect = initialFontEffect,
			.parsedText = std.ArrayList(u32).init(stackFallbackAllocator),
			.fontEffects = std.ArrayList(FontEffect).init(allocator),
			.characterIndex = std.ArrayList(u32).init(allocator),
			.showControlCharacters = showControlCharacters
		};
		defer parser.fontEffects.deinit();
		defer parser.parsedText.deinit();
		defer parser.characterIndex.deinit();
		self.lines = std.ArrayList(Line).init(allocator);
		self.lineBreaks = std.ArrayList(LineBreak).init(allocator);
		try parser.parse();
		if(parser.parsedText.items.len == 0) {
			self.glyphs = &[0]GlyphData{};
			return self;
		}

		// Let harfbuzz do its thing:
		var buffer = harfbuzz.Buffer.init() orelse return error.OutOfMemory;
		defer buffer.deinit();
		buffer.addUTF32(parser.parsedText.items, 0, null);
		buffer.setDirection(.ltr);
		buffer.setScript(.common);
		buffer.setLanguage(harfbuzz.Language.getDefault());
		TextRendering.harfbuzzFont.shape(buffer, null);
		const glyphInfos = buffer.getGlyphInfos();
		const glyphPositions = buffer.getGlyphPositions().?;

		// Guess the text index from the given cluster indices. Only works if the number of glyphs and the number of characters in a cluster is the same.
		var textIndexGuess = try stackFallbackAllocator.alloc(u32, glyphInfos.len);
		defer stackFallbackAllocator.free(textIndexGuess);
		for(textIndexGuess, 0..) |*index, i| {
			if(i == 0 or glyphInfos[i-1].cluster != glyphInfos[i].cluster) {
				index.* = glyphInfos[i].cluster;
			} else {
				index.* = @min(textIndexGuess[i-1] + 1, @as(u32, @intCast(parser.parsedText.items.len-1)));
				for(glyphInfos[i..]) |glyphInfo| {
					if(glyphInfo.cluster != glyphInfos[i].cluster) {
						index.* = @min(index.*, glyphInfo.cluster - 1);
						break;
					}
				}
			}
		}

		// Merge it all together:
		self.glyphs = try allocator.alloc(GlyphData, glyphInfos.len);
		for(self.glyphs, 0..) |*glyph, i| {
			glyph.x_advance = @as(f32, @floatFromInt(glyphPositions[i].x_advance))/4.0;
			glyph.y_advance = @as(f32, @floatFromInt(glyphPositions[i].y_advance))/4.0;
			glyph.x_offset = @as(f32, @floatFromInt(glyphPositions[i].x_offset))/4.0;
			glyph.y_offset = @as(f32, @floatFromInt(glyphPositions[i].y_offset))/4.0;
			glyph.character = @intCast(parser.parsedText.items[textIndexGuess[i]]);
			glyph.index = glyphInfos[i].codepoint;
			glyph.cluster = glyphInfos[i].cluster;
			glyph.fontEffect = parser.fontEffects.items[textIndexGuess[i]];
			glyph.characterIndex = parser.characterIndex.items[textIndexGuess[i]];
		}

		// Find the lines:
		try self.initLines(true);
		try self.initLines(false);
		try self.lineBreaks.append(.{.index = 0, .width = 0});
		try self.lineBreaks.append(.{.index = @intCast(self.glyphs.len), .width = 0});
		return self;
	}

	pub fn deinit(self: TextBuffer) void {
		self.lines.allocator.free(self.glyphs);
		self.lines.deinit();
		self.lineBreaks.deinit();
	}

	fn getLineOffset(self: TextBuffer, line: usize) f32 {
		const factor: f32 = switch(self.alignment) {
			.left => 0,
			.center => 0.5,
			.right => 1,
		};
		const diff = self.width - self.lineBreaks.items[line+1].width;
		return diff*factor;
	}

	pub fn mousePosToIndex(self: TextBuffer, mousePos: Vec2f, bufferLen: usize) u32 {
		var line: usize = @intFromFloat(@max(0, mousePos[1]/16.0));
		line = @min(line, self.lineBreaks.items.len - 2);
		var x: f32 = self.getLineOffset(line);
		const start = self.lineBreaks.items[line].index;
		const end = self.lineBreaks.items[line + 1].index;
		for(self.glyphs[start..end]) |glyph| {
			if(mousePos[0] < x + glyph.x_advance/2) {
				return @intCast(glyph.characterIndex);
			}

			x += glyph.x_advance;
		}
		return @intCast(if(end < self.glyphs.len) self.glyphs[end-1].characterIndex else bufferLen);
	}

	pub fn indexToCursorPos(self: TextBuffer, index: u32) Vec2f {
		var x: f32 = 0;
		var y: f32 = 0;
		var i: usize = 0;
		while(true) {
			x = self.getLineOffset(i);
			for(self.glyphs[self.lineBreaks.items[i].index..self.lineBreaks.items[i+1].index]) |glyph| {
				if(glyph.characterIndex == index) {
					return .{x, y};
				}

				x += glyph.x_advance;
				y -= glyph.y_advance;
			}
			i += 1;
			if(i >= self.lineBreaks.items.len - 1) {
				return .{x, y};
			}
			y += 16;
		}
	}

	/// Returns the calculated dimensions of the text block.
	pub fn calculateLineBreaks(self: *TextBuffer, fontSize: f32, maxLineWidth: f32) !Vec2f {
		self.lineBreaks.clearRetainingCapacity();
		const spaceCharacterWidth = 8;
		try self.lineBreaks.append(.{.index = 0, .width = 0});
		var scaledMaxWidth = maxLineWidth/fontSize*16.0;
		var lineWidth: f32 = 0;
		var lastSpaceWidth: f32 = 0;
		var lastSpaceIndex: u32 = 0;
		for(self.glyphs, 0..) |glyph, i| {
			lineWidth += glyph.x_advance;
			if(glyph.character == ' ') {
				lastSpaceWidth = lineWidth;
				lastSpaceIndex = @intCast(i+1);
			}
			if(glyph.character == '\n') {
				try self.lineBreaks.append(.{.index = @intCast(i+1), .width = lineWidth - spaceCharacterWidth});
				lineWidth = 0;
				lastSpaceIndex = 0;
				lastSpaceWidth = 0;
			}
			if(lineWidth > scaledMaxWidth) {
				if(lastSpaceIndex != 0) {
					lineWidth -= lastSpaceWidth;
					try self.lineBreaks.append(.{.index = lastSpaceIndex, .width = lastSpaceWidth - spaceCharacterWidth});
					lastSpaceIndex = 0;
					lastSpaceWidth = 0;
				} else {
					try self.lineBreaks.append(.{.index = @intCast(i), .width = lineWidth - glyph.x_advance});
					lineWidth = glyph.x_advance;
					lastSpaceIndex = 0;
					lastSpaceWidth = 0;
				}
			}
		}
		self.width = maxLineWidth;
		try self.lineBreaks.append(.{.index = @intCast(self.glyphs.len), .width = lineWidth});
		return Vec2f{maxLineWidth*fontSize/16.0, @as(f32, @floatFromInt(self.lineBreaks.items.len - 1))*fontSize};
	}

	pub fn drawSelection(self: TextBuffer, pos: Vec2f, selectionStart: u32, selectionEnd: u32) !void {
		std.debug.assert(selectionStart <= selectionEnd);
		var x: f32 = self.getLineOffset(0);
		var y: f32 = 0;
		var i: usize = 0;
		var j: usize = 0;
		// Find the start row:
		outer: while(i < self.lineBreaks.items.len - 1) : (i += 1) {
			x = self.getLineOffset(i);
			while(j < self.lineBreaks.items[i+1].index) : (j += 1) {
				const glyph = self.glyphs[j];
				if(glyph.characterIndex >= selectionStart) break :outer;
				x += glyph.x_advance;
				y -= glyph.y_advance;
			}
			y += 16;
		}
		while(i < self.lineBreaks.items.len - 1) {
			const startX = x;
			while(j < self.lineBreaks.items[i+1].index and j < selectionEnd) : (j += 1) {
				const glyph = self.glyphs[j];
				if(glyph.characterIndex >= selectionEnd) break;
				x += glyph.x_advance;
				y -= glyph.y_advance;
			}
			draw.rect(pos + Vec2f{startX, y}, .{x - startX, 16});
			i += 1;
			if(i >= self.lineBreaks.items.len - 1) break;
			x = self.getLineOffset(i);
			y += 16;
		}
	}

	pub fn render(self: TextBuffer, _x: f32, _y: f32, _fontSize: f32) !void {
		try self.renderShadow(_x, _y, _fontSize);
		const oldTranslation = draw.setTranslation(.{_x, _y});
		defer draw.restoreTranslation(oldTranslation);
		const oldScale = draw.setScale(_fontSize/16.0);
		defer draw.restoreScale(oldScale);
		var x: f32 = 0;
		var y: f32 = 0;
		TextRendering.shader.bind();
		c.glUniform2f(TextRendering.uniforms.scene, @floatFromInt(main.Window.width), @floatFromInt(main.Window.height));
		c.glUniform1f(TextRendering.uniforms.ratio, draw.scale);
		c.glUniform1f(TextRendering.uniforms.alpha, @as(f32, @floatFromInt(draw.color >> 24)) / 255.0);
		c.glActiveTexture(c.GL_TEXTURE0);
		c.glBindTexture(c.GL_TEXTURE_2D, TextRendering.glyphTexture[0]);
		c.glBindVertexArray(draw.rectVAO);
		var stackFallback = std.heap.stackFallback(4096, main.threadAllocator);
		const allocator = stackFallback.get();
		const lineWraps: []f32 = try allocator.alloc(f32, self.lineBreaks.items.len - 1);
		defer allocator.free(lineWraps);
		var i: usize = 0;
		while(i < self.lineBreaks.items.len - 1) : (i += 1) {
			x = self.getLineOffset(i);
			for(self.glyphs[self.lineBreaks.items[i].index..self.lineBreaks.items[i+1].index]) |glyph| {
				if(glyph.character != '\n') {
					const ftGlyph = try TextRendering.getGlyph(glyph.index);
					TextRendering.drawGlyph(ftGlyph, x + glyph.x_offset, y - glyph.y_offset, @bitCast(glyph.fontEffect));
				}
				x += glyph.x_advance;
				y -= glyph.y_advance;
			}
			lineWraps[i] = x - self.getLineOffset(i);
			x = 0;
			y += 16;
		}

		for(self.lines.items) |_line| {
			var line: Line = _line;
			y = 0;
			if(line.isUnderline) y += 15
			else y += 8;
			draw.setColor(line.color | (@as(u32, 0xff000000) & draw.color));
			for(lineWraps, 0..) |lineWrap, j| {
				const lineStart = @max(0, line.start);
				const lineEnd = @min(lineWrap, line.end);
				if(lineStart < lineEnd) {
					var start = Vec2f{lineStart + self.getLineOffset(j), y};
					const dim = Vec2f{lineEnd - lineStart, 1};
					draw.rect(start, dim);
				}
				line.start -= lineWrap;
				line.end -= lineWrap;
				y += 16;
			}
		}
	}

	fn shadowColor(color: u24) u24 {
		const r: f32 = @floatFromInt(color >> 16);
		const g: f32 = @floatFromInt(color >> 8  &  255);
		const b: f32 = @floatFromInt(color & 255);
		const perceivedBrightness = @sqrt(0.299*r*r + 0.587*g*g + 0.114*b*b);
		if(perceivedBrightness < 64) {
			return 0xffffff; // Make shadows white for better readability.
		} else {
			return 0;
		}
	}

	fn renderShadow(self: TextBuffer, _x: f32, _y: f32, _fontSize: f32) !void { // Basically a copy of render with some color and position changes.
		const oldTranslation = draw.setTranslation(.{_x + _fontSize/16.0, _y + _fontSize/16.0});
		defer draw.restoreTranslation(oldTranslation);
		const oldScale = draw.setScale(_fontSize/16.0);
		defer draw.restoreScale(oldScale);
		var x: f32 = 0;
		var y: f32 = 0;
		TextRendering.shader.bind();
		c.glUniform2f(TextRendering.uniforms.scene, @floatFromInt(main.Window.width), @floatFromInt(main.Window.height));
		c.glUniform1f(TextRendering.uniforms.ratio, draw.scale);
		c.glUniform1f(TextRendering.uniforms.alpha, @as(f32, @floatFromInt(draw.color >> 24)) / 255.0);
		c.glActiveTexture(c.GL_TEXTURE0);
		c.glBindTexture(c.GL_TEXTURE_2D, TextRendering.glyphTexture[0]);
		c.glBindVertexArray(draw.rectVAO);
		var stackFallback = std.heap.stackFallback(4096, main.threadAllocator);
		const allocator = stackFallback.get();
		const lineWraps: []f32 = try allocator.alloc(f32, self.lineBreaks.items.len - 1);
		defer allocator.free(lineWraps);
		var i: usize = 0;
		while(i < self.lineBreaks.items.len - 1) : (i += 1) {
			x = self.getLineOffset(i);
			for(self.glyphs[self.lineBreaks.items[i].index..self.lineBreaks.items[i+1].index]) |glyph| {
				if(glyph.character != '\n') {
					const ftGlyph = try TextRendering.getGlyph(glyph.index);
					var fontEffect = glyph.fontEffect;
					fontEffect.color = shadowColor(fontEffect.color);
					TextRendering.drawGlyph(ftGlyph, x + glyph.x_offset, y - glyph.y_offset, @bitCast(fontEffect));
				}
				x += glyph.x_advance;
				y -= glyph.y_advance;
			}
			lineWraps[i] = x - self.getLineOffset(i);
			x = 0;
			y += 16;
		}

		for(self.lines.items) |_line| {
			var line: Line = _line;
			y = 0;
			if(line.isUnderline) y += 15
			else y += 8;
			draw.setColor(shadowColor(line.color) | (@as(u32, 0xff000000) & draw.color));
			for(lineWraps, 0..) |lineWrap, j| {
				const lineStart = @max(0, line.start);
				const lineEnd = @min(lineWrap, line.end);
				if(lineStart < lineEnd) {
					var start = Vec2f{lineStart + self.getLineOffset(j), y};
					const dim = Vec2f{lineEnd - lineStart, 1};
					draw.rect(start, dim);
				}
				line.start -= lineWrap;
				line.end -= lineWrap;
				y += 16;
			}
		}
	}
};

const TextRendering = struct {
	const Glyph = struct {
		textureX: i32,
		size: Vec2i,
		bearing: Vec2i,
		advance: f32,
	};
	var shader: Shader = undefined;
	var uniforms: struct {
		texture_rect: c_int,
		scene: c_int,
		offset: c_int,
		ratio: c_int,
		fontEffects: c_int,
		fontSize: c_int,
		texture_sampler: c_int,
		alpha: c_int,
	} = undefined;

	var freetypeLib: freetype.Library = undefined;
	var freetypeFace: freetype.Face = undefined;
	var harfbuzzFace: harfbuzz.Face = undefined;
	var harfbuzzFont: harfbuzz.Font = undefined;
	var glyphMapping: std.ArrayList(u31) = undefined;
	var glyphData: std.ArrayList(Glyph) = undefined;
	var glyphTexture: [2]c_uint = undefined;
	var textureWidth: i32 = 1024;
	const textureHeight: i32 = 16;
	var textureOffset: i32 = 0;
	fn init() !void {
		shader = try Shader.initAndGetUniforms("assets/cubyz/shaders/graphics/Text.vs", "assets/cubyz/shaders/graphics/Text.fs", &uniforms);
		shader.bind();
		c.glUniform1i(uniforms.texture_sampler, 0);
		c.glUniform1f(uniforms.alpha, 1.0);
		c.glUniform2f(uniforms.fontSize, @floatFromInt(textureWidth), @floatFromInt(textureHeight));
		freetypeLib = try freetype.Library.init();
		freetypeFace = try freetypeLib.createFace("assets/cubyz/fonts/unscii-16-full.ttf", 0);
		try freetypeFace.setPixelSizes(0, textureHeight);
		harfbuzzFace = harfbuzz.Face.fromFreetypeFace(freetypeFace);
		harfbuzzFont = harfbuzz.Font.init(harfbuzzFace);

		glyphMapping = std.ArrayList(u31).init(main.globalAllocator);
		glyphData = std.ArrayList(Glyph).init(main.globalAllocator);
		try glyphData.append(undefined); // 0 is a reserved value.
		c.glGenTextures(2, &glyphTexture);
		c.glBindTexture(c.GL_TEXTURE_2D, glyphTexture[0]);
		c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_R8, textureWidth, textureHeight, 0, c.GL_RED, c.GL_UNSIGNED_BYTE, null);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
		c.glBindTexture(c.GL_TEXTURE_2D, glyphTexture[1]);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
	}

	fn deinit() void {
		shader.deinit();
		freetypeLib.deinit();
		glyphMapping.deinit();
		glyphData.deinit();
		c.glDeleteTextures(2, &glyphTexture);
		harfbuzzFont.deinit();
	}

	fn resizeTexture(newWidth: i32) !void {
		textureWidth = newWidth;
		const swap = glyphTexture[1];
		glyphTexture[1] = glyphTexture[0];
		glyphTexture[0] = swap;
		c.glActiveTexture(c.GL_TEXTURE0);
		c.glBindTexture(c.GL_TEXTURE_2D, glyphTexture[0]);
		c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_R8, newWidth, textureHeight, 0, c.GL_RED, c.GL_UNSIGNED_BYTE, null);
		c.glCopyImageSubData(
			glyphTexture[1], c.GL_TEXTURE_2D, 0, 0, 0, 0,
			glyphTexture[0], c.GL_TEXTURE_2D, 0, 0, 0, 0,
			textureOffset, textureHeight, 1
		);
		shader.bind();
		c.glUniform2f(uniforms.fontSize, @floatFromInt(textureWidth), @floatFromInt(textureHeight));
	}

	fn uploadData(bitmap: freetype.Bitmap) !void {
		const width: i32 = @bitCast(bitmap.width());
		const height: i32 = @bitCast(bitmap.rows());
		const buffer = bitmap.buffer() orelse return;
		if(textureOffset + width > textureWidth) {
			try resizeTexture(textureWidth*2);
		}
		c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
		c.glTexSubImage2D(c.GL_TEXTURE_2D, 0, textureOffset, 0, width, height, c.GL_RED, c.GL_UNSIGNED_BYTE, buffer.ptr);
		textureOffset += width;
	}

	fn getGlyph(index: u32) !Glyph {
		if(index >= glyphMapping.items.len) {
			try glyphMapping.appendNTimes(0, index - glyphMapping.items.len + 1);
		}
		if(glyphMapping.items[index] == 0) {// glyph was not initialized yet.
			try freetypeFace.loadGlyph(index, freetype.LoadFlags{.render = true});
			const glyph = freetypeFace.glyph();
			const bitmap = glyph.bitmap();
			const width = bitmap.width();
			const height = bitmap.rows();
			glyphMapping.items[index] = @intCast(glyphData.items.len);
			(try glyphData.addOne()).* = Glyph {
				.textureX = textureOffset,
				.size = Vec2i{@intCast(width), @intCast(height)},
				.bearing = Vec2i{glyph.bitmapLeft(), 16 - glyph.bitmapTop()},
				.advance = @as(f32, @floatFromInt(glyph.advance().x))/@as(f32, 1 << 6),
			};
			try uploadData(bitmap);
		}
		return glyphData.items[glyphMapping.items[index]];
	}

	fn drawGlyph(glyph: Glyph, _x: f32, _y: f32, fontEffects: u28) void {
		var x = _x;
		var y = _y;
		x *= draw.scale;
		y *= draw.scale;
		x += draw.translation[0];
		y += draw.translation[1];
		x = @floor(x);
		y = @ceil(y);
		c.glUniform1i(uniforms.fontEffects, fontEffects);
		if(fontEffects & 0x1000000 != 0) { // bold
			c.glUniform2f(uniforms.offset, @as(f32, @floatFromInt(glyph.bearing[0]))*draw.scale + x, @as(f32, @floatFromInt(glyph.bearing[1]))*draw.scale + y - 1);
			c.glUniform4f(uniforms.texture_rect, @floatFromInt(glyph.textureX), -1, @floatFromInt(glyph.size[0]), @floatFromInt(glyph.size[1] + 1));
			c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
			// Just draw another thing on top in x direction. The y-direction is handled in the shader.
			c.glUniform2f(uniforms.offset, @as(f32, @floatFromInt(glyph.bearing[0]))*draw.scale + x + 0.5, @as(f32, @floatFromInt(glyph.bearing[1]))*draw.scale + y - 1);
			c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
		} else {
			c.glUniform2f(uniforms.offset, @as(f32, @floatFromInt(glyph.bearing[0]))*draw.scale + x, @as(f32, @floatFromInt(glyph.bearing[1]))*draw.scale + y);
			c.glUniform4f(uniforms.texture_rect, @floatFromInt(glyph.textureX), 0, @floatFromInt(glyph.size[0]), @floatFromInt(glyph.size[1]));
			c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
		}
	}

	fn renderText(text: []const u8, x: f32, y: f32, fontSize: f32, initialFontEffect: TextBuffer.FontEffect, alignment: TextBuffer.Alignment) !void {
		var stackFallback = std.heap.stackFallback(4096, main.threadAllocator);
		const allocator = stackFallback.get();
		const buf = try TextBuffer.init(allocator, text, initialFontEffect, false, alignment);
		defer buf.deinit();

		try buf.render(x, y, fontSize);
	}
};

pub fn init() !void {
	draw.initCircle();
	draw.initDrawRect();
	draw.initImage();
	draw.initLine();
	draw.initRect();
	try TextRendering.init();
	try block_texture.init();
}

pub fn deinit() void {
	draw.deinitCircle();
	draw.deinitDrawRect();
	draw.deinitImage();
	draw.deinitLine();
	draw.deinitRect();
	TextRendering.deinit();
	block_texture.deinit();
}

pub const Shader = struct {
	id: c_uint,

	fn expandSourceIncludes(source: []u8) !std.ArrayList(u8) {
		var output = std.ArrayList(u8).init(main.globalAllocator);
		var cursor: u64 = 0;
		while(std.mem.indexOf(u8, source[cursor..], "#include")) |index| {
			try output.appendSlice(source[cursor..cursor + index]);

			cursor += index + 8;
			while(cursor < source.len and source[cursor] == ' ') {
				cursor += 1;
			}

			if(cursor >= source.len or source[cursor] == '\n') {
				cursor += 1;
			} else if(source[cursor] == '"') {
				cursor += 1;
				const filename_start = cursor;
				while(cursor < source.len and source[cursor] != '"' and source[cursor] != '\n') {
					cursor += 1;
				}
				
				if(cursor < source.len and source[cursor] == '"') {
					const filename = source[filename_start..cursor];
					const rawIncludeSource = main.files.read(main.threadAllocator, filename) catch |err| {
						std.log.warn("Couldn't find file for #include: {s}", .{filename});
						return err;
					};
					defer main.threadAllocator.free(rawIncludeSource);

					const includeSource = try expandSourceIncludes(rawIncludeSource);
					defer includeSource.deinit();

					try output.appendSlice(includeSource.items);
				}

				cursor += 1;
			}
		}

		try output.appendSlice(source[cursor..]);

		return output;
	}
	
	fn addShader(self: *const Shader, filename: []const u8, shader_stage: c_uint) !void {
		const rawSource = main.files.read(main.threadAllocator, filename) catch |err| {
			std.log.warn("Couldn't find file: {s}", .{filename});
			return err;
		};
		defer main.threadAllocator.free(rawSource);

		const sourceArray = try expandSourceIncludes(rawSource);
		const source = sourceArray.items;
		defer sourceArray.deinit();

		std.debug.print("{s}\n", .{source});

		const shader = c.glCreateShader(shader_stage);
		defer c.glDeleteShader(shader);
		
		const sourceLen: c_int = @intCast(source.len);
		c.glShaderSource(shader, 1, &source.ptr, &sourceLen);
		
		c.glCompileShader(shader);

		var success: c_int = undefined;
		c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &success);
		if(success != c.GL_TRUE) {
			var len: u32 = undefined;
			c.glGetShaderiv(shader, c.GL_INFO_LOG_LENGTH, @ptrCast(&len));
			var buf: [4096] u8 = undefined;
			c.glGetShaderInfoLog(shader, 4096, @ptrCast(&len), &buf);
			std.log.err("Error compiling shader {s}:\n{s}\n", .{filename, buf[0..len]});
			return error.FailedCompiling;
		}

		c.glAttachShader(self.id, shader);
	}

	fn link(self: *const Shader) !void {
		c.glLinkProgram(self.id);

		var success: c_int = undefined;
		c.glGetProgramiv(self.id, c.GL_LINK_STATUS, &success);
		if(success != c.GL_TRUE) {
			var len: u32 = undefined;
			c.glGetProgramiv(self.id, c.GL_INFO_LOG_LENGTH, @ptrCast(&len));
			var buf: [4096] u8 = undefined;
			c.glGetProgramInfoLog(self.id, 4096, @ptrCast(&len), &buf);
			std.log.err("Error Linking Shader program:\n{s}\n", .{buf[0..len]});
			return error.FailedLinking;
		}
	}
	
	pub fn init(vertex: []const u8, fragment: []const u8) !Shader {
		var shader = Shader{.id = c.glCreateProgram()};
		try shader.addShader(vertex, c.GL_VERTEX_SHADER);
		try shader.addShader(fragment, c.GL_FRAGMENT_SHADER);
		try shader.link();
		return shader;
	}
	
	pub fn initAndGetUniforms(vertex: []const u8, fragment: []const u8, ptrToUniformStruct: anytype) !Shader {
		const self = try Shader.init(vertex, fragment);
		inline for(@typeInfo(@TypeOf(ptrToUniformStruct.*)).Struct.fields) |field| {
			if(field.type == c_int) {
				@field(ptrToUniformStruct, field.name) = c.glGetUniformLocation(self.id, field.name[0..] ++ "\x00"); // TODO: #16072
			}
		}
		return self;
	}

	pub fn initCompute(compute: []const u8) !Shader {
		var shader = Shader{.id = c.glCreateProgram()};
		try shader.addShader(compute, c.GL_COMPUTE_SHADER);
		try shader.link();
		return shader;
	}

	pub fn initComputeAndGetUniforms(compute: []const u8, ptrToUniformStruct: anytype) !Shader {
		const self = try Shader.initCompute(compute);
		inline for(@typeInfo(@TypeOf(ptrToUniformStruct.*)).Struct.fields) |field| {
			if(field.type == c_int) {
				@field(ptrToUniformStruct, field.name) = c.glGetUniformLocation(self.id, field.name[0..] ++ "\x00"); // TODO: #16072
			}
		}
		return self;
	}

	pub fn bind(self: *const Shader) void {
		c.glUseProgram(self.id);
	}

	pub fn deinit(self: *const Shader) void {
		c.glDeleteProgram(self.id);
	}
};

pub const SSBO = struct {
	bufferID: c_uint,
	pub fn init() SSBO {
		var self = SSBO{.bufferID = undefined};
		c.glGenBuffers(1, &self.bufferID);
		return self;
	}

	pub fn deinit(self: SSBO) void {
		c.glDeleteBuffers(1, &self.bufferID);
	}

	pub fn bind(self: SSBO, binding: c_uint) void {
		c.glBindBufferBase(c.GL_SHADER_STORAGE_BUFFER, binding, self.bufferID);
	}

	pub fn bufferData(self: SSBO, comptime T: type, data: []const T) void {
		c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, self.bufferID);
		c.glBufferData(c.GL_SHADER_STORAGE_BUFFER, @intCast(data.len*@sizeOf(T)), data.ptr, c.GL_STATIC_DRAW);
		c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, 0);
	}

	pub fn createDynamicBuffer(self: SSBO, size: usize) void {
		c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, self.bufferID);
		c.glBufferData(c.GL_SHADER_STORAGE_BUFFER, @intCast(size), null, c.GL_DYNAMIC_DRAW);
		c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, 0);
	}
};

/// A big SSBO that is able to allocate/free smaller regions.
pub const LargeBuffer = struct {
	pub const Allocation = struct {
		start: u31,
		len: u31,
	};
	ssbo: SSBO,
	freeBlocks: std.ArrayList(Allocation),
	capacity: u32,
	used: u32,

	pub fn init(self: *LargeBuffer, allocator: Allocator, size: u31, binding: c_uint) !void {
		self.ssbo = SSBO.init();
		self.ssbo.createDynamicBuffer(size);
		self.ssbo.bind(binding);
		self.capacity = size;

		self.freeBlocks = std.ArrayList(Allocation).init(allocator);
		try self.freeBlocks.append(.{.start = 0, .len = size});
	}

	pub fn deinit(self: *LargeBuffer) void {
		self.ssbo.deinit();
		self.freeBlocks.deinit();
	}

	fn alloc(self: *LargeBuffer, size: u31) !Allocation {
		self.used += size;
		var smallestBlock: ?*Allocation = null;
		for(self.freeBlocks.items, 0..) |*block, i| {
			if(size == block.len) {
				return self.freeBlocks.swapRemove(i);
			}
			if(size < block.len and if(smallestBlock) |_smallestBlock| block.len > _smallestBlock.len else true) {
				smallestBlock = block;
			}
		}
		if(smallestBlock) |block| {
			const result = Allocation {.start = block.start, .len = size};
			block.start += size;
			block.len -= size;
			return result;
		} else return error.OutOfMemory; // TODO: Increase the buffer size.
	}

	pub fn free(self: *LargeBuffer, _allocation: Allocation) !void {
		self.used -= _allocation.len;
		var allocation = _allocation;
		if(allocation.len == 0) return;
		for(self.freeBlocks.items, 0..) |*block, i| {
			if(allocation.start + allocation.len == block.start) {
				allocation.len += block.len;
				_ = self.freeBlocks.swapRemove(i);
				break;
			}
		}
		for(self.freeBlocks.items) |*block| {
			if(allocation.start == block.start + block.len) {
				block.len += allocation.len;
				return;
			}
		}
		try self.freeBlocks.append(allocation);
	}

	pub fn realloc(self: *LargeBuffer, allocation: *Allocation, newSize: u31) !void {
		if(allocation.len == 0) allocation.* = try self.alloc(newSize);
		if(newSize == allocation.len) return;
		if(newSize < allocation.len) {
			const diff = allocation.len - newSize;
			self.used -= diff;
			// Check if there is a free block directly after:
			for(self.freeBlocks.items) |*block| {
				if(allocation.start + allocation.len == block.start and block.len + allocation.len >= newSize) {
					block.start -= diff;
					block.len += diff;
					allocation.len -= diff;
					return;
				}
			}
			// Create a new free block:
			allocation.len -= diff;
			try self.freeBlocks.append(.{.start = allocation.start + allocation.len, .len = diff});
		} else {
			const diff = newSize - allocation.len;
			self.used += diff;
			// Check if the buffer can be extended without a problem:
			for(self.freeBlocks.items, 0..) |*block, i| {
				if(allocation.start + allocation.len == block.start and block.len + allocation.len >= newSize) {
					allocation.len += diff;
					if(block.len != diff) {
						block.start += diff;
						block.len -= diff;
					} else {
						_ = self.freeBlocks.swapRemove(i);
					}
					return;
				}
			}
			const oldAllocation = allocation.*;
			allocation.* = try self.alloc(newSize);

			c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, self.ssbo.bufferID);
			c.glCopyBufferSubData(c.GL_SHADER_STORAGE_BUFFER, c.GL_SHADER_STORAGE_BUFFER, oldAllocation.start, allocation.start, oldAllocation.len);
			c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, 0);

			try self.free(oldAllocation);
		}
	}

	pub fn bufferSubData(self: *LargeBuffer, offset: u31, comptime T: type, data: []T) void {
		c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, self.ssbo.bufferID);
		c.glBufferSubData(c.GL_SHADER_STORAGE_BUFFER, offset, @sizeOf(T)*@as(c_long, @intCast(data.len)), data.ptr);
		c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, 0);
	}
};

pub const FrameBuffer = struct {
	frameBuffer: c_uint,
	texture: c_uint,
	hasDepthTexture: bool,
	depthTexture: c_uint,

	pub fn init(self: *FrameBuffer, hasDepthTexture: bool, textureFilter: c_int, textureWrap: c_int) void {
		self.* = FrameBuffer{
			.frameBuffer = undefined,
			.texture = undefined,
			.depthTexture = undefined,
			.hasDepthTexture = hasDepthTexture,
		};
		c.glGenFramebuffers(1, &self.frameBuffer);
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.frameBuffer);
		if(hasDepthTexture) {
			c.glGenTextures(1, &self.depthTexture);
			c.glBindTexture(c.GL_TEXTURE_2D, self.depthTexture);
			c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, textureFilter);
			c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, textureFilter);
			c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, textureWrap);
			c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, textureWrap);
			c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_TEXTURE_2D, self.depthTexture, 0);
		}
		c.glGenTextures(1, &self.texture);
		c.glBindTexture(c.GL_TEXTURE_2D, self.texture);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, textureFilter);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, textureFilter);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, textureWrap);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, textureWrap);
		c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, self.texture, 0);

		c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
	}

	pub fn deinit(self: *FrameBuffer) void {
		c.glDeleteFramebuffers(1, &self.frameBuffer);
		if(self.hasDepthTexture) {
			c.glDeleteRenderbuffers(1, &self.depthTexture);
		}
		c.glDeleteTextures(1, &self.texture);
	}

	pub fn updateSize(self: *FrameBuffer, width: u31, height: u31, internalFormat: c_int) void {
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.frameBuffer);
		if(self.hasDepthTexture) {
			c.glBindTexture(c.GL_TEXTURE_2D, self.depthTexture);
			c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_DEPTH_COMPONENT32F, width, height, 0, c.GL_DEPTH_COMPONENT, c.GL_FLOAT, null);
		}

		c.glBindTexture(c.GL_TEXTURE_2D, self.texture);
		c.glTexImage2D(c.GL_TEXTURE_2D, 0, internalFormat, width, height, 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, null);
	}

	pub fn clear(_: FrameBuffer, clearColor: Vec4f) void {
		c.glClearColor(clearColor[0], clearColor[1], clearColor[2], clearColor[3]);
		c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);
	}

	pub fn validate(self: *const FrameBuffer) bool {
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.frameBuffer);
		defer c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
		if(c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER) != c.GL_FRAMEBUFFER_COMPLETE) {
			std.log.err("Frame Buffer Object error: {}", .{c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER)});
			return false;
		}
		return true;
	}

	pub fn bindTexture(self: *const FrameBuffer, target: c_uint) void {
		c.glActiveTexture(target);
		c.glBindTexture(c.GL_TEXTURE_2D, self.texture);
	}

	pub fn bindDepthTexture(self: *const FrameBuffer, target: c_uint) void {
		std.debug.assert(self.hasDepthTexture);
		c.glActiveTexture(target);
		c.glBindTexture(c.GL_TEXTURE_2D, self.depthTexture);
	}

	pub fn bind(self: *const FrameBuffer) void {
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.frameBuffer);
	}

	pub fn unbind(_: *const FrameBuffer) void {
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
	}
};

pub const TextureArray = struct {
	textureID: c_uint,

	pub fn init() TextureArray {
		var self: TextureArray = undefined;
		c.glGenTextures(1, &self.textureID);
		return self;
	}

	pub fn deinit(self: TextureArray) void {
		c.glDeleteTextures(1, &self.textureID);
	}

	pub fn bind(self: TextureArray) void {
		c.glBindTexture(c.GL_TEXTURE_2D_ARRAY, self.textureID);
	}

	fn lodColorInterpolation(colors: [4]Color, isTransparent: bool) Color {
		_ = isTransparent;
		var r: [4]f32 = undefined;
		var g: [4]f32 = undefined;
		var b: [4]f32 = undefined;
		var a: [4]f32 = undefined;
		for(0..4) |i| {
			r[i] = @floatFromInt(colors[i].r);
			g[i] = @floatFromInt(colors[i].g);
			b[i] = @floatFromInt(colors[i].b);
			a[i] = @floatFromInt(colors[i].a);
		}
		// Use gamma corrected average(https://stackoverflow.com/a/832314/13082649):
		var aSum: f32 = 0;
		var rSum: f32 = 0;
		var gSum: f32 = 0;
		var bSum: f32 = 0;
		for(0..4) |i| {
			const w = a[i]*a[i];
			aSum += w;
			rSum += w*r[i]*r[i];
			gSum += w*g[i]*g[i];
			bSum += w*b[i]*b[i];
		}
		aSum = @round(@sqrt(aSum))/2;
		rSum = @round(@sqrt(rSum))/2;
		gSum = @round(@sqrt(gSum))/2;
		bSum = @round(@sqrt(bSum))/2;
		if(aSum != 0) {
			rSum /= aSum;
			gSum /= aSum;
			bSum /= aSum;
		}
		return Color{.r=@intFromFloat(rSum), .g=@intFromFloat(gSum), .b=@intFromFloat(bSum), .a=@intFromFloat(aSum)};
	}

	/// (Re-)Generates the GPU buffer.
	pub fn generate(self: TextureArray, images: []Image, mipmapping: bool) !void {
		var maxWidth: u31 = 0;
		var maxHeight: u31 = 0;
		for(images) |image| {
			maxWidth = @max(maxWidth, image.width);
			maxHeight = @max(maxHeight, image.height);
		}
		// Make sure the width and height use a power of 2:
		if(maxWidth-1 & maxWidth != 0) {
			maxWidth = @as(u31, 2) << std.math.log2_int(u31, maxWidth);
		}
		if(maxHeight-1 & maxHeight != 0) {
			maxHeight = @as(u31, 2) << std.math.log2_int(u31, maxHeight);
		}

		std.log.debug("Creating Texture Array of size {}×{} with {} layers.", .{maxWidth, maxHeight, images.len});

		self.bind();

		const maxLOD = if(mipmapping) 1 + std.math.log2_int(u31, @min(maxWidth, maxHeight)) else 1;
		c.glTexStorage3D(c.GL_TEXTURE_2D_ARRAY, maxLOD, c.GL_RGBA8, maxWidth, maxHeight, @intCast(images.len));
		var arena = std.heap.ArenaAllocator.init(main.threadAllocator);
		defer arena.deinit();
		var lodBuffer: [][]Color = try arena.allocator().alloc([]Color, maxLOD);
		for(lodBuffer, 0..) |*buffer, i| {
			buffer.* = try arena.allocator().alloc(Color, (maxWidth >> @intCast(i))*(maxHeight >> @intCast(i)));
		}
		
		for(images, 0..) |image, i| {
			// Check if the image contains non-binary alpha values, which makes it transparent.
			var isTransparent = false;
			for(image.imageData) |color| {
				if(color.a != 0 or color.a != 255) {
					isTransparent = true;
					break;
				}
			}

			// Fill the buffer using nearest sampling. Probably not the best solutions for all textures, but that's what happens when someone doesn't use power of 2 textures...
			for(0..maxWidth) |x| {
				for(0..maxHeight) |y| {
					const index = x + y*maxWidth;
					const imageIndex = (x*image.width)/maxWidth + image.width*(y*image.height)/maxHeight;
					lodBuffer[0][index] = image.imageData[imageIndex];
				}
			}

			// Calculate the mipmap levels:
			for(lodBuffer, 0..) |_, _lod| {
				const lod: u5 = @intCast(_lod);
				const curWidth = maxWidth >> lod;
				const curHeight = maxHeight >> lod;
				if(lod != 0) {
					for(0..curWidth) |x| {
						for(0..curHeight) |y| {
							const index = x + y*curWidth;
							const index2 = 2*x + 2*y*2*curWidth;
							const colors = [4]Color {
								lodBuffer[lod-1][index2],
								lodBuffer[lod-1][index2 + 1],
								lodBuffer[lod-1][index2 + curWidth*2],
								lodBuffer[lod-1][index2 + curWidth*2 + 1],
							};
							lodBuffer[lod][index] = lodColorInterpolation(colors, isTransparent);
						}
					}
				}
				c.glTexSubImage3D(c.GL_TEXTURE_2D_ARRAY, lod, 0, 0, @intCast(i), curWidth, curHeight, 1, c.GL_RGBA, c.GL_UNSIGNED_BYTE, lodBuffer[lod].ptr);
			}
		}
		c.glTexParameteri(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_MAX_LOD, maxLOD);
		//glGenerateMipmap(GL_TEXTURE_2D_ARRAY);
		c.glTexParameteri(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST_MIPMAP_LINEAR);
		c.glTexParameteri(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
		c.glTexParameteri(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
		c.glTexParameteri(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
	}
};

pub const Texture = struct {
	textureID: c_uint,

	pub fn init() Texture {
		var self: Texture = undefined;
		c.glGenTextures(1, &self.textureID);
		return self;
	}

	pub fn initFromFile(path: []const u8) !Texture {
		const self = Texture.init();
		const image = try Image.readFromFile(main.threadAllocator, path);
		defer image.deinit(main.threadAllocator);
		try self.generate(image);
		return self;
	}

	pub fn deinit(self: Texture) void {
		c.glDeleteTextures(1, &self.textureID);
	}

	pub fn bindTo(self: Texture, binding: u5) void {
		c.glActiveTexture(@intCast(c.GL_TEXTURE0 + binding));
		c.glBindTexture(c.GL_TEXTURE_2D, self.textureID);
	}

	pub fn bind(self: Texture) void {
		c.glBindTexture(c.GL_TEXTURE_2D, self.textureID);
	}

	/// (Re-)Generates the GPU buffer.
	pub fn generate(self: Texture, image: Image) !void {
		self.bind();

		c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA8, image.width, image.height, 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, image.imageData.ptr);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
	}

	pub fn render(self: Texture, pos: Vec2f, dim: Vec2f) void {
		self.bindTo(0);
		draw.boundImage(pos, dim);
	}
};

pub const CubeMapTexture = struct {
	textureID: c_uint,

	pub fn init() CubeMapTexture {
		var self: CubeMapTexture = undefined;
		c.glGenTextures(1, &self.textureID);
		return self;
	}

	pub fn deinit(self: CubeMapTexture) void {
		c.glDeleteTextures(1, &self.textureID);
	}

	pub fn bindTo(self: CubeMapTexture, binding: u5) void {
		c.glActiveTexture(@intCast(c.GL_TEXTURE0 + binding));
		c.glBindTexture(c.GL_TEXTURE_CUBE_MAP, self.textureID);
	}

	pub fn bind(self: CubeMapTexture) void {
		c.glBindTexture(c.GL_TEXTURE_CUBE_MAP, self.textureID);
	}

	/// (Re-)Generates the GPU buffer.
	pub fn generate(self: CubeMapTexture, width: u31, height: u31) void {
		self.bind();

		c.glTexImage2D(c.GL_TEXTURE_CUBE_MAP_POSITIVE_X, 0, c.GL_RGBA8, width, height, 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, null);
		c.glTexImage2D(c.GL_TEXTURE_CUBE_MAP_NEGATIVE_X, 0, c.GL_RGBA8, width, height, 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, null);
		c.glTexImage2D(c.GL_TEXTURE_CUBE_MAP_POSITIVE_Y, 0, c.GL_RGBA8, width, height, 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, null);
		c.glTexImage2D(c.GL_TEXTURE_CUBE_MAP_NEGATIVE_Y, 0, c.GL_RGBA8, width, height, 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, null);
		c.glTexImage2D(c.GL_TEXTURE_CUBE_MAP_POSITIVE_Z, 0, c.GL_RGBA8, width, height, 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, null);
		c.glTexImage2D(c.GL_TEXTURE_CUBE_MAP_NEGATIVE_Z, 0, c.GL_RGBA8, width, height, 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, null);
		c.glTexParameteri(c.GL_TEXTURE_CUBE_MAP, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
		c.glTexParameteri(c.GL_TEXTURE_CUBE_MAP, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
		c.glTexParameteri(c.GL_TEXTURE_CUBE_MAP, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
		c.glTexParameteri(c.GL_TEXTURE_CUBE_MAP, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
		c.glTexParameteri(c.GL_TEXTURE_CUBE_MAP, c.GL_TEXTURE_WRAP_R, c.GL_CLAMP_TO_EDGE);
		c.glTexParameteri(c.GL_TEXTURE_CUBE_MAP, c.GL_TEXTURE_BASE_LEVEL, 0);
		c.glTexParameteri(c.GL_TEXTURE_CUBE_MAP, c.GL_TEXTURE_MAX_LEVEL, 0);
	}

	pub fn faceNormal(face: usize) Vec3f {
		const normals = [_]Vec3f {
			.{ 1, 0, 0}, // +x
			.{-1, 0, 0}, // -x
			.{0,  1, 0}, // +y
			.{0, -1, 0}, // -y
			.{0, 0,  1}, // +z
			.{0, 0, -1}, // -z
		};
		return normals[face];
	}

	pub fn faceUp(face: usize) Vec3f {
		const ups = [_]Vec3f {
			.{0, -1, 0}, // +x
			.{0, -1, 0}, // -x
			.{0, 0,  1}, // +y
			.{0, 0, -1}, // -y
			.{0, -1, 0}, // +z
			.{0, -1, 0}, // -z
		};
		return ups[face];
	}

	pub fn faceRight(face: usize) Vec3f {
		comptime var rights: [6]Vec3f = undefined;
		inline for(0..6) |i| {
			rights[i] = comptime vec.cross(faceNormal(i), faceUp(i));
		}
		return rights[face];
	}

	pub fn bindToFramebuffer(self: CubeMapTexture, fb: FrameBuffer, face: c_uint) void {
		fb.bind();
		c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, @as(c_uint, c.GL_TEXTURE_CUBE_MAP_POSITIVE_X) + face, self.textureID, 0);
	}
};

pub const Color = extern struct {
	r: u8,
	g: u8,
	b: u8,
	a: u8,

	pub fn toARBG(self: Color) u32 {
		return @as(u32, self.a)<<24 | @as(u32, self.r)<<16 | @as(u32, self.g)<<8 | @as(u32, self.b);
	}
};

pub const Image = struct {
	var defaultImageData = [4]Color {
		Color{.r=0, .g=0, .b=0, .a=255},
		Color{.r=255, .g=0, .b=255, .a=255},
		Color{.r=255, .g=0, .b=255, .a=255},
		Color{.r=0, .g=0, .b=0, .a=255},
	};
	pub const defaultImage = Image {
		.width = 2,
		.height = 2,
		.imageData = &defaultImageData,
	};
	width: u31,
	height: u31,
	imageData: []Color,
	pub fn init(allocator: Allocator, width: u31, height: u31) !Image {
		return Image{
			.width = width,
			.height = height,
			.imageData = try allocator.alloc(Color, width*height),
		};
	}
	pub fn deinit(self: Image, allocator: Allocator) void {
		if(self.imageData.ptr == &defaultImageData) return;
		allocator.free(self.imageData);
	}
	pub fn readFromFile(allocator: Allocator, path: []const u8) !Image {
		var result: Image = undefined;
		var channel: c_int = undefined;
		const nullTerminatedPath = try std.fmt.allocPrintZ(main.threadAllocator, "{s}", .{path}); // TODO: Find a more zig-friendly image loading library.
		defer main.threadAllocator.free(nullTerminatedPath);
		stb_image.stbi_set_flip_vertically_on_load(1);
		const data = stb_image.stbi_load(nullTerminatedPath.ptr, @ptrCast(&result.width), @ptrCast(&result.height), &channel, 4) orelse {
			return error.FileNotFound;
		};
		result.imageData = try allocator.dupe(Color, @as([*]Color, @ptrCast(data))[0..result.width*result.height]);
		stb_image.stbi_image_free(data);
		return result;
	}
	pub fn exportToFile(self: Image, path: []const u8) !void {
		const nullTerminated = try main.threadAllocator.dupeZ(u8, path);
		defer main.threadAllocator.free(nullTerminated);
		_ = stb_image.stbi_write_png(nullTerminated.ptr, self.width, self.height, 4, self.imageData.ptr, self.width*4);
	}
	pub fn getRGB(self: Image, x: usize, y: usize) Color {
		std.debug.assert(x < self.width);
		std.debug.assert(y < self.height);
		const index = x + y*self.width;
		return self.imageData[index];
	}
	pub fn setRGB(self: Image, x: usize, y: usize, rgb: Color) void {
		std.debug.assert(x < self.width);
		std.debug.assert(y < self.height);
		const index = x + y*self.width;
		self.imageData[index] = rgb;
	}
};

pub const Fog = struct {
	color: Vec3f,
	density: f32,
};

const block_texture = struct {
	var uniforms: struct {
		color: c_int,
		transparent: c_int,
	} = undefined;
	var shader: Shader = undefined;
	var depthTexture: Texture = undefined;
	const textureSize = 128;

	fn init() !void {
		shader = try Shader.initAndGetUniforms("assets/cubyz/shaders/item_texture_post.vs", "assets/cubyz/shaders/item_texture_post.fs", &uniforms);
		depthTexture = Texture.init();
		depthTexture.bind();
		var data: [128*128]f32 = undefined;

		const z: f32 = 134;
		const near = main.renderer.zNear;
		const far = main.renderer.zFar;
		const depth = ((far + near)/(near - far)*z + 2*near*far/(near - far))/-z*0.5 + 0.5;

		@memset(&data, depth);
		c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_R32F, textureSize, textureSize, 0, c.GL_RED, c.GL_FLOAT, &data);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
	}
	fn deinit() void {
		shader.deinit();
		depthTexture.deinit();
	}
};

pub fn generateBlockTexture(blockType: u16) !Texture {
	const block = main.blocks.Block{.typ = blockType, .data = 0}; // TODO: Use natural standard data.
	const textureSize = block_texture.textureSize;
	c.glViewport(0, 0, textureSize, textureSize);

	var frameBuffer: FrameBuffer = undefined;
	const scissor = c.glIsEnabled(c.GL_SCISSOR_TEST);
	c.glDisable(c.GL_SCISSOR_TEST);
	defer if(scissor != 0) c.glEnable(c.GL_SCISSOR_TEST);
	const depthTest = c.glIsEnabled(c.GL_DEPTH_TEST);
	c.glDisable(c.GL_DEPTH_TEST);
	defer if(depthTest != 0) c.glEnable(c.GL_DEPTH_TEST);
	const cullFace = c.glIsEnabled(c.GL_CULL_FACE);
	c.glDisable(c.GL_CULL_FACE);
	defer if(cullFace != 0) c.glEnable(c.GL_CULL_FACE);

	frameBuffer.init(false, c.GL_NEAREST, c.GL_REPEAT);
	defer frameBuffer.deinit();
	frameBuffer.updateSize(textureSize, textureSize, c.GL_RGBA16F);
	frameBuffer.bind();
	if(block.transparent()) {
		frameBuffer.clear(.{0.683421, 0.6854237, 0.685426, 1});
	} else {
		frameBuffer.clear(.{0, 0, 0, 0});
	}

	const projMatrix = Mat4f.perspective(0.013, 1, 64, 256);
	const oldViewMatrix = main.game.camera.viewMatrix;
	main.game.camera.viewMatrix = Mat4f.rotationX(std.math.pi/4.0).mul(Mat4f.rotationY(-std.math.pi/4.0));
	defer main.game.camera.viewMatrix = oldViewMatrix;
	if(block.transparent()) {
		c.glBlendEquation(c.GL_FUNC_ADD);
		c.glBlendFunc(c.GL_ONE, c.GL_SRC1_COLOR);
		main.chunk.meshing.bindTransparentShaderAndUniforms(projMatrix, .{1, 1, 1});
	} else {
		main.chunk.meshing.bindShaderAndUniforms(projMatrix, .{1, 1, 1});
	}
	const uniforms = if(block.transparent()) &main.chunk.meshing.transparentUniforms else &main.chunk.meshing.uniforms;

	var faceData: [6]main.chunk.meshing.FaceData = undefined;
	var faces: u8 = 0;
	if(block.hasBackFace()) {
		faceData[2] = main.chunk.meshing.ChunkMesh.constructFaceData(block, main.chunk.Neighbors.dirPosX, 1, 1, 1, true);
		faceData[1] = main.chunk.meshing.ChunkMesh.constructFaceData(block, main.chunk.Neighbors.dirUp, 1, 1, 1, true);
		faceData[0] = main.chunk.meshing.ChunkMesh.constructFaceData(block, main.chunk.Neighbors.dirPosZ, 1, 1, 1, true);
		faces += 3;
	}
	faceData[faces + 0] = main.chunk.meshing.ChunkMesh.constructFaceData(block, main.chunk.Neighbors.dirPosX, 1+1, 1, 1, false);
	faceData[faces + 1] = main.chunk.meshing.ChunkMesh.constructFaceData(block, main.chunk.Neighbors.dirUp, 1, 1+1, 1, false);
	faceData[faces + 2] = main.chunk.meshing.ChunkMesh.constructFaceData(block, main.chunk.Neighbors.dirPosZ, 1, 1, 1+1, false);
	faces += 3;
	var allocation: LargeBuffer.Allocation = .{.start = 0, .len = 0};
	try main.chunk.meshing.faceBuffer.realloc(&allocation, faces*@sizeOf(main.chunk.meshing.FaceData));
	main.chunk.meshing.faceBuffer.bufferSubData(allocation.start, main.chunk.meshing.FaceData, faceData[0..faces]);

	c.glUniform3f(uniforms.modelPosition, -65.5 - 1.5, -92.631 - 1.5, -65.5 - 1.5);
	c.glUniform1i(uniforms.visibilityMask, 0xff);
	c.glUniform1i(uniforms.voxelSize, 1);
	c.glActiveTexture(c.GL_TEXTURE0);
	main.blocks.meshes.blockTextureArray.bind();
	c.glActiveTexture(c.GL_TEXTURE1);
	main.blocks.meshes.emissionTextureArray.bind();
	block_texture.depthTexture.bindTo(3);
	c.glDrawElementsBaseVertex(c.GL_TRIANGLES, 6*faces, c.GL_UNSIGNED_INT, null, allocation.start/8*4);

	var finalFrameBuffer: FrameBuffer = undefined;
	finalFrameBuffer.init(false, c.GL_NEAREST, c.GL_REPEAT);
	finalFrameBuffer.updateSize(textureSize, textureSize, c.GL_RGBA8);
	finalFrameBuffer.bind();
	var texture = Texture{.textureID = finalFrameBuffer.texture};
	defer c.glDeleteFramebuffers(1, &finalFrameBuffer.frameBuffer);
	block_texture.shader.bind();
	c.glUniform1i(block_texture.uniforms.transparent, if(block.transparent()) c.GL_TRUE else c.GL_FALSE);
	c.glUniform1i(block_texture.uniforms.color, 3);
	frameBuffer.bindTexture(c.GL_TEXTURE3);

	c.glBindVertexArray(draw.rectVAO);
	c.glDisable(c.GL_BLEND);
	c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	c.glEnable(c.GL_BLEND);

	c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);

	try main.chunk.meshing.faceBuffer.free(allocation);
	c.glViewport(0, 0, main.Window.width, main.Window.height);
	c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
	return texture;
}