const std = @import("std");

const main = @import("main");
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;

pub const systems = @import("systems/_list.zig");

pub const client = struct {
	pub fn init() void {
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).client.init();
		}
	}
	pub fn deinit() void {
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).client.deinit();
		}
	}
	pub fn clear() void {
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).client.clear();
		}
	}
	pub fn render(ambientLight: Vec3f, playerPos: Vec3d, deltaTime: f64) void {
		main.client.entity_manager.update();
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).client.render(ambientLight, playerPos, deltaTime);
		}
	}
	pub fn renderHud(ambientLight: Vec3f, playerPos: Vec3d) void {
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).client.renderHud(ambientLight, playerPos);
		}
	}
};

pub const server = struct {
	pub fn init() void {
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).server.init();
		}
	}
	pub fn deinit() void {
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
