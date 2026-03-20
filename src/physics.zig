const std = @import("std");

const items = @import("items.zig");
const main = @import("main");
const vec = @import("vec.zig");
const Vec2f = vec.Vec2f;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const settings = @import("settings.zig");
const Player = main.game.Player;
const collision = main.game.collision;
const camera = main.game.camera;

pub const gravity = 30.0;
pub const airTerminalVelocity = 90.0;
pub const airDensity = 0.001;
const playerDensity = 1.2;

pub const PhysicsState = struct {
	pos: Vec3d,
	vel: Vec3d,
	volumeProperties: collision.VolumeProperties = .{.density = 0, .maxDensity = 0, .mobileFriction = 0, .terminalVelocity = 0},
	currentFriction: f32 = 0,
	mobileFriction: f32 = 0,
	onGround: bool = false,
	jumpCoyote: f64 = 0,
	eye: ?*Player.EyeData = null,
	fallDamage: f32 = 0.0,

	pub fn fromPlayer() PhysicsState {
		return .{
			.pos = Player.super.pos,
			.vel = Player.super.vel,
			.volumeProperties = Player.volumeProperties,
			.currentFriction = Player.currentFriction,
			.mobileFriction = Player.mobileFriction,
			.onGround = Player.onGround,
			.jumpCoyote = Player.jumpCoyote,
			.eye = &Player.eye,
		};
	}

	pub fn toPlayer(self: PhysicsState) void {
		Player.mutex.lock();
		defer Player.mutex.unlock();
		Player.super.pos = self.pos;
		Player.super.vel = self.vel;
		Player.volumeProperties = self.volumeProperties;
		Player.currentFriction = self.currentFriction;
		Player.mobileFriction = self.mobileFriction;
		Player.onGround = self.onGround;
		Player.jumpCoyote = self.jumpCoyote;
	}
};

pub const InputState = struct {
	boundingBox: collision.Box = .{.min = @splat(0), .max = @splat(0)},
	movementForce: Vec3d = .{0, 0, 0},
	jumping: bool = false,
	crouching: bool = false,
	isFlying: bool = false,
	isGhost: bool = false,
	entityGravity: f64 = gravity,
	entityDensity: f64 = playerDensity,
	steppingHeight: Vec3d = .{0, 0, 0},
	jumpHeight: f64 = Player.jumpHeight,
	hasCollision: bool = true,
	runTouchBlocks: bool = false,
	entity: ?*main.server.Entity = null,
};

const volumeDefaults: collision.VolumeProperties = .{
	.density = airDensity,
	.terminalVelocity = airTerminalVelocity,
	.maxDensity = airDensity,
	.mobileFriction = 1.0/airTerminalVelocity,
};

pub fn calculateProperties(state: *PhysicsState, input: InputState, comptime side: main.utils.Side) void {
	state.volumeProperties = collision.calculateVolumeProperties(side, state.pos, input.boundingBox, volumeDefaults);
	const groundFriction = if (!state.onGround and !input.isFlying) 0 else collision.calculateSurfaceProperties(side, state.pos, input.boundingBox, 20).friction;
	const volumeFrictionCoeffecient: f32 = @floatCast(input.entityGravity/state.volumeProperties.terminalVelocity);
	const mobileFriction: f32 = @floatCast(input.entityGravity*state.volumeProperties.mobileFriction);
	state.currentFriction = if (input.isFlying) 20 else groundFriction + volumeFrictionCoeffecient;
	state.mobileFriction = if (input.isFlying) 20 else groundFriction + mobileFriction;
}

pub fn update(deltaTime: f64, state: *PhysicsState, input: InputState, comptime side: main.utils.Side) void { // MARK: update()
	var move: Vec3d = .{0, 0, 0};
	if (side == .server or main.renderer.mesh_storage.getBlockFromRenderThread(@intFromFloat(@floor(state.pos[0])), @intFromFloat(@floor(state.pos[1])), @intFromFloat(@floor(state.pos[2]))) != null) {
		const effectiveGravity = input.entityGravity*(input.entityDensity - state.volumeProperties.density)/input.entityDensity;
		const volumeFrictionCoeffecient: f32 = @floatCast(input.entityGravity/state.volumeProperties.terminalVelocity);
		var acc = input.movementForce;
		if (!input.isFlying) {
			acc[2] -= effectiveGravity;
		}

		const baseFrictionCoefficient: f32 = state.currentFriction;
		var directionalFrictionCoefficients: Vec3f = @splat(0);

		// This our model for movement on a single frame:
		// dv/dt = a - λ·v
		// dx/dt = v
		// Where a is the acceleration and λ is the friction coefficient
		inline for (0..3) |i| {
			var frictionCoefficient = baseFrictionCoefficient + directionalFrictionCoefficients[i];
			if (i == 2 and input.jumping) { // No friction while jumping
				// Here we want to ensure a specified jump height under air friction.
				const jumpVelocity = @sqrt(input.jumpHeight*input.entityGravity*2);
				state.vel[i] = @max(jumpVelocity, state.vel[i] + jumpVelocity);
				frictionCoefficient = volumeFrictionCoeffecient;
			}
			const v_0 = state.vel[i];
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
			state.vel[i] = a/frictionCoefficient + c_1*@exp(-frictionCoefficient*deltaTime);
			move[i] = a/frictionCoefficient*deltaTime - c_1/frictionCoefficient*@exp(-frictionCoefficient*deltaTime) + c_1/frictionCoefficient;
		}

		if (state.eye) |eyeData| {
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
			inline for (0..3) |i| blk: {
				if (eyeData.step[i]) {
					const oldPos = eyeData.pos[i];
					const newPos = oldPos + eyeData.vel[i]*deltaTime;
					if (newPos*std.math.sign(eyeData.vel[i]) <= -0.1) {
						eyeData.pos[i] = newPos;
						break :blk;
					} else {
						eyeData.step[i] = false;
					}
				}
				if (i == 2 and eyeData.coyote > 0) {
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

	if (input.hasCollision) {
		const hitBox = input.boundingBox;
		var steppingHeight = input.steppingHeight[2];
		if (state.vel[2] > 0) {
			steppingHeight = state.vel[2]*state.vel[2]/input.entityGravity/2;
		}
		if (state.eye) |eyeData| {
			steppingHeight = @min(steppingHeight, eyeData.pos[2] - eyeData.box.min[2]);
		}

		const slipLimit = 0.25*state.currentFriction;

		const xMovement = collision.collideOrStep(side, .x, move[0], state.pos, hitBox, steppingHeight);
		state.pos += xMovement;
		if (input.crouching and state.onGround and @abs(state.vel[0]) < slipLimit) {
			if (collision.collides(side, .x, 0, state.pos - Vec3d{0, 0, 1}, hitBox) == null) {
				state.pos -= xMovement;
				state.vel[0] = 0;
			}
		}

		const yMovement = collision.collideOrStep(side, .y, move[1], state.pos, hitBox, steppingHeight);
		state.pos += yMovement;
		if (input.crouching and state.onGround and @abs(state.vel[1]) < slipLimit) {
			if (collision.collides(side, .y, 0, state.pos - Vec3d{0, 0, 1}, hitBox) == null) {
				state.pos -= yMovement;
				state.vel[1] = 0;
			}
		}

		if (xMovement[0] != move[0]) {
			state.vel[0] = 0;
		}
		if (yMovement[1] != move[1]) {
			state.vel[1] = 0;
		}

		const stepAmount = xMovement[2] + yMovement[2];
		if (stepAmount > 0) {
			if (state.eye) |eyeData| {
				if (eyeData.coyote <= 0) {
					eyeData.vel[2] = @max(1.5*vec.length(state.vel), eyeData.vel[2], 4);
					eyeData.step[2] = true;
					if (state.vel[2] > 0) {
						eyeData.vel[2] = state.vel[2];
						eyeData.step[2] = false;
					}
				} else {
					eyeData.coyote = 0;
				}
				eyeData.pos[2] -= stepAmount;
			}
			move[2] = -0.01;
			state.onGround = true;
		}

		const wasOnGround = state.onGround;
		state.onGround = false;
		state.pos[2] += move[2];
		if (collision.collides(side, .z, -move[2], state.pos, hitBox)) |box| {
			if (move[2] < 0) {
				if (state.eye) |eyeData| {
					if (!wasOnGround) {
						eyeData.vel[2] = state.vel[2];
						eyeData.pos[2] -= (box.max[2] - hitBox.min[2] - state.pos[2]);
					}
					eyeData.coyote = 0;
				}
				state.onGround = true;
				state.pos[2] = box.max[2] - hitBox.min[2];
			} else {
				state.pos[2] = box.min[2] - hitBox.max[2];
			}
			var bounciness = if (input.isFlying) 0 else collision.calculateSurfaceProperties(side, state.pos, input.boundingBox, 0.0).bounciness;
			if (input.crouching) {
				bounciness *= 0.5;
			}
			var velocityChange: f64 = undefined;

			if (bounciness != 0.0 and state.vel[2] < -3.0) {
				velocityChange = state.vel[2]*@as(f64, @floatCast(1 - bounciness));
				state.vel[2] = -state.vel[2]*bounciness;
				state.jumpCoyote = Player.jumpCoyoteTimeConstant + deltaTime;
				if (state.eye) |eyeData| {
					eyeData.vel[2] *= 2;
				}
			} else {
				velocityChange = state.vel[2];
				state.vel[2] = 0;
			}
			const damage: f32 = @floatCast(@round(@max((velocityChange*velocityChange)/(2*input.entityGravity) - 7, 0))/2);
			if (damage > 0.01) {
				state.fallDamage += damage;
			}

			// Always unstuck upwards for now
			while (collision.collides(side, .z, 0, state.pos, hitBox)) |_| {
				state.pos[2] += 1;
			}
		} else if (wasOnGround and move[2] < 0) {
			// If the entity drops off a ledge, they might just be walking over a small gap, so lock the y position of the eyes that long.
			// This calculates how long the entity has to fall until we know they're not walking over a small gap.
			// We add deltaTime because we subtract deltaTime at the bottom of update
			state.jumpCoyote = Player.jumpCoyoteTimeConstant + deltaTime;
			if (state.eye) |eyeData| {
				eyeData.coyote = @sqrt(2*input.steppingHeight[2]/input.entityGravity) + deltaTime;
				eyeData.pos[2] -= move[2];
			}
		} else if (state.eye) |eyeData| {
			if (eyeData.coyote > 0) {
				eyeData.pos[2] -= move[2];
			}
		}
		if (input.runTouchBlocks) {
			if (input.entity) |entity| {
				collision.touchBlocks(entity, hitBox, side, deltaTime);
			}
		}
	} else {
		state.pos += move;
	}

	// Clamp the eye position and subtract eye coyote time.
	if (state.eye) |eyeData| {
		eyeData.pos = @max(eyeData.box.min, @min(eyeData.pos, eyeData.box.max));
		eyeData.coyote -= deltaTime;
	}
	state.jumpCoyote -= deltaTime;
}
