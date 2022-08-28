/// A collection of things that should make dealing with opengl easier.
/// Also contains some basic 2d drawing stuff.

const std = @import("std");
const Vec4i = @import("vec.zig").Vec4i;
const Vec2f = @import("vec.zig").Vec2f;

const Window = @import("main.zig").Window;

const Allocator = std.mem.Allocator;

const c = @cImport ({
	@cInclude("glad/glad.h");
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
	var rectVAO: c_uint = undefined;
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
		c.glUniform2f(rectUniforms.start, pos.x, pos.y);
		c.glUniform2f(rectUniforms.size, dim.x, dim.y);
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
		c.glUniform2f(lineUniforms.start, pos1.x, pos1.y);
		c.glUniform2f(lineUniforms.direction, pos2.x - pos1.x, pos2.y - pos1.y);
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
		c.glUniform2f(lineUniforms.start, pos.x, pos.y); // Move the coordinates, so they are in the center of a pixel.
		c.glUniform2f(lineUniforms.direction, dim.x - 1, dim.y - 1); // The height is a lot smaller because the inner edge of the rect is drawn.
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
		c.glUniform2f(circleUniforms.center, center.x, center.y); // Move the coordinates, so they are in the center of a pixel.
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
		c.glUniform2f(imageUniforms.start, pos.x, pos.y);
		c.glUniform2f(imageUniforms.size, dim.x, dim.y);
		c.glUniform1i(imageUniforms.color, color);

		c.glBindVertexArray(rectVAO);
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}

//	// ----------------------------------------------------------------------------
//	// TODO: Stuff for drawText:
//
//	private static CubyzFont font;
//	private static float fontSize;
//	public static void setFont(CubyzFont font, float fontSize) {
//		Graphics.font = font;
//		Graphics.fontSize = fontSize;
//	}
//	
//	/**
//	 * Draws a given string.
//	 * Uses TextLine.
//	 * @param x left
//	 * @param y top
//	 * @param text
//	 */
//	public static void drawText(float x, float y, String text) {
//		text = String.format("#%06x", 0xffffff & color) + text; // Add the coloring information.
//		TextLine line = new TextLine(font, text, fontSize, false);
//		line.render(x, y);
//	}
};

pub fn init() void {
	Draw.initCircle();
	Draw.initDrawRect();
	Draw.initImage();
	Draw.initLine();
	Draw.initRect();
}

pub fn deinit() void {
	Draw.deinitCircle();
	Draw.deinitDrawRect();
	Draw.deinitImage();
	Draw.deinitLine();
	Draw.deinitRect();
}

pub const Shader = struct {
	id: c_uint,
	
	fn addShader(self: *const Shader, filename: []const u8, shader_stage: c_uint) !void {
		const source = fileToString(std.heap.page_allocator, filename) catch |err| {
			std.log.warn("Couldn't find file: {s}", .{filename});
			return err;
		};
		defer std.heap.page_allocator.free(source);
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
			if(field.field_type == c_int) {
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