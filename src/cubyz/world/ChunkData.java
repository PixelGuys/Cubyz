package cubyz.world;

import cubyz.world.entity.Player;

public class ChunkData {
	public final int wx, wy, wz;
	public final int voxelSize;

	public ChunkData(int wx, int wy, int wz, int voxelSize) {
		assert (voxelSize - 1 & voxelSize) == 0 : "the voxel size must be a power of 2.";
		assert wx % voxelSize == 0 && wy % voxelSize == 0 && wz % voxelSize == 0 : "The coordinates are misaligned. They need to be aligned to the voxel size grid.";
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
		int shift = Math.min(Integer.numberOfTrailingZeros(wx), Math.min(Integer.numberOfTrailingZeros(wy), Integer.numberOfTrailingZeros(wz)));
		return (((wx >> shift) * 31 + (wy >> shift)) * 31 + (wz >> shift)) * 31 + voxelSize;
	}

	public float getPriority(Player source) {
		int halfWidth = voxelSize * Chunk.chunkSize / 2;
		return -(float) source.getPosition().distance(wx + halfWidth, wy + halfWidth, wz + halfWidth) / voxelSize;
	}

	public double getMinDistanceSquared(double px, double py, double pz) {
		int halfWidth = voxelSize * Chunk.chunkSize / 2;
		double dx = Math.abs(wx + halfWidth - px);
		double dy = Math.abs(wy + halfWidth - py);
		double dz = Math.abs(wz + halfWidth - pz);
		dx = Math.max(0, dx - halfWidth);
		dy = Math.max(0, dy - halfWidth);
		dz = Math.max(0, dz - halfWidth);
		return dx*dx + dy*dy + dz*dz;
	}
	
	@Override
	public String toString() {
		return "{("+wx+", "+wy+", "+wz+"), "+voxelSize+"}";
	}
}
