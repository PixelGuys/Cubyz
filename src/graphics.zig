/// A collection of things that should make dealing with opengl easier.
/// Also contains some basic 2d drawing stuff.

const std = @import("std");

const Vec4i = @import("vec.zig").Vec4i;
const Vec2f = @import("vec.zig").Vec2f;
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
	pub fn readFromFile(allocator: Allocator, path: []const u8) !Image {
		var result: Image = undefined;
		var channel: c_int = undefined;
		const nullTerminatedPath = try std.fmt.allocPrintZ(main.threadAllocator, "{s}", .{path}); // TODO: Find a more zig-friendly image loading library.
		defer main.threadAllocator.free(nullTerminatedPath);
		const data = stb_image.stbi_load(nullTerminatedPath.ptr, @ptrCast([*c]c_int, &result.width), @ptrCast([*c]c_int, &result.height), &channel, 4) orelse {
			return error.FileNotFound;
		};
		result.imageData = try allocator.dupe(Color, @ptrCast([*]Color, data)[0..result.width*result.height]);
		stb_image.stbi_image_free(data);
		return result;
	}
};

pub const Fog = struct {
	active: bool,
	color: Vec3f,
	density: f32,
};