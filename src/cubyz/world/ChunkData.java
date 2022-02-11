package cubyz.world;

import cubyz.world.entity.Player;

public class ChunkData implements Comparable<ChunkData> {
	public final int wx, wy, wz;
	public final int voxelSize;
	protected float priority;

	public ChunkData(int wx, int wy, int wz, int voxelSize) {
		assert((voxelSize - 1 & voxelSize) == 0) : "the voxel size must be a power of 2.";
		assert(wx % voxelSize == 0 && wy % voxelSize == 0 && wz % voxelSize == 0) : "The coordinates are misaligned. They need to be aligned to the voxel size grid.";
		this.wx = wx;
		this.wy = wy;
		this.wz = wz;
		this.voxelSize = voxelSize;
	}

	@Override
	public boolean equals(Object other) {
		if (other instanceof ChunkData) {
			ChunkData data = (ChunkData) other;
			return wx == data.wx && wy == data.wy && wz == data.wz && voxelSize == data.voxelSize;
		}
		return false;
	}

	@Override
	public int hashCode() {
		return ((wx * 31 + wy) * 31 + wz) * 31 + voxelSize;
	}

	public void updatePriority(Player source) {
		int halfWidth = voxelSize * Chunk.chunkSize / 2;
		priority = -(float) source.getPosition().distance(wx + halfWidth, wy + halfWidth, wz + halfWidth) / voxelSize;
	}

	@Override
	public int compareTo(ChunkData other) {
		return (int) Math.signum(priority - other.priority);
	}
	
	@Override
	public String toString() {
		return "{("+wx+", "+wy+", "+wz+"), "+voxelSize+"}";
	}
}
