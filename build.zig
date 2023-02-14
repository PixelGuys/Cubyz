const std = @import("std");
const freetype = @import("mach-freetype/build.zig");

pub fn build(b: *std.build.Builder) !void {
	// Standard target options allows the person running `zig build` to choose
	// what target to build for. Here we do not override the defaults, which
	// means any target is allowed, and the default is native. Other options
	// for restricting supported target set are available.
	const target = b.standardTargetOptions(.{});

	// Standard release options allow the person running `zig build` to select
	// between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
	const optimize = b.standardOptimizeOption(.{});
	const exe = b.addExecutable(.{
		.name = "Cubyzig",
		.root_source_file = .{ .path = "src/main.zig" },
		.target = target,
		.optimize = optimize,
	});
	exe.addIncludePath("include");
	exe.linkLibC();
	{ // compile glfw from source:
		if(target.getOsTag() == .windows) {
			exe.addCSourceFiles(&[_][]const u8 {
				"lib/glfw/src/win32_init.c", "lib/glfw/src/win32_joystick.c", "lib/glfw/src/win32_monitor.c", "lib/glfw/src/win32_time.c", "lib/glfw/src/win32_thread.c", "lib/glfw/src/win32_window.c", "lib/glfw/src/wgl_context.c", "lib/glfw/src/egl_context.c", "lib/glfw/src/osmesa_context.c", "lib/glfw/src/context.c", "lib/glfw/src/init.c", "lib/glfw/src/input.c", "lib/glfw/src/monitor.c", "lib/glfw/src/vulkan.c", "lib/glfw/src/window.c"
			}, &[_][]const u8{"-g", "-std=c99", "-D_GLFW_WIN32"});
			exe.linkSystemLibrary("gdi32");
			exe.linkSystemLibrary("opengl32");
			exe.linkSystemLibrary("ws2_32");
		} else if(target.getOsTag() == .linux) {
			// TODO: if(isWayland) {
			//	exe.addCSourceFiles(&[_][]const u8 {
			//		"lib/glfw/src/linux_joystick.c", "lib/glfw/src/wl_init.c", "lib/glfw/src/wl_monitor.c", "lib/glfw/src/wl_window.c", "lib/glfw/src/posix_time.c", "lib/glfw/src/posix_thread.c", "lib/glfw/src/xkb_unicode.c", "lib/glfw/src/egl_context.c", "lib/glfw/src/osmesa_context.c", "lib/glfw/src/context.c", "lib/glfw/src/init.c", "lib/glfw/src/input.c", "lib/glfw/src/monitor.c", "lib/glfw/src/vulkan.c", "lib/glfw/src/window.c"
			//	}, &[_][]const u8{"-g",});
			//} else {
				exe.addCSourceFiles(&[_][]const u8 {
					"lib/glfw/src/linux_joystick.c", "lib/glfw/src/x11_init.c", "lib/glfw/src/x11_monitor.c", "lib/glfw/src/x11_window.c", "lib/glfw/src/xkb_unicode.c", "lib/glfw/src/posix_time.c", "lib/glfw/src/posix_thread.c", "lib/glfw/src/glx_context.c", "lib/glfw/src/egl_context.c", "lib/glfw/src/osmesa_context.c", "lib/glfw/src/context.c", "lib/glfw/src/init.c", "lib/glfw/src/input.c", "lib/glfw/src/monitor.c", "lib/glfw/src/vulkan.c", "lib/glfw/src/window.c"
				}, &[_][]const u8{"-g", "-std=c99", "-D_GLFW_X11"});
				exe.linkSystemLibrary("x11");
			//}
			exe.linkSystemLibrary("GL");
		} else {
			std.log.err("Unsupported target: {}\n", .{ target.getOsTag() });
		}
	}
	exe.addCSourceFiles(&[_][]const u8{"lib/glad.c", "lib/stb_image.c"}, &[_][]const u8{"-g"});
	exe.addAnonymousModule("gui", .{.source_file = .{.path = "src/gui/gui.zig"}});
	exe.addModule("freetype", freetype.module(b));
	exe.addModule("harfbuzz", freetype.harfbuzzModule(b));
	freetype.link(b, exe, .{ .harfbuzz = .{} });
	//exe.sanitize_thread = true;
	exe.install();

	const run_cmd = exe.run();
	run_cmd.step.dependOn(b.getInstallStep());
	if (b.args) |args| {
		run_cmd.addArgs(args);
	}

	const run_step = b.step("run", "Run the app");
	run_step.dependOn(&run_cmd.step);

	const exe_tests = b.addTest(.{
		.root_source_file = .{ .path = "src/main.zig" },
		.target = target,
		.optimize = optimize,
	});

	const test_step = b.step("test", "Run unit tests");
	test_step.dependOn(&exe_tests.step);
}
