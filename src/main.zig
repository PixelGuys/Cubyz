const std = @import("std");

const graphics = @import("graphics.zig");

const Vec2f = @import("vec.zig").Vec2f;

pub const c = @cImport ({
	@cInclude("glad/glad.h");
	@cInclude("GLFW/glfw3.h");
});

var logFile: std.fs.File = undefined;

pub fn log(
	comptime level: std.log.Level,
	comptime scope: @Type(.EnumLiteral),
	comptime format: []const u8,
	args: anytype,
) void {
	if(scope != .default) {
		@compileError("Scopes are not supported.");
	}
	const color = comptime switch (level) {
		std.log.Level.err => "\x1b[31m",
		std.log.Level.info => "",
		std.log.Level.warn => "\x1b[33m",
		std.log.Level.debug => "\x1b[37;44m",
	};
	var buf: [4096]u8 = undefined;

	std.debug.getStderrMutex().lock();
	defer std.debug.getStderrMutex().unlock();

	const fileMessage = std.fmt.bufPrint(&buf, "[" ++ level.asText() ++ "]" ++ ": " ++ format ++ "\n", args) catch return;
	logFile.writeAll(fileMessage) catch return;

	const terminalMessage = std.fmt.bufPrint(&buf, color ++ format ++ "\x1b[0m\n", args) catch return;
	nosuspend std.io.getStdErr().writeAll(terminalMessage) catch return;
}

pub const Window = struct {
	var isFullscreen: bool = false;
	pub var width: u31 = 1280;
	pub var height: u31 = 720;
	var window: *c.GLFWwindow = undefined;
	const GLFWCallbacks = struct {
		fn errorCallback(errorCode: c_int, description: [*c]const u8) callconv(.C) void {
			std.log.err("GLFW Error({}): {s}", .{errorCode, description});
		}
		fn keyCallback(_: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
			std.log.info("Key pressed: {}, {}, {}, {}", .{key, scancode, action, mods});
			if(key == c.GLFW_KEY_F11 and action == c.GLFW_RELEASE) {
				toggleFullscreen();
			}
		}
		fn framebufferSize(_: ?*c.GLFWwindow, newWidth: c_int, newHeight: c_int) callconv(.C) void {
			std.log.info("Framebuffer: {}, {}", .{newWidth, newHeight});
			width = @intCast(u31, newWidth);
			height = @intCast(u31, newHeight);
		}
		fn glDebugOutput(_: c_uint, typ: c_uint, _: c_uint, severity: c_uint, length: c_int, message: [*c]const u8, _: ?*const anyopaque) callconv(.C) void {
			if(typ == c.GL_DEBUG_TYPE_ERROR or typ == c.GL_DEBUG_TYPE_DEPRECATED_BEHAVIOR or typ == c.GL_DEBUG_TYPE_UNDEFINED_BEHAVIOR or typ == c.GL_DEBUG_TYPE_PORTABILITY or typ == c.GL_DEBUG_TYPE_PERFORMANCE) {
				std.log.err("OpenGL {}:{s}", .{severity, message[0..@intCast(usize, length)]});
				@panic("OpenGL error");
			}
		}
	};

	fn init() !void {
		_ = c.glfwSetErrorCallback(GLFWCallbacks.errorCallback);

		if(c.glfwInit() == 0) {
			return error.GLFWFailed;
		}

		if(@import("builtin").mode == .Debug) {
			c.glfwWindowHint(c.GLFW_OPENGL_DEBUG_CONTEXT, 1);
		}
		c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 4);
		c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);

		window = c.glfwCreateWindow(width, height, "Cubyz", null, null) orelse return error.GLFWFailed;

		_ = c.glfwSetKeyCallback(window, GLFWCallbacks.keyCallback);
		_ = c.glfwSetFramebufferSizeCallback(window, GLFWCallbacks.framebufferSize);

		c.glfwMakeContextCurrent(window);

		if(c.gladLoadGL() == 0) {
			return error.GLADFailed;
		}
		c.glfwSwapInterval(1);

		if(@import("builtin").mode == .Debug) {
			c.glEnable(c.GL_DEBUG_OUTPUT);
			c.glEnable(c.GL_DEBUG_OUTPUT_SYNCHRONOUS);
			c.glDebugMessageCallback(GLFWCallbacks.glDebugOutput, null);
			c.glDebugMessageControl(c.GL_DONT_CARE, c.GL_DONT_CARE, c.GL_DONT_CARE, 0, null, c.GL_TRUE);
		}
	}

	fn deinit() void {
		c.glfwDestroyWindow(window);
		c.glfwTerminate();
	}

	var oldX: c_int = 0;
	var oldY: c_int = 0;
	var oldWidth: c_int = 0;
	var oldHeight: c_int = 0;
	pub fn toggleFullscreen() void {
		isFullscreen = !isFullscreen;
		if (isFullscreen) {
			c.glfwGetWindowPos(window, &oldX, &oldY);
			c.glfwGetWindowSize(window, &oldWidth, &oldHeight);
			const monitor = c.glfwGetPrimaryMonitor();
			if(monitor == null) {
				isFullscreen = false;
				return;
			}
			const vidMode = c.glfwGetVideoMode(monitor).?;
			c.glfwSetWindowMonitor(window, monitor, 0, 0, vidMode[0].width, vidMode[0].height, c.GLFW_DONT_CARE);
		} else {
			c.glfwSetWindowMonitor(window, null, oldX, oldY, oldWidth, oldHeight, c.GLFW_DONT_CARE);
			c.glfwSetWindowAttrib(window, c.GLFW_DECORATED, c.GLFW_TRUE);
		}
	}
};

pub fn main() !void {
	// init logging.
	logFile = std.fs.cwd().createFile("logs/latest.log", .{}) catch unreachable;
	defer logFile.close();

	try Window.init();
	defer Window.deinit();

	graphics.init();
	defer graphics.deinit();

	c.glEnable(c.GL_CULL_FACE);
	c.glCullFace(c.GL_BACK);
	c.glEnable(c.GL_BLEND);
	c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);

	while(c.glfwWindowShouldClose(Window.window) == 0) {
		{ // Check opengl errors:
			const err = c.glGetError();
			if(err != 0) {
				std.log.err("Got opengl error: {}", .{err});
			}
		}
		c.glfwSwapBuffers(Window.window);
		c.glfwPollEvents();
		c.glViewport(0, 0, Window.width, Window.height);
		c.glClearColor(1, 1, 0, 1);
		c.glClear(c.GL_DEPTH_BUFFER_BIT | c.GL_COLOR_BUFFER_BIT);
		{ // Render the game
			c.glEnable(c.GL_DEPTH_TEST);
			// TODO
		}

		{ // Render the GUI
			c.glDisable(c.GL_DEPTH_TEST);

			graphics.Draw.setColor(0xff0000ff);
			graphics.Draw.rect(Vec2f{.x = 100, .y = 100}, Vec2f{.x = 200, .y = 100});
			graphics.Draw.circle(Vec2f{.x = 200, .y = 200}, 59);
			graphics.Draw.setColor(0xffff00ff);
			graphics.Draw.line(Vec2f{.x = 0, .y = 0}, Vec2f{.x = 1920, .y = 1080});
		}
	}

	std.log.info("Hello zig.", .{});
}

test "abc" {
	_ = @import("json.zig");
}