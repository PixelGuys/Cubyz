const std = @import("std");

const items = @import("items.zig");
const Inventory = items.Inventory;
const main = @import("main");
const vec = @import("vec.zig");
const Vec2f = vec.Vec2f;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const settings = @import("settings.zig");
const Player = main.game.Player;
const collision = main.game.collision;
const camera = main.game.camera;

const gravity = 30.0;
const airTerminalVelocity = 90.0;
const playerDensity = 1.2;

pub fn calculateProperties() void {
	if(main.renderer.mesh_storage.getBlockFromRenderThread(@intFromFloat(@floor(Player.super.pos[0])), @intFromFloat(@floor(Player.super.pos[1])), @intFromFloat(@floor(Player.super.pos[2]))) != null) {
		Player.volumeProperties = collision.calculateVolumeProperties(.client, Player.super.pos, Player.outerBoundingBox, .{.density = 0.001, .terminalVelocity = airTerminalVelocity, .maxDensity = 0.001, .mobility = 1.0});

		const groundFriction = if(!Player.onGround and !Player.isFlying.load(.monotonic)) 0 else collision.calculateSurfaceProperties(.client, Player.super.pos, Player.outerBoundingBox, 20).friction;
		const volumeFrictionCoeffecient: f32 = @floatCast(gravity/Player.volumeProperties.terminalVelocity);
		Player.currentFriction = if(Player.isFlying.load(.monotonic)) 20 else groundFriction + volumeFrictionCoeffecient;
	}
}

pub fn update(deltaTime: f64, inputAcc: Vec3d, jumping: bool) void { // MARK: update()
	var move: Vec3d = .{0, 0, 0};
	if(main.renderer.mesh_storage.getBlockFromRenderThread(@intFromFloat(@floor(Player.super.pos[0])), @intFromFloat(@floor(Player.super.pos[1])), @intFromFloat(@floor(Player.super.pos[2]))) != null) {
		const effectiveGravity = gravity*(playerDensity - Player.volumeProperties.density)/playerDensity;
		const volumeFrictionCoeffecient: f32 = @floatCast(gravity/Player.volumeProperties.terminalVelocity);
		var acc = inputAcc;
		if(!Player.isFlying.load(.monotonic)) {
			acc[2] -= effectiveGravity;
		}

		const baseFrictionCoefficient: f32 = Player.currentFriction;
		var directionalFrictionCoefficients: Vec3f = @splat(0);

		// This our model for movement on a single frame:
		// dv/dt = a - λ·v
		// dx/dt = v
		// Where a is the acceleration and λ is the friction coefficient
		inline for(0..3) |i| {
			var frictionCoefficient = baseFrictionCoefficient + directionalFrictionCoefficients[i];
			if(i == 2 and jumping) { // No friction while jumping
				// Here we want to ensure a specified jump height under air friction.
				const jumpVelocity = @sqrt(Player.jumpHeight*gravity*2);
				Player.super.vel[i] = @max(jumpVelocity, Player.super.vel[i] + jumpVelocity);
				frictionCoefficient = volumeFrictionCoeffecient;
			}
			const v_0 = Player.super.vel[i];
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
			Player.super.vel[i] = a/frictionCoefficient + c_1*@exp(-frictionCoefficient*deltaTime);
			move[i] = a/frictionCoefficient*deltaTime - c_1/frictionCoefficient*@exp(-frictionCoefficient*deltaTime) + c_1/frictionCoefficient;
		}

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
			const strength = (-Player.eye.pos)/(Player.eye.box.max - Player.eye.box.min);
			const force = strength*forceMultipliers;
			const friction = frictionMultipliers;
			springConstants += forceMultipliers/(Player.eye.box.max - Player.eye.box.min);
			directionalFrictionCoefficients += @floatCast(friction);
			acc += force;
		}

		// This our model for movement of the eye position on a single frame:
		// dv/dt = a - k*x - λ·v
		// dx/dt = v
		// Where a is the acceleration, k is the spring constant and λ is the friction coefficient
		inline for(0..3) |i| blk: {
			if(Player.eye.step[i]) {
				const oldPos = Player.eye.pos[i];
				const newPos = oldPos + Player.eye.vel[i]*deltaTime;
				if(newPos*std.math.sign(Player.eye.vel[i]) <= -0.1) {
					Player.eye.pos[i] = newPos;
					break :blk;
				} else {
					Player.eye.step[i] = false;
				}
			}
			if(i == 2 and Player.eye.coyote > 0) {
				break :blk;
			}
			const frictionCoefficient = directionalFrictionCoefficients[i];
			const v_0 = Player.eye.vel[i];
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
			Player.eye.vel[i] = firstTerm.mul(c_3.negate().subScalar(frictionCoefficient).mulScalar(0.5)).add(secondTerm.mul((c_3.subScalar(frictionCoefficient)).mulScalar(0.5))).val[0];
			Player.eye.pos[i] += firstTerm.add(secondTerm).addScalar(a/k).val[0];
		}
	}

	if(!Player.isGhost.load(.monotonic)) {
		Player.mutex.lock();
		defer Player.mutex.unlock();

		const hitBox = Player.outerBoundingBox;
		var steppingHeight = Player.steppingHeight()[2];
		if(Player.super.vel[2] > 0) {
			steppingHeight = Player.super.vel[2]*Player.super.vel[2]/gravity/2;
		}
		steppingHeight = @min(steppingHeight, Player.eye.pos[2] - Player.eye.box.min[2]);

		const slipLimit = 0.25*Player.currentFriction;

		const xMovement = collision.collideOrStep(.client, .x, move[0], Player.super.pos, hitBox, steppingHeight);
		Player.super.pos += xMovement;
		if(Player.crouching and Player.onGround and @abs(Player.super.vel[0]) < slipLimit) {
			if(collision.collides(.client, .x, 0, Player.super.pos - Vec3d{0, 0, 1}, hitBox) == null) {
				Player.super.pos -= xMovement;
				Player.super.vel[0] = 0;
			}
		}

		const yMovement = collision.collideOrStep(.client, .y, move[1], Player.super.pos, hitBox, steppingHeight);
		Player.super.pos += yMovement;
		if(Player.crouching and Player.onGround and @abs(Player.super.vel[1]) < slipLimit) {
			if(collision.collides(.client, .y, 0, Player.super.pos - Vec3d{0, 0, 1}, hitBox) == null) {
				Player.super.pos -= yMovement;
				Player.super.vel[1] = 0;
			}
		}

		if(xMovement[0] != move[0]) {
			Player.super.vel[0] = 0;
		}
		if(yMovement[1] != move[1]) {
			Player.super.vel[1] = 0;
		}

		const stepAmount = xMovement[2] + yMovement[2];
		if(stepAmount > 0) {
			if(Player.eye.coyote <= 0) {
				Player.eye.vel[2] = @max(1.5*vec.length(Player.super.vel), Player.eye.vel[2], 4);
				Player.eye.step[2] = true;
				if(Player.super.vel[2] > 0) {
					Player.eye.vel[2] = Player.super.vel[2];
					Player.eye.step[2] = false;
				}
			} else {
				Player.eye.coyote = 0;
			}
			Player.eye.pos[2] -= stepAmount;
			move[2] = -0.01;
			Player.onGround = true;
		}

		const wasOnGround = Player.onGround;
		Player.onGround = false;
		Player.super.pos[2] += move[2];
		if(collision.collides(.client, .z, -move[2], Player.super.pos, hitBox)) |box| {
			if(move[2] < 0) {
				if(!wasOnGround) {
					Player.eye.vel[2] = Player.super.vel[2];
					Player.eye.pos[2] -= (box.max[2] - hitBox.min[2] - Player.super.pos[2]);
				}
				Player.onGround = true;
				Player.super.pos[2] = box.max[2] - hitBox.min[2];
				Player.eye.coyote = 0;
			} else {
				Player.super.pos[2] = box.min[2] - hitBox.max[2];
			}
			var bounciness = if(Player.isFlying.load(.monotonic)) 0 else collision.calculateSurfaceProperties(.client, Player.super.pos, Player.outerBoundingBox, 0.0).bounciness;
			if(Player.crouching) {
				bounciness *= 0.5;
			}
			var velocityChange: f64 = undefined;

			if(bounciness != 0.0 and Player.super.vel[2] < -3.0) {
				velocityChange = Player.super.vel[2]*@as(f64, @floatCast(1 - bounciness));
				Player.super.vel[2] = -Player.super.vel[2]*bounciness;
				Player.jumpCoyote = Player.jumpCoyoteTimeConstant + deltaTime;
				Player.eye.vel[2] *= 2;
			} else {
				velocityChange = Player.super.vel[2];
				Player.super.vel[2] = 0;
			}
			const damage: f32 = @floatCast(@round(@max((velocityChange*velocityChange)/(2*gravity) - 7, 0))/2);
			if(damage > 0.01) {
				Inventory.Sync.addHealth(-damage, .fall, .client, Player.id);
			}

			// Always unstuck upwards for now
			while(collision.collides(.client, .z, 0, Player.super.pos, hitBox)) |_| {
				Player.super.pos[2] += 1;
			}
		} else if(wasOnGround and move[2] < 0) {
			// If the player drops off a ledge, they might just be walking over a small gap, so lock the y position of the eyes that long.
			// This calculates how long the player has to fall until we know they're not walking over a small gap.
			// We add deltaTime because we subtract deltaTime at the bottom of update
			Player.eye.coyote = @sqrt(2*Player.steppingHeight()[2]/gravity) + deltaTime;
			Player.jumpCoyote = Player.jumpCoyoteTimeConstant + deltaTime;
			Player.eye.pos[2] -= move[2];
		} else if(Player.eye.coyote > 0) {
			Player.eye.pos[2] -= move[2];
		}
		collision.touchBlocks(&Player.super, hitBox, .client, deltaTime);
	} else {
		Player.super.pos += move;
	}

	// Clamp the eye.position and subtract eye coyote time.
	Player.eye.pos = @max(Player.eye.box.min, @min(Player.eye.pos, Player.eye.box.max));
	Player.eye.coyote -= deltaTime;
	Player.jumpCoyote -= deltaTime;
}
