const std = @import("std");

pub var globalAllocator: std.mem.Allocator = undefined;
pub var io: std.Io = undefined;

var failed: bool = false;

fn printError(msg: []const u8, filePath: []const u8, data: []const u8, charIndex: usize) void {
	var lineStart: usize = 0;
	var lineNumber: usize = 1;
	var lineEnd: usize = data.len;
	for (data[0..charIndex], 0..) |c, i| {
		if (c == '\n') {
			lineStart = i + 1;
			lineNumber += 1;
		}
	}
	for (data[charIndex..], charIndex..) |c, i| {
		if (c == '\n') {
			lineEnd = i;
			break;
		}
	}

	var startLineChars: std.ArrayList(u8) = .empty;
	defer startLineChars.deinit(globalAllocator);
	for (data[lineStart..charIndex]) |c| {
		if (c == '\t') {
			startLineChars.append(globalAllocator, '\t') catch {};
		} else {
			startLineChars.append(globalAllocator, ' ') catch {};
		}
	}

	failed = true;

	std.log.err("Found formatting error in line {} of file {s}: {s}\n{s}\n{s}^", .{lineNumber, filePath, msg, data[lineStart..lineEnd], startLineChars.items});
}

fn checkFile(dir: std.Io.Dir, filePath: []const u8) !void {
	const data = try dir.readFileAlloc(io, filePath, globalAllocator, .unlimited);
	defer globalAllocator.free(data);

	var lineStart: bool = true;

	for (data, 0..) |c, i| {
		switch (c) {
			'\n' => {
				lineStart = true;
				if (i != 0 and (data[i - 1] == ' ' or data[i - 1] == '\t')) {
					printError("Line contains trailing whitespaces. Please remove them.", filePath, data, i - 1);
				}
			},
			'\r' => {
				printError("Incorrect line ending \\r. Please configure your editor to use LF instead CRLF.", filePath, data, i);
			},
			' ' => {
				if (lineStart) {
					printError("Incorrect indentation. Please use tabs instead of spaces.", filePath, data, i);
				}
			},
			'/' => {
				if (data[i + 1] == '/' and data[i + 2] != '/' and data[i + 2] != '!' and data[i + 2] != ' ' and data[i + 2] != '\n' and (i == 0 or (data[i - 1] != ':' and data[i - 1] != '"'))) {
					printError("Comments should include a space before text, ex: // whatever", filePath, data, i + 2);
				}
				lineStart = false;
			},
			'\t' => {},
			else => {
				lineStart = false;
			},
		}
	}
	if (std.mem.containsAtLeast(u8, data, 1, "anyerror" ++ "!")) {
		if (!std.mem.eql(u8, filePath, "network/protocols.zig")) {
			std.log.err("Found anyerror" ++ "! in file {s}. Please avoid the use of anyerror" ++ "! instead please define an error set.", .{filePath});
		}
	}
	if (data.len != 0 and data[data.len - 1] != '\n' or (data.len > 2 and data[data.len - 2] == '\n')) {
		printError("File should end with a single empty line", filePath, data, data.len - 1);
	}
}

fn checkDirectory(dir: std.Io.Dir) !void {
	var walker = try dir.walk(globalAllocator);
	defer walker.deinit();
	while (try walker.next(io)) |child| {
		if (std.mem.endsWith(u8, child.basename, ".zon") and !std.mem.endsWith(u8, child.basename, ".zig.zon")) {
			std.log.err("File name should end with .zig.zon so it gets syntax highlighting on github.", .{});
			failed = true;
		}
		if (child.kind == .file and (std.mem.endsWith(u8, child.basename, ".vert") or std.mem.endsWith(u8, child.basename, ".frag") or std.mem.endsWith(u8, child.basename, ".comp") or (std.mem.endsWith(u8, child.basename, ".zig") and !std.mem.eql(u8, child.basename, "fmt.zig")))) {
			try checkFile(dir, child.path);
		}
	}
}

pub fn main(init: std.process.Init) !void {
	globalAllocator = init.gpa;
	io = init.io;

	var dir = try std.Io.Dir.cwd().openDir(io, "src", .{.iterate = true});
	defer dir.close(io);
	try checkDirectory(dir);
	dir.close(io);
	dir = try std.Io.Dir.cwd().openDir(io, "assets", .{.iterate = true});
	try checkDirectory(dir);

	if (failed) std.process.exit(1);
}
