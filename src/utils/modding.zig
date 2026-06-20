const std = @import("std");

const Feature = struct {
	id: []const u8,
	field: type,
};

pub fn getFeatures(comptime T: type) []const Feature {
	var features: []const Feature = &.{};

	inline for (@typeInfo(T).@"struct".decls) |mod| {
		const mod_struct = @field(T, mod.name);
		inline for (std.meta.declarations(mod_struct)) |feature| {
			features = features ++ [_]Feature{.{
				.id = mod.name ++ ":" ++ feature.name,
				.field = @field(mod_struct, feature.name),
			}};
		}
	}
	return features;
}
