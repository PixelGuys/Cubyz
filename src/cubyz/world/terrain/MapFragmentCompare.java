package cubyz.world.terrain;

public class MapFragmentCompare {
	public final int wx, wz;
	public final int voxelSize;

	public MapFragmentCompare(int wx, int wz, int voxelSize) {
		this.wx = wx;
		this.wz = wz;
		this.voxelSize = voxelSize;
	}

	@Override
	public boolean equals(Object other) {
		if(other instanceof MapFragment) {
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
