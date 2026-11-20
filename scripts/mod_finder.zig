const std = @import("std");

pub fn makeModFeatureList(io: std.Io, gpa: std.mem.Allocator, modsFolder: []const u8, name: []const u8, outputFolder: []const u8) !void {
	var featureList: std.ArrayListUnmanaged(u8) = .empty;
	defer featureList.deinit(gpa);

	var modDir = try std.Io.Dir.cwd().openDir(io, modsFolder, .{.iterate = true});
	defer modDir.close(io);

	var iterator = modDir.iterate();
	while (try iterator.next(io)) |modEntry| {
		if (modEntry.kind != .directory) continue;

		var mod = try modDir.openDir(io, modEntry.name, .{});
		defer mod.close(io);

		var featureDir = mod.openDir(io, name, .{.iterate = true}) catch continue;
		defer featureDir.close(io);

		var featureWalker = try std.Io.Dir.walk(featureDir, gpa);
		defer featureWalker.deinit();

		var modFeatureList: std.ArrayListUnmanaged([]const u8) = .empty;
		defer modFeatureList.deinit(gpa);
		defer for (modFeatureList.items) |modFeature| gpa.free(modFeature);

		while (try featureWalker.next(io)) |featureEntry| {
			if (featureEntry.kind != .file) continue;
			if (!std.mem.endsWith(u8, featureEntry.basename, ".zig")) continue;

			const normalizedPath = try gpa.dupe(u8, featureEntry.path);
			defer gpa.free(normalizedPath);
			if (std.Io.Dir.path.sep != '/') std.mem.replaceScalar(u8, normalizedPath, std.Io.Dir.path.sep, '/');

			try modFeatureList.append(gpa, try std.fmt.allocPrint(
				gpa,
				\\pub const @"{s}:{s}" = @import("{s}/{s}/{s}");
			,
				.{
					modEntry.name,
					normalizedPath[0 .. normalizedPath.len - 4],
					modEntry.name,
					name,
					normalizedPath,
				},
			));
		}
		std.mem.sort([]const u8, modFeatureList.items, {}, struct {
			fn lessThanFn(_: void, lhs: []const u8, rhs: []const u8) bool {
				return std.mem.lessThan(u8, lhs, rhs);
			}
		}.lessThanFn);

		if (featureList.items.len != 0) try featureList.append(gpa, '\n');
		try featureList.print(gpa,
			\\// MARK: {s}
			\\
		, .{modEntry.name});

		for (modFeatureList.items, 0..) |item, i| {
			if (i != 0) try featureList.append(gpa, '\n');
			try featureList.appendSlice(gpa, item);
		}
		try featureList.append(gpa, '\n');
	}

	const testTextSpaces =
		\\
		\\const main = @import("main");
		\\test "abc" {
		\\    @setEvalBranchQuota(1000000);
		\\    main.refAllDeclsRecursiveExceptCImports(@This());
		\\}
	;
	const testText = try std.mem.replaceOwned(u8, gpa, testTextSpaces, "    ", "\t");
	defer gpa.free(testText);
	try featureList.appendSlice(gpa, testText);
	try featureList.append(gpa, '\n');

	const outputFile = try std.fmt.allocPrint(gpa, "{s}/{s}.zig", .{outputFolder, name});
	defer gpa.free(outputFile);
	try std.Io.Dir.cwd().writeFile(io, .{.data = featureList.items, .sub_path = outputFile});
}

fn printUsage(args: std.process.Init) !noreturn {
	const actualArgs = try std.mem.join(args.arena.allocator(), ", ", (try args.minimal.args.toSlice(args.arena.allocator()))[1..]);
	std.log.err("Inccorect usage, found \n{s}\nexpected:\n<input mods folder> <output mods folder>", .{actualArgs});
	std.process.exit(1);
}

pub fn main(args: std.process.Init) !void {
	var argsIterator = try args.minimal.args.iterateAllocator(args.gpa);
	defer argsIterator.deinit();
	_ = argsIterator.next();
	const modsFolder = argsIterator.next() orelse try printUsage(args);
	const outputFolder = argsIterator.next() orelse try printUsage(args);
	if (argsIterator.next() != null) try printUsage(args);
	
	try makeModFeatureList(args.io, args.gpa, modsFolder, "rotations", outputFolder);
}
