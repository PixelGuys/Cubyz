/// A collection of things that should make dealing with opengl easier.
/// Also contains some basic 2d drawing stuff.
const std = @import("std");
const builtin = @import("builtin");

const vec = @import("vec.zig");
const Mat4f = vec.Mat4f;
const Vec4i = vec.Vec4i;
const Vec4f = vec.Vec4f;
const Vec2f = vec.Vec2f;
const Vec2i = vec.Vec2i;
const Vec3f = vec.Vec3f;

const main = @import("main");
const Window = main.Window;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const c = @import("c");

const pipelines = @import("graphics/pipelines.zig");
pub const ComputePipeline = pipelines.ComputePipeline;
pub const Pipeline = pipelines.Pipeline;

pub const vulkan = @import("graphics/vulkan.zig");

pub const draw = struct { // MARK: draw
	var color: u32 = 0;
	var clip: ?Vec4i = null;
	var translation: Vec2f = Vec2f{0, 0};
	var scale: f32 = 1;

	pub fn setColor(newColor: u32) void {
		color = newColor;
	}

	pub fn setColorSameAlpha(newColor: u24) void {
		color = (color & 0xff000000) | newColor;
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
		var viewport: [4]c_int = undefined;
		c.glGetIntegerv(c.GL_VIEWPORT, &viewport);
		var newClip = Vec4i{
			std.math.lossyCast(i32, translation[0]),
			viewport[3] - std.math.lossyCast(i32, translation[1] + clipRect[1]*scale),
			std.math.lossyCast(i32, clipRect[0]*scale),
			std.math.lossyCast(i32, clipRect[1]*scale),
		};
		if (clip) |oldClip| {
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
		}
		const oldClip = clip;
		clip = newClip;
		return oldClip;
	}

	pub fn getScissor() ?c.VkRect2D {
		const clipRect = clip orelse return null;
		return .{
			.offset = .{
				.x = clipRect[0],
				.y = clipRect[1],
			},
			.extent = .{
				.width = @intCast(clipRect[2]),
				.height = @intCast(clipRect[3]),
			},
		};
	}

	/// Should be used to restore the old clip when leaving the render function.
	pub fn restoreClip(previousClip: ?Vec4i) void {
		clip = previousClip;
	}

	pub const SimpleVertex2D = struct {
		pos: [2]f32,

		pub const attributeDescriptions: []const c.VkVertexInputAttributeDescription = &.{
			.{
				.location = 0,
				.format = c.VK_FORMAT_R32G32_SFLOAT,
				.offset = @offsetOf(@This(), "pos"),
			},
		};
	};

	// ----------------------------------------------------------------------------
	// MARK: fillRect()
	var rectUniforms: struct {
		screen: c_int,
		start: c_int,
		size: c_int,
		rectColor: c_int,
	} = undefined;
	var rectPipeline: Pipeline = undefined;
	pub var rectVao: VertexArray = undefined;

	fn initRect() void {
		rectPipeline = Pipeline.init(
			"assets/cubyz/shaders/graphics/Rect.vert",
			"assets/cubyz/shaders/graphics/Rect.frag",
			"",
			&rectUniforms,
			SimpleVertex2D,
			&.{},
			.{.cullMode = .none},
			.{.depthTest = false, .depthWrite = false},
			.{.attachments = &.{.alphaBlending}},
		);
		const rawData = [_]SimpleVertex2D{
			.{.pos = .{0, 0}},
			.{.pos = .{0, 1}},
			.{.pos = .{1, 0}},
			.{.pos = .{1, 1}},
		};

		rectVao = .init(SimpleVertex2D, &rawData, null);
	}

	fn deinitRect() void {
		rectPipeline.deinit();
		rectVao.deinit();
	}

	pub fn rect(_pos: Vec2f, _dim: Vec2f) void {
		var pos = _pos;
		var dim = _dim;
		pos *= @splat(scale);
		pos += translation;
		dim *= @splat(scale);

		rectPipeline.bind(getScissor());

		var viewport: [4]c_int = undefined;
		c.glGetIntegerv(c.GL_VIEWPORT, &viewport);
		c.glUniform2f(rectUniforms.screen, @floatFromInt(viewport[2]), @floatFromInt(viewport[3]));
		c.glUniform2f(rectUniforms.start, pos[0], pos[1]);
		c.glUniform2f(rectUniforms.size, dim[0], dim[1]);
		c.glUniform1i(rectUniforms.rectColor, @bitCast(color));

		rectVao.bind();
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}

	// ----------------------------------------------------------------------------
	// MARK: fillRectBorder()
	var rectBorderUniforms: struct {
		screen: c_int,
		start: c_int,
		size: c_int,
		rectColor: c_int,
		lineWidth: c_int,
	} = undefined;
	var rectBorderPipeline: Pipeline = undefined;
	var rectBorderVao: VertexArray = undefined;

	fn initRectBorder() void {
		const RectBorderVertex = struct {
			pos: [4]f32,

			pub const attributeDescriptions: []const c.VkVertexInputAttributeDescription = &.{
				.{
					.location = 0,
					.format = c.VK_FORMAT_R32G32B32A32_SFLOAT,
					.offset = @offsetOf(@This(), "pos"),
				},
			};
		};
		rectBorderPipeline = Pipeline.init(
			"assets/cubyz/shaders/graphics/RectBorder.vert",
			"assets/cubyz/shaders/graphics/RectBorder.frag",
			"",
			&rectBorderUniforms,
			RectBorderVertex,
			&.{},
			.{.cullMode = .none},
			.{.depthTest = false, .depthWrite = false},
			.{.attachments = &.{.alphaBlending}},
		);
		const rawData = [_]RectBorderVertex{
			.{.pos = .{0, 0, 0, 0}},
			.{.pos = .{0, 0, 1, 1}},
			.{.pos = .{0, 1, 0, 0}},
			.{.pos = .{0, 1, 1, -1}},
			.{.pos = .{1, 1, 0, 0}},
			.{.pos = .{1, 1, -1, -1}},
			.{.pos = .{1, 0, 0, 0}},
			.{.pos = .{1, 0, -1, 1}},
			.{.pos = .{0, 0, 0, 0}},
			.{.pos = .{0, 0, 1, 1}},
		};

		rectBorderVao = .init(RectBorderVertex, &rawData, null);
	}

	fn deinitRectBorder() void {
		rectBorderPipeline.deinit();
		rectBorderVao.deinit();
	}

	pub fn rectBorder(_pos: Vec2f, _dim: Vec2f, _width: f32) void {
		var pos = _pos;
		var dim = _dim;
		var width = _width;
		pos *= @splat(scale);
		pos += translation;
		dim *= @splat(scale);
		width *= scale;

		rectBorderPipeline.bind(getScissor());

		var viewport: [4]c_int = undefined;
		c.glGetIntegerv(c.GL_VIEWPORT, &viewport);
		c.glUniform2f(rectBorderUniforms.screen, @floatFromInt(viewport[2]), @floatFromInt(viewport[3]));
		c.glUniform2f(rectBorderUniforms.start, pos[0], pos[1]);
		c.glUniform2f(rectBorderUniforms.size, dim[0], dim[1]);
		c.glUniform1i(rectBorderUniforms.rectColor, @bitCast(color));
		c.glUniform1f(rectBorderUniforms.lineWidth, width);

		rectBorderVao.bind();
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 10);
	}

	// ----------------------------------------------------------------------------
	// MARK: drawLine()
	var lineUniforms: struct {
		screen: c_int,
		start: c_int,
		direction: c_int,
		lineColor: c_int,
	} = undefined;
	var linePipeline: Pipeline = undefined;
	var lineVao: VertexArray = undefined;

	fn initLine() void {
		linePipeline = Pipeline.init(
			"assets/cubyz/shaders/graphics/Line.vert",
			"assets/cubyz/shaders/graphics/Line.frag",
			"",
			&lineUniforms,
			SimpleVertex2D,
			&.{},
			.{.cullMode = .none},
			.{.depthTest = false, .depthWrite = false},
			.{.attachments = &.{.alphaBlending}},
		);
		const rawData = [_]SimpleVertex2D{
			.{.pos = .{0, 0}},
			.{.pos = .{1, 1}},
		};

		lineVao = .init(SimpleVertex2D, &rawData, null);
	}

	fn deinitLine() void {
		linePipeline.deinit();
		lineVao.deinit();
	}

	pub fn line(_pos1: Vec2f, _pos2: Vec2f) void {
		var pos1 = _pos1;
		var pos2 = _pos2;
		pos1 *= @splat(scale);
		pos1 += translation;
		pos2 *= @splat(scale);
		pos2 += translation;

		linePipeline.bind(getScissor());

		var viewport: [4]c_int = undefined;
		c.glGetIntegerv(c.GL_VIEWPORT, &viewport);
		c.glUniform2f(lineUniforms.screen, @floatFromInt(viewport[2]), @floatFromInt(viewport[3]));
		c.glUniform2f(lineUniforms.start, pos1[0], pos1[1]);
		c.glUniform2f(lineUniforms.direction, pos2[0] - pos1[0], pos2[1] - pos1[1]);
		c.glUniform1i(lineUniforms.lineColor, @bitCast(color));

		lineVao.bind();
		c.glDrawArrays(c.GL_LINE_STRIP, 0, 2);
	}

	pub fn rectOutline(_pos: Vec2f, _dim: Vec2f) void {
		var pos = _pos;
		var dim = _dim;
		pos *= @splat(scale);
		pos += translation;
		dim *= @splat(scale);

		linePipeline.bind(getScissor());

		var viewport: [4]c_int = undefined;
		c.glGetIntegerv(c.GL_VIEWPORT, &viewport);
		c.glUniform2f(lineUniforms.screen, @floatFromInt(viewport[2]), @floatFromInt(viewport[3]));
		c.glUniform2f(lineUniforms.start, pos[0], pos[1]); // Move the coordinates, so they are in the center of a pixel.
		c.glUniform2f(lineUniforms.direction, dim[0] - 1, dim[1] - 1); // The height is a lot smaller because the inner edge of the rect is drawn.
		c.glUniform1i(lineUniforms.lineColor, @bitCast(color));

		lineVao.bind();
		c.glDrawArrays(c.GL_LINE_LOOP, 0, 5);
	}

	// ----------------------------------------------------------------------------
	// MARK: fillCircle()
	var circleUniforms: struct {
		screen: c_int,
		center: c_int,
		radius: c_int,
		circleColor: c_int,
	} = undefined;
	var circlePipeline: Pipeline = undefined;
	var circleVao: VertexArray = undefined;

	fn initCircle() void {
		circlePipeline = Pipeline.init(
			"assets/cubyz/shaders/graphics/Circle.vert",
			"assets/cubyz/shaders/graphics/Circle.frag",
			"",
			&circleUniforms,
			SimpleVertex2D,
			&.{},
			.{.cullMode = .none},
			.{.depthTest = false, .depthWrite = false},
			.{.attachments = &.{.alphaBlending}},
		);
		const rawData = [_]SimpleVertex2D{
			.{.pos = .{-1, -1}},
			.{.pos = .{-1, 1}},
			.{.pos = .{1, -1}},
			.{.pos = .{1, 1}},
		};

		circleVao = .init(SimpleVertex2D, &rawData, null);
	}

	fn deinitCircle() void {
		circlePipeline.deinit();
		circleVao.deinit();
	}

	pub fn circle(_center: Vec2f, _radius: f32) void {
		var center = _center;
		var radius = _radius;
		center *= @splat(scale);
		center += translation;
		radius *= scale;
		circlePipeline.bind(getScissor());

		var viewport: [4]c_int = undefined;
		c.glGetIntegerv(c.GL_VIEWPORT, &viewport);
		c.glUniform2f(circleUniforms.screen, @floatFromInt(viewport[2]), @floatFromInt(viewport[3]));
		c.glUniform2f(circleUniforms.center, center[0], center[1]); // Move the coordinates, so they are in the center of a pixel.
		c.glUniform1f(circleUniforms.radius, radius); // The height is a lot smaller because the inner edge of the rect is drawn.
		c.glUniform1i(circleUniforms.circleColor, @bitCast(color));

		circleVao.bind();
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}

	// ----------------------------------------------------------------------------
	// MARK: drawImage()
	// Luckily the vao of the regular rect can used.
	var imageUniforms: struct {
		screen: c_int,
		start: c_int,
		size: c_int,
		color: c_int,
		uvOffset: c_int,
		uvDim: c_int,
	} = undefined;
	var imagePipeline: Pipeline = undefined;

	fn initImage() void {
		imagePipeline = Pipeline.init(
			"assets/cubyz/shaders/graphics/Image.vert",
			"assets/cubyz/shaders/graphics/Image.frag",
			"",
			&imageUniforms,
			SimpleVertex2D,
			&.{},
			.{.cullMode = .none},
			.{.depthTest = false, .depthWrite = false},
			.{.attachments = &.{.alphaBlending}},
		);
	}

	fn deinitImage() void {
		imagePipeline.deinit();
	}

	pub fn boundImage(_pos: Vec2f, _dim: Vec2f) void {
		imagePipeline.bind(getScissor());

		customShadedImage(&imageUniforms, _pos, _dim);
	}

	pub fn boundSubImage(_pos: Vec2f, _dim: Vec2f, uvOffset: Vec2f, uvDim: Vec2f) void {
		var pos = _pos;
		var dim = _dim;
		pos *= @splat(scale);
		pos += translation;
		dim *= @splat(scale);
		pos = @floor(pos);
		dim = @ceil(dim);

		imagePipeline.bind(getScissor());

		var viewport: [4]c_int = undefined;
		c.glGetIntegerv(c.GL_VIEWPORT, &viewport);
		c.glUniform2f(imageUniforms.screen, @floatFromInt(viewport[2]), @floatFromInt(viewport[3]));
		c.glUniform2f(imageUniforms.start, pos[0], pos[1]);
		c.glUniform2f(imageUniforms.size, dim[0], dim[1]);
		c.glUniform1i(imageUniforms.color, @bitCast(color));
		c.glUniform2f(imageUniforms.uvOffset, uvOffset[0], 1 - uvOffset[1] - uvDim[1]);
		c.glUniform2f(imageUniforms.uvDim, uvDim[0], uvDim[1]);

		rectVao.bind();
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}

	pub fn customShadedImage(uniforms: anytype, _pos: Vec2f, _dim: Vec2f) void {
		var pos = _pos;
		var dim = _dim;
		pos *= @splat(scale);
		pos += translation;
		dim *= @splat(scale);
		pos = @floor(pos);
		dim = @ceil(dim);

		var viewport: [4]c_int = undefined;
		c.glGetIntegerv(c.GL_VIEWPORT, &viewport);
		c.glUniform2f(uniforms.screen, @floatFromInt(viewport[2]), @floatFromInt(viewport[3]));
		c.glUniform2f(uniforms.start, pos[0], pos[1]);
		c.glUniform2f(uniforms.size, dim[0], dim[1]);
		c.glUniform1i(uniforms.color, @bitCast(color));
		c.glUniform2f(uniforms.uvOffset, 0, 0);
		c.glUniform2f(uniforms.uvDim, 1, 1);

		rectVao.bind();
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}

	// ----------------------------------------------------------------------------
	// MARK: customShadedRect()

	pub fn customShadedRect(uniforms: anytype, _pos: Vec2f, _dim: Vec2f) void {
		var pos = _pos;
		var dim = _dim;
		pos *= @splat(scale);
		pos += translation;
		dim *= @splat(scale);
		pos = @floor(pos);
		dim = @ceil(dim);

		var viewport: [4]c_int = undefined;
		c.glGetIntegerv(c.GL_VIEWPORT, &viewport);
		c.glUniform2f(uniforms.screen, @floatFromInt(viewport[2]), @floatFromInt(viewport[3]));
		c.glUniform2f(uniforms.start, pos[0], pos[1]);
		c.glUniform2f(uniforms.size, dim[0], dim[1]);
		c.glUniform1i(uniforms.color, @bitCast(color));
		c.glUniform1f(uniforms.scale, scale);

		rectVao.bind();
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}

	// ----------------------------------------------------------------------------
	// MARK: text()

	pub fn text(_text: []const u8, x: f32, y: f32, fontSize: f32, alignment: TextBuffer.Alignment) void {
		TextRendering.renderText(_text, x, y, fontSize, .{.color = @truncate(@as(u32, @bitCast(color)))}, alignment);
	}

	pub inline fn print(comptime format: []const u8, args: anytype, x: f32, y: f32, fontSize: f32, alignment: TextBuffer.Alignment) void {
		const string = std.fmt.allocPrint(main.stackAllocator.allocator, format, args) catch unreachable;
		defer main.stackAllocator.free(string);
		text(string, x, y, fontSize, alignment);
	}
};

pub const TextBuffer = struct { // MARK: TextBuffer

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
			if (isUnderline) return self.underline;
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
	buffer: ?*c.hb_buffer_t,
	glyphs: []GlyphData,
	lines: main.List(Line),
	lineBreaks: main.List(LineBreak),

	fn addLine(self: *TextBuffer, line: Line) void {
		if (line.start != line.end) {
			self.lines.append(line);
		}
	}

	fn initLines(self: *TextBuffer, comptime isUnderline: bool) void {
		var line: Line = Line{.start = 0, .end = 0, .color = 0, .isUnderline = isUnderline};
		var lastFontEffect: FontEffect = .{};
		for (self.glyphs) |glyph| {
			const fontEffect = glyph.fontEffect;
			if (lastFontEffect.hasLine(isUnderline)) {
				if (fontEffect.color != lastFontEffect.color) {
					self.addLine(line);
					line.color = fontEffect.color;
					line.start = line.end;
				} else if (!fontEffect.hasLine(isUnderline)) {
					self.addLine(line);
				}
			} else if (fontEffect.hasLine(isUnderline)) {
				line.start = line.end;
				line.color = fontEffect.color;
			}
			lastFontEffect = fontEffect;
			line.end += glyph.x_advance;
		}
		if (lastFontEffect.hasLine(isUnderline)) {
			self.addLine(line);
		}
	}

	pub const Parser = struct {
		unicodeIterator: std.unicode.Utf8Iterator,
		currentFontEffect: FontEffect,
		parsedText: main.List(u32),
		fontEffects: main.List(FontEffect),
		characterIndex: main.List(u32),
		showControlCharacters: bool,
		curChar: u21 = undefined,
		curIndex: u32 = 0,

		fn appendControlGetNext(self: *Parser) ?void {
			if (self.showControlCharacters) {
				self.fontEffects.append(.{.color = 0x808080});
				self.parsedText.append(self.curChar);
				self.characterIndex.append(self.curIndex);
			}
			self.curIndex = @intCast(self.unicodeIterator.i);
			self.curChar = self.unicodeIterator.nextCodepoint() orelse return null;
		}

		fn appendGetNext(self: *Parser) ?void {
			self.fontEffects.append(self.currentFontEffect);
			self.parsedText.append(self.curChar);
			self.characterIndex.append(self.curIndex);
			self.curIndex = @intCast(self.unicodeIterator.i);
			self.curChar = self.unicodeIterator.nextCodepoint() orelse return null;
		}

		fn peekNextByte(self: *Parser) u8 {
			const next = self.unicodeIterator.peek(1);
			if (next.len == 0) return 0;
			return next[0];
		}

		fn parse(self: *Parser) void {
			self.curIndex = @intCast(self.unicodeIterator.i);
			self.curChar = self.unicodeIterator.nextCodepoint() orelse return;
			while (true) switch (self.curChar) {
				'*' => {
					self.appendControlGetNext() orelse return;
					if (self.curChar == '*') {
						self.appendControlGetNext() orelse return;
						self.currentFontEffect.bold = !self.currentFontEffect.bold;
					} else {
						self.currentFontEffect.italic = !self.currentFontEffect.italic;
					}
				},
				'_' => {
					if (self.peekNextByte() == '_') {
						self.appendControlGetNext() orelse return;
						self.appendControlGetNext() orelse return;
						self.currentFontEffect.underline = !self.currentFontEffect.underline;
					} else {
						self.appendGetNext() orelse return;
					}
				},
				'~' => {
					if (self.peekNextByte() == '~') {
						self.appendControlGetNext() orelse return;
						self.appendControlGetNext() orelse return;
						self.currentFontEffect.strikethrough = !self.currentFontEffect.strikethrough;
					} else {
						self.appendGetNext() orelse return;
					}
				},
				'\\' => {
					self.appendControlGetNext() orelse return;
					self.appendGetNext() orelse return;
				},
				'#' => {
					self.appendControlGetNext() orelse return;
					var shift: u5 = 20;
					while (true) : (shift -= 4) {
						self.currentFontEffect.color = (self.currentFontEffect.color & ~(@as(u24, 0xf) << shift)) | @as(u24, switch (self.curChar) {
							'0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => self.curChar - '0',
							'a', 'b', 'c', 'd', 'e', 'f' => self.curChar - 'a' + 10,
							'A', 'B', 'C', 'D', 'E', 'F' => self.curChar - 'A' + 10,
							else => 0,
						}) << shift;
						self.appendControlGetNext() orelse return;
						if (shift == 0) break;
					}
				},
				'§' => {
					self.currentFontEffect = .{.color = self.currentFontEffect.color};
					self.appendControlGetNext() orelse return;
				},
				else => {
					self.appendGetNext() orelse return;
				},
			};
		}

		pub fn countVisibleCharacters(text: []const u8) usize {
			var unicodeIterator = std.unicode.Utf8Iterator{.bytes = text, .i = 0};
			var count: usize = 0;
			var curChar = unicodeIterator.nextCodepoint() orelse return count;
			outer: while (true) switch (curChar) {
				'*' => {
					curChar = unicodeIterator.nextCodepoint() orelse break;
				},
				'_' => {
					curChar = unicodeIterator.nextCodepoint() orelse break;
					if (curChar == '_') {
						curChar = unicodeIterator.nextCodepoint() orelse break;
					} else {
						count += 1;
					}
				},
				'~' => {
					curChar = unicodeIterator.nextCodepoint() orelse break;
					if (curChar == '~') {
						curChar = unicodeIterator.nextCodepoint() orelse break;
					} else {
						count += 1;
					}
				},
				'\\' => {
					curChar = unicodeIterator.nextCodepoint() orelse break;
					curChar = unicodeIterator.nextCodepoint() orelse break;
					count += 1;
				},
				'#' => {
					for (0..7) |_| curChar = unicodeIterator.nextCodepoint() orelse break :outer;
				},
				'§' => {
					curChar = unicodeIterator.nextCodepoint() orelse break;
				},
				else => {
					count += 1;
					curChar = unicodeIterator.nextCodepoint() orelse break;
				},
			};
			return count;
		}
	};

	pub fn init(allocator: NeverFailingAllocator, text: []const u8, initialFontEffect: FontEffect, showControlCharacters: bool, alignment: Alignment) TextBuffer {
		var self: TextBuffer = .{
			.alignment = alignment,
			.width = 1e9,
			.buffer = null,
			.glyphs = &.{},
			.lines = .init(allocator),
			.lineBreaks = .init(allocator),
		};
		// Parse the input text:
		var parser = Parser{
			.unicodeIterator = std.unicode.Utf8Iterator{.bytes = text, .i = 0},
			.currentFontEffect = initialFontEffect,
			.parsedText = .init(main.stackAllocator),
			.fontEffects = .init(allocator),
			.characterIndex = .init(allocator),
			.showControlCharacters = showControlCharacters,
		};
		defer parser.fontEffects.deinit();
		defer parser.parsedText.deinit();
		defer parser.characterIndex.deinit();
		parser.parse();
		if (parser.parsedText.items.len == 0) {
			self.lineBreaks.append(.{.index = 0, .width = 0});
			return self;
		}

		// Let harfbuzz do its thing:
		const buffer = c.hb_buffer_create() orelse @panic("Out of Memory while creating harfbuzz buffer");
		defer c.hb_buffer_destroy(buffer);
		c.hb_buffer_add_utf32(buffer, parser.parsedText.items.ptr, @intCast(parser.parsedText.items.len), 0, @intCast(parser.parsedText.items.len));
		c.hb_buffer_set_direction(buffer, c.HB_DIRECTION_LTR);
		c.hb_buffer_set_script(buffer, c.HB_SCRIPT_COMMON);
		c.hb_buffer_set_language(buffer, c.hb_language_get_default());
		c.hb_shape(TextRendering.harfbuzzFont, buffer, null, 0);
		var glyphInfos: []c.hb_glyph_info_t = undefined;
		var glyphPositions: []c.hb_glyph_position_t = undefined;
		{
			var len: c_uint = 0;
			glyphInfos.ptr = c.hb_buffer_get_glyph_infos(buffer, &len).?;
			glyphPositions.ptr = c.hb_buffer_get_glyph_positions(buffer, &len).?;
			glyphInfos.len = len;
			glyphPositions.len = len;
		}

		// Guess the text index from the given cluster indices. Only works if the number of glyphs and the number of characters in a cluster is the same.
		const textIndexGuess = main.stackAllocator.alloc(u32, glyphInfos.len);
		defer main.stackAllocator.free(textIndexGuess);
		for (textIndexGuess, 0..) |*index, i| {
			if (i == 0 or glyphInfos[i - 1].cluster != glyphInfos[i].cluster) {
				index.* = glyphInfos[i].cluster;
			} else {
				index.* = @min(textIndexGuess[i - 1] + 1, @as(u32, @intCast(parser.parsedText.items.len - 1)));
				for (glyphInfos[i..]) |glyphInfo| {
					if (glyphInfo.cluster != glyphInfos[i].cluster) {
						index.* = @min(index.*, glyphInfo.cluster - 1);
						break;
					}
				}
			}
		}

		// Merge it all together:
		self.glyphs = allocator.alloc(GlyphData, glyphInfos.len);
		for (self.glyphs, 0..) |*glyph, i| {
			glyph.x_advance = @as(f32, @floatFromInt(glyphPositions[i].x_advance))/TextRendering.fontUnitsPerPixel;
			glyph.y_advance = @as(f32, @floatFromInt(glyphPositions[i].y_advance))/TextRendering.fontUnitsPerPixel;
			glyph.x_offset = @as(f32, @floatFromInt(glyphPositions[i].x_offset))/TextRendering.fontUnitsPerPixel;
			glyph.y_offset = @as(f32, @floatFromInt(glyphPositions[i].y_offset))/TextRendering.fontUnitsPerPixel;
			glyph.character = @intCast(parser.parsedText.items[textIndexGuess[i]]);
			glyph.index = glyphInfos[i].codepoint;
			glyph.cluster = glyphInfos[i].cluster;
			glyph.fontEffect = parser.fontEffects.items[textIndexGuess[i]];
			glyph.characterIndex = parser.characterIndex.items[textIndexGuess[i]];
		}

		// Find the lines:
		self.initLines(true);
		self.initLines(false);
		self.lineBreaks.append(.{.index = 0, .width = 0});
		self.lineBreaks.append(.{.index = @intCast(self.glyphs.len), .width = 0});
		return self;
	}

	pub fn deinit(self: TextBuffer) void {
		self.lines.allocator.free(self.glyphs);
		self.lines.deinit();
		self.lineBreaks.deinit();
	}

	fn getLineOffset(self: TextBuffer, line: usize) f32 {
		const factor: f32 = switch (self.alignment) {
			.left => 0,
			.center => 0.5,
			.right => 1,
		};
		const diff = self.width - self.lineBreaks.items[line + 1].width;
		return diff*factor;
	}

	pub fn mousePosToIndex(self: TextBuffer, mousePos: Vec2f, bufferLen: usize) u32 {
		var line: usize = @trunc(@max(0, mousePos[1]/16.0));
		line = @min(line, self.lineBreaks.items.len - 2);
		var x: f32 = self.getLineOffset(line);
		const start = self.lineBreaks.items[line].index;
		const end = self.lineBreaks.items[line + 1].index;
		for (self.glyphs[start..end]) |glyph| {
			if (mousePos[0] < x + glyph.x_advance/2) {
				return @intCast(glyph.characterIndex);
			}

			x += glyph.x_advance;
		}
		return @intCast(if (end < self.glyphs.len) self.glyphs[end - 1].characterIndex else bufferLen);
	}

	pub fn indexToCursorPos(self: TextBuffer, index: u32) Vec2f {
		var x: f32 = 0;
		var y: f32 = 0;
		var i: usize = 0;
		while (true) {
			x = self.getLineOffset(i);
			for (self.glyphs[self.lineBreaks.items[i].index..self.lineBreaks.items[i + 1].index]) |glyph| {
				if (glyph.characterIndex == index) {
					return .{x, y};
				}

				x += glyph.x_advance;
				y -= glyph.y_advance;
			}
			i += 1;
			if (i >= self.lineBreaks.items.len - 1) {
				return .{x, y};
			}
			y += 16;
		}
	}

	/// Returns the calculated dimensions of the text block.
	pub fn calculateLineBreaks(self: *TextBuffer, fontSize: f32, maxLineWidth: f32) Vec2f {
		self.lineBreaks.clearRetainingCapacity();
		const spaceCharacterWidth = 8;
		self.lineBreaks.append(.{.index = 0, .width = 0});
		const scaledMaxWidth = maxLineWidth/fontSize*16.0;
		var lineWidth: f32 = 0;
		var lastSpaceWidth: f32 = 0;
		var lastSpaceIndex: u32 = 0;
		for (self.glyphs, 0..) |glyph, i| {
			lineWidth += glyph.x_advance;
			if (glyph.character == ' ') {
				lastSpaceWidth = lineWidth;
				lastSpaceIndex = @intCast(i + 1);
			}
			if (glyph.character == '\n') {
				self.lineBreaks.append(.{.index = @intCast(i + 1), .width = lineWidth - spaceCharacterWidth});
				lineWidth = 0;
				lastSpaceIndex = 0;
				lastSpaceWidth = 0;
			}
			if (lineWidth > scaledMaxWidth) {
				if (lastSpaceIndex != 0) {
					lineWidth -= lastSpaceWidth;
					self.lineBreaks.append(.{.index = lastSpaceIndex, .width = lastSpaceWidth - spaceCharacterWidth});
					lastSpaceIndex = 0;
					lastSpaceWidth = 0;
				} else {
					self.lineBreaks.append(.{.index = @intCast(i), .width = lineWidth - glyph.x_advance});
					lineWidth = glyph.x_advance;
					lastSpaceIndex = 0;
					lastSpaceWidth = 0;
				}
			}
		}
		self.width = maxLineWidth;
		self.lineBreaks.append(.{.index = @intCast(self.glyphs.len), .width = lineWidth});
		return Vec2f{maxLineWidth*fontSize/16.0, @as(f32, @floatFromInt(self.lineBreaks.items.len - 1))*fontSize};
	}

	pub fn drawSelection(self: TextBuffer, pos: Vec2f, selectionStart: u32, selectionEnd: u32) void {
		std.debug.assert(selectionStart <= selectionEnd);
		var x: f32 = self.getLineOffset(0);
		var y: f32 = 0;
		var i: usize = 0;
		var j: usize = 0;
		// Find the start row:
		outer: while (i < self.lineBreaks.items.len - 1) : (i += 1) {
			x = self.getLineOffset(i);
			while (j < self.lineBreaks.items[i + 1].index) : (j += 1) {
				const glyph = self.glyphs[j];
				if (glyph.characterIndex >= selectionStart) break :outer;
				x += glyph.x_advance;
				y -= glyph.y_advance;
			}
			y += 16;
		}
		while (i < self.lineBreaks.items.len - 1) {
			const startX = x;
			while (j < self.lineBreaks.items[i + 1].index and j < selectionEnd) : (j += 1) {
				const glyph = self.glyphs[j];
				if (glyph.characterIndex >= selectionEnd) break;
				x += glyph.x_advance;
				y -= glyph.y_advance;
			}
			draw.rect(pos + Vec2f{startX, y}, .{x - startX, 16});
			i += 1;
			if (i >= self.lineBreaks.items.len - 1) break;
			x = self.getLineOffset(i);
			y += 16;
		}
	}

	pub fn render(self: TextBuffer, _x: f32, _y: f32, _fontSize: f32) void {
		self.renderShadow(_x, _y, _fontSize);
		self.renderTextWithoutShadow(_x, _y, _fontSize);
	}

	pub fn renderTextWithoutShadow(self: TextBuffer, _x: f32, _y: f32, _fontSize: f32) void {
		const oldTranslation = draw.setTranslation(.{_x, _y});
		defer draw.restoreTranslation(oldTranslation);
		const oldScale = draw.setScale(_fontSize/16.0);
		defer draw.restoreScale(oldScale);
		var x: f32 = 0;
		var y: f32 = 0;
		TextRendering.pipeline.bind(draw.getScissor());
		var viewport: [4]c_int = undefined;
		c.glGetIntegerv(c.GL_VIEWPORT, &viewport);
		c.glUniform2f(TextRendering.uniforms.scene, @floatFromInt(viewport[2]), @floatFromInt(viewport[3]));
		c.glUniform1f(TextRendering.uniforms.ratio, draw.scale);
		c.glUniform1f(TextRendering.uniforms.alpha, @as(f32, @floatFromInt(draw.color >> 24))/255.0);
		c.glActiveTexture(c.GL_TEXTURE0);
		c.glBindTexture(c.GL_TEXTURE_2D, TextRendering.glyphTexture[0]);
		draw.rectVao.bind();
		const lineWraps: []f32 = main.stackAllocator.alloc(f32, self.lineBreaks.items.len - 1);
		defer main.stackAllocator.free(lineWraps);
		var i: usize = 0;
		while (i < self.lineBreaks.items.len - 1) : (i += 1) {
			x = self.getLineOffset(i);
			for (self.glyphs[self.lineBreaks.items[i].index..self.lineBreaks.items[i + 1].index]) |glyph| {
				if (glyph.character != '\n') {
					const ftGlyph = TextRendering.getGlyph(glyph.index) catch continue;
					TextRendering.drawGlyph(ftGlyph, x + glyph.x_offset, y - glyph.y_offset, @bitCast(glyph.fontEffect));
				}
				x += glyph.x_advance;
				y -= glyph.y_advance;
			}
			lineWraps[i] = x - self.getLineOffset(i);
			x = 0;
			y += 16;
		}

		for (self.lines.items) |_line| {
			var line: Line = _line;
			y = 0;
			y += if (line.isUnderline) 15 else 8;
			const oldColor = draw.color;
			draw.setColor(line.color | (@as(u32, 0xff000000) & draw.color));
			defer draw.setColor(oldColor);
			for (lineWraps, 0..) |lineWrap, j| {
				const lineStart = @max(0, line.start);
				const lineEnd = @min(lineWrap, line.end);
				if (lineStart < lineEnd) {
					const start = Vec2f{lineStart + self.getLineOffset(j), y};
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
		const g: f32 = @floatFromInt(color >> 8 & 255);
		const b: f32 = @floatFromInt(color & 255);
		const perceivedBrightness = @sqrt(0.299*r*r + 0.587*g*g + 0.114*b*b);
		if (perceivedBrightness < 64) {
			return 0xffffff; // Make shadows white for better readability.
		} else {
			return 0;
		}
	}

	fn renderShadow(self: TextBuffer, _x: f32, _y: f32, _fontSize: f32) void { // Basically a copy of render with some color and position changes.
		const oldTranslation = draw.setTranslation(.{_x + _fontSize/16.0, _y + _fontSize/16.0});
		defer draw.restoreTranslation(oldTranslation);
		const oldScale = draw.setScale(_fontSize/16.0);
		defer draw.restoreScale(oldScale);
		var x: f32 = 0;
		var y: f32 = 0;
		TextRendering.pipeline.bind(draw.getScissor());
		var viewport: [4]c_int = undefined;
		c.glGetIntegerv(c.GL_VIEWPORT, &viewport);
		c.glUniform2f(TextRendering.uniforms.scene, @floatFromInt(viewport[2]), @floatFromInt(viewport[3]));
		c.glUniform1f(TextRendering.uniforms.ratio, draw.scale);
		c.glUniform1f(TextRendering.uniforms.alpha, @as(f32, @floatFromInt(draw.color >> 24))/255.0);
		c.glActiveTexture(c.GL_TEXTURE0);
		c.glBindTexture(c.GL_TEXTURE_2D, TextRendering.glyphTexture[0]);
		draw.rectVao.bind();
		const lineWraps: []f32 = main.stackAllocator.alloc(f32, self.lineBreaks.items.len - 1);
		defer main.stackAllocator.free(lineWraps);
		var i: usize = 0;
		while (i < self.lineBreaks.items.len - 1) : (i += 1) {
			x = self.getLineOffset(i);
			for (self.glyphs[self.lineBreaks.items[i].index..self.lineBreaks.items[i + 1].index]) |glyph| {
				if (glyph.character != '\n') {
					const ftGlyph = TextRendering.getGlyph(glyph.index) catch continue;
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

		for (self.lines.items) |_line| {
			var line: Line = _line;
			y = 0;
			y += if (line.isUnderline) 15 else 8;
			const oldColor = draw.color;
			draw.setColor(shadowColor(line.color) | (@as(u32, 0xff000000) & draw.color));
			defer draw.setColor(oldColor);
			for (lineWraps, 0..) |lineWrap, j| {
				const lineStart = @max(0, line.start);
				const lineEnd = @min(lineWrap, line.end);
				if (lineStart < lineEnd) {
					const start = Vec2f{lineStart + self.getLineOffset(j), y};
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

const TextRendering = struct { // MARK: TextRendering
	const Glyph = struct {
		textureX: i32,
		size: Vec2i,
		bearing: Vec2i,
		advance: f32,
	};
	var pipeline: Pipeline = undefined;
	var uniforms: struct {
		textureBounds: c_int,
		textureRect: c_int,
		scene: c_int,
		offset: c_int,
		ratio: c_int,
		fontEffects: c_int,
		fontSize: c_int,
		alpha: c_int,
	} = undefined;

	var freetypeLib: c.FT_Library = undefined;
	var freetypeFace: c.FT_Face = undefined;
	var harfbuzzFace: ?*c.hb_face_t = undefined;
	var harfbuzzFont: ?*c.hb_font_t = undefined;
	var glyphMapping: main.List(u31) = undefined;
	var glyphData: main.List(Glyph) = undefined;
	var glyphTexture: [2]c_uint = undefined;
	var textureWidth: i32 = 1024;
	const textureHeight: i32 = 16;
	var textureOffset: i32 = 0;
	var fontUnitsPerPixel: f32 = undefined;

	fn ftError(errorCode: c.FT_Error) !void {
		if (errorCode == 0) return;
		const errorString = c.FT_Error_String(errorCode);
		std.log.err("Got freetype error {s}", .{errorString});
		return error.freetype;
	}

	fn init() !void {
		pipeline = Pipeline.init(
			"assets/cubyz/shaders/graphics/Text.vert",
			"assets/cubyz/shaders/graphics/Text.frag",
			"",
			&uniforms,
			draw.SimpleVertex2D,
			&.{},
			.{.cullMode = .none},
			.{.depthTest = false, .depthWrite = false},
			.{.attachments = &.{.alphaBlending}},
		);
		pipeline.bind(null);
		errdefer pipeline.deinit();
		c.glUniform1f(uniforms.alpha, 1.0);
		c.glUniform2f(uniforms.fontSize, @floatFromInt(textureWidth), @floatFromInt(textureHeight));
		try ftError(c.FT_Init_FreeType(&freetypeLib));
		try ftError(c.FT_New_Face(freetypeLib, "assets/cubyz/fonts/unscii-16-full.ttf", 0, &freetypeFace));
		try ftError(c.FT_Set_Pixel_Sizes(freetypeFace, 0, textureHeight));
		harfbuzzFace = c.hb_ft_face_create_referenced(freetypeFace);
		harfbuzzFont = c.hb_font_create(harfbuzzFace);
		fontUnitsPerPixel = @as(f32, @floatFromInt(freetypeFace.*.units_per_EM))/@as(f32, @floatFromInt(textureHeight));

		glyphMapping = .init(main.globalAllocator);
		glyphData = .init(main.globalAllocator);
		glyphData.append(undefined); // 0 is a reserved value.
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
		pipeline.deinit();
		ftError(c.FT_Done_FreeType(freetypeLib)) catch {};
		glyphMapping.deinit();
		glyphData.deinit();
		c.glDeleteTextures(2, &glyphTexture);
		c.hb_font_destroy(harfbuzzFont);
	}

	fn resizeTexture(newWidth: i32) void {
		textureWidth = newWidth;
		const swap = glyphTexture[1];
		glyphTexture[1] = glyphTexture[0];
		glyphTexture[0] = swap;
		c.glActiveTexture(c.GL_TEXTURE0);
		c.glBindTexture(c.GL_TEXTURE_2D, glyphTexture[0]);
		c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_R8, newWidth, textureHeight, 0, c.GL_RED, c.GL_UNSIGNED_BYTE, null);
		c.glCopyImageSubData(glyphTexture[1], c.GL_TEXTURE_2D, 0, 0, 0, 0, glyphTexture[0], c.GL_TEXTURE_2D, 0, 0, 0, 0, textureOffset, textureHeight, 1);
		pipeline.bind(draw.getScissor());
		c.glUniform2f(uniforms.fontSize, @floatFromInt(textureWidth), @floatFromInt(textureHeight));
	}

	fn uploadData(bitmap: c.FT_Bitmap) void {
		const width: i32 = @bitCast(bitmap.width);
		const height: i32 = @bitCast(bitmap.rows);
		const buffer = bitmap.buffer orelse return;
		if (textureOffset + width > textureWidth) {
			resizeTexture(textureWidth*2);
		}
		c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
		c.glTexSubImage2D(c.GL_TEXTURE_2D, 0, textureOffset, 0, width, height, c.GL_RED, c.GL_UNSIGNED_BYTE, buffer);
		textureOffset += width;
	}

	fn getGlyph(index: u32) !Glyph {
		if (index >= glyphMapping.items.len) {
			glyphMapping.appendNTimes(0, index - glyphMapping.items.len + 1);
		}
		if (glyphMapping.items[index] == 0) { // glyph was not initialized yet.
			try ftError(c.FT_Load_Glyph(freetypeFace, index, c.FT_LOAD_RENDER));
			const glyph = freetypeFace.*.glyph;
			const bitmap = glyph.*.bitmap;
			const width = bitmap.width;
			const height = bitmap.rows;
			glyphMapping.items[index] = @intCast(glyphData.items.len);
			glyphData.addOne().* = Glyph{
				.textureX = textureOffset,
				.size = Vec2i{@intCast(width), @intCast(height)},
				.bearing = Vec2i{glyph.*.bitmap_left, 16 - glyph.*.bitmap_top},
				.advance = @as(f32, @floatFromInt(glyph.*.advance.x))/@as(f32, 1 << 6),
			};
			uploadData(bitmap);
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
		c.glUniform4f(uniforms.textureBounds, @floatFromInt(glyph.textureX), 0, @floatFromInt(glyph.size[0]), @floatFromInt(glyph.size[1]));
		if (fontEffects & 0x1000000 != 0) { // bold
			c.glUniform2f(uniforms.offset, @as(f32, @floatFromInt(glyph.bearing[0]))*draw.scale + x - 1, @as(f32, @floatFromInt(glyph.bearing[1]))*draw.scale + y - 1);
			c.glUniform4f(uniforms.textureRect, @floatFromInt(glyph.textureX - 1), -1, @floatFromInt(glyph.size[0] + 2), @floatFromInt(glyph.size[1] + 2));
		} else {
			c.glUniform2f(uniforms.offset, @as(f32, @floatFromInt(glyph.bearing[0]))*draw.scale + x, @as(f32, @floatFromInt(glyph.bearing[1]))*draw.scale + y);
			c.glUniform4f(uniforms.textureRect, @floatFromInt(glyph.textureX), 0, @floatFromInt(glyph.size[0]), @floatFromInt(glyph.size[1]));
		}
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}

	fn renderText(text: []const u8, x: f32, y: f32, fontSize: f32, initialFontEffect: TextBuffer.FontEffect, alignment: TextBuffer.Alignment) void {
		const buf = TextBuffer.init(main.stackAllocator, text, initialFontEffect, false, alignment);
		defer buf.deinit();

		buf.render(x, y, fontSize);
	}
};

pub fn init() void { // MARK: init()
	draw.initCircle();
	draw.initImage();
	draw.initLine();
	draw.initRect();
	draw.initRectBorder();
	TextRendering.init() catch |err| {
		std.log.err("Error while initializing TextRendering: {s}", .{@errorName(err)});
	};
	block_texture.init();
	pipelines.init();
	RenderPass.initRenderPasses() catch @panic("Failed to create render passes");
}

pub fn deinit() void {
	RenderPass.deinitRenderPasses();
	draw.deinitCircle();
	draw.deinitImage();
	draw.deinitLine();
	draw.deinitRect();
	draw.deinitRectBorder();
	TextRendering.deinit();
	block_texture.deinit();
	pipelines.deinit();
}

pub const RenderPass = struct { // MARK: RenderPass
	renderPass: c.VkRenderPass,

	pub var renderToWindow: RenderPass = undefined;

	fn initRenderPasses() !void {
		if (main.settings.launchConfig.vulkanTestingMode) {
			renderToWindow = try RenderPass.init();
		}
	}

	fn deinitRenderPasses() void {
		if (main.settings.launchConfig.vulkanTestingMode) {
			renderToWindow.deinit();
		}
	}

	pub fn init() !RenderPass {
		const colorAttachment = c.VkAttachmentDescription{
			.format = vulkan.SwapChain.imageFormat, // TODO: This needs to be configurable to be able to render to f16 framebuffer
			.samples = c.VK_SAMPLE_COUNT_1_BIT,
			.loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
			.storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
			.stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
			.stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
			.initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
			.finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
		};
		const colorAttachmentRef = c.VkAttachmentReference{
			.attachment = 0,
			.layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
		};
		const subpass = c.VkSubpassDescription{
			.pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
			.colorAttachmentCount = 1,
			.pColorAttachments = &colorAttachmentRef,
		};
		const dependency = c.VkSubpassDependency{
			.srcSubpass = c.VK_SUBPASS_EXTERNAL,
			.dstSubpass = 0,
			.srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
			.srcAccessMask = 0,
			.dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
			.dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
		};
		const renderPassInfo = c.VkRenderPassCreateInfo{
			.sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
			.attachmentCount = 1,
			.pAttachments = &colorAttachment,
			.subpassCount = 1,
			.pSubpasses = &subpass,
			.dependencyCount = 1,
			.pDependencies = &dependency,
		};

		var self: RenderPass = undefined;
		try vulkan.checkResultErr(c.vkCreateRenderPass(vulkan.device, &renderPassInfo, null, &self.renderPass));
		return self;
	}

	pub fn deinit(self: RenderPass) void {
		c.vkDestroyRenderPass(vulkan.device, self.renderPass, null);
	}
};

pub const VertexArray = struct { // MARK: VertexArray
	vao: c_uint,
	vbo: c_uint,
	ibo: ?c_uint,

	pub const EmptyVertex = struct {
		pub const attributeDescriptions: []const c.VkVertexInputAttributeDescription = &.{};
	};

	pub fn init(T: type, data: []const T, indices_: ?[]const u32) VertexArray {
		var result: VertexArray = undefined;
		c.glGenVertexArrays(1, &result.vao);
		c.glBindVertexArray(result.vao);
		c.glGenBuffers(1, &result.vbo);
		c.glBindBuffer(c.GL_ARRAY_BUFFER, result.vbo);
		c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(data.len*@sizeOf(T)), data.ptr, c.GL_STATIC_DRAW);
		if (indices_) |indices| {
			result.ibo = 0;
			c.glGenBuffers(1, &result.ibo.?);
			c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, result.ibo.?);
			c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @intCast(indices.len*@sizeOf(u32)), indices.ptr, c.GL_STATIC_DRAW);
		} else {
			result.ibo = null;
		}

		const attributeDescriptions: []const c.VkVertexInputAttributeDescription = T.attributeDescriptions;
		inline for (attributeDescriptions) |desc| {
			std.debug.assert(desc.binding == 0);
			c.glEnableVertexAttribArray(desc.location);
			const glType = comptime switch (desc.format) {
				c.VK_FORMAT_R32_SFLOAT => c.GL_FLOAT,
				c.VK_FORMAT_R32G32_SFLOAT => c.GL_FLOAT,
				c.VK_FORMAT_R32G32B32_SFLOAT => c.GL_FLOAT,
				c.VK_FORMAT_R32G32B32A32_SFLOAT => c.GL_FLOAT,
				else => @compileError("Unrecognized format"),
			};
			const size = comptime switch (desc.format) {
				c.VK_FORMAT_R32_SFLOAT => 1,
				c.VK_FORMAT_R32G32_SFLOAT => 2,
				c.VK_FORMAT_R32G32B32_SFLOAT => 3,
				c.VK_FORMAT_R32G32B32A32_SFLOAT => 4,
				else => @compileError("Unrecognized format"),
			};
			c.glVertexAttribPointer(desc.location, size, glType, c.GL_FALSE, @sizeOf(T), @ptrFromInt(desc.offset));
		}

		c.glBindVertexArray(0);
		return result;
	}

	pub fn deinit(self: VertexArray) void {
		c.glDeleteVertexArrays(1, &self.vao);
		c.glDeleteBuffers(1, &self.vbo);
		if (self.ibo != null) {
			c.glDeleteBuffers(1, &self.ibo.?);
		}
	}

	pub fn bind(self: VertexArray) void {
		c.glBindVertexArray(self.vao);
	}
};

pub const SSBO = struct { // MARK: SSBO
	bufferID: c_uint,
	pub fn init() SSBO {
		var self = SSBO{.bufferID = undefined};
		c.glGenBuffers(1, &self.bufferID);
		return self;
	}

	pub fn initStatic(comptime T: type, data: []const T) SSBO {
		var self = SSBO{.bufferID = undefined};
		c.glGenBuffers(1, &self.bufferID);
		c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, self.bufferID);
		c.glBufferStorage(c.GL_SHADER_STORAGE_BUFFER, @intCast(data.len*@sizeOf(T)), data.ptr, 0);
		return self;
	}

	pub fn initStaticSize(comptime T: type, len: usize) SSBO {
		var self = SSBO{.bufferID = undefined};
		c.glGenBuffers(1, &self.bufferID);
		c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, self.bufferID);
		c.glBufferStorage(c.GL_SHADER_STORAGE_BUFFER, @intCast(len*@sizeOf(T)), null, 0);
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

	pub fn bufferSubData(self: SSBO, comptime T: type, data: []const T, length: usize) void {
		c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, self.bufferID);
		c.glBufferSubData(c.GL_SHADER_STORAGE_BUFFER, 0, @intCast(length*@sizeOf(T)), data.ptr);
		c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, 0);
	}

	pub fn createDynamicBuffer(self: SSBO, comptime T: type, size: usize) void {
		c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, self.bufferID);
		c.glBufferData(c.GL_SHADER_STORAGE_BUFFER, @intCast(size*@sizeOf(T)), null, c.GL_DYNAMIC_DRAW);
		c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, 0);
	}
};

pub const SubAllocation = struct {
	start: u31,
	len: u31,
};

/// A big SSBO that is able to allocate/free smaller regions.
pub fn LargeBuffer(comptime Entry: type) type { // MARK: LargerBuffer
	return struct {
		ssbo: SSBO,
		freeBlocks: main.List(SubAllocation),
		fences: [3]c.GLsync,
		fencedFreeLists: [3]main.List(SubAllocation),
		activeFence: u8,
		capacity: u31,
		used: u31,
		binding: c_uint,

		const Self = @This();

		fn createBuffer(self: *Self, size: u31) void {
			self.ssbo = .init();
			c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, self.ssbo.bufferID);
			const flags = c.GL_MAP_WRITE_BIT | c.GL_DYNAMIC_STORAGE_BIT;
			const bytes = @as(c.GLsizeiptr, size)*@sizeOf(Entry);
			c.glBufferStorage(c.GL_SHADER_STORAGE_BUFFER, bytes, null, flags);
			self.ssbo.bind(self.binding);
			self.capacity = size;
		}

		pub fn init(self: *Self, allocator: NeverFailingAllocator, size: u31, binding: c_uint) void {
			self.used = 0;
			self.binding = binding;
			self.createBuffer(size);
			self.activeFence = 0;
			for (&self.fences) |*fence| {
				fence.* = c.glFenceSync(c.GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
			}
			for (&self.fencedFreeLists) |*list| {
				list.* = .init(allocator);
			}

			self.freeBlocks = .init(allocator);
			self.freeBlocks.append(.{.start = 0, .len = size});
		}

		pub fn deinit(self: *Self) void {
			for (self.fences) |fence| {
				c.glDeleteSync(fence);
			}
			for (self.fencedFreeLists) |list| {
				list.deinit();
			}
			self.ssbo.deinit();
			self.freeBlocks.deinit();
		}

		pub fn beginRender(self: *Self) void {
			self.activeFence += 1;
			if (self.activeFence == self.fences.len) self.activeFence = 0;
			const endTime = main.timestamp().addDuration(.fromMilliseconds(5));
			while (self.fencedFreeLists[self.activeFence].popOrNull()) |allocation| {
				self.finalFree(allocation);
				if (main.timestamp().durationTo(endTime).nanoseconds < 0) break; // TODO: Remove after #1434
			}
			_ = c.glClientWaitSync(self.fences[self.activeFence], 0, c.GL_TIMEOUT_IGNORED); // Make sure the render calls that accessed these parts of the buffer have finished.
		}

		pub fn endRender(self: *Self) void {
			c.glDeleteSync(self.fences[self.activeFence]);
			self.fences[self.activeFence] = c.glFenceSync(c.GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
		}

		pub fn rawAlloc(self: *Self, size: u31) SubAllocation {
			var smallestBlock: ?*SubAllocation = null;
			for (self.freeBlocks.items, 0..) |*block, i| {
				if (size == block.len) {
					self.used += size;
					return self.freeBlocks.swapRemove(i);
				}
				if (size < block.len and if (smallestBlock) |_smallestBlock| block.len < _smallestBlock.len else true) {
					smallestBlock = block;
				}
			}
			if (smallestBlock) |block| {
				const result = SubAllocation{.start = block.start, .len = size};
				block.start += size;
				block.len -= size;
				self.used += size;
				return result;
			} else {
				std.log.info("Resizing internal mesh buffer from {} MiB to {} MiB", .{@as(usize, self.capacity)*@sizeOf(Entry) >> 20, (@as(usize, self.capacity)*@sizeOf(Entry) >> 20)*2});
				if (@as(usize, self.capacity)*@sizeOf(Entry)*2 > 1 << 31) @panic("OpenGL 2 GiB buffer size limit reached. Please lower your render distance.");
				const oldBuffer = self.ssbo;
				defer oldBuffer.deinit();
				const oldCapacity = self.capacity;
				self.createBuffer(self.capacity*|2); // TODO: Is there a way to free the old buffer before creating the new one?
				self.used += self.capacity - oldCapacity;
				self.finalFree(.{.start = oldCapacity, .len = self.capacity - oldCapacity});

				c.glBindBuffer(c.GL_COPY_READ_BUFFER, oldBuffer.bufferID);
				c.glBindBuffer(c.GL_COPY_WRITE_BUFFER, self.ssbo.bufferID);
				c.glCopyBufferSubData(c.GL_COPY_READ_BUFFER, c.GL_COPY_WRITE_BUFFER, 0, 0, @as(c.GLsizeiptr, oldCapacity)*@sizeOf(Entry));
				return rawAlloc(self, size);
			}
		}

		fn finalFree(self: *Self, _allocation: SubAllocation) void {
			if (_allocation.len == 0) return;
			self.used -= _allocation.len;
			var allocation = _allocation;
			for (self.freeBlocks.items, 0..) |*block, i| {
				if (allocation.start + allocation.len == block.start) {
					allocation.len += block.len;
					_ = self.freeBlocks.swapRemove(i);
					break;
				}
			}
			for (self.freeBlocks.items) |*block| {
				if (allocation.start == block.start + block.len) {
					block.len += allocation.len;
					return;
				}
			}
			self.freeBlocks.append(allocation);
		}

		pub fn free(self: *Self, allocation: SubAllocation) void {
			if (allocation.len == 0) return;
			self.fencedFreeLists[self.activeFence].append(allocation);
		}

		/// Must unmap after use!
		pub fn allocateAndMapRange(self: *Self, len: usize, allocation: *SubAllocation) []Entry {
			self.free(allocation.*);
			if (len == 0) {
				allocation.len = 0;
				return &.{};
			}
			allocation.* = self.rawAlloc(@intCast(len));
			c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, self.ssbo.bufferID);
			const ptr: [*]Entry = @ptrCast(@alignCast(c.glMapBufferRange(
				c.GL_SHADER_STORAGE_BUFFER,
				@as(c.GLintptr, allocation.start)*@sizeOf(Entry),
				@as(c.GLsizeiptr, allocation.len)*@sizeOf(Entry),
				c.GL_MAP_WRITE_BIT | c.GL_MAP_INVALIDATE_RANGE_BIT,
			)));
			return ptr[0..len];
		}

		pub fn unmapRange(self: *Self, range: []Entry) void {
			if (range.len == 0) return;
			c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, self.ssbo.bufferID);
			std.debug.assert(c.glUnmapBuffer(c.GL_SHADER_STORAGE_BUFFER) == c.GL_TRUE);
		}

		pub fn uploadData(self: *Self, data: []const Entry, allocation: *SubAllocation) void {
			self.free(allocation.*);
			if (data.len == 0) {
				allocation.len = 0;
				return;
			}
			allocation.* = self.rawAlloc(@intCast(data.len));
			c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, self.ssbo.bufferID);
			const ptr: [*]Entry = @ptrCast(@alignCast(c.glMapBufferRange(
				c.GL_SHADER_STORAGE_BUFFER,
				@as(c.GLintptr, allocation.start)*@sizeOf(Entry),
				@as(c.GLsizeiptr, allocation.len)*@sizeOf(Entry),
				c.GL_MAP_WRITE_BIT | c.GL_MAP_INVALIDATE_RANGE_BIT,
			)));
			@memcpy(ptr, data);
			std.debug.assert(c.glUnmapBuffer(c.GL_SHADER_STORAGE_BUFFER) == c.GL_TRUE);
		}
	};
}

pub const FrameBuffer = struct { // MARK: FrameBuffer
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
		if (hasDepthTexture) {
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
		if (self.hasDepthTexture) {
			c.glDeleteRenderbuffers(1, &self.depthTexture);
		}
		c.glDeleteTextures(1, &self.texture);
	}

	pub fn updateSize(self: *FrameBuffer, _width: u31, _height: u31, internalFormat: c_int) void {
		const width = @max(_width, 1);
		const height = @max(_height, 1);
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.frameBuffer);
		if (self.hasDepthTexture) {
			c.glBindTexture(c.GL_TEXTURE_2D, self.depthTexture);
			c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_DEPTH_COMPONENT32F, width, height, 0, c.GL_DEPTH_COMPONENT, c.GL_FLOAT, null);
		}

		c.glBindTexture(c.GL_TEXTURE_2D, self.texture);
		c.glTexImage2D(c.GL_TEXTURE_2D, 0, internalFormat, width, height, 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, null);
	}

	pub fn clear(_: FrameBuffer, clearColor: Vec4f) void {
		c.glDepthFunc(c.GL_LESS);
		c.glDepthMask(c.GL_TRUE);
		c.glDisable(c.GL_SCISSOR_TEST);
		c.glClearColor(clearColor[0], clearColor[1], clearColor[2], clearColor[3]);
		c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);
	}

	pub fn validate(self: *const FrameBuffer) bool {
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.frameBuffer);
		defer c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
		if (c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER) != c.GL_FRAMEBUFFER_COMPLETE) {
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

pub const TextureArray = struct { // MARK: TextureArray
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

	fn lodColorInterpolation(colors: [4]Color, alphaCorrection: bool) Color {
		var r: [4]f32 = undefined;
		var g: [4]f32 = undefined;
		var b: [4]f32 = undefined;
		var a: [4]f32 = undefined;
		for (0..4) |i| {
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
		for (0..4) |i| {
			const w = if (alphaCorrection) a[i]*a[i] else 1;
			aSum += a[i]*a[i];
			rSum += w*r[i]*r[i];
			gSum += w*g[i]*g[i];
			bSum += w*b[i]*b[i];
		}
		aSum = @sqrt(aSum)/2;
		rSum = @sqrt(rSum)/2;
		gSum = @sqrt(gSum)/2;
		bSum = @sqrt(bSum)/2;
		if (alphaCorrection and aSum != 0) {
			rSum /= aSum;
			gSum /= aSum;
			bSum /= aSum;
		}
		return Color{.r = @trunc(rSum), .g = @trunc(gSum), .b = @trunc(bSum), .a = @trunc(aSum)};
	}

	/// (Re-)Generates the GPU buffer.
	pub fn generate(self: TextureArray, images: []Image, mipmapping: bool, alphaCorrectMipmapping: bool) void {
		var maxWidth: u31 = 1;
		var maxHeight: u31 = 1;
		for (images) |image| {
			maxWidth = @max(maxWidth, image.width);
			maxHeight = @max(maxHeight, image.height);
		}
		// Make sure the width and height use a power of 2:
		if (maxWidth - 1 & maxWidth != 0) {
			maxWidth = @as(u31, 2) << std.math.log2_int(u31, maxWidth);
		}
		if (maxHeight - 1 & maxHeight != 0) {
			maxHeight = @as(u31, 2) << std.math.log2_int(u31, maxHeight);
		}

		std.log.debug("Creating Texture Array of size {}×{} with {} layers.", .{maxWidth, maxHeight, images.len});

		self.bind();

		const maxLOD = if (mipmapping) 1 + std.math.log2_int(u31, @max(maxWidth, maxHeight)) else 1;
		for (0..maxLOD) |i| {
			c.glTexImage3D(c.GL_TEXTURE_2D_ARRAY, @intCast(i), c.GL_RGBA8, @max(1, maxWidth >> @intCast(i)), @max(1, maxHeight >> @intCast(i)), @intCast(images.len), 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, null);
		}
		const arena = main.stackAllocator.createArena();
		defer main.stackAllocator.destroyArena(arena);
		const lodBuffer: [][]Color = arena.alloc([]Color, maxLOD);
		for (lodBuffer, 0..) |*buffer, i| {
			buffer.* = arena.alloc(Color, @max(1, maxWidth >> @intCast(i))*@max(1, maxHeight >> @intCast(i)));
		}

		for (images, 0..) |image, i| {
			// Fill the buffer using nearest sampling. Probably not the best solutions for all textures, but that's what happens when someone doesn't use power of 2 textures...
			for (0..maxWidth) |x| {
				for (0..maxHeight) |y| {
					const index = x + y*maxWidth;
					const imageIndex = (x*image.width)/maxWidth + image.width*((y*image.height)/maxHeight);
					lodBuffer[0][index] = image.imageData[imageIndex];
				}
			}

			// Calculate the mipmap levels:
			for (1..lodBuffer.len) |_lod| {
				const lod: u5 = @intCast(_lod);
				const curWidth = @max(1, maxWidth >> lod);
				const curHeight = @max(1, maxHeight >> lod);
				const nextWidth = @max(1, maxWidth >> (lod - 1));
				const nextHeight = @max(1, maxHeight >> (lod - 1));
				for (0..curWidth) |x| {
					for (0..curHeight) |y| {
						const index = x + y*curWidth;
						const colors = [4]Color{
							lodBuffer[lod - 1][@min(2*x, nextWidth - 1) + @min(2*y, nextHeight - 1)*nextWidth],
							lodBuffer[lod - 1][@min(2*x, nextWidth - 1) + @min(2*y + 1, nextHeight - 1)*nextWidth],
							lodBuffer[lod - 1][@min(2*x + 1, nextWidth - 1) + @min(2*y, nextHeight - 1)*nextWidth],
							lodBuffer[lod - 1][@min(2*x + 1, nextWidth - 1) + @min(2*y + 1, nextHeight - 1)*nextWidth],
						};
						lodBuffer[lod][index] = lodColorInterpolation(colors, alphaCorrectMipmapping);
					}
				}
			}
			// Give the correct color to alpha 0 pixels, to avoid dark pixels:
			for (1..lodBuffer.len) |_lod| {
				const lod: u5 = @intCast(lodBuffer.len - 1 - _lod);
				const curWidth = @max(1, maxWidth >> lod);
				const curHeight = @max(1, maxHeight >> lod);
				for (0..curWidth) |x| {
					for (0..curHeight) |y| {
						const index = x + y*curWidth;
						const index2 = x/2 + y/2*curWidth/2;
						if (lodBuffer[lod][index].a == 0) {
							lodBuffer[lod][index].r = lodBuffer[lod + 1][index2].r;
							lodBuffer[lod][index].g = lodBuffer[lod + 1][index2].g;
							lodBuffer[lod][index].b = lodBuffer[lod + 1][index2].b;
						}
					}
				}
			}
			// Upload:
			for (0..lodBuffer.len) |_lod| {
				const lod: u5 = @intCast(lodBuffer.len - 1 - _lod);
				const curWidth = @max(1, maxWidth >> lod);
				const curHeight = @max(1, maxHeight >> lod);
				c.glTexSubImage3D(c.GL_TEXTURE_2D_ARRAY, lod, 0, 0, @intCast(i), curWidth, curHeight, 1, c.GL_RGBA, c.GL_UNSIGNED_BYTE, lodBuffer[lod].ptr);
			}
		}
		c.glTexParameteri(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_MAX_LOD, maxLOD);
		c.glTexParameteri(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST_MIPMAP_LINEAR);
		c.glTexParameteri(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
		c.glTexParameteri(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
		c.glTexParameteri(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
	}
};

pub const Texture = struct { // MARK: Texture
	textureID: c_uint,

	pub fn init() Texture {
		var self: Texture = undefined;
		c.glGenTextures(1, &self.textureID);
		return self;
	}

	pub fn initFromFile(path: []const u8) Texture {
		const self = Texture.init();
		const image = Image.readFromFile(main.stackAllocator, path) catch |err| blk: {
			std.log.err("Couldn't read image from {s}: {s}", .{path, @errorName(err)});
			break :blk Image.defaultImage;
		};
		defer image.deinit(main.stackAllocator);
		self.generate(image);
		return self;
	}

	pub fn initFromMipmapFiles(pathPrefix: []const u8, largestSize: u31, lodBias: f32) Texture {
		const self = Texture.init();
		self.bind();

		const maxLod = std.math.log2_int(u31, largestSize);

		var curSize: u31 = largestSize;
		while (curSize != 0) : (curSize /= 2) {
			c.glTexImage2D(c.GL_TEXTURE_2D, maxLod - std.math.log2_int(u31, curSize), c.GL_RGBA8, curSize, curSize, 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, null);
		}

		curSize = largestSize;
		while (curSize != 0) : (curSize /= 2) {
			const path = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}{}.png", .{pathPrefix, curSize}) catch unreachable;
			defer main.stackAllocator.free(path);
			const image = Image.readFromFile(main.stackAllocator, path) catch |err| blk: {
				std.log.err("Couldn't read image from {s}: {s}", .{path, @errorName(err)});
				break :blk Image.defaultImage;
			};
			defer image.deinit(main.stackAllocator);
			c.glTexSubImage2D(c.GL_TEXTURE_2D, maxLod - std.math.log2_int(u31, curSize), 0, 0, curSize, curSize, c.GL_RGBA, c.GL_UNSIGNED_BYTE, image.imageData.ptr);
		}

		c.glTexParameteri(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_MAX_LOD, maxLod);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST_MIPMAP_LINEAR);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
		c.glTexParameterf(c.GL_TEXTURE_2D, c.GL_TEXTURE_LOD_BIAS, lodBias);
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
	pub fn generate(self: Texture, image: Image) void {
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

	pub fn size(self: Texture) Vec2i {
		self.bind();
		var result: Vec2i = undefined;
		c.glGetTexLevelParameteriv(c.GL_TEXTURE_2D, 0, c.GL_TEXTURE_WIDTH, &result[0]);
		c.glGetTexLevelParameteriv(c.GL_TEXTURE_2D, 0, c.GL_TEXTURE_HEIGHT, &result[1]);
		return result;
	}
};

pub const CubeMapTexture = struct { // MARK: CubeMapTexture
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
		const normals = [_]Vec3f{
			.{1, 0, 0}, // +x
			.{-1, 0, 0}, // -x
			.{0, 1, 0}, // +y
			.{0, -1, 0}, // -y
			.{0, 0, 1}, // +z
			.{0, 0, -1}, // -z
		};
		return normals[face];
	}

	pub fn faceUp(face: usize) Vec3f {
		const ups = [_]Vec3f{
			.{0, -1, 0}, // +x
			.{0, -1, 0}, // -x
			.{0, 0, 1}, // +y
			.{0, 0, -1}, // -y
			.{0, -1, 0}, // +z
			.{0, -1, 0}, // -z
		};
		return ups[face];
	}

	pub fn faceRight(face: usize) Vec3f {
		comptime var rights: [6]Vec3f = undefined;
		inline for (0..6) |i| {
			rights[i] = comptime vec.cross(faceNormal(i), faceUp(i));
		}
		return rights[face];
	}

	pub fn bindToFramebuffer(self: CubeMapTexture, fb: FrameBuffer, face: c_uint) void {
		fb.bind();
		c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, @as(c_uint, c.GL_TEXTURE_CUBE_MAP_POSITIVE_X) + face, self.textureID, 0);
	}
};

pub const Color = extern struct { // MARK: Color
	r: u8,
	g: u8,
	b: u8,
	a: u8,

	pub fn toARBG(self: Color) u32 {
		return @as(u32, self.a) << 24 | @as(u32, self.r) << 16 | @as(u32, self.g) << 8 | @as(u32, self.b);
	}
};

pub const Image = struct { // MARK: Image
	var defaultImageData = [4]Color{
		Color{.r = 0, .g = 0, .b = 0, .a = 255},
		Color{.r = 255, .g = 0, .b = 255, .a = 255},
		Color{.r = 255, .g = 0, .b = 255, .a = 255},
		Color{.r = 0, .g = 0, .b = 0, .a = 255},
	};
	pub const defaultImage = Image{
		.width = 2,
		.height = 2,
		.imageData = &defaultImageData,
	};
	var emptyImageData = [1]Color{
		Color{.r = 0, .g = 0, .b = 0, .a = 0},
	};
	pub const emptyImage = Image{
		.width = 1,
		.height = 1,
		.imageData = &emptyImageData,
	};
	var whiteImageData = [1]Color{
		Color{.r = 255, .g = 255, .b = 255, .a = 255},
	};
	pub const whiteEmptyImage = Image{
		.width = 1,
		.height = 1,
		.imageData = &whiteImageData,
	};
	width: u31,
	height: u31,
	imageData: []Color,
	pub fn init(allocator: NeverFailingAllocator, width: u31, height: u31) Image {
		return Image{
			.width = width,
			.height = height,
			.imageData = allocator.alloc(Color, width*height),
		};
	}
	pub fn deinit(self: Image, allocator: NeverFailingAllocator) void {
		if (self.imageData.ptr == &defaultImageData or self.imageData.ptr == &emptyImageData or self.imageData.ptr == &whiteImageData) return;
		allocator.free(self.imageData);
	}
	pub fn readFromFile(allocator: NeverFailingAllocator, path: []const u8) !Image {
		var result: Image = undefined;
		var channel: c_int = undefined;
		const nullTerminatedPath = main.stackAllocator.dupeZ(u8, path); // TODO: Find a more zig-friendly image loading library.
		errdefer main.stackAllocator.free(nullTerminatedPath);
		c.stbi_set_flip_vertically_on_load(1);
		const data = c.stbi_load(nullTerminatedPath.ptr, @ptrCast(&result.width), @ptrCast(&result.height), &channel, 4) orelse {
			return error.FileNotFound;
		};
		main.stackAllocator.free(nullTerminatedPath);
		result.imageData = allocator.dupe(Color, @as([*]Color, @ptrCast(data))[0 .. result.width*result.height]);
		c.stbi_image_free(data);
		return result;
	}
	pub fn readUnflippedFromFile(allocator: NeverFailingAllocator, path: []const u8) !Image {
		var result: Image = undefined;
		var channel: c_int = undefined;
		const nullTerminatedPath = main.stackAllocator.dupeZ(u8, path); // TODO: Find a more zig-friendly image loading library.
		errdefer main.stackAllocator.free(nullTerminatedPath);
		const data = c.stbi_load(nullTerminatedPath.ptr, @ptrCast(&result.width), @ptrCast(&result.height), &channel, 4) orelse {
			return error.FileNotFound;
		};
		main.stackAllocator.free(nullTerminatedPath);
		result.imageData = allocator.dupe(Color, @as([*]Color, @ptrCast(data))[0 .. result.width*result.height]);
		c.stbi_image_free(data);
		return result;
	}
	pub fn exportToFile(self: Image, path: []const u8) !void {
		const nullTerminated = main.stackAllocator.dupeZ(u8, path);
		defer main.stackAllocator.free(nullTerminated);
		_ = c.stbi_write_png(nullTerminated.ptr, self.width, self.height, 4, self.imageData.ptr, self.width*4); // TODO: Handle the return type.
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

pub const Fog = struct { // MARK: Fog
	fogColor: Vec3f,
	skyColor: Vec3f,
	density: f32,
	fogLower: f32,
	fogHigher: f32,
};

const block_texture = struct { // MARK: block_texture
	var uniforms: struct {
		transparent: c_int,
	} = undefined;
	var pipeline: Pipeline = undefined;
	var depthTexture: Texture = undefined;
	const textureSize = 128;

	fn init() void {
		pipeline = Pipeline.init(
			"assets/cubyz/shaders/item_texture_post.vert",
			"assets/cubyz/shaders/item_texture_post.frag",
			"",
			&uniforms,
			VertexArray.EmptyVertex,
			&.{},
			.{.cullMode = .none},
			.{.depthTest = false, .depthWrite = false},
			.{.attachments = &.{.noBlending}},
		);
		depthTexture = .init();
		depthTexture.bind();
		var data: [128*128]f32 = undefined;

		const z: f32 = 134;
		const near = main.renderer.zNear;
		const far = main.renderer.zFar;
		const depth = ((far + near)/(near - far)*-z + 2*near*far/(near - far))/z*0.5 + 0.5;

		@memset(&data, depth);
		c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_R32F, textureSize, textureSize, 0, c.GL_RED, c.GL_FLOAT, &data);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
	}
	fn deinit() void {
		pipeline.deinit();
		depthTexture.deinit();
	}
};

pub fn generateBlockTexture(blockType: u16) Texture {
	const block = main.blocks.Block{.typ = blockType, .data = 0}; // TODO: Use natural standard data.
	const textureSize = block_texture.textureSize;
	c.glViewport(0, 0, textureSize, textureSize);

	var frameBuffer: FrameBuffer = undefined;

	frameBuffer.init(false, c.GL_NEAREST, c.GL_REPEAT);
	defer frameBuffer.deinit();
	frameBuffer.updateSize(textureSize, textureSize, c.GL_RGBA16F);
	frameBuffer.bind();
	if (block.transparent()) {
		frameBuffer.clear(.{0.683421, 0.6854237, 0.685426, 1});
	} else {
		frameBuffer.clear(.{0, 0, 0, 0});
	}

	const projMatrix = Mat4f.perspective(0.013, 1, 64, 256);
	const oldViewMatrix = main.game.camera.viewMatrix;
	main.game.camera.viewMatrix = Mat4f.identity().mul(Mat4f.rotationX(std.math.pi/4.0)).mul(Mat4f.rotationZ(1.0*std.math.pi/4.0));
	defer main.game.camera.viewMatrix = oldViewMatrix;
	const uniforms = if (block.transparent()) &main.renderer.chunk_meshing.transparentUniforms else &main.renderer.chunk_meshing.uniforms;

	var faceData: main.ListUnmanaged(main.renderer.chunk_meshing.FaceData) = .{};
	defer faceData.deinit(main.stackAllocator);
	const model = main.blocks.meshes.model(block).model();
	const pos: main.chunk.BlockPos = .fromCoords(1, 1, 1);
	if (block.hasBackFace()) {
		model.appendInternalQuadsToList(&faceData, main.stackAllocator, block, pos, true);
		for (main.chunk.Neighbor.iterable) |neighbor| {
			model.appendNeighborFacingQuadsToList(&faceData, main.stackAllocator, block, neighbor, pos, true);
		}
	}
	model.appendInternalQuadsToList(&faceData, main.stackAllocator, block, pos, false);
	for (main.chunk.Neighbor.iterable) |neighbor| {
		model.appendNeighborFacingQuadsToList(&faceData, main.stackAllocator, block, neighbor, pos.neighbor(neighbor)[0], false);
	}

	for (faceData.items) |*face| {
		face.position.lightIndex = 0;
	}
	var allocation: SubAllocation = .{.start = 0, .len = 0};
	main.renderer.chunk_meshing.faceBuffers[0].uploadData(faceData.items, &allocation);
	defer main.renderer.chunk_meshing.faceBuffers[0].free(allocation);
	var lightAllocation: SubAllocation = .{.start = 0, .len = 0};
	main.renderer.chunk_meshing.lightBuffers[0].uploadData(&.{0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff}, &lightAllocation);
	defer main.renderer.chunk_meshing.lightBuffers[0].free(lightAllocation);

	{
		const i = 4; // Easily switch between the 8 diagonal coordinates.
		var x: f64 = -65.5 + 1.5;
		var y: f64 = -65.5 + 1.5;
		var z: f64 = -92.631 + 1.5;
		if (i & 1 != 0) x = -x + 3;
		if (i & 2 != 0) y = -y + 3;
		if (i & 4 != 0) z = -z + 3;
		var chunkAllocation: SubAllocation = .{.start = 0, .len = 0};
		main.renderer.chunk_meshing.chunkBuffer.uploadData(&.{.{
			.position = .{0, 0, 0},
			.min = undefined,
			.max = undefined,
			.voxelSize = 1,
			.lightStart = lightAllocation.start,
			.vertexStartOpaque = undefined,
			.faceCountsByNormalOpaque = undefined,
			.vertexStartTransparent = undefined,
			.vertexCountTransparent = undefined,
			.visibilityState = 0,
			.oldVisibilityState = 0,
		}}, &chunkAllocation);
		defer main.renderer.chunk_meshing.chunkBuffer.free(chunkAllocation);
		if (block.transparent()) {
			c.glBlendEquation(c.GL_FUNC_ADD);
			c.glBlendFunc(c.GL_ONE, c.GL_SRC1_COLOR);
			main.renderer.chunk_meshing.bindTransparentShaderAndUniforms(projMatrix, .{1, 1, 1}, .{x, y, z});
		} else {
			main.renderer.chunk_meshing.bindShaderAndUniforms(projMatrix, .{1, 1, 1}, .{x, y, z});
		}
		c.glUniform1f(uniforms.contrast, 0.25);
		c.glActiveTexture(c.GL_TEXTURE0);
		main.blocks.meshes.blockTextureArray.bind();
		c.glActiveTexture(c.GL_TEXTURE1);
		main.blocks.meshes.emissionTextureArray.bind();
		c.glActiveTexture(c.GL_TEXTURE2);
		main.blocks.meshes.reflectivityAndAbsorptionTextureArray.bind();
		block_texture.depthTexture.bindTo(5);
		c.glDrawElementsInstancedBaseVertexBaseInstance(c.GL_TRIANGLES, @intCast(6*faceData.items.len), c.GL_UNSIGNED_INT, null, 1, allocation.start*4, chunkAllocation.start);
	}

	c.glDisable(c.GL_CULL_FACE);
	var finalFrameBuffer: FrameBuffer = undefined;
	finalFrameBuffer.init(false, c.GL_NEAREST, c.GL_REPEAT);
	finalFrameBuffer.updateSize(textureSize, textureSize, c.GL_RGBA8);
	finalFrameBuffer.bind();
	const texture = Texture{.textureID = finalFrameBuffer.texture};
	defer c.glDeleteFramebuffers(1, &finalFrameBuffer.frameBuffer);
	block_texture.pipeline.bind(null);
	c.glUniform1i(block_texture.uniforms.transparent, if (block.transparent()) c.GL_TRUE else c.GL_FALSE);
	frameBuffer.bindTexture(c.GL_TEXTURE3);

	draw.rectVao.bind();
	c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);

	c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);

	c.glViewport(0, 0, main.Window.width, main.Window.height);
	c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
	return texture;
}
