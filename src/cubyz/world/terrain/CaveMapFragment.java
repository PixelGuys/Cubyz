package cubyz.world.terrain;

import cubyz.utils.math.CubyzMath;
import cubyz.world.ChunkData;
import cubyz.world.World;

/**
 * Cave data represented in a 1-Bit per block format, where 0 means empty and 1 means not empty.
 */
public class CaveMapFragment extends ChunkData {
	public static final int WIDTH = 1 << 8;
	public static final int WIDTH_MASK = WIDTH - 1;
	public static final int HEIGHT = 64; // Size of long
	public static final int HEIGHT_MASK = HEIGHT - 1;

	private final long[] data = new long[WIDTH*WIDTH];
	private final int voxelShift;

	public CaveMapFragment(int wx, int wy, int wz, int voxelSize, World world) {
		super(wx, wy, wz, voxelSize);
		voxelShift = CubyzMath.binaryLog(voxelSize);
		for(int x0 = 0; x0 < WIDTH*voxelSize; x0 += MapFragment.MAP_SIZE) {
			for(int z0 = 0; z0 < WIDTH*voxelSize; z0 += MapFragment.MAP_SIZE) {
				MapFragment mapFragment = world.chunkManager.getOrGenerateMapFragment(wx + x0, wz + z0, voxelSize);
				for(int x = 0; x < Math.min(WIDTH*voxelSize, MapFragment.MAP_SIZE); x += voxelSize) {
					for(int z = 0; z < Math.min(WIDTH*voxelSize, MapFragment.MAP_SIZE); z += voxelSize) {
						addRange(x0 + x, z0 + z, 0, (int)mapFragment.getHeight(wx + x + x0, wz + z + z0) - wy);
					}
				}
			}
		}
		world.chunkManager.generateCaveMapFragment(this);
	}

	private static int getIndex(int x, int z) {
		return x*WIDTH + z;
	}

	/**
	 * for example 3,11 would create the mask ...111_11111100_00000011
	 * @param start inclusive
	 * @param end exclusive
	 * @return
	 */
	public static long getMask(int start, int end) {
		long maskLower = 0xffff_ffff_ffff_ffffL >>> (64 - start);
		if(start <= 0) {
			maskLower = 0;
		} else if(start >= 64) {
			maskLower = 0xffff_ffff_ffff_ffffL;
		}
		long maskUpper = 0xffff_ffff_ffff_ffffL << end;
		if(end <= 0) {
			maskUpper = 0xffff_ffff_ffff_ffffL;
		} else if(end >= 64) {
			maskUpper = 0;
		}
		return maskLower | maskUpper;
	}

	/**
	 * 
	 * @param start inclusive
	 * @param end exclusive
	 */
	public void addRange(int relX, int relZ, int start, int end) {
		relX >>= voxelShift;
		relZ >>= voxelShift;
		start >>= voxelShift;
		end >>= voxelShift;
		assert(relX >= 0 && relX < WIDTH && relZ >= 0 && relZ < WIDTH) : "Coordinates out of range. Please provide correct relative coordinates.";
		data[getIndex(relX, relZ)] |= ~getMask(start, end);
	}

	/**
	 * 
	 * @param start inclusive
	 * @param end exclusive
	 */
	public void removeRange(int relX, int relZ, int start, int end) {
		relX >>= voxelShift;
		relZ >>= voxelShift;
		start >>= voxelShift;
		end >>= voxelShift;
		assert(relX >= 0 && relX < WIDTH && relZ >= 0 && relZ < WIDTH) : "Coordinates out of range. Please provide correct relative coordinates.";
		data[getIndex(relX, relZ)] &= getMask(start, end);
	}

	public long getHeightData(int relX, int relZ) {
		relX >>= voxelShift;
		relZ >>= voxelShift;
		assert(relX >= 0 && relX < WIDTH && relZ >= 0 && relZ < WIDTH) : "Coordinates out of range. Please provide correct relative coordinates.";
		return data[getIndex(relX, relZ)];
	}

	
}
