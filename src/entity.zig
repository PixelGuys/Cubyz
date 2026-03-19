const std = @import("std");
const main = @import("main.zig");
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;

pub const components = @import("entityComponent/_list.zig");
pub const systems = @import("entitySystem/_list.zig");

pub const EntityNetworkData = struct {
	id: u32,
	pos: Vec3d,
	vel: Vec3d,
	rot: Vec3f,
};

pub const client = struct {
	pub fn init() void {
		inline for (@typeInfo(components).@"struct".decls) |decl| {
			@field(components, decl.name).client.init();
		}
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).client.init();
		}
		main.client.entity_manager.init();
	}
	pub fn deinit() void {
		inline for (@typeInfo(components).@"struct".decls) |decl| {
			@field(components, decl.name).client.deinit();
		}
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).client.deinit();
		}
		main.client.entity_manager.deinit();
	}
	pub fn clear() void {
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).client.clear();
		}
		inline for (@typeInfo(components).@"struct".decls) |decl| {
			@field(components, decl.name).client.clear();
		}
		main.client.entity_manager.clear();
	}
};
pub const server = struct {
	pub fn init() void {
		inline for (@typeInfo(components).@"struct".decls) |decl| {
			@field(components, decl.name).server.init();
		}
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).server.init();
		}
	}
	pub fn deinit() void {
		inline for (@typeInfo(components).@"struct".decls) |decl| {
			@field(components, decl.name).server.deinit();
		}
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).server.deinit();
		}
	}
	pub fn update() void {
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).server.update();
		}
	}
};
