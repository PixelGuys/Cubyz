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
			const strength = (-Player.eyePos)/(Player.eyeBox.max - Player.eyeBox.min);
			const force = strength*forceMultipliers;
			const friction = frictionMultipliers;
			springConstants += forceMultipliers/(Player.eyeBox.max - Player.eyeBox.min);
			directionalFrictionCoefficients += @floatCast(friction);
			acc += force;
		}

		// This our model for movement of the eye position on a single frame:
		// dv/dt = a - k*x - λ·v
		// dx/dt = v
		// Where a is the acceleration, k is the spring constant and λ is the friction coefficient
		inline for(0..3) |i| blk: {
			if(Player.eyeStep[i]) {
				const oldPos = Player.eyePos[i];
				const newPos = oldPos + Player.eyeVel[i]*deltaTime;
				if(newPos*std.math.sign(Player.eyeVel[i]) <= -0.1) {
					Player.eyePos[i] = newPos;
					break :blk;
				} else {
					Player.eyeStep[i] = false;
				}
			}
			if(i == 2 and Player.eyeCoyote > 0) {
				break :blk;
			}
			const frictionCoefficient = directionalFrictionCoefficients[i];
			const v_0 = Player.eyeVel[i];
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
			Player.eyeVel[i] = firstTerm.mul(c_3.negate().subScalar(frictionCoefficient).mulScalar(0.5)).add(secondTerm.mul((c_3.subScalar(frictionCoefficient)).mulScalar(0.5))).val[0];
			Player.eyePos[i] += firstTerm.add(secondTerm).addScalar(a/k).val[0];
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
		steppingHeight = @min(steppingHeight, Player.eyePos[2] - Player.eyeBox.min[2]);

		const slipLimit = 0.25*Player.currentFriction;

		// Use new collision system with stepping for horizontal movement
		const horizontalMovement = Vec3d{move[0], move[1], 0};
		const actualMovement = collision.resolveCollisionWithStepping(.client, horizontalMovement, Player.super.pos, hitBox, steppingHeight, main.stackAllocator.allocator) catch horizontalMovement;

		Player.super.pos += actualMovement;

		// Crouch edge detection - prevent sliding off edges
		if(Player.crouching and Player.onGround) {
			if(@abs(Player.super.vel[0]) < slipLimit and actualMovement[0] != 0) {
				// Check if we'd fall off the edge
				const checkResult = collision.resolveCollision(.client, Vec3d{0, 0, -1}, Player.super.pos, hitBox, main.stackAllocator.allocator) catch Vec3d{0, 0, -1};
				if(@abs(checkResult[2]) > 0.99) { // Would fall
					Player.super.pos[0] -= actualMovement[0];
					Player.super.vel[0] = 0;
				}
			}
			if(@abs(Player.super.vel[1]) < slipLimit and actualMovement[1] != 0) {
				const checkResult = collision.resolveCollision(.client, Vec3d{0, 0, -1}, Player.super.pos, hitBox, main.stackAllocator.allocator) catch Vec3d{0, 0, -1};
				if(@abs(checkResult[2]) > 0.99) {
					Player.super.pos[1] -= actualMovement[1];
					Player.super.vel[1] = 0;
				}
			}
		}

		// Zero velocity on blocked axes
		if(@abs(actualMovement[0]) < @abs(horizontalMovement[0]) * 0.999) {
			Player.super.vel[0] = 0;
		}
		if(@abs(actualMovement[1]) < @abs(horizontalMovement[1]) * 0.999) {
			Player.super.vel[1] = 0;
		}

		// Handle stepping
		const stepAmount = actualMovement[2];
		if(stepAmount > 0) {
			if(Player.eyeCoyote <= 0) {
				Player.eyeVel[2] = @max(1.5*vec.length(Player.super.vel), Player.eyeVel[2], 4);
				Player.eyeStep[2] = true;
				if(Player.super.vel[2] > 0) {
					Player.eyeVel[2] = Player.super.vel[2];
					Player.eyeStep[2] = false;
				}
			} else {
				Player.eyeCoyote = 0;
			}
			Player.eyePos[2] -= stepAmount;
			move[2] = -0.01;
			Player.onGround = true;
		}

		// Handle vertical movement
		const wasOnGround = Player.onGround;
		Player.onGround = false;

		const verticalMovement = Vec3d{0, 0, move[2]};
		const verticalResult = collision.resolveCollision(.client, verticalMovement, Player.super.pos, hitBox, main.stackAllocator.allocator) catch verticalMovement;
		Player.super.pos[2] += verticalResult[2];

		// Check if we hit something vertically
		if(@abs(verticalResult[2]) < @abs(move[2]) * 0.999) {
			if(move[2] < 0) {
				// Hit ground
				if(!wasOnGround) {
					Player.eyeVel[2] = Player.super.vel[2];
					Player.eyePos[2] -= verticalResult[2] - move[2];
				}
				Player.onGround = true;
				Player.eyeCoyote = 0;
			}

			// Calculate bounciness
			var bounciness = if(Player.isFlying.load(.monotonic)) 0 else collision.calculateSurfaceProperties(.client, Player.super.pos, Player.outerBoundingBox, 0.0).bounciness;
			if(Player.crouching) {
				bounciness *= 0.5;
			}
			var velocityChange: f64 = undefined;

			if(bounciness != 0.0 and Player.super.vel[2] < -3.0) {
				velocityChange = Player.super.vel[2]*@as(f64, @floatCast(1 - bounciness));
				Player.super.vel[2] = -Player.super.vel[2]*bounciness;
				Player.jumpCoyote = Player.jumpCoyoteTimeConstant + deltaTime;
				Player.eyeVel[2] *= 2;
			} else {
				velocityChange = Player.super.vel[2];
				Player.super.vel[2] = 0;
			}

			// Fall damage
			const damage: f32 = @floatCast(@round(@max((velocityChange*velocityChange)/(2*gravity) - 7, 0))/2);
			if(damage > 0.01) {
				Inventory.Sync.addHealth(-damage, .fall, .client, Player.id);
			}
		} else if(wasOnGround and move[2] < 0) {
			// Dropped off ledge - eye coyote time
			Player.eyeCoyote = @sqrt(2*Player.steppingHeight()[2]/gravity) + deltaTime;
			Player.jumpCoyote = Player.jumpCoyoteTimeConstant + deltaTime;
			Player.eyePos[2] -= move[2];
		} else if(Player.eyeCoyote > 0) {
			Player.eyePos[2] -= move[2];
		}

		collision.touchBlocks(Player.super, hitBox, .client);
	} else {
		Player.super.pos += move;
	}

	// Clamp the eyePosition and subtract eye coyote time.
	Player.eyePos = @max(Player.eyeBox.min, @min(Player.eyePos, Player.eyeBox.max));
	Player.eyeCoyote -= deltaTime;
	Player.jumpCoyote -= deltaTime;
}
