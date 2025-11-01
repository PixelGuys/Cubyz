const std = @import("std");

const items = @import("items.zig");
const Inventory = items.Inventory;
const main = @import("main");
const vec = @import("vec.zig");
const Vec2f = vec.Vec2f;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const settings = @import("settings.zig");
const collision = main.game.collision;
const Player = main.game.Player;
const camera = main.game.camera;

pub const PhysicsState = struct {
	pos: Vec3d,
	vel: Vec3d,
	volumeProperties: collision.VolumeProperties = undefined,
	currentFriction: f32 = undefined,
	onGround: bool = false,
	jumpCoyote: f64 = 0,
	eyeData: ?Player.EyeData = null,
	fallDamage: f32 = 0.0,

	pub fn fromPlayer() PhysicsState {
		return .{
			.pos = Player.super.pos,
			.vel = Player.super.vel,
			.volumeProperties = Player.volumeProperties,
			.currentFriction = Player.currentFriction,
			.onGround = Player.onGround,
			.eyeData = Player.eyeData,
		};
	}
	pub fn toPlayer(self: PhysicsState) void {
		Player.mutex.lock();
		defer Player.mutex.unlock();
		Player.super.pos = self.pos;
		Player.super.vel = self.vel;
		Player.volumeProperties = self.volumeProperties;
		Player.currentFriction = self.currentFriction;
		Player.onGround = self.onGround;
		Player.eyeData = self.eyeData.?;
		Inventory.Sync.addHealth(-self.fallDamage, .fall, .client, Player.id);
	}
};

pub const InputState = struct {
	steppingHeight: Vec3d = .{0.0, 0.0, 0.0},
	movementForce: Vec3d = .{0.0, 0.0, 0.0},
	jumping: bool = false,
	crouching: bool = false,
	jumpHeight: f64 = 0.0,
	isFlying: bool = false,
	hasCollision: bool = true,
	boundingBox: collision.Box = collision.Box.point,
	gravity: f64 = 30.0,
	airTerminalVelocity: f64 = 90.0,
	density: f64 = 1.2,

	pub fn fromPlayer() InputState {
		return .{
			.crouching = Player.crouching,
			.jumpHeight = Player.jumpHeight,
			.steppingHeight = Player.steppingHeight(),
			.isFlying = Player.isFlying.load(.monotonic),
			.hasCollision = !Player.isGhost.load(.monotonic),
			.boundingBox = Player.outerBoundingBox,
		};
	}
};

pub fn calculateProperties(physicsState: *PhysicsState, inputState: InputState, comptime side: main.utils.Side) void {
	if(side == .server or main.renderer.mesh_storage.getBlockFromRenderThread(@intFromFloat(@floor(physicsState.pos[0])), @intFromFloat(@floor(physicsState.pos[1])), @intFromFloat(@floor(physicsState.pos[2]))) != null) {
		physicsState.volumeProperties = collision.calculateVolumeProperties(side, physicsState.pos, inputState.boundingBox, .{.density = 0.001, .terminalVelocity = inputState.airTerminalVelocity, .maxDensity = 0.001, .mobility = 1.0});

		const groundFriction = if(!physicsState.onGround and !inputState.isFlying) 0 else collision.calculateSurfaceProperties(side, physicsState.pos, inputState.boundingBox, 20).friction;
		const volumeFrictionCoeffecient: f32 = @floatCast(inputState.gravity/physicsState.volumeProperties.terminalVelocity);
		physicsState.currentFriction = if(inputState.isFlying) 20 else groundFriction + volumeFrictionCoeffecient;
	}
}

pub fn update(deltaTime: f64, physicsState: *PhysicsState, inputState: InputState, comptime side: main.utils.Side) void { // MARK: update()
	var move: Vec3d = .{0, 0, 0};
	if(side == .server or main.renderer.mesh_storage.getBlockFromRenderThread(@intFromFloat(@floor(physicsState.pos[0])), @intFromFloat(@floor(physicsState.pos[1])), @intFromFloat(@floor(physicsState.pos[2]))) != null) {
		const effectiveGravity = inputState.gravity*(inputState.density - physicsState.volumeProperties.density)/inputState.density;
		const volumeFrictionCoeffecient: f32 = @floatCast(inputState.gravity/physicsState.volumeProperties.terminalVelocity);
		var acc = inputState.movementForce;
		if(!inputState.isFlying) {
			acc[2] -= effectiveGravity;
		}

		const baseFrictionCoefficient: f32 = physicsState.currentFriction;
		var directionalFrictionCoefficients: Vec3f = @splat(0);

		// This our model for movement on a single frame:
		// dv/dt = a - λ·v
		// dx/dt = v
		// Where a is the acceleration and λ is the friction coefficient
		inline for(0..3) |i| {
			var frictionCoefficient = baseFrictionCoefficient + directionalFrictionCoefficients[i];
			if(i == 2 and inputState.jumping) { // No friction while jumping
				// Here we want to ensure a specified jump height under air friction.
				const jumpVelocity = @sqrt(inputState.jumpHeight*inputState.gravity*2);
				physicsState.vel[i] = @max(jumpVelocity, physicsState.vel[i] + jumpVelocity);
				frictionCoefficient = volumeFrictionCoeffecient;
			}
			const v_0 = physicsState.vel[i];
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
			physicsState.vel[i] = a/frictionCoefficient + c_1*@exp(-frictionCoefficient*deltaTime);
			move[i] = a/frictionCoefficient*deltaTime - c_1/frictionCoefficient*@exp(-frictionCoefficient*deltaTime) + c_1/frictionCoefficient;
		}

		if(physicsState.eyeData) |*eyeData| {
			acc = @splat(0);
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
				const strength = (-eyeData.pos)/(eyeData.box.max - eyeData.box.min);
				const force = strength*forceMultipliers;
				const friction = frictionMultipliers;
				springConstants += forceMultipliers/(eyeData.box.max - eyeData.box.min);
				directionalFrictionCoefficients += @floatCast(friction);
				acc += force;
			}

			// This our model for movement of the eye position on a single frame:
			// dv/dt = a - k*x - λ·v
			// dx/dt = v
			// Where a is the acceleration, k is the spring constant and λ is the friction coefficient
			inline for(0..3) |i| blk: {
				if(eyeData.step[i]) {
					const oldPos = eyeData.pos[i];
					const newPos = oldPos + eyeData.vel[i]*deltaTime;
					if(newPos*std.math.sign(eyeData.vel[i]) <= -0.1) {
						eyeData.pos[i] = newPos;
						break :blk;
					} else {
						eyeData.step[i] = false;
					}
				}
				if(i == 2 and eyeData.coyote > 0) {
					break :blk;
				}
				const frictionCoefficient = directionalFrictionCoefficients[i];
				const v_0 = eyeData.vel[i];
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
				eyeData.vel[i] = firstTerm.mul(c_3.negate().subScalar(frictionCoefficient).mulScalar(0.5)).add(secondTerm.mul((c_3.subScalar(frictionCoefficient)).mulScalar(0.5))).val[0];
				eyeData.pos[i] += firstTerm.add(secondTerm).addScalar(a/k).val[0];
			}
		}
	}

	if(inputState.hasCollision) {
		const hitBox = inputState.boundingBox;
		var steppingHeight = inputState.steppingHeight[2];
		if(physicsState.vel[2] > 0) {
			steppingHeight = physicsState.vel[2]*physicsState.vel[2]/inputState.gravity/2;
		}
		if(physicsState.eyeData) |eyeData| {
			steppingHeight = @min(steppingHeight, eyeData.pos[2] - eyeData.box.min[2]);
		}

		const slipLimit = 0.25*physicsState.currentFriction;

		const xMovement = collision.collideOrStep(side, .x, move[0], physicsState.pos, hitBox, steppingHeight);
		physicsState.pos += xMovement;
		if(inputState.crouching and physicsState.onGround and @abs(physicsState.vel[0]) < slipLimit) {
			if(collision.collides(side, .x, 0, physicsState.pos - Vec3d{0, 0, 1}, hitBox) == null) {
				physicsState.pos -= xMovement;
				physicsState.vel[0] = 0;
			}
		}

		const yMovement = collision.collideOrStep(side, .y, move[1], physicsState.pos, hitBox, steppingHeight);
		physicsState.pos += yMovement;
		if(inputState.crouching and physicsState.onGround and @abs(physicsState.vel[1]) < slipLimit) {
			if(collision.collides(side, .y, 0, physicsState.pos - Vec3d{0, 0, 1}, hitBox) == null) {
				physicsState.pos -= yMovement;
				physicsState.vel[1] = 0;
			}
		}

		if(xMovement[0] != move[0]) {
			physicsState.vel[0] = 0;
		}
		if(yMovement[1] != move[1]) {
			physicsState.vel[1] = 0;
		}

		const stepAmount = xMovement[2] + yMovement[2];
		if(stepAmount > 0) {
			if(physicsState.eyeData) |*eyeData| {
				if(eyeData.coyote <= 0) {
					eyeData.vel[2] = @max(1.5*vec.length(physicsState.vel), eyeData.vel[2], 4);
					eyeData.step[2] = true;
					if(physicsState.vel[2] > 0) {
						eyeData.vel[2] = physicsState.vel[2];
						eyeData.step[2] = false;
					}
				} else {
					eyeData.coyote = 0;
				}
				eyeData.pos[2] -= stepAmount;
			}
			move[2] = -0.01;
			physicsState.onGround = true;
		}

		const wasOnGround = physicsState.onGround;
		physicsState.onGround = false;
		physicsState.pos[2] += move[2];
		if(collision.collides(side, .z, -move[2], physicsState.pos, hitBox)) |box| {
			if(move[2] < 0) {
				if(physicsState.eyeData) |*eyeData| {
					if(!wasOnGround) {
						eyeData.vel[2] = physicsState.vel[2];
						eyeData.pos[2] -= (box.max[2] - hitBox.min[2] - physicsState.pos[2]);
					}
					eyeData.coyote = 0;
				}
				physicsState.onGround = true;
				physicsState.pos[2] = box.max[2] - hitBox.min[2];
			} else {
				physicsState.pos[2] = box.min[2] - hitBox.max[2];
			}
			var bounciness = if(inputState.isFlying) 0 else collision.calculateSurfaceProperties(side, physicsState.pos, inputState.boundingBox, 0.0).bounciness;
			if(inputState.crouching) {
				bounciness *= 0.5;
			}
			var velocityChange: f64 = undefined;

			if(bounciness != 0.0 and physicsState.vel[2] < -3.0) {
				velocityChange = physicsState.vel[2]*@as(f64, @floatCast(1 - bounciness));
				physicsState.vel[2] = -physicsState.vel[2]*bounciness;
				physicsState.jumpCoyote = Player.jumpCoyoteTimeConstant + deltaTime;
				if(physicsState.eyeData) |*eyeData| {
					eyeData.vel[2] *= 2;
				}
			} else {
				velocityChange = physicsState.vel[2];
				physicsState.vel[2] = 0;
			}
			const damage: f32 = @floatCast(@round(@max((velocityChange*velocityChange)/(2*inputState.gravity) - 7, 0))/2);
			if(damage > 0.01) {
				physicsState.fallDamage += damage;
			}

			// Always unstuck upwards for now
			while(collision.collides(side, .z, 0, physicsState.pos, hitBox)) |_| {
				physicsState.pos[2] += 1;
			}
		} else if(wasOnGround and move[2] < 0) {
			// If the physicsState drops off a ledge, they might just be walking over a small gap, so lock the y position of the eyes that long.
			// This calculates how long the physicsState has to fall until we know they're not walking over a small gap.
			// We add deltaTime because we subtract deltaTime at the bottom of update
			physicsState.jumpCoyote = Player.jumpCoyoteTimeConstant + deltaTime;
			if(physicsState.eyeData) |*eyeData| {
				eyeData.coyote = @sqrt(2*inputState.steppingHeight[2]/inputState.gravity) + deltaTime;
				eyeData.pos[2] -= move[2];
			}
		} else if(physicsState.eyeData) |*eyeData| {
			if(eyeData.coyote > 0) {
				eyeData.pos[2] -= move[2];
			}
		}
	} else {
		physicsState.pos += move;
	}

	// Clamp the eyePosition and subtract eye coyote time.
	if(physicsState.eyeData) |*eyeData| {
		eyeData.pos = @max(eyeData.box.min, @min(eyeData.pos, eyeData.box.max));
		eyeData.coyote -= deltaTime;
	}
	physicsState.jumpCoyote -= deltaTime;
}
