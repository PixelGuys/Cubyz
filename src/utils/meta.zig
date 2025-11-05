const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub fn StringIndexedVTables(VTable: type, TypeList: type, Defaults: type) type {
	return struct {
		var hashmap: std.StringHashMap(VTable) = undefined;

		pub fn init(allocator: NeverFailingAllocator) void {
			hashmap = .init(allocator.allocator);
			inline for(@typeInfo(TypeList).@"struct".decls) |declaration| {
				register(declaration.name, @field(TypeList, declaration.name));
			}
		}

		pub fn getEntry(id: []const u8) ?*VTable {
			return hashmap.getPtr(id);
		}

		fn register(comptime id: []const u8, comptime Type: type) void {
			if(@hasDecl(Type, "init")) {
				Type.init();
			}
			var result: VTable = undefined;
			inline for(@typeInfo(VTable).@"struct".fields) |field| {
				comptime if(std.mem.eql(u8, field.name, "id")) {
					continue;
				};
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
				result.id = id;
			}
			hashmap.putNoClobber(id, result) catch unreachable;
		}

		pub fn callAll(comptime func: []const u8) void {
			inline for(@typeInfo(TypeList).@"struct".decls) |declaration| {
				const mode = @field(TypeList, declaration.name);
				if(@hasDecl(mode, func)) {
					@field(mode, func)();
				}
			}
		}

		pub fn reset() void {
			callAll("reset");
		}

		pub fn deinit() void {
			callAll("deinit");
			hashmap.deinit();
		}
	};
}
