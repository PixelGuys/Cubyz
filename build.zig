const std = @import("std");

fn libName(b: *std.Build, name: []const u8, target: std.Target) []const u8 {
	return switch(target.os.tag) {
		.windows => b.fmt("{s}.lib", .{name}),
		else => b.fmt("lib{s}.a", .{name}),
	};
}

fn linkLibraries(b: *std.Build, exe: *std.Build.Step.Compile, useLocalDeps: bool) void {
	const target = exe.root_module.resolved_target.?;
	const t = target.result;
	const optimize = exe.root_module.optimize.?;

	exe.linkLibC();
	exe.linkLibCpp();

	const depsLib = b.fmt("cubyz_deps_{s}-{s}-{s}", .{@tagName(t.cpu.arch), @tagName(t.os.tag), switch(t.os.tag) {
		.linux => "musl",
		.macos => "none",
		.windows => "gnu",
		else => "none",
	}});
	const artifactName = libName(b, depsLib, t);

	var depsName: []const u8 = b.fmt("cubyz_deps_{s}_{s}", .{@tagName(t.cpu.arch), @tagName(t.os.tag)});
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
	const headersDeps = if(useLocalDeps) libsDeps else b.lazyDependency("cubyz_deps_headers", .{}) orelse {
		std.log.info("Downloading cubyz_deps headers {s}.", .{depsName});
		return;
	};

	exe.addIncludePath(headersDeps.path("include"));
	exe.addObjectFile(libsDeps.path("lib").path(b, artifactName));
	const subPath = libsDeps.path("lib").path(b, depsLib);
	exe.addObjectFile(subPath.path(b, libName(b, "glslang", t)));
	exe.addObjectFile(subPath.path(b, libName(b, "MachineIndependent", t)));
	exe.addObjectFile(subPath.path(b, libName(b, "GenericCodeGen", t)));
	exe.addObjectFile(subPath.path(b, libName(b, "glslang-default-resource-limits", t)));
	exe.addObjectFile(subPath.path(b, libName(b, "SPIRV", t)));
	exe.addObjectFile(subPath.path(b, libName(b, "SPIRV-Tools", t)));
	exe.addObjectFile(subPath.path(b, libName(b, "SPIRV-Tools-opt", t)));

	if(t.os.tag == .windows) {
		exe.linkSystemLibrary("ole32");
		exe.linkSystemLibrary("winmm");
		exe.linkSystemLibrary("uuid");
		exe.linkSystemLibrary("gdi32");
		exe.linkSystemLibrary("opengl32");
		exe.linkSystemLibrary("ws2_32");
	} else if(t.os.tag == .linux) {
		exe.linkSystemLibrary("asound");
		exe.linkSystemLibrary("X11");
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
}

pub fn makeModFeature(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
	const b = step.owner;
	const allocator = b.allocator;

	var out: std.ArrayListUnmanaged(u8) = .{};

	var assetsDir = try std.fs.cwd().openDir("mods", .{ .iterate = true });
	defer assetsDir.close();

	var iterator = assetsDir.iterate();
	while (try iterator.next()) |addonEntry| {
		if (addonEntry.kind != .directory) continue;

		var addon = try assetsDir.openDir(addonEntry.name, .{});
		defer addon.close();

		var rotationDir = addon.openDir(step.name, .{ .iterate = true }) catch continue;
		defer rotationDir.close();

		var rotationIterator = rotationDir.iterate();
		while (try rotationIterator.next()) |rotationEntry| {
			if (rotationEntry.kind != .file) continue;
			if (!std.mem.endsWith(u8, rotationEntry.name, ".zig")) continue;

			try out.appendSlice(allocator, b.fmt(
				"pub const @\"{s}:{s}\" = @import(\"{s}/{s}/{s}\");\n",
				.{
					addonEntry.name,
					rotationEntry.name[0..rotationEntry.name.len - 4],
					addonEntry.name,
					step.name,
					rotationEntry.name,
				},
			));
		}
	}

	const file_path = try std.fs.path.join(allocator, &.{ "mods", b.fmt("{s}.zig", .{step.name}) });
	var file = try std.fs.cwd().createFile(file_path, .{ .truncate = true });
	defer file.close();

	try file.writeAll(out.items);
	out.deinit(allocator);
}

pub fn addModFeatureStep(b: *std.Build, name: []const u8) !*std.Build.Step {
    const step = try b.allocator.create(std.Build.Step);
	step.* = std.Build.Step.init(.{
        .id = .custom,
        .name = name,
        .owner = b,
        .makeFn = makeModFeature,
    });
	return step;
}

pub fn addModFeature(b: *std.Build, exe: *std.Build.Step.Compile, name: []const u8) !void {
	exe.step.dependOn(try addModFeatureStep(b, name));

	const module = b.createModule(.{
		.root_source_file = b.path(try std.fs.path.join(b.allocator, &.{"mods", b.fmt("{s}.zig", .{name})})),
		.target = exe.root_module.resolved_target,
		.optimize = exe.root_module.optimize
	});
	module.addImport("main", exe.root_module);
	exe.root_module.addImport(name, module);
}

fn addModFeatures(b: *std.Build, exe: *std.Build.Step.Compile) !void {
	try addModFeature(b, exe, "rotation");
}

pub fn build(b: *std.Build) !void {
	// Standard target options allows the person running `zig build` to choose
	// what target to build for. Here we do not override the defaults, which
	// means any target is allowed, and the default is native. Other options
	// for restricting supported target set are available.
	const target = b.standardTargetOptions(.{});

	// Standard release options allow the person running `zig build` to select
	// between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
	const optimize = b.standardOptimizeOption(.{});

	const useLocalDeps = b.option(bool, "local", "Use local cubyz_deps") orelse false;

	const exe = b.addExecutable(.{
		.name = "Cubyzig",
		.root_source_file = b.path("src/main.zig"),
		.target = target,
		.optimize = optimize,
		//.sanitize_thread = true,
		//.use_llvm = false,
	});
	exe.root_module.addImport("main", exe.root_module);
	try addModFeatures(b, exe);

	linkLibraries(b, exe, useLocalDeps);

	b.installArtifact(exe);

	const run_cmd = b.addRunArtifact(exe);
	run_cmd.step.dependOn(b.getInstallStep());
	if(b.args) |args| {
		run_cmd.addArgs(args);
	}

	const run_step = b.step("run", "Run the app");
	run_step.dependOn(&run_cmd.step);

	const exe_tests = b.addTest(.{
		.root_source_file = b.path("src/main.zig"),
		.test_runner = .{.path = b.path("test/runner.zig"), .mode = .simple},
		.target = target,
		.optimize = optimize,
	});
	linkLibraries(b, exe_tests, useLocalDeps);
	exe_tests.root_module.addImport("main", exe_tests.root_module);
	try addModFeatures(b, exe_tests);
	const run_exe_tests = b.addRunArtifact(exe_tests);

	const test_step = b.step("test", "Run unit tests");
	test_step.dependOn(&run_exe_tests.step);

	// MARK: Formatter

	const formatter = b.addExecutable(.{
		.name = "CubyzigFormatter",
		.root_source_file = b.path("src/formatter/format.zig"),
		.target = target,
		.optimize = optimize,
	});
	// ZLS is stupid and cannot detect which executable is the main one, so we add the import everywhere...
	formatter.root_module.addAnonymousImport("main", .{
		.target = target,
		.optimize = optimize,
		.root_source_file = b.path("src/main.zig"),
	});

	const formatter_install = b.addInstallArtifact(formatter, .{});

	const formatter_cmd = b.addRunArtifact(formatter);
	formatter_cmd.step.dependOn(&formatter_install.step);
	if(b.args) |args| {
		formatter_cmd.addArgs(args);
	}

	const formatter_step = b.step("format", "Check the formatting of the code");
	formatter_step.dependOn(&formatter_cmd.step);

	const zig_fmt = b.addExecutable(.{
		.name = "zig_fmt",
		.root_source_file = b.path("src/formatter/fmt.zig"),
		.target = target,
		.optimize = optimize,
	});
	// ZLS is stupid and cannot detect which executable is the main one, so we add the import everywhere...
	zig_fmt.root_module.addAnonymousImport("main", .{
		.target = target,
		.optimize = optimize,
		.root_source_file = b.path("src/main.zig"),
	});

	const zig_fmt_install = b.addInstallArtifact(zig_fmt, .{});

	const zig_fmt_cmd = b.addRunArtifact(zig_fmt);
	zig_fmt_cmd.step.dependOn(&zig_fmt_install.step);
	if(b.args) |args| {
		zig_fmt_cmd.addArgs(args);
	}

	const zig_fmt_step = b.step("fmt", "Run the (modified) zig fmt on the code");
	zig_fmt_step.dependOn(&zig_fmt_cmd.step);
}
