const std = @import("std");

// MARK: functionPtrCast()
fn CastFunctionSelfToConstAnyopaqueType(Fn: type) type {
	var typeInfo = @typeInfo(Fn);
	var paramTypes: [typeInfo.@"fn".params.len]type = undefined;
	var paramAttributes: [typeInfo.@"fn".params.len]std.builtin.Type.Fn.Param.Attributes = undefined;
	for (typeInfo.@"fn".params[0..typeInfo.@"fn".params.len], 0..) |param, i| {
		paramTypes[i] = param.type.?;
		paramAttributes[i] = .{.@"noalias" = param.is_noalias};
	}
	const isMutablePointer = @typeInfo(paramTypes[0]) == .pointer and !@typeInfo(paramTypes[0]).pointer.is_const;
	if (@sizeOf(paramTypes[0]) != @sizeOf(*const anyopaque) or @alignOf(paramTypes[0]) != @alignOf(*const anyopaque) or isMutablePointer) {
		@compileError(std.fmt.comptimePrint("Cannot convert {} to *const anyopaque", .{paramTypes[0]}));
	}
	paramTypes[0] = *const anyopaque;
	return @Fn(&paramTypes, &paramAttributes, typeInfo.@"fn".return_type.?, .{.@"callconv" = typeInfo.@"fn".calling_convention, .varargs = typeInfo.@"fn".is_var_args});
}
/// Turns the first parameter into a *const anyopaque
pub fn castFunctionSelfToConstAnyopaque(function: anytype) *const CastFunctionSelfToConstAnyopaqueType(@TypeOf(function)) {
	return @ptrCast(&function);
}

// MARK: functionPtrCast()
fn CastFunctionSelfToAnyopaqueType(Fn: type) type {
	var typeInfo = @typeInfo(Fn);
	var paramTypes: [typeInfo.@"fn".params.len]type = undefined;
	var paramAttributes: [typeInfo.@"fn".params.len]std.builtin.Type.Fn.Param.Attributes = undefined;
	for (typeInfo.@"fn".params[0..typeInfo.@"fn".params.len], 0..) |param, i| {
		paramTypes[i] = param.type.?;
		paramAttributes[i] = .{.@"noalias" = param.is_noalias};
	}
	if (@sizeOf(paramTypes[0]) != @sizeOf(*anyopaque) or @alignOf(paramTypes[0]) != @alignOf(*anyopaque)) {
		@compileError(std.fmt.comptimePrint("Cannot convert {} to *anyopaque", .{paramTypes[0]}));
	}
	paramTypes[0] = *anyopaque;
	return @Fn(&paramTypes, &paramAttributes, typeInfo.@"fn".return_type.?, .{.@"callconv" = typeInfo.@"fn".calling_convention, .varargs = typeInfo.@"fn".is_var_args});
}
/// Turns the first parameter into a *anyopaque
pub fn castFunctionSelfToAnyopaque(function: anytype) *const CastFunctionSelfToAnyopaqueType(@TypeOf(function)) {
	return @ptrCast(&function);
}

fn CastFunctionReturnToAnyopaqueType(Fn: type) type {
	var typeInfo = @typeInfo(Fn);
	var paramTypes: [typeInfo.@"fn".params.len]type = undefined;
	var paramAttributes: [typeInfo.@"fn".params.len]std.builtin.Type.Fn.Param.Attributes = undefined;
	for (typeInfo.@"fn".params[0..typeInfo.@"fn".params.len], 0..) |param, i| {
		paramTypes[i] = param.type.?;
		paramAttributes[i] = .{.@"noalias" = param.is_noalias};
	}
	if (@sizeOf(typeInfo.@"fn".return_type.?) != @sizeOf(*anyopaque) or @alignOf(typeInfo.@"fn".return_type.?) != @alignOf(*anyopaque) or @typeInfo(typeInfo.@"fn".return_type.?) == .optional) {
		@compileError(std.fmt.comptimePrint("Cannot convert {} to *anyopaque", .{typeInfo.@"fn".return_type.?}));
	}
	const ReturnType = *anyopaque;
	return @Fn(&paramTypes, &paramAttributes, ReturnType, .{.@"callconv" = typeInfo.@"fn".calling_convention, .varargs = typeInfo.@"fn".is_var_args});
}

fn CastFunctionReturnToOptionalAnyopaqueType(Fn: type) type {
	var typeInfo = @typeInfo(Fn);
	var paramTypes: [typeInfo.@"fn".params.len]type = undefined;
	var paramAttributes: [typeInfo.@"fn".params.len]std.builtin.Type.Fn.Param.Attributes = undefined;
	for (typeInfo.@"fn".params[0..typeInfo.@"fn".params.len], 0..) |param, i| {
		paramTypes[i] = param.type.?;
		paramAttributes[i] = .{.@"noalias" = param.is_noalias};
	}
	if (@sizeOf(typeInfo.@"fn".return_type.?) != @sizeOf(?*anyopaque) or @alignOf(typeInfo.@"fn".return_type.?) != @alignOf(?*anyopaque) or @typeInfo(typeInfo.@"fn".return_type.?) != .optional) {
		@compileError(std.fmt.comptimePrint("Cannot convert {} to ?*anyopaque", .{typeInfo.@"fn".return_type.?}));
	}
	const ReturnType = ?*anyopaque;
	return @Fn(&paramTypes, &paramAttributes, ReturnType, .{.@"callconv" = typeInfo.@"fn".calling_convention, .varargs = typeInfo.@"fn".is_var_args});
}
/// Turns the return parameter into a *anyopaque
pub fn castFunctionReturnToAnyopaque(function: anytype) *const CastFunctionReturnToAnyopaqueType(@TypeOf(function)) {
	return @ptrCast(&function);
}
pub fn castFunctionReturnToOptionalAnyopaque(function: anytype) *const CastFunctionReturnToOptionalAnyopaqueType(@TypeOf(function)) {
	return @ptrCast(&function);
}

pub fn concatComptime(comptime separator: []const u8, comptime array: anytype) []const u8 {
	comptime var str: []const u8 = "";
	comptime for (array, 0..) |fieldName, index| {
		str = str ++ fieldName;
		if (index < array.len - 1) str = str ++ separator;
	};
	return str;
}
