package cubyz.world.terrain.cavegenerators;

import cubyz.api.CurrentWorldRegistries;
import cubyz.api.Resource;
import cubyz.multiplayer.server.Server;
import cubyz.world.terrain.CaveMapFragment;
import cubyz.world.terrain.MapFragment;
import pixelguys.json.JsonObject;

public class SurfaceGenerator implements CaveGenerator {
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz:surface");
	}

	@Override
	public void init(JsonObject parameters, CurrentWorldRegistries registries) {

	}

	@Override
	public int getPriority() {
		return 1024;
	}

	@Override
	public void generate(long seed, CaveMapFragment map) {
		for(int x0 = 0; x0 < CaveMapFragment.WIDTH*map.voxelSize; x0 += MapFragment.MAP_SIZE) {
			for(int z0 = 0; z0 < CaveMapFragment.WIDTH*map.voxelSize; z0 += MapFragment.MAP_SIZE) {
				MapFragment mapFragment = Server.world.chunkManager.getOrGenerateMapFragment(map.wx + x0, map.wz + z0, map.voxelSize);
				for(int x = 0; x < Math.min(CaveMapFragment.WIDTH*map.voxelSize, MapFragment.MAP_SIZE); x += map.voxelSize) {
					for(int z = 0; z < Math.min(CaveMapFragment.WIDTH*map.voxelSize, MapFragment.MAP_SIZE); z += map.voxelSize) {
						map.addRange(x0 + x, z0 + z, 0, (int)mapFragment.getHeight(map.wx + x + x0, map.wz + z + z0) - map.wy);
					}
				}
			}
		}
	}

	@Override
	public long getGeneratorSeed() {
		return 0x7658930674389L;
	}
}
