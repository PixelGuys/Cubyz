const std = @import("std");

const main = @import("main");
const chunk = main.chunk;
const Entity = main.entity.Entity;
const ServerChunk = chunk.ServerChunk;
const game = main.game;
const graphics = main.graphics;
const ZonElement = main.ZonElement;
const renderer = main.renderer;
const settings = main.settings;
const utils = main.utils;
const BinaryReader = utils.BinaryReader;
const BinaryWriter = utils.BinaryWriter;
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const blocks = main.blocks;
const World = game.World;
const ServerWorld = main.server.ServerWorld;
const items = main.items;
const ItemStack = items.ItemStack;
const random = main.random;

const c = @import("c");

const entityComponent = main.entityComponent;

// ############################# Client only stuff ################################
pub const client = struct {
	pub fn init() void {}
	pub fn deinit() void {}
	pub fn clear() void {}

	pub fn render(ambientLight: Vec3f, playerPos: Vec3d, deltaTime: f64) void {
		_ = ambientLight;
		_ = playerPos;
		_ = deltaTime;
	}
	pub fn renderHud(ambientLight: Vec3f, playerPos: Vec3d) void {
		_ = ambientLight;
		_ = playerPos;
	}

	pub fn addPredictedHealth(entity: Entity, change: f32) void {
		const healthComponent = main.entity.components.@"cubyz:health".client.components.get(entity) orelse return;
		healthComponent.health = std.math.clamp(healthComponent.health + change, 0, healthComponent.maxHealth);
	}
	pub fn setPredictedHealth(entity: Entity, value: f32) void {
		const healthComponent = main.entity.components.@"cubyz:health".client.components.get(entity) orelse return;
		healthComponent.health = std.math.clamp(value, 0, healthComponent.maxHealth);
	}

	pub fn getPredictedHealth(entity: Entity) ?f32 {
		const healthComponent = main.entity.components.@"cubyz:health".client.components.get(entity) orelse return null;
		return healthComponent.health;
	}
	pub fn getPredictedMaxHealth(entity: Entity) ?f32 {
		const healthComponent = main.entity.components.@"cubyz:health".client.components.get(entity) orelse return null;
		return healthComponent.maxHealth;
	}
};
// ############################# Server only stuff ################################
pub const server = struct {
	pub fn init() void {}
	pub fn deinit() void {}

	pub fn update() void {}

	pub fn addHealth(entity: Entity, change: f32, cause: main.game.DamageType) bool {
		_ = cause;
		const healthComponent = main.entity.components.@"cubyz:health".server.components.get(entity) orelse return false;
		healthComponent.health = std.math.clamp(healthComponent.health + change, 0, healthComponent.maxHealth);
		main.entity.server.transmitChange(main.entity.components.@"cubyz:health", entity);
		var ifKilled = false;
		if (healthComponent.health == 0) ifKilled = true;
		return ifKilled;
	}
	pub fn setHealth(entity: Entity, value: f32) void {
		const healthComponent = main.entity.components.@"cubyz:health".server.components.get(entity) orelse return;
		healthComponent.health = std.math.clamp(value, 0, healthComponent.maxHealth);
		main.entity.server.transmitChange(main.entity.components.@"cubyz:health", entity);
	}
};
