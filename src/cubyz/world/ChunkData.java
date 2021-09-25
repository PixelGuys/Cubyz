package cubyz.world;

import java.util.function.Consumer;

public class ChunkData {
	protected Consumer<ChunkData> meshListener;
	public final int wx, wy, wz;
	public final int voxelSize;
	public ChunkData(int wx, int wy, int wz, int voxelSize) {
		this.wx = wx;
		this.wy = wy;
		this.wz = wz;
		this.voxelSize = voxelSize;
	}

	/**
	 * The mesh listener will be notified every time the mesh should change.
	 * @param listener
	 */
	public void setMeshListener(Consumer<ChunkData> listener) {
		meshListener = listener;
	}

	@Override
	public boolean equals(Object other) {
		if(other instanceof ChunkData) {
			ChunkData data = (ChunkData)other;
			return wx == data.wx && wy == data.wy && wz == data.wz && voxelSize == data.voxelSize;
		}
		return false;
	}

	@Override
	public int hashCode() {
		return ((wx*31 + wy)*31 + wz)*31 + voxelSize;
	}
}
