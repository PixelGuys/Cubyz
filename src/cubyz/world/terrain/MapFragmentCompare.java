package cubyz.world.terrain;

public class MapFragmentCompare {
	public final int wx, wz;
	public final int voxelSize;

	public MapFragmentCompare(int wx, int wz, int voxelSize) {
		assert((voxelSize - 1 & voxelSize) == 0) : "the voxel size must be a power of 2.";
		assert(wx % voxelSize == 0 && wz % voxelSize == 0) : "The coordinates are misaligned. They need to be aligned to the voxel size grid.";
		this.wx = wx;
		this.wz = wz;
		this.voxelSize = voxelSize;
	}

	@Override
	public boolean equals(Object other) {
		if (other instanceof MapFragment) {
			MapFragment map = (MapFragment) other;
			return wx == map.wx && wz == map.wz && voxelSize == map.voxelSize;
		}
		return false;
	}

	@Override
	public int hashCode() {
		return (wx >> MapFragment.MAP_SHIFT) * 33 + (wz >> MapFragment.MAP_SHIFT) ^ voxelSize;
	}
}
