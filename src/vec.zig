const std = @import("std");

pub const Vec2i = GenericVector2(i32);
pub const Vec2f = GenericVector2(f32);
pub const Vec2d = GenericVector2(f64);
pub const Vec3i = GenericVector3(i32);
pub const Vec3f = extern struct {// This one gets a bit of extra functionality for rotating in 3d.
	x: f32,
	y: f32,
	z: f32,
	pub usingnamespace GenericVectorMath(@This(), f32);
	
	pub fn rotateX(self: Vec3f, angle: f32) Vec3f {
		const sin = @sin(angle);
		const cos = @cos(angle); // TODO: Consider using sqrt here.
		return Vec3f{
			.x = self.x,
			.y = self.y*cos - self.z*sin,
			.z = self.y*sin + self.z*cos,
		};
	}
	
	pub fn rotateY(self: Vec3f, angle: f32) Vec3f {
		const sin = @sin(angle);
		const cos = @cos(angle); // TODO: Consider using sqrt here.
		return Vec3f{
			.x = self.x*cos + self.z*sin,
			.y = self.y,
			.z = -self.x*sin + self.z*cos,
		};
	}
	
	pub fn rotateZ(self: Vec3f, angle: f32) Vec3f {
		const sin = @sin(angle);
		const cos = @cos(angle); // TODO: Consider using sqrt here.
		return Vec3f{
			.x = self.x*cos - self.y*sin,
			.y = self.x*sin + self.y*cos,
			.z = self.z,
		};
	}
};
pub const Vec3d = GenericVector3(f64);
pub const Vec4i = GenericVector4(i32);
pub const Vec4f = GenericVector4(f32);
pub const Vec4d = GenericVector4(f64);

fn GenericVectorMath(comptime Vec: type, comptime T: type) type {
	return struct {
		pub fn add(self: Vec, other: Vec) Vec {
			var result: Vec = undefined;
			inline for(@typeInfo(Vec).Struct.fields) |field| {
				@field(result, field.name) = @field(self, field.name) + @field(other, field.name);
			}
			return result;
		}

		pub fn sub(self: Vec, other: Vec) Vec {
			var result: Vec = undefined;
			inline for(@typeInfo(Vec).Struct.fields) |field| {
				@field(result, field.name) = @field(self, field.name) - @field(other, field.name);
			}
			return result;
		}

		pub fn mul(self: Vec, other: Vec) Vec {
			var result: Vec = undefined;
			inline for(@typeInfo(Vec).Struct.fields) |field| {
				@field(result, field.name) = @field(self, field.name) * @field(other, field.name);
			}
			return result;
		}

		pub fn div(self: Vec, other: Vec) Vec {
			if(@typeInfo(T) == .Float) {
				var result: Vec = undefined;
				inline for(@typeInfo(Vec).Struct.fields) |field| {
					@field(result, field.name) = @field(self, field.name) / @field(other, field.name);
				}
				return result;
			} else {
				@compileError("Not supported for integer types.");
			}
		}

		pub fn minimum(self: Vec, other: Vec) Vec {
			var result: Vec = undefined;
			inline for(@typeInfo(Vec).Struct.fields) |field| {
				@field(result, field.name) = @minimum(@field(self, field.name), @field(other, field.name));
			}
			return result;
		}

		pub fn maximum(self: Vec, other: Vec) Vec {
			var result: Vec = undefined;
			inline for(@typeInfo(Vec).Struct.fields) |field| {
				@field(result, field.name) = @maximum(@field(self, field.name), @field(other, field.name));
			}
			return result;
		}

		pub fn addEqual(self: *Vec, other: Vec) void {
			inline for(@typeInfo(Vec).Struct.fields) |field| {
				@field(self, field.name) += @field(other, field.name);
			}
		}

		pub fn subEqual(self: *Vec, other: Vec) void {
			inline for(@typeInfo(Vec).Struct.fields) |field| {
				@field(self, field.name) -= @field(other, field.name);
			}
		}

		pub fn mulEqual(self: *Vec, other: Vec) void {
			inline for(@typeInfo(Vec).Struct.fields) |field| {
				@field(self, field.name) *= @field(other, field.name);
			}
		}

		pub fn divEqual(self: *Vec, other: Vec) void {
			if(@typeInfo(T) == .Float) {
				inline for(@typeInfo(Vec).Struct.fields) |field| {
					@field(self, field.name) /= @field(other, field.name);
				}
			} else {
				@compileError("Not supported for integer types.");
			}
		}

		pub fn dot(self: Vec, other: Vec) T {
			var result: T = 0;
			inline for(@typeInfo(Vec).Struct.fields) |field| {
				result += @field(self, field.name) * @field(other, field.name);
			}
			return result;
		}
	};
}

fn GenericVector2(comptime T: type) type {
	return extern struct {
		x: T,
		y: T,
		pub usingnamespace GenericVectorMath(@This(), T);
	};
}

fn GenericVector3(comptime T: type) type {
	return extern struct {
		x: T,
		y: T,
		z: T,
		pub usingnamespace GenericVectorMath(@This(), T);
	};
}

fn GenericVector4(comptime T: type) type {
	return extern struct {
		x: T,
		y: T,
		z: T,
		w: T,
		pub usingnamespace GenericVectorMath(@This(), T);
	};
}

pub const Mat4f = struct {
	columns: [4]Vec4f,
	pub fn identity() Mat4f {
		return Mat4f {
			.columns = [4]Vec4f { // Keep in mind that his is the transpose!
				Vec4f{.x=1, .y=0, .z=0, .w=0},
				Vec4f{.x=0, .y=1, .z=0, .w=0},
				Vec4f{.x=0, .y=0, .z=1, .w=0},
				Vec4f{.x=0, .y=0, .z=0, .w=1},
			}
		};
	}

	pub fn rotationX(rad: f32) Mat4f {
		const s = @sin(rad);
		const c = @cos(rad);
		return Mat4f {
			.columns = [4]Vec4f { // Keep in mind that his is the transpose!
				Vec4f{.x=1, .y=0, .z=0, .w=0},
				Vec4f{.x=0, .y=c, .z=s, .w=0},
				Vec4f{.x=0,.y=-s, .z=c, .w=0},
				Vec4f{.x=0, .y=0, .z=0, .w=1},
			}
		};
	}

	pub fn rotationY(rad: f32) Mat4f {
		const s = @sin(rad);
		const c = @cos(rad);
		return Mat4f {
			.columns = [4]Vec4f { // Keep in mind that his is the transpose!
				Vec4f{.x=c, .y=0,.z=-s, .w=0},
				Vec4f{.x=0, .y=1, .z=0, .w=0},
				Vec4f{.x=s, .y=0, .z=c, .w=0},
				Vec4f{.x=0, .y=0, .z=0, .w=1},
			}
		};
	}

	pub fn rotationZ(rad: f32) Mat4f {
		const s = @sin(rad);
		const c = @cos(rad);
		return Mat4f {
			.columns = [4]Vec4f { // Keep in mind that his is the transpose!
				Vec4f{.x=c, .y=s, .z=0, .w=0},
				Vec4f{.x=-s,.y=c, .z=0, .w=0},
				Vec4f{.x=0, .y=0, .z=1, .w=0},
				Vec4f{.x=0, .y=0, .z=0, .w=1},
			}
		};
	}

	pub fn perspective(fovY: f32, aspect: f32, near: f32, far: f32) Mat4f {
		const tanY = std.math.tan(fovY*0.5);
		const tanX = aspect*tanY;
		return Mat4f {
			.columns = [4]Vec4f { // Keep in mind that this is the transpose!
				Vec4f{.x=1/tanX, .y=0,      .z=0,                         .w=0},
				Vec4f{.x=0,      .y=1/tanY, .z=0,                         .w=0},
				Vec4f{.x=0,      .y=0,      .z=(far + near)/(near - far), .w=-1},
				Vec4f{.x=0,      .y=0,      .z=2*near*far/(near - far),   .w=0},
			}
		};
	}

	pub fn transpose(self: Mat4f) Mat4f {
		return Mat4f {
			.columns = [4]Vec4f { // Keep in mind that this is the transpose!
				Vec4f{.x=self.columns[0].x, .y=self.columns[1].x, .z=self.columns[2].x, .w=self.columns[3].x},
				Vec4f{.x=self.columns[0].y, .y=self.columns[1].y, .z=self.columns[2].y, .w=self.columns[3].y},
				Vec4f{.x=self.columns[0].z, .y=self.columns[1].z, .z=self.columns[2].z, .w=self.columns[3].z},
				Vec4f{.x=self.columns[0].w, .y=self.columns[1].w, .z=self.columns[2].w, .w=self.columns[3].w},
			}
		};
	}

	pub fn mul(self: Mat4f, other: Mat4f) Mat4f {
		var transposeSelf = self.transpose();
		var result: Mat4f = undefined;
		for(other.columns) |_, col| {
			result.columns[col].x = transposeSelf.columns[0].dot(other.columns[col]);
			result.columns[col].y = transposeSelf.columns[1].dot(other.columns[col]);
			result.columns[col].z = transposeSelf.columns[2].dot(other.columns[col]);
			result.columns[col].w = transposeSelf.columns[3].dot(other.columns[col]);
		}
		return result;
	}
};