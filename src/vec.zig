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

pub fn xyz(self: anytype) @Vector(3, @typeInfo(@TypeOf(self)).Vector.child) {
	return @Vector(3, @typeInfo(@TypeOf(self)).Vector.child){self[0], self[1], self[2]};
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
	return self/@splat(@typeInfo(@TypeOf(self)).Vector.len, length(self));
}

pub fn floatToInt(comptime DestType: type, self: anytype) @Vector(@typeInfo(@TypeOf(self)).Vector.len, DestType) { // TODO: Remove once @floatToInt supports vectors.
	const len = @typeInfo(@TypeOf(self)).Vector.len;
	var result: @Vector(len, DestType) = undefined;
	comptime var i: u32 = 0;
	inline while(i < len) : (i += 1) {
		result[i] = @floatToInt(DestType, self[i]);
	}
	return result;
}

pub fn intToFloat(comptime DestType: type, self: anytype) @Vector(@typeInfo(@TypeOf(self)).Vector.len, DestType) { // TODO: Remove once @intToFloat supports vectors.
	const len = @typeInfo(@TypeOf(self)).Vector.len;
	var result: @Vector(len, DestType) = undefined;
	comptime var i: u32 = 0;
	inline while(i < len) : (i += 1) {
		result[i] = @intToFloat(DestType, self[i]);
	}
	return result;
}

pub fn floatCast(comptime DestType: type, self: anytype) @Vector(@typeInfo(@TypeOf(self)).Vector.len, DestType) { // TODO: Remove once @intToFloat supports vectors.
	const len = @typeInfo(@TypeOf(self)).Vector.len;
	var result: @Vector(len, DestType) = undefined;
	comptime var i: u32 = 0;
	inline while(i < len) : (i += 1) {
		result[i] = @floatCast(DestType, self[i]);
	}
	return result;
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
	const cos = @cos(angle); // TODO: Consider using sqrt here.
	return @TypeOf(self){
		self[0],
		self[1]*cos - self[2]*sin,
		self[1]*sin + self[2]*cos,
	};
}

pub fn rotateY(self: anytype, angle: @typeInfo(@TypeOf(self)).Vector.child) @TypeOf(self) {
	if(@typeInfo(@TypeOf(self)).Vector.len != 3) @compileError("Only available for vectors of length 3.");
	const sin = @sin(angle);
	const cos = @cos(angle); // TODO: Consider using sqrt here.
	return @TypeOf(self){
		self[0]*cos + self[2]*sin,
		self[1],
		-self[0]*sin + self[2]*cos,
	};
}

pub fn rotateZ(self: anytype, angle: @typeInfo(@TypeOf(self)).Vector.child) @TypeOf(self) {
	if(@typeInfo(@TypeOf(self)).Vector.len != 3) @compileError("Only available for vectors of length 3.");
	const sin = @sin(angle);
	const cos = @cos(angle); // TODO: Consider using sqrt here.
	return @TypeOf(self){
		self[0]*cos - self[1]*sin,
		self[0]*sin + self[1]*cos,
		self[2],
	};
}

pub const Mat4f = struct {
	columns: [4]Vec4f,
	pub fn identity() Mat4f {
		return Mat4f {
			.columns = [4]Vec4f { // Keep in mind that this is the transpose!
				Vec4f{1, 0, 0, 0},
				Vec4f{0, 1, 0, 0},
				Vec4f{0, 0, 1, 0},
				Vec4f{0, 0, 0, 1},
			}
		};
	}

	pub fn translation(pos: Vec3f) Mat4f {
		return Mat4f {
			.columns = [4]Vec4f { // Keep in mind that this is the transpose!
				Vec4f{1, 0, 0, 0},
				Vec4f{0, 1, 0, 0},
				Vec4f{0, 0, 1, 0},
				Vec4f{pos[0], pos[1], pos[2], 1},
			}
		};
	}

	pub fn rotationX(rad: f32) Mat4f {
		const s = @sin(rad);
		const c = @cos(rad);
		return Mat4f {
			.columns = [4]Vec4f { // Keep in mind that this is the transpose!
				Vec4f{1, 0, 0, 0},
				Vec4f{0, c, s, 0},
				Vec4f{0,-s, c, 0},
				Vec4f{0, 0, 0, 1},
			}
		};
	}

	pub fn rotationY(rad: f32) Mat4f {
		const s = @sin(rad);
		const c = @cos(rad);
		return Mat4f {
			.columns = [4]Vec4f { // Keep in mind that this is the transpose!
				Vec4f{c, 0,-s, 0},
				Vec4f{0, 1, 0, 0},
				Vec4f{s, 0, c, 0},
				Vec4f{0, 0, 0, 1},
			}
		};
	}

	pub fn rotationZ(rad: f32) Mat4f {
		const s = @sin(rad);
		const c = @cos(rad);
		return Mat4f {
			.columns = [4]Vec4f { // Keep in mind that this is the transpose!
				Vec4f{c, s, 0, 0},
				Vec4f{-s,c, 0, 0},
				Vec4f{0, 0, 1, 0},
				Vec4f{0, 0, 0, 1},
			}
		};
	}

	pub fn perspective(fovY: f32, aspect: f32, near: f32, far: f32) Mat4f {
		const tanY = std.math.tan(fovY*0.5);
		const tanX = aspect*tanY;
		return Mat4f {
			.columns = [4]Vec4f { // Keep in mind that this is the transpose!
				Vec4f{1/tanX, 0,      0,                         0},
				Vec4f{0,      1/tanY, 0,                         0},
				Vec4f{0,      0,      (far + near)/(near - far), -1},
				Vec4f{0,      0,      2*near*far/(near - far),   0},
			}
		};
	}

	pub fn transpose(self: Mat4f) Mat4f {
		return Mat4f {
			.columns = [4]Vec4f { // Keep in mind that this is the transpose!
				Vec4f{self.columns[0][0], self.columns[1][0], self.columns[2][0], self.columns[3][0]},
				Vec4f{self.columns[0][1], self.columns[1][1], self.columns[2][1], self.columns[3][1]},
				Vec4f{self.columns[0][2], self.columns[1][2], self.columns[2][2], self.columns[3][2]},
				Vec4f{self.columns[0][3], self.columns[1][3], self.columns[2][3], self.columns[3][3]},
			}
		};
	}

	pub fn mul(self: Mat4f, other: Mat4f) Mat4f {
		var transposeSelf = self.transpose();
		var result: Mat4f = undefined;
		for(&result.columns, other.columns) |*resCol, otherCol| {
			resCol.*[0] = dot(transposeSelf.columns[0], otherCol);
			resCol.*[1] = dot(transposeSelf.columns[1], otherCol);
			resCol.*[2] = dot(transposeSelf.columns[2], otherCol);
			resCol.*[3] = dot(transposeSelf.columns[3], otherCol);
		}
		return result;
	}

	pub fn mulVec(self: Mat4f, vec: Vec4f) Vec4f {
		var transposeSelf = self.transpose();
		var result: Vec4f = undefined;
		result[0] = dot(transposeSelf.columns[0], vec);
		result[1] = dot(transposeSelf.columns[1], vec);
		result[2] = dot(transposeSelf.columns[2], vec);
		result[3] = dot(transposeSelf.columns[3], vec);
		return result;
	}
};