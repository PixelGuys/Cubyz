const std = @import("std");

const main = @import("main");
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;

pub const systems = @import("systems/_list.zig");

pub const client = struct {
	pub fn init() void {
		inline for (@typeInfo(systems).@"struct".decl_names) |decl| {
			@field(systems, decl).client.init();
		}
	}
	pub fn deinit() void {
		inline for (@typeInfo(systems).@"struct".decl_names) |decl| {
			@field(systems, decl).client.deinit();
		}
	}
	pub fn clear() void {
		inline for (@typeInfo(systems).@"struct".decl_names) |decl| {
			@field(systems, decl).client.clear();
		}
	}
	pub fn render(ambientLight: Vec3f, playerPos: Vec3d, deltaTime: f64) void {
		main.client.entity_manager.update();
		inline for (@typeInfo(systems).@"struct".decl_names) |decl| {
			@field(systems, decl).client.render(ambientLight, playerPos, deltaTime);
		}
	}
	pub fn renderHud(ambientLight: Vec3f, playerPos: Vec3d) void {
		inline for (@typeInfo(systems).@"struct".decl_names) |decl| {
			@field(systems, decl).client.renderHud(ambientLight, playerPos);
		}
	}
};

pub const server = struct {
	pub fn init() void {
		inline for (@typeInfo(systems).@"struct".decl_names) |decl| {
			@field(systems, decl).server.init();
		}
	}
	pub fn deinit() void {
		inline for (@typeInfo(systems).@"struct".decl_names) |decl| {
			@field(systems, decl).server.deinit();
		}
	}
	pub fn update() void {
		inline for (@typeInfo(systems).@"struct".decl_names) |decl| {
			@field(systems, decl).server.update();
		}
	}
};
