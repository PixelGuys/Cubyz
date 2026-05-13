const std = @import("std");

pub const Vec2i = @Vector(2, i32);
pub const Vec2f = @Vector(2, f32);
pub const Vec2d = @Vector(2, f64);
pub const Vec3i = @Vector(3, i32);
pub const Vec3f = @Vector(3, f32);
pub const Vec3d = @Vector(3, f64);
pub const Vec4i = @Vector(4, i32);
pub const Vec4f = @Vector(4, f32);
pub const Vec4d = @Vector(4, f64);

// copied from zmath library (MIT Liscence) : https://github.com/zig-gamedev/zmath/blob/3a5955b2b72cd081563fbb084eff05bffd1e3fbb/src/root.zig#L1430
pub const Vec4fComponent = enum { x, y, z, w };

pub inline fn swizzle(
	v: Vec4f,
	comptime x: Vec4fComponent,
	comptime y: Vec4fComponent,
	comptime z: Vec4fComponent,
	comptime w: Vec4fComponent,
) Vec4f {
	return @shuffle(f32, v, undefined, [4]i32{@intFromEnum(x), @intFromEnum(y), @intFromEnum(z), @intFromEnum(w)});
}

pub inline fn combine(pos: Vec3f, w: f32) Vec4f {
	return .{pos[0], pos[1], pos[2], w};
}

pub fn xyz(self: anytype) @Vector(3, @typeInfo(@TypeOf(self)).vector.child) {
	return @Vector(3, @typeInfo(@TypeOf(self)).vector.child){self[0], self[1], self[2]};
}

pub fn xy(self: anytype) @Vector(2, @typeInfo(@TypeOf(self)).vector.child) {
	return @Vector(2, @typeInfo(@TypeOf(self)).vector.child){self[0], self[1]};
}

pub fn dot(self: anytype, other: @TypeOf(self)) @typeInfo(@TypeOf(self)).vector.child {
	return @reduce(.Add, self*other);
}

pub fn lengthSquare(self: anytype) @typeInfo(@TypeOf(self)).vector.child {
	return @reduce(.Add, self*self);
}

pub fn length(self: anytype) @typeInfo(@TypeOf(self)).vector.child {
	return @sqrt(@reduce(.Add, self*self));
}

pub fn normalize(self: anytype) @TypeOf(self) {
	return self/@as(@TypeOf(self), @splat(length(self)));
}

pub fn clampMag(self: anytype, maxMag: @typeInfo(@TypeOf(self)).vector.child) @TypeOf(self) {
	if (lengthSquare(self) > maxMag*maxMag) {
		return normalize(self)*@as(@TypeOf(self), @splat(maxMag));
	}

	return self;
}

pub fn cross(self: anytype, other: @TypeOf(self)) @TypeOf(self) {
	if (@typeInfo(@TypeOf(self)).vector.len != 3) @compileError("Only available for vectors of length 3.");
	return @TypeOf(self){
		self[1]*other[2] - self[2]*other[1],
		self[2]*other[0] - self[0]*other[2],
		self[0]*other[1] - self[1]*other[0],
	};
}

pub fn rotateX(self: anytype, angle: @typeInfo(@TypeOf(self)).vector.child) @TypeOf(self) {
	if (@typeInfo(@TypeOf(self)).vector.len != 3) @compileError("Only available for vectors of length 3.");
	const sin = @sin(angle);
	const cos = @cos(angle);
	return @TypeOf(self){
		self[0],
		self[1]*cos - self[2]*sin,
		self[1]*sin + self[2]*cos,
	};
}

pub fn rotateY(self: anytype, angle: @typeInfo(@TypeOf(self)).vector.child) @TypeOf(self) {
	if (@typeInfo(@TypeOf(self)).vector.len != 3) @compileError("Only available for vectors of length 3.");
	const sin = @sin(angle);
	const cos = @cos(angle);
	return @TypeOf(self){
		self[0]*cos + self[2]*sin,
		self[1],
		-self[0]*sin + self[2]*cos,
	};
}

pub fn rotateZ(self: anytype, angle: @typeInfo(@TypeOf(self)).vector.child) @TypeOf(self) {
	if (@typeInfo(@TypeOf(self)).vector.len != 3) @compileError("Only available for vectors of length 3.");
	const sin = @sin(angle);
	const cos = @cos(angle);
	return @TypeOf(self){
		self[0]*cos - self[1]*sin,
		self[0]*sin + self[1]*cos,
		self[2],
	};
}

pub fn rotate2d(self: anytype, angle: @typeInfo(@TypeOf(self)).vector.child, center: @TypeOf(self)) @TypeOf(self) {
	if (@typeInfo(@TypeOf(self)).vector.len != 2) @compileError("Only available for vectors of length 2.");

	const sin = @sin(angle);
	const cos = @cos(angle);
	const pos = self - center;

	return @TypeOf(self){
		cos*pos[0] - sin*pos[1],
		sin*pos[0] + cos*pos[1],
	} + center;
}

pub const Mat4f = struct { // MARK: Mat4f
	rows: [4]Vec4f,
	pub fn identity() Mat4f {
		return Mat4f{
			.rows = [4]Vec4f{
				Vec4f{1, 0, 0, 0},
				Vec4f{0, 1, 0, 0},
				Vec4f{0, 0, 1, 0},
				Vec4f{0, 0, 0, 1},
			},
		};
	}

	pub fn translation(pos: Vec3f) Mat4f {
		return Mat4f{
			.rows = [4]Vec4f{
				Vec4f{1, 0, 0, pos[0]},
				Vec4f{0, 1, 0, pos[1]},
				Vec4f{0, 0, 1, pos[2]},
				Vec4f{0, 0, 0, 1},
			},
		};
	}

	pub fn scale(vector: Vec3f) Mat4f { // zig fmt: off
		return Mat4f{
			.rows = [4]Vec4f{
				Vec4f{vector[0], 0,         0,         0},
				Vec4f{0,         vector[1], 0,         0},
				Vec4f{0,         0,         vector[2], 0},
				Vec4f{0,         0,         0,         1},
			},
		};
	} // zig fmt: on

	pub fn rotationX(rad: f32) Mat4f {
		const s = @sin(rad);
		const c = @cos(rad);
		return Mat4f{
			.rows = [4]Vec4f{
				Vec4f{1, 0, 0, 0},
				Vec4f{0, c, -s, 0},
				Vec4f{0, s, c, 0},
				Vec4f{0, 0, 0, 1},
			},
		};
	}

	pub fn rotationY(rad: f32) Mat4f {
		const s = @sin(rad);
		const c = @cos(rad);
		return Mat4f{
			.rows = [4]Vec4f{
				Vec4f{c, 0, s, 0},
				Vec4f{0, 1, 0, 0},
				Vec4f{-s, 0, c, 0},
				Vec4f{0, 0, 0, 1},
			},
		};
	}

	pub fn rotationZ(rad: f32) Mat4f {
		const s = @sin(rad);
		const c = @cos(rad);
		return Mat4f{
			.rows = [4]Vec4f{
				Vec4f{c, -s, 0, 0},
				Vec4f{s, c, 0, 0},
				Vec4f{0, 0, 1, 0},
				Vec4f{0, 0, 0, 1},
			},
		};
	}

	// copied from zmath library (MIT Liscence) : https://github.com/zig-gamedev/zmath/blob/3a5955b2b72cd081563fbb084eff05bffd1e3fbb/src/root.zig#L634
	inline fn andInt(v0: anytype, v1: anytype) @TypeOf(v0, v1) {
		const T = @TypeOf(v0, v1);
		const Tu = @Vector(@typeInfo(T).vector.len, u32);
		const v0u = @as(Tu, @bitCast(v0));
		const v1u = @as(Tu, @bitCast(v1));
		return @as(T, @bitCast(v0u & v1u)); // andps
	}

	// copied from zmath library (MIT Liscence) : https://github.com/zig-gamedev/zmath/blob/3a5955b2b72cd081563fbb084eff05bffd1e3fbb/src/root.zig#L2726
	pub fn rotationQuat(quat: Vec4f) Mat4f {
		const f32x4_mask3: Vec4f = Vec4f{
			@as(f32, @bitCast(@as(u32, 0xffff_ffff))),
			@as(f32, @bitCast(@as(u32, 0xffff_ffff))),
			@as(f32, @bitCast(@as(u32, 0xffff_ffff))),
			0,
		};
		const q0 = quat + quat;
		var q1 = quat*q0;

		var v0 = swizzle(q1, .y, .x, .x, .w);
		v0 = andInt(v0, f32x4_mask3);

		var v1 = swizzle(q1, .z, .z, .y, .w);
		v1 = andInt(v1, f32x4_mask3);

		const r0 = (Vec4f{1.0, 1.0, 1.0, 0.0} - v0) - v1;

		v0 = swizzle(quat, .x, .x, .y, .w);
		v1 = swizzle(q0, .z, .y, .z, .w);
		v0 = v0*v1;

		v1 = swizzle(quat, .w, .w, .w, .w);
		const v2 = swizzle(q0, .y, .z, .x, .w);
		v1 = v1*v2;

		const r1 = v0 + v1;
		const r2 = v0 - v1;

		v0 = @shuffle(f32, r1, r2, [4]i32{1, 2, ~@as(i32, 0), ~@as(i32, 1)});
		v0 = swizzle(v0, .x, .z, .w, .y);
		v1 = @shuffle(f32, r1, r2, [4]i32{0, 0, ~@as(i32, 2), ~@as(i32, 2)});
		v1 = swizzle(v1, .x, .z, .x, .z);

		q1 = @shuffle(f32, r0, v0, [4]i32{0, 3, ~@as(i32, 0), ~@as(i32, 1)});
		q1 = swizzle(q1, .x, .z, .w, .y);

		var m: Mat4f = undefined;
		m.rows[0] = q1;

		q1 = @shuffle(f32, r0, v0, [4]i32{1, 3, ~@as(i32, 2), ~@as(i32, 3)});
		q1 = swizzle(q1, .z, .x, .w, .y);
		m.rows[1] = q1;

		q1 = @shuffle(f32, v1, r0, [4]i32{0, 1, ~@as(i32, 2), ~@as(i32, 3)});
		m.rows[2] = q1;
		m.rows[3] = Vec4f{0.0, 0.0, 0.0, 1.0};
		return m;
	}

	pub fn perspective(fovY: f32, aspect: f32, near: f32, far: f32) Mat4f { // zig fmt: off
		const tanY = std.math.tan(fovY*0.5);
		const tanX = aspect*tanY;
		return Mat4f{
			.rows = [4]Vec4f{
				Vec4f{1/tanX, 0,                          0,      0},
				Vec4f{0,      0,                          1/tanY, 0},
				Vec4f{0,      -(far + near)/(near - far), 0,      2*near*far/(near - far)},
				Vec4f{0,      1,                          0,      0},
			},
		};
	} // zig fmt: on

	pub fn transpose(self: Mat4f) Mat4f {
		return Mat4f{
			.rows = [4]Vec4f{
				Vec4f{self.rows[0][0], self.rows[1][0], self.rows[2][0], self.rows[3][0]},
				Vec4f{self.rows[0][1], self.rows[1][1], self.rows[2][1], self.rows[3][1]},
				Vec4f{self.rows[0][2], self.rows[1][2], self.rows[2][2], self.rows[3][2]},
				Vec4f{self.rows[0][3], self.rows[1][3], self.rows[2][3], self.rows[3][3]},
			},
		};
	}

	pub fn mul(self: Mat4f, other: Mat4f) Mat4f {
		const transposeOther = other.transpose();
		var result: Mat4f = undefined;
		for (&result.rows, self.rows) |*resRow, selfRow| {
			resRow.* = .{
				dot(selfRow, transposeOther.rows[0]),
				dot(selfRow, transposeOther.rows[1]),
				dot(selfRow, transposeOther.rows[2]),
				dot(selfRow, transposeOther.rows[3]),
			};
		}
		return result;
	}

	pub fn mulVec(self: Mat4f, vec: Vec4f) Vec4f {
		return Vec4f{
			dot(self.rows[0], vec),
			dot(self.rows[1], vec),
			dot(self.rows[2], vec),
			dot(self.rows[3], vec),
		};
	}
};

pub const Complex = struct { // MARK: Complex
	val: Vec2d,

	fn valSquare(a: Complex) f64 {
		return @reduce(.Add, a.val*a.val);
	}

	fn conjugate(a: Complex) Complex {
		return .{.val = a.val*Vec2d{1, -1}};
	}

	pub fn negate(a: Complex) Complex {
		return .{.val = -a.val};
	}

	pub fn add(a: Complex, b: Complex) Complex {
		return .{.val = a.val + b.val};
	}

	pub fn addScalar(a: Complex, b: f64) Complex {
		return .{.val = a.val + Vec2d{b, 0}};
	}

	pub fn sub(a: Complex, b: Complex) Complex {
		return .{.val = a.val - b.val};
	}

	pub fn subScalar(a: Complex, b: f64) Complex {
		return .{.val = a.val - Vec2d{b, 0}};
	}

	pub fn mul(a: Complex, b: Complex) Complex {
		return .{.val = .{a.val[0]*b.val[0] - a.val[1]*b.val[1], a.val[0]*b.val[1] + a.val[1]*b.val[0]}};
	}

	pub fn mulScalar(a: Complex, b: f64) Complex {
		return .{.val = a.val*@as(Vec2d, @splat(b))};
	}

	pub fn div(a: Complex, b: Complex) Complex {
		const denom = b.valSquare();
		return a.mul(b.conjugate()).divScalar(denom);
	}

	pub fn divScalar(a: Complex, b: f64) Complex {
		return .{.val = a.val/@as(Vec2d, @splat(b))};
	}

	pub fn fromSqrt(val: f64) Complex {
		if (val < 0) {
			return .{.val = .{0, @sqrt(-val)}};
		} else {
			return .{.val = .{@sqrt(val), 0}};
		}
	}

	pub fn exp(a: Complex) Complex {
		const realFactor = @exp(a.val[0]);
		const complexFactor: Complex = .{.val = .{@cos(a.val[1]), @sin(a.val[1])}};
		return complexFactor.mulScalar(realFactor);
	}
};

// MARK: Box

pub const Boxi = struct {
	min: Vec3i,
	max: Vec3i,

	pub fn merge(self: Boxi, other: Boxi) Boxi {
		return .{.min = @min(self.min, other.min), .max = @max(self.max, other.max)};
	}
};
