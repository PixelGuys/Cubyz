const std = @import("std");

const Feature = struct {
	id: []const u8,
	field: type,
};

pub fn getFeatures(comptime T: type) []const Feature {
	var features: []const Feature = &.{};

	inline for (@typeInfo(T).@"struct".decls) |mod| {
		const mod_struct = @field(T, mod.name);
		inline for (std.meta.declarations(mod_struct)) |feature| {
			features = features ++ [_]Feature{.{
				.id = mod.name ++ ":" ++ feature.name,
				.field = @field(mod_struct, feature.name),
			}};
		}
	}
	return features;
}

/// Copied from std with a few differences as we need to do things when we leave / enter folders
pub const SelectiveWalker = struct {
	stack: std.ArrayList(StackItem),
	name_buffer: std.ArrayList(u8),
	featureList: *std.ArrayListUnmanaged(u8),
	owner: *std.Build,

	pub const Error = std.Io.Dir.Iterator.Error || std.mem.Allocator.Error;

	const StackItem = struct {
		iter: std.Io.Dir.Iterator,
		dirname_len: usize,
	};

	/// After each call to this function, and on deinit(), the memory returned
	/// from this function becomes invalid. A copy must be made in order to keep
	/// a reference to the path.
	pub fn next(self: *SelectiveWalker, io: std.Io) Error!?Walker.Entry {
		while (self.stack.items.len > 0) {
			const top = &self.stack.items[self.stack.items.len - 1];
			var dirname_len = top.dirname_len;
			if (top.iter.next(io) catch |err| {
				// If we get an error, then we want the user to be able to continue
				// walking if they want, which means that we need to pop the directory
				// that errored from the stack. Otherwise, all future `next` calls would
				// likely just fail with the same error.
				var item = self.stack.pop().?;
				if (self.stack.items.len != 0) {
					item.iter.reader.dir.close(io);
				}
				return err;
			}) |entry| {
				self.name_buffer.shrinkRetainingCapacity(dirname_len);
				if (self.name_buffer.items.len != 0) {
					try self.name_buffer.append(self.owner.allocator, std.Io.Dir.path.sep);
					dirname_len += 1;
				}
				try self.name_buffer.ensureUnusedCapacity(self.owner.allocator, entry.name.len + 1);
				self.name_buffer.appendSliceAssumeCapacity(entry.name);
				self.name_buffer.appendAssumeCapacity(0);
				const walker_entry: Walker.Entry = .{
					.dir = top.iter.reader.dir,
					.basename = self.name_buffer.items[dirname_len .. self.name_buffer.items.len - 1 :0],
					.path = self.name_buffer.items[0 .. self.name_buffer.items.len - 1 :0],
					.kind = entry.kind,
				};
				return walker_entry;
			} else {
				var item = self.stack.pop().?;
				if (self.stack.items.len != 0) {
					item.iter.reader.dir.close(io);
					for (0..std.mem.countScalar(u8, self.name_buffer.items[0..dirname_len], std.Io.Dir.path.sep) + 1) |_| {
						try self.featureList.appendSlice(self.owner.allocator, "    ");
					}
					try self.featureList.appendSlice(self.owner.allocator, "};\n");
				}
			}
		}
		return null;
	}

	/// Traverses into the directory, continuing walking one level down.
	pub fn enter(self: *SelectiveWalker, io: std.Io, entry: Walker.Entry) !void {
		if (entry.kind != .directory) {
			@branchHint(.cold);
			return;
		}
		try self.featureList.appendSlice(self.owner.allocator,
			\\
			\\
		);

		for (0..std.mem.countScalar(u8, self.name_buffer.items, std.Io.Dir.path.sep) + 1) |_| {
			try self.featureList.appendSlice(self.owner.allocator, "    ");
		}
		try self.featureList.appendSlice(self.owner.allocator, self.owner.fmt("pub const {s} = struct {{\n", .{entry.basename}));

		var new_dir = entry.dir.openDir(io, entry.basename, .{.iterate = true}) catch |err| {
			switch (err) {
				error.NameTooLong => unreachable,
				else => |e| return e,
			}
		};
		errdefer new_dir.close(io);

		try self.stack.append(self.owner.allocator, .{
			.iter = new_dir.iterateAssumeFirstIteration(),
			.dirname_len = self.name_buffer.items.len - 1,
		});
	}

	pub fn deinit(self: *SelectiveWalker) void {
		self.name_buffer.deinit(self.owner.allocator);
		self.stack.deinit(self.owner.allocator);
	}

	/// Leaves the current directory, continuing walking one level up.
	/// If the current entry is a directory entry, then the "current directory"
	/// will pertain to that entry if `enter` is called before `leave`.
	pub fn leave(self: *SelectiveWalker, io: std.Io) void {
		var item = self.stack.pop().?;
		if (self.stack.items.len != 0) {
			@branchHint(.likely);
			item.iter.reader.dir.close(io);
		}
	}
};

/// Recursively iterates over a directory, but requires the user to
/// opt-in to recursing into each directory entry.
///
/// `dir` must have been opened with `OpenOptions.iterate` set to `true`.
///
/// `Walker.deinit` releases allocated memory and directory handles.
///
/// The order of returned file system entries is undefined.
///
/// `dir` will not be closed after walking it.
///
/// See also `walk`.
pub fn walkSelectively(dir: std.Io.Dir, owner: *std.Build, featureList: *std.ArrayListUnmanaged(u8)) !SelectiveWalker {
	var stack: std.ArrayList(SelectiveWalker.StackItem) = .empty;

	try stack.append(owner.allocator, .{
		.iter = dir.iterate(),
		.dirname_len = 0,
	});

	return .{
		.stack = stack,
		.name_buffer = .empty,
		.owner = owner,
		.featureList = featureList,
	};
}

pub const Walker = struct {
	inner: SelectiveWalker,

	pub const Entry = struct {
		/// The containing directory. This can be used to operate directly on `basename`
		/// rather than `path`, avoiding `error.NameTooLong` for deeply nested paths.
		/// The directory remains open until `next` or `deinit` is called.
		dir: std.Io.Dir,
		basename: [:0]const u8,
		path: [:0]const u8,
		kind: std.Io.File.Kind,

		/// Returns the depth of the entry relative to the initial directory.
		/// Returns 1 for a direct child of the initial directory, 2 for an entry
		/// within a direct child of the initial directory, etc.
		pub fn depth(self: Walker.Entry) usize {
			return std.mem.countScalar(u8, self.path, std.Io.Dir.path.sep) + 1;
		}
	};

	/// After each call to this function, and on deinit(), the memory returned
	/// from this function becomes invalid. A copy must be made in order to keep
	/// a reference to the path.
	pub fn next(self: *Walker, io: std.Io) !?Walker.Entry {
		const entry = try self.inner.next(io);
		if (entry != null and entry.?.kind == .directory) {
			try self.inner.enter(io, entry.?);
		}
		return entry;
	}

	pub fn deinit(self: *Walker) void {
		self.inner.deinit();
	}

	/// Leaves the current directory, continuing walking one level up.
	/// If the current entry is a directory entry, then the "current directory"
	/// is the directory pertaining to the current entry.
	pub fn leave(self: *Walker, io: std.Io) void {
		self.inner.leave(io);
	}
};

/// Recursively iterates over a directory.
///
/// `dir` must have been opened with `OpenOptions.iterate` set to `true`.
///
/// `Walker.deinit` releases allocated memory and directory handles.
///
/// The order of returned file system entries is undefined.
///
/// `dir` will not be closed after walking it.
///
/// See also:
/// * `walkSelectively`
pub fn walk(dir: std.Io.Dir, owner: *std.Build, featureList: *std.ArrayListUnmanaged(u8)) std.mem.Allocator.Error!Walker {
	return .{.inner = try walkSelectively(dir, owner, featureList)};
}
