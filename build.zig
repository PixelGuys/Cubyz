const std = @import("std");

pub fn build(b: *std.Build) !void {
	// Standard target options allows the person running `zig build` to choose
	// what target to build for. Here we do not override the defaults, which
	// means any target is allowed, and the default is native. Other options
	// for restricting supported target set are available.
	const target = b.standardTargetOptions(.{});
	const t = target.result;

	// Standard release options allow the person running `zig build` to select
	// between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
	const optimize = b.standardOptimizeOption(.{});
	const exe = b.addExecutable(.{
		.name = "Cubyzig",
		.root_source_file = b.path("src/main.zig"),
		.target = target,
		.optimize = optimize,
		//.sanitize_thread = true,
	});
	exe.linkLibC();
	exe.linkLibCpp();

	const depsLib = b.fmt("cubyz_deps_{s}-{s}-{s}", .{@tagName(t.cpu.arch), @tagName(t.os.tag), switch(t.os.tag) {
		.linux => "musl",
		.macos => "none",
		.windows => "gnu",
		else => "none",
	}});
	const artifactName = switch(t.os.tag) {
		.windows => b.fmt("{s}.lib", .{depsLib}),
		else => b.fmt("lib{s}.a", .{depsLib}),
	};

	var depsName: []const u8 = b.fmt("cubyz_deps_{s}_{s}", .{@tagName(t.cpu.arch), @tagName(t.os.tag)});
	const useLocalDeps = b.option(bool, "local", "Use local cubyz_deps") orelse false;
	if(useLocalDeps) depsName = "local";

	const libsDeps = b.lazyDependency(depsName, .{
		.target = target,
		.optimize = optimize,
	}) orelse {
		// Lazy dependencies with a `url` field will fail here the first time.
		// build.zig will restart and try again.
		std.log.info("Downloading cubyz_deps libraries {s}.", .{depsName});
		return;
	};
	const headersDeps = if(useLocalDeps) libsDeps else
		b.lazyDependency("cubyz_deps_headers", .{}) orelse {
		std.log.info("Downloading cubyz_deps headers {s}.", .{depsName});
		return;
	};

	exe.addIncludePath(headersDeps.path("include"));
	exe.addObjectFile(libsDeps.path("lib").path(b, artifactName));

	if(t.os.tag == .windows) {
		exe.linkSystemLibrary("ole32");
		exe.linkSystemLibrary("winmm");
		exe.linkSystemLibrary("uuid");
		exe.linkSystemLibrary("gdi32");
		exe.linkSystemLibrary("opengl32");
		exe.linkSystemLibrary("ws2_32");
	} else if(t.os.tag == .linux) {
		exe.linkSystemLibrary("asound");
		exe.linkSystemLibrary("x11");
		exe.linkSystemLibrary("GL");
	} else if(t.os.tag == .macos) {
		exe.linkFramework("AudioUnit");
		exe.linkFramework("AudioToolbox");
		exe.linkFramework("CoreAudio");
		exe.linkFramework("CoreServices");
		exe.linkFramework("Foundation");
		exe.linkFramework("IOKit");
		exe.linkFramework("Cocoa");
		exe.linkFramework("QuartzCore");
		exe.addRPath(.{.cwd_relative = "/usr/local/GL/lib"});
		exe.root_module.addRPathSpecial("@executable_path/../Library");
		exe.addRPath(.{.cwd_relative = "/opt/X11/lib"});
	} else {
		std.log.err("Unsupported target: {}\n", .{t.os.tag});
	}

	exe.root_module.addAnonymousImport("gui", .{
		.target = target,
		.optimize = optimize,
		.root_source_file = b.path("src/gui/gui.zig"),
	});
	exe.root_module.addAnonymousImport("server", .{
		.target = target,
		.optimize = optimize,
		.root_source_file = b.path("src/server/server.zig"),
	});

	b.installArtifact(exe);

	const run_cmd = b.addRunArtifact(exe);
	run_cmd.step.dependOn(b.getInstallStep());
	if (b.args) |args| {
		run_cmd.addArgs(args);
	}

	const run_step = b.step("run", "Run the app");
	run_step.dependOn(&run_cmd.step);

	const exe_tests = b.addTest(.{
		.root_source_file = b.path("src/main.zig"),
		.target = target,
		.optimize = optimize,
	});

	const test_step = b.step("test", "Run unit tests");
	test_step.dependOn(&exe_tests.step);
}
