pub const components = @import("entityComponent/_list.zig");
pub const systems = @import("entitySystem/_list.zig");
const main = @import("main.zig");

const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;

pub const EntityNetworkData = struct {
	id: u32,
	pos: Vec3d,
	vel: Vec3d,
	rot: Vec3f,
};

pub const Client = struct {
	pub fn init() void {
		inline for (@typeInfo(components).@"struct".decls) |decl| {
			@field(components, decl.name).Client.init();
		}
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).Client.init();
		}
	}
	pub fn deinit() void {
		inline for (@typeInfo(components).@"struct".decls) |decl| {
			@field(components, decl.name).Client.deinit();
		}
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).Client.deinit();
		}
	}
	pub fn clear() void {
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).Client.clear();
		}
		inline for (@typeInfo(components).@"struct".decls) |decl| {
			@field(components, decl.name).Client.clear();
		}
	}
};
pub const Server = struct {
	pub fn init() void {
		inline for (@typeInfo(components).@"struct".decls) |decl| {
			@field(components, decl.name).Server.init();
		}
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).Server.init();
		}
	}
	pub fn deinit() void {
		inline for (@typeInfo(components).@"struct".decls) |decl| {
			@field(components, decl.name).Server.deinit();
		}
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).Server.deinit();
		}
	}
	pub fn update() void {
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).Server.update();
		}
	}
};
