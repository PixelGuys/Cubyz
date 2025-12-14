const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

// MARK: functionPtrCast()
fn CastFunctionSelfToAnyopaqueType(Fn: type) type {
	var typeInfo = @typeInfo(Fn);
	var params = typeInfo.@"fn".params[0..typeInfo.@"fn".params.len].*;
	if(@sizeOf(params[0].type.?) != @sizeOf(*anyopaque) or @alignOf(params[0].type.?) != @alignOf(*anyopaque)) {
		@compileError(std.fmt.comptimePrint("Cannot convert {} to *anyopaque", .{params[0].type.?}));
	}
	params[0].type = *anyopaque;
	typeInfo.@"fn".params = params[0..];
	return @Type(typeInfo);
}
/// Turns the first parameter into a anyopaque*
pub fn castFunctionSelfToAnyopaque(function: anytype) *const CastFunctionSelfToAnyopaqueType(@TypeOf(function)) {
	return @ptrCast(&function);
}

fn CastFunctionReturnToAnyopaqueType(Fn: type) type {
	var typeInfo = @typeInfo(Fn);
	if(@sizeOf(typeInfo.@"fn".return_type.?) != @sizeOf(*anyopaque) or @alignOf(typeInfo.@"fn".return_type.?) != @alignOf(*anyopaque) or @typeInfo(typeInfo.@"fn".return_type.?) == .optional) {
		@compileError(std.fmt.comptimePrint("Cannot convert {} to *anyopaque", .{typeInfo.@"fn".return_type.?}));
	}
	typeInfo.@"fn".return_type = *anyopaque;
	return @Type(typeInfo);
}

fn CastFunctionReturnToOptionalAnyopaqueType(Fn: type) type {
	var typeInfo = @typeInfo(Fn);
	if(@sizeOf(typeInfo.@"fn".return_type.?) != @sizeOf(?*anyopaque) or @alignOf(typeInfo.@"fn".return_type.?) != @alignOf(?*anyopaque) or @typeInfo(typeInfo.@"fn".return_type.?) != .optional) {
		@compileError(std.fmt.comptimePrint("Cannot convert {} to ?*anyopaque", .{typeInfo.@"fn".return_type.?}));
	}
	typeInfo.@"fn".return_type = ?*anyopaque;
	return @Type(typeInfo);
}
/// Turns the return parameter into a anyopaque*
pub fn castFunctionReturnToAnyopaque(function: anytype) *const CastFunctionReturnToAnyopaqueType(@TypeOf(function)) {
	return @ptrCast(&function);
}
pub fn castFunctionReturnToOptionalAnyopaque(function: anytype) *const CastFunctionReturnToOptionalAnyopaqueType(@TypeOf(function)) {
	return @ptrCast(&function);
}

pub fn StringIndexedVTables(VTable: type, TypeList: type) type {
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
						if(field.default_value_ptr) |default_| {
							const default: *const field.type = @ptrCast(@alignCast(default_));
							if(field.type == @TypeOf(default)) {
								@field(result, field.name) = default;
							} else {
								@field(result, field.name) = default.*;
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
