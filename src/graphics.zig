/// A collection of things that should make dealing with opengl easier.
/// Also contains some basic 2d drawing stuff.

const std = @import("std");

const Allocator = std.mem.Allocator;

const c = @cImport ({
	@cInclude("glad/glad.h");
});

fn fileToString(allocator: Allocator, path: []const u8) ![]u8 {
	const file = try std.fs.cwd().openFile(path, .{});
	return file.readToEndAlloc(allocator, std.math.maxInt(usize));
}

pub fn init() void {

}

pub fn deinit() void {

}

pub const Shader = struct {
	id: c_uint,
	
	fn addShader(self: *const Shader, filename: []const u8, shader_stage: c_uint) !void {
		const source = try fileToString(std.heap.page_allocator, filename);
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