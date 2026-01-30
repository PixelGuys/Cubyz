const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const PermissionLayer = union(enum) {
	none: void,
	all: void,
	subPermissions: std.StringHashMap(*PermissionLayer),

	pub fn init() *PermissionLayer {
		const self = main.globalAllocator.create(PermissionLayer);
		self.* = .none;
		return self;
	}

	pub fn deinit(self: *PermissionLayer) void {
		if (self.* == .subPermissions) {
			var it = self.subPermissions.iterator();
			while (it.next()) |entry| {
				main.globalAllocator.free(entry.key_ptr.*);
				entry.value_ptr.*.deinit();
			}
			self.subPermissions.deinit();
		}
		main.globalAllocator.destroy(self);
	}

	pub fn addPermission(self: *PermissionLayer, permissionPath: []const u8, source: *User) void {
		if (permissionPath.len == 0) return;
		if (self.* == .all) {
			source.sendMessage("#ff0000User already has all permissions inside \"{s}\"", .{permissionPath});
			return;
		}
		if (std.mem.eql(u8, permissionPath, "*")) {
			if (self.* == .subPermissions) {
				self.subPermissions.deinit();
			}
			self.* = .all;
			return;
		}

		const end = std.mem.indexOfScalar(u8, permissionPath, '.') orelse permissionPath.len;
		if (self.* == .none) {
			self.* = .{.subPermissions = .init(main.globalAllocator.allocator)};
		}
		if (!self.subPermissions.contains(permissionPath[0..end])) {
			const perm: *PermissionLayer = .init();
			self.subPermissions.put(main.globalAllocator.dupe(u8, permissionPath[0..end]), perm) catch unreachable;
		}
		if (self.subPermissions.get(permissionPath[0..end])) |perm| {
			perm.addPermission(permissionPath[@min(end + 1, permissionPath.len)..], source);
			return;
		}
	}

	pub fn hasPermission(self: *PermissionLayer, permissionPath: []const u8) bool {
		return switch (self.*) {
			.all => true,
			.none => (permissionPath.len == 0),
			.subPermissions => |subPermissions| {
				const end = std.mem.indexOfScalar(u8, permissionPath, '.') orelse permissionPath.len;
				if (subPermissions.get(permissionPath[0..end])) |perm| {
					return perm.hasPermission(permissionPath[@min(end + 1, permissionPath.len)..]);
				}
				return false;
			},
		};
	}
};
