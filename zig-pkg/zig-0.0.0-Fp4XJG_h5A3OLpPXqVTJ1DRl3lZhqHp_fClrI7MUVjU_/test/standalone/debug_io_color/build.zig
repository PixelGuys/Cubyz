const std = @import("std");

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Test");
    b.default_step = test_step;

    // Most targets handle color the same way, regardless of whether libc is linked.
    const native_target = b.graph.host;
    addTestCases(test_step, native_target, false);
    addTestCases(test_step, native_target, true);

    // WASI behaves differently depending on whether libc is linked.
    if (b.enable_wasmtime) {
        const wasi_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .wasi });
        addTestCases(test_step, wasi_target, false);
        addTestCases(test_step, wasi_target, true);
    }
}

fn addTestCases(
    test_step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    link_libc: bool,
) void {
    const b = test_step.owner;
    const exe = b.addExecutable(.{
        .name = b.fmt("{s}{s}", .{ @tagName(target.result.os.tag), if (link_libc) "-libc" else "" }),
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .link_libc = link_libc,
        }),
    });

    // Should reflect 'std.process.Environ.Block' and 'std.Io.Threaded.init_single_threaded'.
    const debug_io_can_read_environ = switch (target.result.os.tag) {
        .windows => true,
        .wasi, .emscripten => link_libc,
        .freestanding, .other => false,
        else => true,
    };

    // Don't forget to account for whether the build process's stderr supports color.
    const parent_stderr_color_enabled = (std.Io.Terminal.Mode.detect(b.graph.io, .stderr(), false, false) catch unreachable) != .no_color;

    _ = addTestCase(test_step, exe, "neither", .inherit, .manual, parent_stderr_color_enabled);
    _ = addTestCase(test_step, exe, "neither", .redirect, .manual, false);
    _ = addTestCase(test_step, exe, "no_color", .inherit, .disable, if (debug_io_can_read_environ) false else parent_stderr_color_enabled);
    _ = addTestCase(test_step, exe, "no_color", .redirect, .disable, false);
    _ = addTestCase(test_step, exe, "clicolor_force", .inherit, .enable, if (debug_io_can_read_environ) true else parent_stderr_color_enabled);
    _ = addTestCase(test_step, exe, "clicolor_force", .redirect, .enable, debug_io_can_read_environ);

    const both = addTestCase(test_step, exe, "both", .inherit, .manual, if (debug_io_can_read_environ) false else parent_stderr_color_enabled);
    both.setEnvironmentVariable("NO_COLOR", "1");
    both.setEnvironmentVariable("CLICOLOR_FORCE", "1");

    const both_redirected = addTestCase(test_step, exe, "both", .redirect, .manual, false);
    both_redirected.setEnvironmentVariable("NO_COLOR", "1");
    both_redirected.setEnvironmentVariable("CLICOLOR_FORCE", "1");
}

fn addTestCase(
    test_step: *std.Build.Step,
    exe: *std.Build.Step.Compile,
    test_case_name: []const u8,
    stderr: enum { inherit, redirect },
    run_step_color: std.Build.Step.Run.Color,
    expected_color_enabled: bool,
) *std.Build.Step.Run {
    const b = test_step.owner;
    const step_name = b.fmt("{s} {s}{s}", .{
        exe.name,
        test_case_name,
        if (stderr == .redirect) "-redirect" else "",
    });
    const run_exe = b.addRunArtifact(exe);
    run_exe.setName(b.fmt("run {s}", .{step_name}));

    run_exe.failing_to_execute_foreign_is_an_error = false;
    if (stderr == .redirect) run_exe.expectStdErrMatch("");

    run_exe.clearEnvironment();
    run_exe.color = run_step_color;

    // Build system quirk: Currently, Run step stdout checks will also redirect stderr, so as a
    // workaround we use a CheckFile step instead. We must also mark the Run step as having side
    // effects, to ensure the parent stderr is inherited when not explicitly redirected.
    run_exe.has_side_effects = true;
    const stdout = run_exe.captureStdOut(.{});
    const check_file = b.addCheckFile(stdout, .{ .expected_exact = if (expected_color_enabled) "true" else "false" });
    check_file.setName(b.fmt("check {s}", .{step_name}));
    test_step.dependOn(&check_file.step);

    return run_exe;
}
