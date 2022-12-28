const std = @import("std");
const freetype = @import("mach-freetype/build.zig");

fn sdkPath(comptime suffix: []const u8) []const u8 {
    if (suffix[0] != '/') @compileError("suffix must be an absolute path");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ suffix;
    };
}

fn ensureDependencySubmodule(allocator: std.mem.Allocator, path: []const u8) !void {
	if (std.process.getEnvVarOwned(allocator, "NO_ENSURE_SUBMODULES")) |no_ensure_submodules| {
		defer allocator.free(no_ensure_submodules);
		if (std.mem.eql(u8, no_ensure_submodules, "true")) return;
	} else |_| {}
	var child = std.ChildProcess.init(&.{ "git", "submodule", "update", "--init", path }, allocator);
	child.cwd = sdkPath("/");
	child.stderr = std.io.getStdErr();
	child.stdout = std.io.getStdOut();

	_ = try child.spawnAndWait();
}

pub fn build(b: *std.build.Builder) !void {
	try ensureDependencySubmodule(b.allocator, "mach-freetype");
	// Standard target options allows the person running `zig build` to choose
	// what target to build for. Here we do not override the defaults, which
	// means any target is allowed, and the default is native. Other options
	// for restricting supported target set are available.
	const target = b.standardTargetOptions(.{});

	// Standard release options allow the person running `zig build` to select
	// between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
	const mode = b.standardReleaseOptions();

	const exe = b.addExecutable("Cubyzig", "src/main.zig");
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
	exe.addCSourceFiles(&[_][]const u8{"lib/glad.c", "lib/stb_image.c", "lib/cross_platform_udp_socket.c"}, &[_][]const u8{"-g"});
	exe.addPackage(freetype.pkg);
	exe.addPackage(freetype.harfbuzz_pkg);
	freetype.link(b, exe, .{ .harfbuzz = .{} });
	exe.setTarget(target);
	exe.setBuildMode(mode);
	//exe.sanitize_thread = true;
	exe.install();

	const run_cmd = exe.run();
	run_cmd.step.dependOn(b.getInstallStep());
	if (b.args) |args| {
		run_cmd.addArgs(args);
	}

	const run_step = b.step("run", "Run the app");
	run_step.dependOn(&run_cmd.step);

	const exe_tests = b.addTest("src/main.zig");
	exe_tests.setTarget(target);
	exe_tests.setBuildMode(mode);

	const test_step = b.step("test", "Run unit tests");
	test_step.dependOn(&exe_tests.step);
}
