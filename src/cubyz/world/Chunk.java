package cubyz.world;

import cubyz.client.ClientSettings;
import cubyz.client.GameLauncher;
import cubyz.utils.Logger;
import cubyz.utils.math.Bits;
import cubyz.world.save.ChunkIO;

public abstract class Chunk extends ChunkData {
	
	public static final int chunkShift = 5;
	
	public static final int chunkShift2 = 2*chunkShift;
	
	public static final int chunkSize = 1 << chunkShift;
	
	public static final int chunkMask = chunkSize - 1;
	
	protected final World world;
	protected final int[] blocks = new int[chunkSize*chunkSize*chunkSize];
	
	private boolean wasChanged = false;
	/** When a chunk is cleaned, it won't be saved by the ChunkMamanger anymore, so following changes need to be saved directly. */
	private boolean wasCleaned = false;
	protected boolean generated = false;
	
	public final int width;

	public Chunk(World world, int wx, int wy, int wz, int voxelSize) {
		super(wx, wy, wz, voxelSize);
		this.world = world;
		width = voxelSize*chunkSize;
	}
	/**
	 * This is useful to convert for loops to work for reduced resolution:<br>
	 * Instead of using<br>
	 * for(int x = start; x < end; x++)<br>
	 * for(int x = chunk.startIndex(start); x < end; x += chunk.getVoxelSize())<br>
	 * should be used to only activate those voxels that are used in Cubyz's downscaling technique.
	 * @param index The normal starting index(for normal generation).
	 * @return the next higher index that is inside the grid of this chunk.
	 */
	public abstract int startIndex(int start);
	
	/**
	 * Updates a block if current value is air or the current block is degradable.<br>
	 * Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	 * @param x relative x without considering resolution.
	 * @param y relative y without considering resolution.
	 * @param z relative z without considering resolution.
	 * @param newBlock
	 */
	public abstract void updateBlockIfDegradable(int x, int y, int z, int newBlock);
	
	/**
	 * Updates a block if it is inside this chunk.<br>
	 * Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	 * @param x relative x without considering resolution.
	 * @param y relative y without considering resolution.
	 * @param z relative z without considering resolution.
	 * @param newBlock
	 */
	public abstract void updateBlock(int x, int y, int z, int newBlock);
	
	/**
	 * Updates a block if it is inside this chunk. Should be used in generation to prevent accidently storing these as changes.<br>
	 * Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	 * @param x relative x without considering resolution.
	 * @param y relative y without considering resolution.
	 * @param z relative z without considering resolution.
	 * @param newBlock
	 */
	public abstract void updateBlockInGeneration(int x, int y, int z, int newBlock);
	
	/**
	 * Updates a block if it is inside this chunk.<br>
	 * Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	 * @param x relative x without considering resolution.
	 * @param y relative y without considering resolution.
	 * @param z relative z without considering resolution.
	 * @return block at x y z
	 */
	public abstract int getBlock(int x, int y, int z);
	
	/**
	 * Generates this chunk.
	 * If the chunk was already saved it is loaded from file instead.
	 * @param gen
	 */
	public void generateFrom(ChunkManager gen) {
		assert(!generated) : "Seriously, why would you generate this chunk twice???";
		if(!ChunkIO.loadChunkFromFile(world, this)) {
			gen.generate(this);
		}
		generated = true;
	}
	
	/**
	 * Checks if the given <b>relative</b> coordinates lie within the bounds of this chunk.
	 * @param x
	 * @param z
	 * @return
	 */
	public boolean liesInChunk(int x, int y, int z) {
		return x >= 0
				&& x < width
				&& y >= 0
				&& y < width
				&& z >= 0
				&& z < width;
	}
	
	/**
	 * @return this chunks width.
	 */
	public int getWidth() {
		return width;
	}
	
	public void setChanged() {
		wasChanged = true;
		synchronized(this) {
			if(wasCleaned) {
				save();
			}
		}
	}
	
	public void clean() {
		synchronized(this) {
			wasCleaned = true;
			save();
		}
	}
	
	/**
	 * Saves this chunk.
	 */
	public void save() {
		if(wasChanged) {
			ChunkIO.storeChunkToFile(world, this);
			wasChanged = false;
			// Update the next lod chunk:
			if(voxelSize != 1 << ClientSettings.HIGHEST_LOD) { // TODO: Store the highest LOD somewhere more accessible.
				ReducedChunk chunk = world.chunkManager.getOrGenerateReducedChunk(wx, wy, wz, voxelSize*2);
				chunk.updateFromLowerResolution(this);
			}
		}
	}
	
	/**
	 * Saves all the data of the chunk into the given byte array using the blockPalette.
	 * @param data data.length = blocks.length*4
	 */
	public void saveTo(byte[] data) {
		for(int i = 0; i < blocks.length; i++) {
			// Convert the runtime ID to the palette (world-specific) ID
			int palId = world.wio.blockPalette.getIndex(blocks[i]);
			Bits.putInt(data, i*4, palId);
		}
	}
	
	/**
	 * Loads all the data of the chunk from the given byte array using the blockPalette.
	 * @param data data.length = blocks.length*4
	 */
	public void loadFrom(byte[] data) {
		for(int i = 0; i < blocks.length; i++) {
			// Convert the palette (world-specific) ID to the runtime ID
			int palId = Bits.getInt(data, i*4);
			blocks[i] = world.wio.blockPalette.getElement(palId);
		}
	}
	
	/**
	 * Gets the index of a given position inside this chunk.
	 * Use this as much as possible, so it gets inlined by the VM.
	 * @param x 0 ≤ x < chunkSize
	 * @param y 0 ≤ y < chunkSize
	 * @param z 0 ≤ z < chunkSize
	 * @return
	 */
	public static int getIndex(int x, int y, int z) {
		assert((x & chunkMask) == x && (y & chunkMask) == y && (z & chunkMask) == z) : "Your coordinates are outside this chunk. You should be happy this assertion caught it.";
		return (x << chunkShift) | (y << chunkShift2) | z;
	}
	
	@Override
	public void finalize() {
		if(wasChanged) {
			Logger.crash("Unsaved chunk: "+wx+" "+wy+" "+wz+" "+voxelSize+" "+wasCleaned);
			clean();
			GameLauncher.instance.exit();
		}
	}
}
