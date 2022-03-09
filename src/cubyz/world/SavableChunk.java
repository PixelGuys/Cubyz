package cubyz.world;

/**
 * A chunk(-like) that can be saved/loaded to/from a byte array.
 */
public abstract class SavableChunk extends ChunkData {
	public SavableChunk(int wx, int wy, int wz, int voxelSize) {
		super(wx, wy, wz, voxelSize);
	}

	public abstract byte[] saveToByteArray();

	public abstract boolean loadFromByteArray(byte[] array, int len);

	public abstract int getWidth();

	/**
	 * @return The file ending of the save file.
	 */
	public abstract String fileEnding();
}
