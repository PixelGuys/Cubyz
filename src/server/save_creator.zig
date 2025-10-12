const std = @import("std");

const main = @import("main");
const ConnectionManager = main.network.ConnectionManager;
const settings = main.settings;
const Vec2f = main.vec.Vec2f;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

fn findValidFolderName(allocator: NeverFailingAllocator, name: []const u8) []const u8 {
	// Remove illegal ASCII characters:
	const escapedName = main.stackAllocator.alloc(u8, name.len);
	defer main.stackAllocator.free(escapedName);
	for(name, 0..) |char, i| {
		escapedName[i] = switch(char) {
			'a'...'z', 'A'...'Z', '0'...'9', '_', '-', '.', ' ' => char,
			128...255 => char,
			else => '-',
		};
	}

	// Avoid duplicates:
	var resultName = main.stackAllocator.dupe(u8, escapedName);
	defer main.stackAllocator.free(resultName);
	var i: usize = 0;
	while(true) {
		const resultPath = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}", .{resultName}) catch unreachable;
		defer main.stackAllocator.free(resultPath);

		if(!main.files.cubyzDir().hasDir(resultPath)) break;

		main.stackAllocator.free(resultName);
		resultName = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}_{}", .{escapedName, i}) catch unreachable;
		i += 1;
	}
	return allocator.dupe(u8, resultName);
}

pub fn flawedCreateWorld(worldName: []const u8, gamemode: main.game.Gamemode, allowCheats: bool, testingMode: bool) !void {
	const worldPath = findValidFolderName(main.stackAllocator, worldName);
	defer main.stackAllocator.free(worldPath);
	const saveFolder = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}", .{worldPath}) catch unreachable;
	defer main.stackAllocator.free(saveFolder);
	try main.files.cubyzDir().makePath(saveFolder);
	{
		const generatorSettingsPath = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/generatorSettings.zig.zon", .{worldPath}) catch unreachable;
		defer main.stackAllocator.free(generatorSettingsPath);
		const generatorSettings = main.ZonElement.initObject(main.stackAllocator);
		defer generatorSettings.deinit(main.stackAllocator);
		const climateGenerator = main.ZonElement.initObject(main.stackAllocator);
		climateGenerator.put("id", "cubyz:noise_based_voronoi"); // TODO: Make this configurable
		generatorSettings.put("climateGenerator", climateGenerator);
		const mapGenerator = main.ZonElement.initObject(main.stackAllocator);
		mapGenerator.put("id", "cubyz:mapgen_v1"); // TODO: Make this configurable
		generatorSettings.put("mapGenerator", mapGenerator);
		const climateWavelengths = main.ZonElement.initObject(main.stackAllocator);
		climateWavelengths.put("hot_cold", 2400);
		climateWavelengths.put("land_ocean", 3200);
		climateWavelengths.put("wet_dry", 1800);
		climateWavelengths.put("vegetation", 1600);
		climateWavelengths.put("mountain", 512);
		generatorSettings.put("climateWavelengths", climateWavelengths);
		try main.files.cubyzDir().writeZon(generatorSettingsPath, generatorSettings);
	}
	{
		const worldInfoPath = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/world.zig.zon", .{worldPath}) catch unreachable;
		defer main.stackAllocator.free(worldInfoPath);
		const worldInfo = main.ZonElement.initObject(main.stackAllocator);
		defer worldInfo.deinit(main.stackAllocator);

		worldInfo.put("name", worldName);
		worldInfo.put("version", main.server.world_zig.worldDataVersion);
		worldInfo.put("lastUsedTime", std.time.milliTimestamp());

		try main.files.cubyzDir().writeZon(worldInfoPath, worldInfo);
	}
	{
		const gamerulePath = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/gamerules.zig.zon", .{worldPath}) catch unreachable;
		defer main.stackAllocator.free(gamerulePath);
		const gamerules = main.ZonElement.initObject(main.stackAllocator);
		defer gamerules.deinit(main.stackAllocator);

		gamerules.put("default_gamemode", @tagName(gamemode));
		gamerules.put("cheats", allowCheats);
		gamerules.put("testingMode", testingMode);

		try main.files.cubyzDir().writeZon(gamerulePath, gamerules);
	}
	{ // Make assets subfolder
		const assetsPath = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/assets", .{worldPath}) catch unreachable;
		defer main.stackAllocator.free(assetsPath);
		try main.files.cubyzDir().makePath(assetsPath);
	}
	// TODO: Make the seed configurable

}
