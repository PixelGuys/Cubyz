const std = @import("std");

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
		.root_source_file = .{.path = "src/main.zig"},
		.target = target,
		.optimize = optimize,
	});
	exe.linkLibC();
	exe.linkLibCpp();

	const deps = b.dependency("deps", .{
		.target = target,
		.optimize = optimize,
	});

	exe.addLibraryPath(deps.path("lib"));
	exe.addIncludePath(deps.path("include"));
	exe.linkSystemLibrary("cubyz_deps");
	exe.addRPath(deps.path("lib")); // TODO: Maybe move the library next to the executable, to make this more portable?

	if(target.getOsTag() == .windows) {
		exe.linkSystemLibrary("ole32");
		exe.linkSystemLibrary("winmm");
		exe.linkSystemLibrary("uuid");
		exe.linkSystemLibrary("gdi32");
		exe.linkSystemLibrary("opengl32");
		exe.linkSystemLibrary("ws2_32");
	} else if(target.getOsTag() == .linux) {
		exe.linkSystemLibrary("asound");
		exe.linkSystemLibrary("x11");
		exe.linkSystemLibrary("GL");
	} else {
		std.log.err("Unsupported target: {}\n", .{ target.getOsTag() });
	}

	exe.addAnonymousModule("gui", .{.source_file = .{.path = "src/gui/gui.zig"}});
	exe.addAnonymousModule("server", .{.source_file = .{.path = "src/server/server.zig"}});

	//exe.strip = true; // Improves compile-time
	//exe.sanitize_thread = true;
	exe.disable_stack_probing = true; // Improves tracing of stack overflow errors.
	b.installArtifact(exe);

	const run_cmd = b.addRunArtifact(exe);
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
