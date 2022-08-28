
pub const Vec2i = GenericVector2(i32);
pub const Vec2f = GenericVector2(f32);
pub const Vec2d = GenericVector2(f64);
pub const Vec3i = GenericVector3(i32);
pub const Vec3f = GenericVector3(f32);
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