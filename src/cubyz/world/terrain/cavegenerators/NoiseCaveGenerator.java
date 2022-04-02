package cubyz.world.terrain.cavegenerators;

import cubyz.api.CurrentWorldRegistries;
import cubyz.api.Resource;
import cubyz.world.terrain.CaveMapFragment;
import cubyz.world.terrain.InterpolatableCaveBiomeMap;
import cubyz.world.terrain.noise.Cached3DFractalNoise;
import pixelguys.json.JsonObject;

/**
 * Generates cave system using a fractal algorithm.
 */

public class NoiseCaveGenerator implements CaveGenerator {
	private static final int SCALE = 64;
	private static final int INTERPOLATED_PART = 4;

	@Override
	public void init(JsonObject parameters, CurrentWorldRegistries registries) {
	}
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "noise_cave");
	}
	
	@Override
	public int getPriority() {
		return 65536;
	}

	private float getValue(Cached3DFractalNoise noise, InterpolatableCaveBiomeMap map, int wx, int wy, int wz) {
		return noise.getValue(wx, wy, wz) + map.interpolateValue(wx, wy, wz)*SCALE;
	}
	
	@Override
	public void generate(long seed, CaveMapFragment map) {
		if (map.voxelSize > 2) return;
		InterpolatableCaveBiomeMap biomeMap = new InterpolatableCaveBiomeMap(map, CaveMapFragment.WIDTH*map.voxelSize);
		int outerSize = Math.max(map.voxelSize, INTERPOLATED_PART);
		Cached3DFractalNoise noise = new Cached3DFractalNoise(map.wx, map.wy & ~(CaveMapFragment.WIDTH*map.voxelSize - 1), map.wz, outerSize, map.voxelSize*CaveMapFragment.WIDTH, seed, SCALE);
		for(int x = 0; x < map.voxelSize*CaveMapFragment.WIDTH; x += outerSize) {
			for(int y = 0; y < map.voxelSize*CaveMapFragment.HEIGHT; y += outerSize) {
				for(int z = 0; z < map.voxelSize*CaveMapFragment.WIDTH; z += outerSize) {
					float val000 = getValue(noise, biomeMap, x + map.wx, y + map.wy, z + map.wz);
					float val001 = getValue(noise, biomeMap, x + map.wx, y + map.wy, z + map.wz + outerSize);
					float val010 = getValue(noise, biomeMap, x + map.wx, y + map.wy + outerSize, z + map.wz);
					float val011 = getValue(noise, biomeMap, x + map.wx, y + map.wy + outerSize, z + map.wz + outerSize);
					float val100 = getValue(noise, biomeMap, x + map.wx + outerSize, y + map.wy, z + map.wz);
					float val101 = getValue(noise, biomeMap, x + map.wx + outerSize, y + map.wy, z + map.wz + outerSize);
					float val110 = getValue(noise, biomeMap, x + map.wx + outerSize, y + map.wy + outerSize, z + map.wz);
					float val111 = getValue(noise, biomeMap, x + map.wx + outerSize, y + map.wy + outerSize, z + map.wz + outerSize);
					// Test if they are all inside or all outside the cave to skip these cases:
					float measureForEquality = Math.signum(val000) + Math.signum(val001) + Math.signum(val010) + Math.signum(val011) + Math.signum(val100) + Math.signum(val101) + Math.signum(val110) + Math.signum(val111);
					if(measureForEquality == -8) {
						// No cave in here :)
						continue;
					}
					if(measureForEquality == 8) {
						// All cave in here :)
						for(int dx = 0; dx < outerSize; dx += map.voxelSize) {
							for(int dz = 0; dz < outerSize; dz += map.voxelSize) {
								map.removeRange(x + dx, z + dz, y, y + outerSize);
							}
						}
					} else {
						// Uses trilinear interpolation for the details.
						// Luckily due to the blocky nature of the game there is no visible artifacts from it.
						for(int dx = 0; dx < outerSize; dx += map.voxelSize) {
							for(int dz = 0; dz < outerSize; dz += map.voxelSize) {
								float ix = dx/(float)outerSize;
								float iz = dz/(float)outerSize;
								float lowerVal = (
									+ (1 - ix)*(1 - iz)*val000
									+ (1 - ix)*iz*val001
									+ ix*(1 - iz)*val100
									+ ix*iz*val101
								);
								float upperVal = (
										+ (1 - ix)*(1 - iz)*val010
										+ (1 - ix)*iz*val011
										+ ix*(1 - iz)*val110
										+ ix*iz*val111
								);
								if(upperVal*lowerVal > 0) { // All y values have the same sign → the entire column is the same.
									if(upperVal > 0) {
										// All cave in here :)
										map.removeRange(x + dx, z + dz, y, y + outerSize);
									} else {
										// No cave in here :)
									}
								} else {
									// Could be probably more efficient, but I'm lazy right now and I'll just go through the entire range:
									for(int dy = 0; dy < outerSize; dy += map.voxelSize) {
										float iy = dy/(float)outerSize;
										float val = (1 - iy)*lowerVal + iy*upperVal;
										if(val > 0)
											map.removeRange(x + dx, z + dz, y + dy, y + dy + map.voxelSize);
									}
								}
							}
						}
					}
				}
			}
		}
	}

	@Override
	public long getGeneratorSeed() {
		return 0x76490367012869L;
	}
}
