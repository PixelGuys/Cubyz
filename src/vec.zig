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

pub inline fn combine(pos: Vec3f, w: f32) Vec4f {
	return .{pos[0], pos[1], pos[2], w};
}

pub fn xyz(self: anytype) @Vector(3, @typeInfo(@TypeOf(self)).Vector.child) {
	return @Vector(3, @typeInfo(@TypeOf(self)).Vector.child){self[0], self[1], self[2]};
}

pub fn xy(self: anytype) @Vector(2, @typeInfo(@TypeOf(self)).Vector.child) {
	return @Vector(2, @typeInfo(@TypeOf(self)).Vector.child){self[0], self[1]};
}

pub fn dot(self: anytype, other: @TypeOf(self)) @typeInfo(@TypeOf(self)).Vector.child {
	return @reduce(.Add, self*other);
}

pub fn lengthSquare(self: anytype) @typeInfo(@TypeOf(self)).Vector.child {
	return @reduce(.Add, self*self);
}

pub fn length(self: anytype) @typeInfo(@TypeOf(self)).Vector.child {
	return @sqrt(@reduce(.Add, self*self));
}

pub fn normalize(self: anytype) @TypeOf(self) {
	return self/@as(@TypeOf(self), @splat(length(self)));
}

pub fn cross(self: anytype, other: @TypeOf(self)) @TypeOf(self) {
	if(@typeInfo(@TypeOf(self)).Vector.len != 3) @compileError("Only available for vectors of length 3.");
	return @TypeOf(self) {
		self[1]*other[2] - self[2]*other[1],
		self[2]*other[0] - self[0]*other[2],
		self[0]*other[1] - self[1]*other[0],
	};
}

pub fn rotateX(self: anytype, angle: @typeInfo(@TypeOf(self)).Vector.child) @TypeOf(self) {
	if(@typeInfo(@TypeOf(self)).Vector.len != 3) @compileError("Only available for vectors of length 3.");
	const sin = @sin(angle);
	const cos = @cos(angle);
	return @TypeOf(self){
		self[0],
		self[1]*cos - self[2]*sin,
		self[1]*sin + self[2]*cos,
	};
}

pub fn rotateY(self: anytype, angle: @typeInfo(@TypeOf(self)).Vector.child) @TypeOf(self) {
	if(@typeInfo(@TypeOf(self)).Vector.len != 3) @compileError("Only available for vectors of length 3.");
	const sin = @sin(angle);
	const cos = @cos(angle);
	return @TypeOf(self){
		self[0]*cos + self[2]*sin,
		self[1],
		-self[0]*sin + self[2]*cos,
	};
}

pub fn rotateZ(self: anytype, angle: @typeInfo(@TypeOf(self)).Vector.child) @TypeOf(self) {
	if(@typeInfo(@TypeOf(self)).Vector.len != 3) @compileError("Only available for vectors of length 3.");
	const sin = @sin(angle);
	const cos = @cos(angle);
	return @TypeOf(self){
		self[0]*cos - self[1]*sin,
		self[0]*sin + self[1]*cos,
		self[2],
	};
}

pub const Mat4f = struct {
	rows: [4]Vec4f,
	pub fn identity() Mat4f {
		return Mat4f {
			.rows = [4]Vec4f {
				Vec4f{1, 0, 0, 0},
				Vec4f{0, 1, 0, 0},
				Vec4f{0, 0, 1, 0},
				Vec4f{0, 0, 0, 1},
			}
		};
	}

	pub fn translation(pos: Vec3f) Mat4f {
		return Mat4f {
			.rows = [4]Vec4f {
				Vec4f{1, 0, 0, pos[0]},
				Vec4f{0, 1, 0, pos[1]},
				Vec4f{0, 0, 1, pos[2]},
				Vec4f{0, 0, 0, 1},
			}
		};
	}

	pub fn rotationX(rad: f32) Mat4f {
		const s = @sin(rad);
		const c = @cos(rad);
		return Mat4f {
			.rows = [4]Vec4f {
				Vec4f{1, 0, 0, 0},
				Vec4f{0, c,-s, 0},
				Vec4f{0, s, c, 0},
				Vec4f{0, 0, 0, 1},
			}
		};
	}

	pub fn rotationY(rad: f32) Mat4f {
		const s = @sin(rad);
		const c = @cos(rad);
		return Mat4f {
			.rows = [4]Vec4f {
				Vec4f{c, 0, s, 0},
				Vec4f{0, 1, 0, 0},
				Vec4f{-s,0, c, 0},
				Vec4f{0, 0, 0, 1},
			}
		};
	}

	pub fn rotationZ(rad: f32) Mat4f {
		const s = @sin(rad);
		const c = @cos(rad);
		return Mat4f {
			.rows = [4]Vec4f {
				Vec4f{c,-s, 0, 0},
				Vec4f{s, c, 0, 0},
				Vec4f{0, 0, 1, 0},
				Vec4f{0, 0, 0, 1},
			}
		};
	}

	pub fn perspective(fovY: f32, aspect: f32, near: f32, far: f32) Mat4f {
		const tanY = std.math.tan(fovY*0.5);
		const tanX = aspect*tanY;
		return Mat4f {
			.rows = [4]Vec4f {
				Vec4f{1/tanX, 0,                          0,      0},
				Vec4f{0,      0,                          1/tanY, 0},
				Vec4f{0,      -(far + near)/(near - far), 0,      2*near*far/(near - far)},
				Vec4f{0,      1,                          0,      0},
			}
		};
	}

	pub fn transpose(self: Mat4f) Mat4f {
		return Mat4f {
			.rows = [4]Vec4f {
				Vec4f{self.rows[0][0], self.rows[1][0], self.rows[2][0], self.rows[3][0]},
				Vec4f{self.rows[0][1], self.rows[1][1], self.rows[2][1], self.rows[3][1]},
				Vec4f{self.rows[0][2], self.rows[1][2], self.rows[2][2], self.rows[3][2]},
				Vec4f{self.rows[0][3], self.rows[1][3], self.rows[2][3], self.rows[3][3]},
			}
		};
	}

	pub fn mul(self: Mat4f, other: Mat4f) Mat4f {
		const transposeOther = other.transpose();
		var result: Mat4f = undefined;
		for(&result.rows, self.rows) |*resRow, selfRow| {
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
		return Vec4f {
			dot(self.rows[0], vec),
			dot(self.rows[1], vec),
			dot(self.rows[2], vec),
			dot(self.rows[3], vec),
		};
	}
};