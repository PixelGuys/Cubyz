const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub fn StringIndexedVTables(VTable: type, TypeList: type, Defaults: type) type {
	return struct {
		const map: std.StaticStringMap(VTable) = createMap();

		fn createMap() std.StaticStringMap(VTable) {
			const decls = @typeInfo(TypeList).@"struct".decls;
			var vals: [decls.len]struct {[]const u8, VTable} = undefined;
			for(0.., decls) |i, declaration| {
				const Type = @field(TypeList, declaration.name);
				var result: VTable = undefined;
				for(@typeInfo(VTable).@"struct".fields) |field| {
					if(std.mem.eql(u8, field.name, "id")) {
						continue;
					}
					if(!@hasDecl(Type, field.name)) {
						if(@hasDecl(Defaults, field.name)) {
							if(field.type == @TypeOf(@field(Defaults, field.name))) {
								@field(result, field.name) = @field(Defaults, field.name);
							} else {
								@field(result, field.name) = &@field(Defaults, field.name);
							}
						} else {
							@compileError("VTable missing field '" ++ field.name ++ "'");
						}
					} else {
						if(field.type == @TypeOf(@field(Type, field.name))) {
							@field(result, field.name) = @field(Type, field.name);
						} else {
							@field(result, field.name) = &@field(Type, field.name);
						}
					}
				}
				if(@hasDecl(VTable, "id")) {
					result.id = declaration.name;
				}
				vals[i] = .{declaration.name, result};
			}
			return .initComptime(vals);
		}

		pub fn getEntry(id: []const u8) ?*const VTable {
			return &map.kvs.values[map.getIndex(id) orelse return null];
		}

		pub fn callAll(comptime func: []const u8) void {
			inline for(@typeInfo(TypeList).@"struct".decls) |declaration| {
				const mode = @field(TypeList, declaration.name);
				if(@hasDecl(mode, func)) {
					@field(mode, func)();
				}
			}
		}
	};
}
