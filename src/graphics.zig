/// A collection of things that should make dealing with opengl easier.
/// Also contains some basic 2d drawing stuff.

const std = @import("std");

const freetype = @import("freetype");

const Vec4i = @import("vec.zig").Vec4i;
const Vec2f = @import("vec.zig").Vec2f;
const Vec2i = @import("vec.zig").Vec2i;
const Vec3f = @import("vec.zig").Vec3f;

const main = @import("main.zig");
const Window = main.Window;

const Allocator = std.mem.Allocator;

pub const c = @cImport ({
	@cInclude("glad/glad.h");
});

pub const stb_image = @cImport ({
	@cInclude("stb/stb_image.h");
});

fn fileToString(allocator: Allocator, path: []const u8) ![]u8 {
	const file = try std.fs.cwd().openFile(path, .{});
	return file.readToEndAlloc(allocator, std.math.maxInt(usize));
}

pub const Draw = struct {
	var color: i32 = 0;
	var clip: ?Vec4i = null;

	pub fn setColor(newColor: u32) void {
		color = @bitCast(i32, newColor);
	}

	/// Returns the previous clip.
	pub fn setClip(newClip: Vec4i) ?Vec4i {
		const oldClip = clip;
		clip = newClip;
		var clipRef: *Vec4i = &clip.?;
		if(oldClip == null) {
			c.glEnable(c.GL_SCISSOR_TEST);
		} else {
			if (clipRef.x < oldClip.x) {
				clipRef.z -= oldClip.x - clipRef.x;
				clipRef.x += oldClip.x - clipRef.x;
			}
			if (clipRef.y < oldClip.y) {
				clipRef.w -= oldClip.y - clipRef.y;
				clipRef.y += oldClip.y - clipRef.y;
			}
			if (clipRef.x + clipRef.z > oldClip.x + oldClip.z) {
				clipRef.z -= (clipRef.x + clipRef.z) - (oldClip.x + oldClip.z);
			}
			if (clipRef.y + clipRef.w > oldClip.y + oldClip.w) {
				clipRef.w -= (clipRef.y + clipRef.w) - (oldClip.y + oldClip.w);
			}
		}
		c.glScissor(clipRef.x, clipRef.y, clipRef.z, clipRef.w);
		return oldClip;
	}

	/// Should be used to restore the old clip when leaving the render function.
	pub fn restoreClip(previousClip: ?Vec4i) void {
		clip = previousClip;
		if (clip) |clipRef| {
			c.glScissor(clipRef.x, clipRef.y, clipRef.z, clipRef.w);
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
		rectShader = Shader.create("assets/cubyz/shaders/graphics/Rect.vs", "assets/cubyz/shaders/graphics/Rect.fs") catch Shader{.id = 0};
		rectUniforms = rectShader.bulkGetUniformLocation(@TypeOf(rectUniforms));
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
		rectShader.delete();
		c.glDeleteVertexArrays(1, &rectVAO);
		c.glDeleteBuffers(1, &rectVBO);
	}

	pub fn rect(pos: Vec2f, dim: Vec2f) void {
		rectShader.bind();

		c.glUniform2f(rectUniforms.screen, @intToFloat(f32, Window.width), @intToFloat(f32, Window.height));
		c.glUniform2f(rectUniforms.start, pos[0], pos[1]);
		c.glUniform2f(rectUniforms.size, dim[0], dim[1]);
		c.glUniform1i(rectUniforms.rectColor, color);

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
		lineShader = Shader.create("assets/cubyz/shaders/graphics/Line.vs", "assets/cubyz/shaders/graphics/Line.fs") catch Shader{.id = 0};
		lineUniforms = lineShader.bulkGetUniformLocation(@TypeOf(lineUniforms));
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
		lineShader.delete();
		c.glDeleteVertexArrays(1, &lineVAO);
		c.glDeleteBuffers(1, &lineVBO);
	}

	pub fn line(pos1: Vec2f, pos2: Vec2f) void {
		lineShader.bind();

		c.glUniform2f(lineUniforms.screen, @intToFloat(f32, Window.width), @intToFloat(f32, Window.height));
		c.glUniform2f(lineUniforms.start, pos1[0], pos1[1]);
		c.glUniform2f(lineUniforms.direction, pos2[0] - pos1[0], pos2[1] - pos1[1]);
		c.glUniform1i(lineUniforms.lineColor, color);

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

	pub fn rectOutline(pos: Vec2f, dim: Vec2f) void {
		lineShader.bind();

		c.glUniform2f(lineUniforms.screen, @intToFloat(f32, Window.width), @intToFloat(f32, Window.height));
		c.glUniform2f(lineUniforms.start, pos[0], pos[1]); // Move the coordinates, so they are in the center of a pixel.
		c.glUniform2f(lineUniforms.direction, dim[0] - 1, dim[1] - 1); // The height is a lot smaller because the inner edge of the rect is drawn.
		c.glUniform1i(lineUniforms.lineColor, color);

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
		circleShader = Shader.create("assets/cubyz/shaders/graphics/Circle.vs", "assets/cubyz/shaders/graphics/Circle.fs") catch Shader{.id = 0};
		circleUniforms = circleShader.bulkGetUniformLocation(@TypeOf(circleUniforms));
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
		circleShader.delete();
		c.glDeleteVertexArrays(1, &circleVAO);
		c.glDeleteBuffers(1, &circleVBO);
	}

	pub fn circle(center: Vec2f, radius: f32) void {
		circleShader.bind();

		c.glUniform2f(circleUniforms.screen, @intToFloat(f32, Window.width), @intToFloat(f32, Window.height));
		c.glUniform2f(circleUniforms.center, center[0], center[1]); // Move the coordinates, so they are in the center of a pixel.
		c.glUniform1f(circleUniforms.radius, radius); // The height is a lot smaller because the inner edge of the rect is drawn.
		c.glUniform1i(circleUniforms.circleColor, color);

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
		imageShader = Shader.create("assets/cubyz/shaders/graphics/Circle.vs", "assets/cubyz/shaders/graphics/Circle.fs") catch Shader{.id = 0};
		imageUniforms = imageShader.bulkGetUniformLocation(@TypeOf(imageUniforms));
	}

	fn deinitImage() void {
		imageShader.delete();
	}

	pub fn boundImage(pos: Vec2f, dim: Vec2f) void {
		imageShader.bind();

		c.glUniform2f(imageUniforms.screen, @intToFloat(f32, Window.width), @intToFloat(f32, Window.height));
		c.glUniform2f(imageUniforms.start, pos[0], pos[1]);
		c.glUniform2f(imageUniforms.size, dim[0], dim[1]);
		c.glUniform1i(imageUniforms.color, color);

		c.glBindVertexArray(rectVAO);
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}

	// ----------------------------------------------------------------------------
	
	pub fn text(_text: []const u8, x: f32, y: f32, fontSize: f32) !void {
		try TextRendering.renderText(_text, x, y, fontSize);
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
	var font: freetype.Face = undefined;
	var glyphMapping: std.ArrayList(u31) = undefined;
	var glyphData: std.ArrayList(Glyph) = undefined;
	var glyphTexture: [2]c_uint = undefined;
	var textureWidth: i32 = 1024;
	const textureHeight: i32 = 16;
	var textureOffset: i32 = 0;
	fn init() !void {
		shader = try Shader.create("assets/cubyz/shaders/graphics/Text.vs", "assets/cubyz/shaders/graphics/Text.fs");
		uniforms = shader.bulkGetUniformLocation(@TypeOf(uniforms));
		shader.bind();
		c.glUniform1i(uniforms.texture_sampler, 0);
		c.glUniform1f(uniforms.alpha, 1.0);
		c.glUniform2f(uniforms.fontSize, @intToFloat(f32, textureWidth), @intToFloat(f32, textureHeight));
		freetypeLib = try freetype.Library.init();
		font = try freetypeLib.createFace("assets/cubyz/fonts/unscii-16-full.ttf", 0);
		try font.setPixelSizes(0, textureHeight);

		glyphMapping = std.ArrayList(u31).init(main.globalAllocator);
		glyphData = std.ArrayList(Glyph).init(main.globalAllocator);
		try glyphData.append(undefined); // 0 is a reserved value.
		c.glCreateTextures(c.GL_TEXTURE_2D, 2, &glyphTexture);
		c.glBindTexture(c.GL_TEXTURE_2D, glyphTexture[0]);
		c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_R8, textureWidth, textureHeight, 0, c.GL_RED, c.GL_UNSIGNED_BYTE, null);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
	}

	fn deinit() void {
		shader.delete();
		font.deinit();
		freetypeLib.deinit();
		glyphMapping.deinit();
		glyphData.deinit();
		c.glDeleteTextures(2, &glyphTexture);
	}

	fn resizeTexture(newWidth: i32) !void {
		textureWidth = newWidth;
		const swap = glyphTexture[1];
		glyphTexture[1] = glyphTexture[0];
		glyphTexture[0] = swap;
		c.glBindTexture(c.GL_TEXTURE_2D, glyphTexture[0]);
		c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_R8, newWidth, textureHeight, 0, c.GL_RED, c.GL_UNSIGNED_BYTE, null);
		c.glCopyImageSubData(
			glyphTexture[1], c.GL_TEXTURE_2D, 0, 0, 0, 0,
			glyphTexture[0], c.GL_TEXTURE_2D, 0, 0, 0, 0,
			textureOffset, textureHeight, 1
		);
		shader.bind();
		c.glUniform2f(uniforms.fontSize, @intToFloat(f32, textureWidth), @intToFloat(f32, textureHeight));
	}

	fn uploadData(bitmap: freetype.Bitmap) !void {
		const width = @bitCast(i32, bitmap.width());
		const height = @bitCast(i32, bitmap.rows());
		const buffer = bitmap.buffer() orelse return;
		if(textureOffset + width > textureWidth) {
			try resizeTexture(textureWidth*2);
		}
		c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
		c.glTexSubImage2D(c.GL_TEXTURE_2D, 0, textureOffset, 0, width, height, c.GL_RED, c.GL_UNSIGNED_BYTE, buffer.ptr);
		textureOffset += width;
	}

	fn getGlyph(char: u21) !Glyph {
		if(char >= glyphMapping.items.len) {
			try glyphMapping.appendNTimes(0, char - glyphMapping.items.len + 1);
		}
		if(glyphMapping.items[char] == 0) {// glyph was not initialized yet.
			try font.loadChar(char, freetype.LoadFlags{.render = true});
			const glyph = font.glyph();
			const bitmap = glyph.bitmap();
			const width = bitmap.width();
			const height = bitmap.rows();
			glyphMapping.items[char] = @intCast(u31, glyphData.items.len);
			(try glyphData.addOne()).* = Glyph {
				.textureX = textureOffset,
				.size = Vec2i{@intCast(i32, width), @intCast(i32, height)},
				.bearing = Vec2i{glyph.bitmapLeft(), 16 - glyph.bitmapTop()},
				.advance = @intToFloat(f32, glyph.advance().x)/@intToFloat(f32, 1 << 6),
			};
			try uploadData(bitmap);
		}
		return glyphData.items[glyphMapping.items[char]];
	}

	fn drawGlyph(glyph: Glyph, x: f32, y: f32, fontEffects: u28) void {
		// TODO: Underline/overline
		c.glUniform1i(uniforms.fontEffects, fontEffects);
		if(fontEffects & 0x1000000 != 0) { // bold
			c.glUniform2f(uniforms.offset, @intToFloat(f32, glyph.bearing[0]) + x, @intToFloat(f32, glyph.bearing[1]) + y - 1);
			c.glUniform4f(uniforms.texture_rect, @intToFloat(f32, glyph.textureX), 0, @intToFloat(f32, glyph.size[0]), @intToFloat(f32, glyph.size[1] + 1));
			c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
			// Just draw another thing on top in x direction. The y-direction is handled in the shader.
			c.glUniform2f(uniforms.offset, @intToFloat(f32, glyph.bearing[0]) + x + 0.5, @intToFloat(f32, glyph.bearing[1]) + y - 1);
			c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
		} else {
			c.glUniform2f(uniforms.offset, @intToFloat(f32, glyph.bearing[0]) + x, @intToFloat(f32, glyph.bearing[1]) + y);
			c.glUniform4f(uniforms.texture_rect, @intToFloat(f32, glyph.textureX), 0, @intToFloat(f32, glyph.size[0]), @intToFloat(f32, glyph.size[1]));
			c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
		}
	}

	fn renderText(text: []const u8, _x: f32, _y: f32, fontSize: f32) !void {
		const fontScaling = fontSize/16.0;
		var x = _x/fontScaling;
		const y = _y/fontScaling;
		shader.bind();
		c.glUniform2f(uniforms.scene, @intToFloat(f32, main.Window.width), @intToFloat(f32, main.Window.height));
		c.glUniform1f(uniforms.ratio, fontScaling);
		c.glActiveTexture(c.GL_TEXTURE0);
		c.glBindTexture(c.GL_TEXTURE_2D, glyphTexture[0]);
		c.glBindVertexArray(Draw.rectVAO);

		var unicodeIterator = std.unicode.Utf8Iterator{.bytes = text, .i = 0};
		var state: enum(u5) {
			colorRU = 5,
			colorRL = 4,
			colorGU = 3,
			colorGL = 2,
			colorBU = 1,
			colorBL = 0,
			text = 6,
			star,
			underscore,
			backslash,
		} = .text;
		var fontEffects: packed struct(u28) {
			color: u24 = 0,
			bold: bool = false,
			italic: bool = false,
			underline: bool = false,
			overline: bool = false,
		} = .{};
		while(unicodeIterator.nextCodepoint()) |codepoint| {
			const isControlCharacter: bool = blk: {
				switch(state) {
					.text => {
						switch(codepoint) {
							'*' => {
								state = .star;
								break :blk true;
							},
							'_' => {
								state = .underscore;
								break :blk true;
							},
							'\\' => {
								state = .backslash;
								break :blk true;
							},
							'#' => {
								state = .colorRU;
								break :blk true;
							},
							else => {
								break :blk false;
							}
						}
					},
					.star => {
						state = .text;
						if(codepoint == '*') {
							fontEffects.bold = !fontEffects.bold;
							break :blk true;
						} else {
							fontEffects.italic = !fontEffects.italic;
							break :blk false;
						}
					},
					.underscore => {
						state = .text;
						if(codepoint == '_') {
							fontEffects.bold = !fontEffects.bold;
							break :blk true;
						} else {
							fontEffects.italic = !fontEffects.italic;
							break :blk false;
						}
					},
					.backslash => {
						state = .text;
						break :blk false;
					},
					else => |colorEnum| {
						const shift = 4*@enumToInt(colorEnum);
						fontEffects.color = (fontEffects.color & ~(@as(u24, 0xf) << shift)) | @as(u24, switch(codepoint) {
							'0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => codepoint - '0',
							'a', 'b', 'c', 'd', 'e', 'f' => codepoint - 'a' + 10,
							'A', 'B', 'C', 'D', 'E', 'F' => codepoint - 'A' + 10,
							else => 0,
						}) << shift;
						if(colorEnum == .colorBL) {
							state = .text;
						} else {
							state = @intToEnum(@TypeOf(state), @enumToInt(colorEnum) - 1);
						}
						break :blk true;
					},
				}
			};
			const glyph = try getGlyph(codepoint);
			drawGlyph(glyph, x, y, if(isControlCharacter) 0x808080 else @bitCast(u28, fontEffects));
			x += glyph.advance;
		}
	}
};

pub fn init() !void {
	Draw.initCircle();
	Draw.initDrawRect();
	Draw.initImage();
	Draw.initLine();
	Draw.initRect();
	try TextRendering.init();
}

pub fn deinit() void {
	Draw.deinitCircle();
	Draw.deinitDrawRect();
	Draw.deinitImage();
	Draw.deinitLine();
	Draw.deinitRect();
	TextRendering.deinit();
}

pub const Shader = struct {
	id: c_uint,
	
	fn addShader(self: *const Shader, filename: []const u8, shader_stage: c_uint) !void {
		const source = fileToString(main.threadAllocator, filename) catch |err| {
			std.log.warn("Couldn't find file: {s}", .{filename});
			return err;
		};
		defer main.threadAllocator.free(source);
		const ref_buffer = [_] [*c]u8 {@ptrCast([*c]u8, source.ptr)};
		const shader = c.glCreateShader(shader_stage);
		defer c.glDeleteShader(shader);
		
		var sourceLen: c_int = @intCast(c_int, source.len);
		c.glShaderSource(shader, 1, @ptrCast([*c]const [*c]const u8, &ref_buffer[0]), &sourceLen);
		
		c.glCompileShader(shader);

		var success: c_int = undefined;
		c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &success);
		if(success != c.GL_TRUE) {
			var len: u32 = undefined;
			c.glGetShaderiv(shader, c.GL_INFO_LOG_LENGTH, @ptrCast(*c_int, &len));
			var buf: [4096] u8 = undefined;
			c.glGetShaderInfoLog(shader, 4096, @ptrCast(*c_int, &len), &buf);
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
			c.glGetProgramiv(self.id, c.GL_INFO_LOG_LENGTH, @ptrCast(*c_int, &len));
			var buf: [4096] u8 = undefined;
			c.glGetProgramInfoLog(self.id, 4096, @ptrCast(*c_int, &len), &buf);
			std.log.err("Error Linking Shader program:\n{s}\n", .{buf[0..len]});
			return error.FailedLinking;
		}
	} 
	
	pub fn create(vertex: []const u8, fragment: []const u8) !Shader {
		var shader = Shader{.id = c.glCreateProgram()};
		try shader.addShader(vertex, c.GL_VERTEX_SHADER);
		try shader.addShader(fragment, c.GL_FRAGMENT_SHADER);
		try shader.link();
		return shader;
	}

	pub fn bulkGetUniformLocation(self: *const Shader, comptime T: type) T {
		var ret: T = undefined;
		inline for(@typeInfo(T).Struct.fields) |field| {
			if(field.type == c_int) {
				@field(ret, field.name) = c.glGetUniformLocation(self.id, field.name[0..]);
			}
		}
		return ret;
	}

	pub fn bind(self: *const Shader) void {
		c.glUseProgram(self.id);
	}

	pub fn delete(self: *const Shader) void {
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

	pub fn bufferData(self: SSBO, comptime T: type, data: []T) void {
		c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, self.bufferID);
		c.glBufferData(c.GL_SHADER_STORAGE_BUFFER, @intCast(c_long, data.len*@sizeOf(T)), data.ptr, c.GL_STATIC_DRAW);
		c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, 0);
	}

	pub fn createDynamicBuffer(self: SSBO, size: usize) void {
		c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, self.bufferID);
		c.glBufferData(c.GL_SHADER_STORAGE_BUFFER, @intCast(c_long, size), null, c.GL_DYNAMIC_DRAW);
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

	pub fn init(self: *LargeBuffer, allocator: Allocator, size: u31, binding: c_uint) !void {
		self.ssbo = SSBO.init();
		self.ssbo.createDynamicBuffer(size);
		self.ssbo.bind(binding);

		self.freeBlocks = std.ArrayList(Allocation).init(allocator);
		try self.freeBlocks.append(.{.start = 0, .len = size});
	}

	pub fn deinit(self: *LargeBuffer) void {
		self.ssbo.deinit();
		self.freeBlocks.deinit();
	}

	fn alloc(self: *LargeBuffer, size: u31) !Allocation {
		var smallestBlock: ?*Allocation = null;
		for(self.freeBlocks.items) |*block, i| {
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
		var allocation = _allocation;
		if(allocation.len == 0) return;
		for(self.freeBlocks.items) |*block, i| {
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
			// Check if the buffer can be extended without a problem:
			for(self.freeBlocks.items) |*block, i| {
				if(allocation.start + allocation.len == block.start and block.len + allocation.len >= newSize) {
					const diff = newSize - allocation.len;
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
		c.glBufferSubData(c.GL_SHADER_STORAGE_BUFFER, offset, @sizeOf(T)*@intCast(c_long, data.len), data.ptr);
		c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, 0);
	}
};

pub const FrameBuffer = struct {
	frameBuffer: c_uint,
	texture: c_uint,
	hasDepthBuffer: bool,
	renderBuffer: c_uint,

	pub fn init(self: *FrameBuffer, hasDepthBuffer: bool) void {
		self.* = FrameBuffer{
			.frameBuffer = undefined,
			.texture = undefined,
			.renderBuffer = undefined,
			.hasDepthBuffer = hasDepthBuffer,
		};
		c.glGenFramebuffers(1, &self.frameBuffer);
		if(hasDepthBuffer) {
			c.glGenRenderbuffers(1, &self.renderBuffer);
		}
		c.glGenTextures(1, &self.texture);
	}

	pub fn deinit(self: *FrameBuffer) void {
		c.glDeleteFramebuffers(1, &self.frameBuffer);
		if(self.hasDepthBuffer) {
			c.glDeleteRenderbuffers(1, &self.renderBuffer);
		}
		c.glDeleteTextures(1, &self.texture);
	}

	pub fn updateSize(self: *FrameBuffer, width: u31, height: u31, textureFilter: c_int, textureWrap: c_int) void {
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.frameBuffer);
		if(self.hasDepthBuffer) {
			c.glBindRenderbuffer(c.GL_RENDERBUFFER, self.renderBuffer);
			c.glRenderbufferStorage(c.GL_RENDERBUFFER, c.GL_DEPTH24_STENCIL8, width, height);
			c.glFramebufferRenderbuffer(c.GL_FRAMEBUFFER, c.GL_DEPTH_STENCIL_ATTACHMENT, c.GL_RENDERBUFFER, self.renderBuffer);
		}

		c.glBindTexture(c.GL_TEXTURE_2D, self.texture);
		c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA8, width, height, 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, null);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, textureFilter);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, textureFilter);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, textureWrap);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, textureWrap);
		c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, self.texture, 0);
	}

	pub fn validate(self: *FrameBuffer) bool {
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.frameBuffer);
		defer c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
		if(c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER) != c.GL_FRAMEBUFFER_COMPLETE) {
			std.log.err("Frame Buffer Object error: {}", .{c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER)});
			return false;
		}
		return true;
	}

	pub fn bind(self: *FrameBuffer) void {
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.frameBuffer);
	}

	pub fn unbind() void {
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
		var r: [4]u32 = undefined;
		var g: [4]u32 = undefined;
		var b: [4]u32 = undefined;
		var a: [4]u32 = undefined;
		for(colors) |_, i| {
			r[i] = colors[i].r;
			g[i] = colors[i].g;
			b[i] = colors[i].b;
			a[i] = colors[i].a;
		}
		// Use gamma corrected average(https://stackoverflow.com/a/832314/13082649):
		var aSum: u32 = 0;
		var rSum: u32 = 0;
		var gSum: u32 = 0;
		var bSum: u32 = 0;
		for(colors) |_, i| {
			aSum += a[i]*a[i];
			rSum += r[i]*r[i];
			gSum += g[i]*g[i];
			bSum += b[i]*b[i];
		}
		aSum = @floatToInt(u32, @round(@sqrt(@intToFloat(f32, aSum)))/2);
		if(!isTransparent) {
			if(aSum < 128) {
				aSum = 0;
			} else {
				aSum = 255;
			}
		}
		rSum = @floatToInt(u32, @round(@sqrt(@intToFloat(f32, rSum)))/2);
		gSum = @floatToInt(u32, @round(@sqrt(@intToFloat(f32, gSum)))/2);
		bSum = @floatToInt(u32, @round(@sqrt(@intToFloat(f32, bSum)))/2);
		return Color{.r=@intCast(u8, rSum), .g=@intCast(u8, gSum), .b=@intCast(u8, bSum), .a=@intCast(u8, aSum)};
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
		c.glTexStorage3D(c.GL_TEXTURE_2D_ARRAY, maxLOD, c.GL_RGBA8, maxWidth, maxHeight, @intCast(c_int, images.len));
		var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
		defer arena.deinit();
		var lodBuffer: [][]Color = try arena.allocator().alloc([]Color, maxLOD);
		for(lodBuffer) |*buffer, i| {
			buffer.* = try arena.allocator().alloc(Color, (maxWidth >> @intCast(u5, i))*(maxHeight >> @intCast(u5, i)));
		}
		
		for(images) |image, i| {
			// Check if the image contains non-binary alpha values, which makes it transparent.
			var isTransparent = false;
			for(image.imageData) |color| {
				if(color.a != 0 or color.a != 255) {
					isTransparent = true;
					break;
				}
			}

			// Fill the buffer using nearest sampling. Probably not the best solutions for all textures, but that's what happens when someone doesn't use power of 2 textures...
			var x: u32 = 0;
			while(x < maxWidth): (x += 1) {
				var y: u32 = 0;
				while(y < maxHeight): (y += 1) {
					const index = x + y*maxWidth;
					const imageIndex = (x*image.width)/maxWidth + image.width*(y*image.height)/maxHeight;
					lodBuffer[0][index] = image.imageData[imageIndex];
				}
			}

			// Calculate the mipmap levels:
			for(lodBuffer) |_, _lod| {
				const lod = @intCast(u5, _lod);
				const curWidth = maxWidth >> lod;
				const curHeight = maxHeight >> lod;
				if(lod != 0) {
					x = 0;
					while(x < curWidth): (x += 1) {
						var y: u32 = 0;
						while(y < curHeight): (y += 1) {
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
				c.glTexSubImage3D(c.GL_TEXTURE_2D_ARRAY, lod, 0, 0, @intCast(c_int, i), curWidth, curHeight, 1, c.GL_RGBA, c.GL_UNSIGNED_BYTE, lodBuffer[lod].ptr);
			}
		}
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAX_LOD, maxLOD);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_BASE_LEVEL, 5);
		//glGenerateMipmap(GL_TEXTURE_2D_ARRAY);
		c.glTexParameteri(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST_MIPMAP_LINEAR);
		c.glTexParameteri(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
		c.glTexParameteri(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
		c.glTexParameteri(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
	}
};

pub const Color = extern struct {
	r: u8,
	g: u8,
	b: u8,
	a: u8
};

pub const Image = struct {
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
		allocator.free(self.imageData);
	}
	pub fn readFromFile(allocator: Allocator, path: []const u8) !Image {
		var result: Image = undefined;
		var channel: c_int = undefined;
		const nullTerminatedPath = try std.fmt.allocPrintZ(main.threadAllocator, "{s}", .{path}); // TODO: Find a more zig-friendly image loading library.
		defer main.threadAllocator.free(nullTerminatedPath);
		stb_image.stbi_set_flip_vertically_on_load(1);
		const data = stb_image.stbi_load(nullTerminatedPath.ptr, @ptrCast([*c]c_int, &result.width), @ptrCast([*c]c_int, &result.height), &channel, 4) orelse {
			return error.FileNotFound;
		};
		result.imageData = try allocator.dupe(Color, @ptrCast([*]Color, data)[0..result.width*result.height]);
		stb_image.stbi_image_free(data);
		return result;
	}
	pub fn setRGB(self: Image, x: usize, y: usize, rgb: Color) void {
		std.debug.assert(x < self.width);
		std.debug.assert(y < self.height);
		const index = x + y*self.width;
		self.imageData[index] = rgb;
	}
};

pub const Fog = struct {
	active: bool,
	color: Vec3f,
	density: f32,
};