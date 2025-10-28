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
		exe.linkSystemLibrary("crypt32");
		exe.linkSystemLibrary("gdi32");
		exe.linkSystemLibrary("opengl32");
		exe.linkSystemLibrary("ws2_32");
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
	} else if(t.os.tag != .linux) {
		std.log.err("Unsupported target: {}\n", .{t.os.tag});
	}
}

pub fn makeModFeature(step: *std.Build.Step, name: []const u8) !void {
	var featureList: std.ArrayListUnmanaged(u8) = .{};
	defer featureList.deinit(step.owner.allocator);

	var modDir = try std.fs.cwd().openDir("mods", .{.iterate = true});
	defer modDir.close();

	var iterator = modDir.iterate();
	while(try iterator.next()) |modEntry| {
		if(modEntry.kind != .directory) continue;

		var mod = try modDir.openDir(modEntry.name, .{});
		defer mod.close();

		var featureDir = mod.openDir(name, .{.iterate = true}) catch continue;
		defer featureDir.close();

		var featureIterator = featureDir.iterate();
		while(try featureIterator.next()) |featureEntry| {
			if(featureEntry.kind != .file) continue;
			if(!std.mem.endsWith(u8, featureEntry.name, ".zig")) continue;

			try featureList.appendSlice(step.owner.allocator, step.owner.fmt(
				\\pub const @"{s}:{s}" = @import("{s}/{s}/{s}");
				\\
			,
				.{
					modEntry.name,
					featureEntry.name[0 .. featureEntry.name.len - 4],
					modEntry.name,
					name,
					featureEntry.name,
				},
			));
		}
	}

	const file_path = step.owner.fmt("mods/{s}.zig", .{name});
	try std.fs.cwd().writeFile(.{.data = featureList.items, .sub_path = file_path});
}

pub fn addModFeatureModule(b: *std.Build, exe: *std.Build.Step.Compile, name: []const u8) !void {
	const module = b.createModule(.{
		.root_source_file = b.path(b.fmt("mods/{s}.zig", .{name})),
		.target = exe.root_module.resolved_target,
		.optimize = exe.root_module.optimize,
	});
	module.addImport("main", exe.root_module);
	exe.root_module.addImport(name, module);
}

fn addModFeatures(b: *std.Build, exe: *std.Build.Step.Compile) !void {
	const step = try b.allocator.create(std.Build.Step);
	step.* = std.Build.Step.init(.{
		.id = .custom,
		.name = "Create Mods",
		.owner = b,
		.makeFn = makeModFeaturesStep,
	});
	exe.step.dependOn(step);

	try addModFeatureModule(b, exe, "rotation");
}

pub fn makeModFeaturesStep(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
	try makeModFeature(step, "rotation");
}

fn createLaunchConfig() !void {
	std.fs.cwd().access("launchConfig.zon", .{}) catch {
		try std.fs.cwd().writeFile(.{
			.data = ".{\n\t.cubyzDir = \"\",\n}\n",
			.sub_path = "launchConfig.zon",
		});
	};
}

pub fn build(b: *std.Build) !void {
	try createLaunchConfig();

	// Standard target options allows the person running `zig build` to choose
	// what target to build for. Here we do not override the defaults, which
	// means any target is allowed, and the default is native. Other options
	// for restricting supported target set are available.
	const target = b.standardTargetOptions(.{});

	// Standard release options allow the person running `zig build` to select
	// between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
	const optimize = b.standardOptimizeOption(.{});

	const options = b.addOptions();
	const isRelease = b.option(bool, "release", "Removes the -dev flag from the version") orelse false;
	const version = b.fmt("0.1.0{s}", .{if(isRelease) "" else "-dev"});
	options.addOption([]const u8, "version", version);
	options.addOption(bool, "isTaggedRelease", isRelease);

	const useLocalDeps = b.option(bool, "local", "Use local cubyz_deps") orelse false;

	const largeAssets = b.dependency("cubyz_large_assets", .{});
	b.installDirectory(.{
		.source_dir = largeAssets.path("music"),
		.install_subdir = "assets/cubyz/music/",
		.install_dir = .{.custom = ".."},
	});
	b.installDirectory(.{
		.source_dir = largeAssets.path("fonts"),
		.install_subdir = "assets/cubyz/fonts/",
		.install_dir = .{.custom = ".."},
	});

	const mainModule = b.addModule("main", .{
		.root_source_file = b.path("src/main.zig"),
		.target = target,
		.optimize = optimize,
	});

	const exe = b.addExecutable(.{
		.name = "Cubyz",
		.root_module = mainModule,
		//.sanitize_thread = true,
		.use_llvm = true,
	});
	exe.root_module.addOptions("build_options", options);
	exe.root_module.addImport("main", mainModule);
	try addModFeatures(b, exe);

	if(isRelease and target.result.os.tag == .windows) {
		exe.subsystem = .Windows;
	}

	linkLibraries(b, exe, useLocalDeps);

	b.installArtifact(exe);

	const run_cmd = b.addRunArtifact(exe);
	run_cmd.step.dependOn(b.getInstallStep());
	if(b.args) |args| {
		run_cmd.addArgs(args);
	}

	const run_step = b.step("run", "Run the app");
	run_step.dependOn(&run_cmd.step);

	const dependencyWithTestRunner = b.lazyDependency("cubyz_test_runner", .{
		.target = target,
		.optimize = optimize,
	}) orelse {
		std.log.info("Downloading cubyz_test_runner dependency.", .{});
		return;
	};
	const exe_tests = b.addTest(.{
		.root_module = mainModule,
		.test_runner = .{.path = dependencyWithTestRunner.path("lib/compiler/test_runner.zig"), .mode = .simple},
	});
	linkLibraries(b, exe_tests, useLocalDeps);
	exe_tests.root_module.addOptions("build_options", options);
	exe_tests.root_module.addImport("main", mainModule);
	try addModFeatures(b, exe_tests);
	const run_exe_tests = b.addRunArtifact(exe_tests);

	const test_step = b.step("test", "Run unit tests");
	test_step.dependOn(&run_exe_tests.step);

	// MARK: Formatter

	const formatter = b.addExecutable(.{
		.name = "CubyzFormatter",
		.root_module = b.addModule("format", .{
			.root_source_file = b.path("src/formatter/format.zig"),
			.target = target,
			.optimize = optimize,
		}),
	});
	// ZLS is stupid and cannot detect which executable is the main one, so we add the import everywhere...
	formatter.root_module.addOptions("build_options", options);
	formatter.root_module.addImport("main", mainModule);

	const formatter_install = b.addInstallArtifact(formatter, .{});

	const formatter_cmd = b.addRunArtifact(formatter);
	formatter_cmd.step.dependOn(&formatter_install.step);
	if(b.args) |args| {
		formatter_cmd.addArgs(args);
	}

	const formatter_step = b.step("format", "Check the formatting of the code");
	formatter_step.dependOn(&formatter_cmd.step);
}
