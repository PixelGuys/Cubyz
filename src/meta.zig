const std = @import("std");

// MARK: functionPtrCast()
fn CastFunctionSelfToConstAnyopaqueType(Fn: type) type {
	var typeInfo = @typeInfo(Fn);
	var params = typeInfo.@"fn".params[0..typeInfo.@"fn".params.len].*;
	const isMutablePointer = @typeInfo(params[0].type.?) == .pointer and !@typeInfo(params[0].type.?).pointer.is_const;
	if(@sizeOf(params[0].type.?) != @sizeOf(*const anyopaque) or @alignOf(params[0].type.?) != @alignOf(*const anyopaque) or isMutablePointer) {
		@compileError(std.fmt.comptimePrint("Cannot convert {} to *const anyopaque", .{params[0].type.?}));
	}
	params[0].type = *const anyopaque;
	typeInfo.@"fn".params = params[0..];
	return @Type(typeInfo);
}
/// Turns the first parameter into a *const anyopaque
pub fn castFunctionSelfToConstAnyopaque(function: anytype) *const CastFunctionSelfToConstAnyopaqueType(@TypeOf(function)) {
	return @ptrCast(&function);
}

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
/// Turns the first parameter into a *anyopaque
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
/// Turns the return parameter into a *anyopaque
pub fn castFunctionReturnToAnyopaque(function: anytype) *const CastFunctionReturnToAnyopaqueType(@TypeOf(function)) {
	return @ptrCast(&function);
}
pub fn castFunctionReturnToOptionalAnyopaque(function: anytype) *const CastFunctionReturnToOptionalAnyopaqueType(@TypeOf(function)) {
	return @ptrCast(&function);
}
