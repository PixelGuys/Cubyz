const std = @import("std");

const items = @import("items.zig");
const main = @import("main");
const vec = @import("vec.zig");
const Vec2f = vec.Vec2f;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const Vec3i = vec.Vec3i;
const settings = @import("settings.zig");
const Player = main.game.Player;
const camera = main.game.camera;

pub const baseGravity = 30.0;
pub const playerAirTerminalVelocity = 90.0;
pub const airDensity = 0.001;
pub const playerDensity = 1.2;

pub const collision = struct {
	pub const Box = struct {
		min: Vec3d,
		max: Vec3d,

		pub fn center(self: Box) Vec3d {
			return (self.min + self.max)*@as(Vec3d, @splat(0.5));
		}

		pub fn extent(self: Box) Vec3d {
			return (self.max - self.min)*@as(Vec3d, @splat(0.5));
		}

		pub fn intersects(self: Box, other: Box) bool {
			return @reduce(.And, (self.max > other.min)) and @reduce(.And, (self.min < other.max));
		}
	};

	const Direction = enum(u2) { x = 0, y = 1, z = 2 };

	pub fn collideWithBlock(block: main.blocks.Block, x: i32, y: i32, z: i32, entityPosition: Vec3d, entityBoundingBoxExtent: Vec3d, directionVector: Vec3d) ?struct { box: Box, dist: f64 } {
		var resultBox: ?Box = null;
		var minDistance: f64 = std.math.floatMax(f64);
		if (block.collide()) {
			const model = block.mode().model(block).model();

			const pos = Vec3d{@floatFromInt(x), @floatFromInt(y), @floatFromInt(z)};
			const entityCollision = Box{.min = entityPosition - entityBoundingBoxExtent, .max = entityPosition + entityBoundingBoxExtent};

			for (model.collision) |relativeBlockCollision| {
				const blockCollision = Box{.min = relativeBlockCollision.min + pos, .max = relativeBlockCollision.max + pos};
				if (blockCollision.intersects(entityCollision)) {
					const dotMin = vec.dot(directionVector, blockCollision.min);
					const dotMax = vec.dot(directionVector, blockCollision.max);

					const distance = @min(dotMin, dotMax);

					if (distance < minDistance) {
						resultBox = blockCollision;
						minDistance = distance;
					} else if (distance == minDistance) {
						resultBox = .{.min = @min(resultBox.?.min, blockCollision.min), .max = @max(resultBox.?.max, blockCollision.max)};
					}
				}
			}
		}
		return .{.box = resultBox orelse return null, .dist = minDistance};
	}

	pub fn collides(comptime side: main.sync.Side, dir: Direction, amount: f64, pos: Vec3d, hitBox: Box) ?Box {
		var boundingBox: Box = .{
			.min = pos + hitBox.min,
			.max = pos + hitBox.max,
		};
		switch (dir) {
			.x => {
				if (amount < 0) boundingBox.min[0] += amount else boundingBox.max[0] += amount;
			},
			.y => {
				if (amount < 0) boundingBox.min[1] += amount else boundingBox.max[1] += amount;
			},
			.z => {
				if (amount < 0) boundingBox.min[2] += amount else boundingBox.max[2] += amount;
			},
		}
		const minX: i32 = @floor(boundingBox.min[0]);
		const maxX: i32 = @floor(boundingBox.max[0]);
		const minY: i32 = @floor(boundingBox.min[1]);
		const maxY: i32 = @floor(boundingBox.max[1]);
		const minZ: i32 = @floor(boundingBox.min[2]);
		const maxZ: i32 = @floor(boundingBox.max[2]);

		const boundingBoxCenter = boundingBox.center();
		const fullBoundingBoxExtent = boundingBox.extent();

		var resultBox: ?Box = null;
		var minDistance: f64 = std.math.floatMax(f64);
		const directionVector: Vec3d = switch (dir) {
			.x => .{-std.math.sign(amount), 0, 0},
			.y => .{0, -std.math.sign(amount), 0},
			.z => .{0, 0, -std.math.sign(amount)},
		};

		var x: i32 = minX;
		while (x <= maxX) : (x += 1) {
			var y: i32 = minY;
			while (y <= maxY) : (y += 1) {
				var z: i32 = maxZ;
				while (z >= minZ) : (z -= 1) {
					if (main.game.getBlockWithSide(side, x, y, z)) |block| {
						if (collideWithBlock(block, x, y, z, boundingBoxCenter, fullBoundingBoxExtent, directionVector)) |res| {
							if (res.dist < minDistance) {
								resultBox = res.box;
								minDistance = res.dist;
							} else if (res.dist == minDistance) {
								resultBox.?.min = @min(resultBox.?.min, res.box.min);
								resultBox.?.max = @min(resultBox.?.max, res.box.max);
							}
						}
					}
				}
			}
		}

		return resultBox;
	}

	const SurfaceProperties = struct {
		friction: f32,
		bounciness: f32,
	};

	pub fn calculateSurfaceProperties(comptime side: main.sync.Side, pos: Vec3d, hitBox: Box, defaultFriction: f32) SurfaceProperties {
		const boundingBox: Box = .{
			.min = pos + hitBox.min,
			.max = pos + hitBox.max,
		};
		const minX: i32 = @floor(boundingBox.min[0]);
		const maxX: i32 = @floor(boundingBox.max[0]);
		const minY: i32 = @floor(boundingBox.min[1]);
		const maxY: i32 = @floor(boundingBox.max[1]);

		const z: i32 = @floor(boundingBox.min[2] - 0.01);

		var friction: f64 = 0;
		var bounciness: f64 = 0;
		var totalArea: f64 = 0;

		var x = minX;
		while (x <= maxX) : (x += 1) {
			var y = minY;
			while (y <= maxY) : (y += 1) {
				if (main.game.getBlockWithSide(side, x, y, z)) |block| {
					const blockPos: Vec3d = .{@floatFromInt(x), @floatFromInt(y), @floatFromInt(z)};

					const blockBox: Box = .{
						.min = blockPos + @as(Vec3d, @floatCast(block.mode().model(block).model().min)),
						.max = blockPos + @as(Vec3d, @floatCast(block.mode().model(block).model().max)),
					};

					if (boundingBox.min[2] > blockBox.max[2] or boundingBox.max[2] < blockBox.min[2]) {
						continue;
					}

					const max = std.math.clamp(vec.xy(blockBox.max), vec.xy(boundingBox.min), vec.xy(boundingBox.max));
					const min = std.math.clamp(vec.xy(blockBox.min), vec.xy(boundingBox.min), vec.xy(boundingBox.max));

					const area = (max[0] - min[0])*(max[1] - min[1]);

					if (block.collide()) {
						totalArea += area;
						friction += area*@as(f64, @floatCast(block.friction()));
						bounciness += area*@as(f64, @floatCast(block.bounciness()));
					}
				}
			}
		}

		if (totalArea == 0) {
			friction = defaultFriction;
			bounciness = 0.0;
		} else {
			friction = friction/totalArea;
			bounciness = bounciness/totalArea;
		}

		return .{
			.friction = @floatCast(friction),
			.bounciness = @floatCast(bounciness),
		};
	}

	pub const VolumeProperties = struct {
		terminalVelocity: f64,
		density: f64,
		maxDensity: f64,
		mobileFriction: f64,
	};

	fn overlapVolume(a: Box, b: Box) f64 {
		const min = @max(a.min, b.min);
		const max = @min(a.max, b.max);
		if (@reduce(.Or, min >= max)) return 0;
		return @reduce(.Mul, max - min);
	}

	pub fn calculateVolumeProperties(comptime side: main.sync.Side, pos: Vec3d, hitBox: Box, defaults: VolumeProperties) VolumeProperties {
		const boundingBox: Box = .{
			.min = pos + hitBox.min,
			.max = pos + hitBox.max,
		};
		const minX: i32 = @floor(boundingBox.min[0]);
		const maxX: i32 = @floor(boundingBox.max[0]);
		const minY: i32 = @floor(boundingBox.min[1]);
		const maxY: i32 = @floor(boundingBox.max[1]);
		const minZ: i32 = @floor(boundingBox.min[2]);
		const maxZ: i32 = @floor(boundingBox.max[2]);

		var invTerminalVelocitySum: f64 = 0;
		var densitySum: f64 = 0;
		var maxDensity: f64 = defaults.maxDensity;
		var mobileFrictionSum: f64 = 0;
		var volumeSum: f64 = 0;

		var x: i32 = minX;
		while (x <= maxX) : (x += 1) {
			var y: i32 = minY;
			while (y <= maxY) : (y += 1) {
				var z: i32 = maxZ;
				while (z >= minZ) : (z -= 1) {
					const totalBox: Box = .{
						.min = @floatFromInt(Vec3i{x, y, z}),
						.max = @floatFromInt(Vec3i{x + 1, y + 1, z + 1}),
					};
					const gridVolume = overlapVolume(boundingBox, totalBox);
					volumeSum += gridVolume;

					if (main.game.getBlockWithSide(side, x, y, z)) |block| {
						const collisionBox: Box = .{ // TODO: Check all AABBs individually
							.min = totalBox.min + main.blocks.meshes.model(block).model().min,
							.max = totalBox.min + main.blocks.meshes.model(block).model().max,
						};
						const filledVolume = @min(gridVolume, overlapVolume(collisionBox, totalBox));
						const emptyVolume = gridVolume - filledVolume;
						invTerminalVelocitySum += emptyVolume/defaults.terminalVelocity;
						mobileFrictionSum += emptyVolume*defaults.mobileFriction;
						densitySum += emptyVolume*defaults.density;
						invTerminalVelocitySum += filledVolume/block.terminalVelocity();
						mobileFrictionSum += filledVolume*block.mobility()/block.terminalVelocity();
						densitySum += filledVolume*block.density();
						maxDensity = @max(maxDensity, block.density());
					} else {
						invTerminalVelocitySum += gridVolume/defaults.terminalVelocity;
						densitySum += gridVolume*defaults.density;
						mobileFrictionSum += gridVolume*defaults.mobileFriction;
					}
				}
			}
		}

		return .{
			.terminalVelocity = volumeSum/invTerminalVelocitySum,
			.density = densitySum/volumeSum,
			.maxDensity = maxDensity,
			.mobileFriction = mobileFrictionSum/volumeSum,
		};
	}

	pub fn collideOrStep(comptime side: main.sync.Side, comptime dir: Direction, amount: f64, pos: Vec3d, hitBox: Box, steppingHeight: f64) Vec3d {
		const index = @intFromEnum(dir);

		// First argument is amount we end up moving in dir, second argument is how far up we step
		var resultingMovement: Vec3d = .{0, 0, 0};
		resultingMovement[index] = amount;
		var checkPos = pos;
		checkPos[index] += amount;

		if (collision.collides(side, dir, -amount, checkPos, hitBox)) |box| {
			const newFloor = box.max[2] + hitBox.max[2];
			const heightDifference = newFloor - checkPos[2];
			if (heightDifference <= steppingHeight) {
				// If we collide but might be able to step up
				checkPos[2] = newFloor;
				if (collision.collides(side, dir, -amount, checkPos, hitBox) == null) {
					// If there's no new collision then we can execute the step-up
					resultingMovement[2] = heightDifference;
					return resultingMovement;
				}
			}

			// Otherwise move as close to the container as possible
			if (amount < 0) {
				resultingMovement[index] = box.max[index] - hitBox.min[index] - pos[index];
			} else {
				resultingMovement[index] = box.min[index] - hitBox.max[index] - pos[index];
			}
		}

		return resultingMovement;
	}

	fn isBlockIntersecting(block: main.blocks.Block, posX: i32, posY: i32, posZ: i32, center: Vec3d, extent: Vec3d) bool {
		const model = block.mode().model(block).model();
		const position = Vec3d{@floatFromInt(posX), @floatFromInt(posY), @floatFromInt(posZ)};
		const entityBox = Box{.min = center - extent, .max = center + extent};
		for (model.collision) |relativeBlockCollision| {
			const blockBox = Box{.min = position + relativeBlockCollision.min, .max = position + relativeBlockCollision.max};
			if (blockBox.intersects(entityBox)) {
				return true;
			}
		}

		return false;
	}

	pub fn touchBlocks(comptime side: main.sync.Side, entity: *main.server.Entity, hitBox: Box, deltaTime: f64) void {
		const boundingBox: Box = .{.min = entity.pos + hitBox.min, .max = entity.pos + hitBox.max};

		const minX: i32 = @floor(boundingBox.min[0] - 0.01);
		const maxX: i32 = @floor(boundingBox.max[0] + 0.01);
		const minY: i32 = @floor(boundingBox.min[1] - 0.01);
		const maxY: i32 = @floor(boundingBox.max[1] + 0.01);
		const minZ: i32 = @floor(boundingBox.min[2] - 0.01);
		const maxZ: i32 = @floor(boundingBox.max[2] + 0.01);

		const center: Vec3d = boundingBox.center();
		const extent: Vec3d = boundingBox.extent();

		const extentX: Vec3d = extent + Vec3d{0.01, -0.01, -0.01};
		const extentY: Vec3d = extent + Vec3d{-0.01, 0.01, -0.01};
		const extentZ: Vec3d = extent + Vec3d{-0.01, -0.01, 0.01};

		var posX: i32 = minX;
		while (posX <= maxX) : (posX += 1) {
			var posY: i32 = minY;
			while (posY <= maxY) : (posY += 1) {
				var posZ: i32 = minZ;
				while (posZ <= maxZ) : (posZ += 1) {
					const block = main.game.getBlockWithSide(side, posX, posY, posZ);
					if (block == null or block.?.onTouch().isNoop())
						continue;
					const touchX: bool = isBlockIntersecting(block.?, posX, posY, posZ, center, extentX);
					const touchY: bool = isBlockIntersecting(block.?, posX, posY, posZ, center, extentY);
					const touchZ: bool = isBlockIntersecting(block.?, posX, posY, posZ, center, extentZ);
					if (touchX or touchY or touchZ) {
						_ = block.?.onTouch().run(.{.entity = entity, .source = block.?, .blockPos = .{posX, posY, posZ}, .deltaTime = deltaTime});
					}
				}
			}
		}
	}
};

pub const FrictionState = struct {
	current: f32,
	mobile: f32,
};

pub fn calculateVolumeProperties(comptime side: main.sync.Side, volumeProperties: *collision.VolumeProperties, pos: @Vector(3, f64), hitBox: collision.Box, airTerminalVelocity: f64) void {
	if (main.game.getBlockWithSide(side, @floor(pos[0]), @floor(pos[1]), @floor(pos[2])) != null) {
		volumeProperties.* = collision.calculateVolumeProperties(side, pos, hitBox, .{.density = airDensity, .terminalVelocity = airTerminalVelocity, .maxDensity = airDensity, .mobileFriction = 1.0/airTerminalVelocity});
	}
}

pub fn calculateFriction(comptime side: main.sync.Side, volumeProperties: *const collision.VolumeProperties, friction: *FrictionState, pos: @Vector(3, f64), hitBox: collision.Box, onGround: bool) void {
	if (main.game.getBlockWithSide(side, @floor(pos[0]), @floor(pos[1]), @floor(pos[2])) != null) {
		const groundFriction = if (!onGround) 0 else collision.calculateSurfaceProperties(side, pos, hitBox, 20).friction;
		const volumeFrictionCoeffecient: f32 = @floatCast(baseGravity/volumeProperties.terminalVelocity);
		const mobileFriction: f32 = @floatCast(baseGravity*volumeProperties.mobileFriction);
		friction.current = groundFriction + volumeFrictionCoeffecient;
		friction.mobile = groundFriction + mobileFriction;
	}
}

pub fn calculateMotion(comptime side: main.sync.Side, deltaTime: f64, friction: FrictionState, volumeProperties: collision.VolumeProperties, density: f64, pos: Vec3d, velocity: *Vec3d, inputAcc: Vec3d, gravity: f64, jumpHeight: f64) Vec3d {
	var move: Vec3d = .{0, 0, 0};

	if (main.game.getBlockWithSide(side, @floor(pos[0]), @floor(pos[1]), @floor(pos[2])) != null) {
		const effectiveGravity = gravity*(density - volumeProperties.density)/density;
		const volumeFrictionCoeffecient: f32 = @floatCast(baseGravity/volumeProperties.terminalVelocity);

		var acc = inputAcc;
		acc[2] -= effectiveGravity;

		const baseFrictionCoefficient: f32 = friction.current;

		// This our model for movement on a single frame:
		// dv/dt = a - λ·v
		// dx/dt = v
		// Where a is the acceleration and λ is the friction coefficient
		inline for (0..3) |i| {
			var frictionCoefficient = baseFrictionCoefficient;
			if (i == 2 and jumpHeight > 0.0) { // No friction while jumping
				// Here we want to ensure a specified jump height under air friction.
				const jumpVelocity = @sqrt(jumpHeight*baseGravity*2);
				velocity[i] = @max(jumpVelocity, velocity[i] + jumpVelocity);
				frictionCoefficient = volumeFrictionCoeffecient;
			}
			const v_0 = velocity[i];
			const a = acc[i];
			// Here the solution can be easily derived:
			// dv/dt = a - λ·v
			// (1 - a)/v dv = -λ dt
			// (1 - a)ln(v) + C = -λt
			// v(t) = a/λ + c_1 e^(λ (-t))
			// v(0) = a/λ + c_1 = v₀
			// c_1 = v₀ - a/λ
			// x(t) = ∫v(t) dt
			// x(t) = ∫a/λ + c_1 e^(λ (-t)) dt
			// x(t) = a/λt - c_1/λ e^(λ (-t)) + C
			// With x(0) = 0 we get C = c_1/λ
			// x(t) = a/λt - c_1/λ e^(λ (-t)) + c_1/λ
			const c_1 = v_0 - a/frictionCoefficient;
			velocity[i] = a/frictionCoefficient + c_1*@exp(-frictionCoefficient*deltaTime);
			move[i] = a/frictionCoefficient*deltaTime - c_1/frictionCoefficient*@exp(-frictionCoefficient*deltaTime) + c_1/frictionCoefficient;
		}
	}
	return move;
}

pub fn calculateEyeMovement(comptime side: main.sync.Side, deltaTime: f64, pos: Vec3d, vel: Vec3d, eye: *Player.EyeData, stepAmount: f64) void {
	if (main.game.getBlockWithSide(side, @floor(pos[0]), @floor(pos[1]), @floor(pos[2])) != null) {
		var directionalFrictionCoefficients: Vec3f = @splat(0);
		var acc: Vec3d = @splat(0);
		// Apply springs to the eye position:
		var springConstants = Vec3d{0, 0, 0};
		{
			const forceMultipliers = Vec3d{
				400,
				400,
				400,
			};
			const frictionMultipliers = Vec3d{
				30,
				30,
				30,
			};
			const strength = (-eye.pos)/(eye.box.max - eye.box.min);
			const force = strength*forceMultipliers;
			const friction = frictionMultipliers;
			springConstants += forceMultipliers/(eye.box.max - eye.box.min);
			directionalFrictionCoefficients += @floatCast(friction);
			acc += force;
		}

		// This our model for movement of the eye position on a single frame:
		// dv/dt = a - k*x - λ·v
		// dx/dt = v
		// Where a is the acceleration, k is the spring constant and λ is the friction coefficient
		inline for (0..3) |i| blk: {
			if (eye.step[i]) {
				const oldPos = eye.pos[i];
				const newPos = oldPos + eye.vel[i]*deltaTime;
				if (newPos*std.math.sign(eye.vel[i]) <= -0.1) {
					eye.pos[i] = newPos;
					break :blk;
				} else {
					eye.step[i] = false;
				}
			}
			if (i == 2 and eye.coyote > 0) {
				break :blk;
			}
			const frictionCoefficient = directionalFrictionCoefficients[i];
			const v_0 = eye.vel[i];
			const k = springConstants[i];
			const a = acc[i];
			// here we need to solve the full equation:
			// The solution of this differential equation is given by
			// x(t) = a/k + c_1 e^(1/2 t (-c_3 - λ)) + c_2 e^(1/2 t (c_3 - λ))
			// With c_3 = sqrt(λ^2 - 4 k) which can be imaginary
			// v(t) is just the derivative, given by
			// v(t) = 1/2 (-c_3 - λ) c_1 e^(1/2 t (-c_3 - λ)) + (1/2 (c_3 - λ)) c_2 e^(1/2 t (c_3 - λ))
			// Now for simplicity we set x(0) = 0 and v(0) = v₀
			// a/k + c_1 + c_2 = 0 → c_1 = -a/k - c_2
			// (-c_3 - λ) c_1 + (c_3 - λ) c_2 = 2v₀
			// → (-c_3 - λ) (-a/k - c_2) + (c_3 - λ) c_2 = 2v₀
			// → (-c_3 - λ) (-a/k) - (-c_3 - λ)c_2 + (c_3 - λ) c_2 = 2v₀
			// → ((c_3 - λ) - (-c_3 - λ))c_2 = 2v₀ - (c_3 + λ) (a/k)
			// → (c_3 - λ + c_3 + λ)c_2 = 2v₀ - (c_3 + λ) (a/k)
			// → 2 c_3 c_2 = 2v₀ - (c_3 + λ) (a/k)
			// → c_2 = (2v₀ - (c_3 + λ) (a/k))/(2 c_3)
			// → c_2 = v₀/c_3 - (1 + λ/c_3)/2 (a/k)
			// In total we get:
			// c_3 = sqrt(λ^2 - 4 k)
			// c_2 = (2v₀ - (c_3 + λ) (a/k))/(2 c_3)
			// c_1 = -a/k - c_2
			const c_3 = vec.Complex.fromSqrt(frictionCoefficient*frictionCoefficient - 4*k);
			const c_2 = (((c_3.addScalar(frictionCoefficient).mulScalar(-a/k)).addScalar(2*v_0)).div(c_3.mulScalar(2)));
			const c_1 = c_2.addScalar(a/k).negate();
			// v(t) = 1/2 (-c_3 - λ) c_1 e^(1/2 t (-c_3 - λ)) + (1/2 (c_3 - λ)) c_2 e^(1/2 t (c_3 - λ))
			// x(t) = a/k + c_1 e^(1/2 t (-c_3 - λ)) + c_2 e^(1/2 t (c_3 - λ))
			const firstTerm = c_1.mul((c_3.negate().subScalar(frictionCoefficient)).mulScalar(deltaTime/2).exp());
			const secondTerm = c_2.mul((c_3.subScalar(frictionCoefficient)).mulScalar(deltaTime/2).exp());
			eye.vel[i] = firstTerm.mul(c_3.negate().subScalar(frictionCoefficient).mulScalar(0.5)).add(secondTerm.mul((c_3.subScalar(frictionCoefficient)).mulScalar(0.5))).val[0];
			eye.pos[i] += firstTerm.add(secondTerm).addScalar(a/k).val[0];
		}
	}

	if (stepAmount > 0) {
		if (eye.coyote <= 0) {
			eye.vel[2] = @max(1.5*vec.length(vel), eye.vel[2], 4);
			eye.step[2] = true;
			if (vel[2] > 0) {
				eye.vel[2] = vel[2];
				eye.step[2] = false;
			}
		} else {
			eye.coyote = 0;
		}
		eye.pos[2] -= stepAmount;
	}
}

pub fn calculateWallCollision(comptime side: main.sync.Side, motion: *Vec3d, pos: *Vec3d, vel: *Vec3d, onGround: *bool, frictionState: FrictionState, hitBox: collision.Box, steppingHeight: f64, steppingHeightLimit: ?f64, crouching: bool) f64 {
	var adjustedSteppingHeight = steppingHeight;
	if (vel[2] > 0) {
		adjustedSteppingHeight = vel[2]*vel[2]/baseGravity/2;
	}
	if (steppingHeightLimit) |limit| {
		adjustedSteppingHeight = @min(adjustedSteppingHeight, limit);
	}
	const slipLimit = 0.25*frictionState.current;

	const xMovement = collision.collideOrStep(side, .x, motion[0], pos.*, hitBox, adjustedSteppingHeight);
	pos.* += xMovement;
	if (crouching and onGround.* and @abs(vel[0]) < slipLimit) {
		if (collision.collides(side, .x, 0, pos.* - Vec3d{0, 0, 1}, hitBox) == null) {
			pos.* -= xMovement;
			vel[0] = 0;
		}
	}

	const yMovement = collision.collideOrStep(side, .y, motion[1], pos.*, hitBox, adjustedSteppingHeight);
	pos.* += yMovement;
	if (crouching and onGround.* and @abs(vel[1]) < slipLimit) {
		if (collision.collides(side, .y, 0, pos.* - Vec3d{0, 0, 1}, hitBox) == null) {
			pos.* -= yMovement;
			vel[1] = 0;
		}
	}

	if (xMovement[0] != motion[0]) {
		vel[0] = 0;
	}
	if (yMovement[1] != motion[1]) {
		vel[1] = 0;
	}

	const stepAmount = xMovement[2] + yMovement[2];
	if (stepAmount > 0) {
		motion[2] = -0.01;
		onGround.* = true;
	}
	return stepAmount;
}

pub fn calculateVerticalCollision(comptime side: main.sync.Side, deltaTime: f64, pos: *Vec3d, vel: *Vec3d, jumpCoyote: ?*f64, onGround: *bool, hitBox: collision.Box, motion: Vec3d, bouncinessMultiplier: f64) bool {
	const wasOnGround = onGround.*;
	onGround.* = false;
	pos[2] += motion[2];

	if (collision.collides(side, .z, -motion[2], pos.*, hitBox)) |box| {
		if (motion[2] < 0) {
			onGround.* = true;
			pos[2] = box.max[2] - hitBox.min[2];
		} else {
			pos[2] = box.min[2] - hitBox.max[2];
		}
		const bounciness = if (bouncinessMultiplier == 0) 0 else collision.calculateSurfaceProperties(side, pos.*, hitBox, 0.0).bounciness*bouncinessMultiplier;

		if (bounciness != 0.0 and vel[2] < -3.0) {
			vel[2] = -vel[2]*bounciness;
			if (jumpCoyote) |coyote| {
				coyote.* = Player.jumpCoyoteTimeConstant + deltaTime;
			}
		} else {
			vel[2] = 0;
		}

		// Always unstuck upwards for now
		while (collision.collides(side, .z, 0, pos.*, hitBox)) |_| {
			pos[2] += 1;
		}
		return true;
	} else {
		if (wasOnGround and motion[2] < 0 and jumpCoyote != null) {
			jumpCoyote.?.* = Player.jumpCoyoteTimeConstant + deltaTime;
		}
		return false;
	}
}

pub fn calculateVerticalCollisionEyeMovement(deltaTime: f64, eye: *Player.EyeData, didCollide: bool, onGround: bool, wasOnGround: bool, prevPos: Vec3d, pos: Vec3d, prevVel: Vec3d, vel: Vec3d, motion: Vec3d, steppingHeight: f64) void {
	if (didCollide) {
		if (onGround) {
			if (!wasOnGround) {
				eye.vel[2] = prevVel[2];
				eye.pos[2] -= pos[2] - prevPos[2] - motion[2];
			}
			eye.coyote = 0.0;
		}
		if (vel[2] != 0.0) {
			eye.vel[2] *= 2.0;
		}
	} else if (wasOnGround and motion[2] < 0) {
		// If the player drops off a ledge, they might just be walking over a small gap, so lock the y position of the eyes that long.
		// This calculates how long the player has to fall until we know they're not walking over a small gap.
		// We add deltaTime because we subtract deltaTime at the bottom of update
		eye.coyote = @sqrt(2*steppingHeight/baseGravity) + deltaTime;
		eye.pos[2] -= motion[2];
	} else if (Player.eye.coyote > 0) {
		eye.pos[2] -= motion[2];
	}
}
