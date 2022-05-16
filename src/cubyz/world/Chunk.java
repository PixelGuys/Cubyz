package cubyz.world;

import cubyz.Constants;
import cubyz.world.terrain.CaveBiomeMap;
import org.joml.Vector3d;

import cubyz.client.GameLauncher;
import cubyz.utils.Logger;
import cubyz.utils.math.Bits;
import cubyz.world.save.ChunkIO;
import cubyz.world.terrain.CaveMap;
import cubyz.world.terrain.TerrainGenerationProfile;
import cubyz.world.terrain.generators.Generator;

public abstract class Chunk extends SavableChunk {
	
	public static final int chunkShift = 5;
	
	public static final int chunkShift2 = 2*chunkShift;
	
	public static final int chunkSize = 1 << chunkShift;
	
	public static final int chunkMask = chunkSize - 1;
	
	public final World world;
	protected final int[] blocks = new int[chunkSize*chunkSize*chunkSize];
	
	private boolean wasChanged = false;
	/** When a chunk is cleaned, it won't be saved by the ChunkManager anymore, so following changes need to be saved directly. */
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
	 * @param start The normal starting index(for normal generation).
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
	 * @param seed
	 * @param terrainGenerationProfile
	 */
	public void generate(long seed, TerrainGenerationProfile terrainGenerationProfile) {
		assert !generated : "Seriously, why would you generate this chunk twice???";
		if(!ChunkIO.loadChunkFromFile(world, this)) {
			CaveMap caveMap = new CaveMap(this);
			CaveBiomeMap biomeMap = new CaveBiomeMap(this);
			
			for (Generator g : terrainGenerationProfile.generators) {
				g.generate(seed ^ g.getGeneratorSeed(), wx, wy, wz, this, caveMap, biomeMap);
			}
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
	
	@Override
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
	
	public Vector3d getMin() {
		return new Vector3d(wx, wy, wz);
	}
	
	public Vector3d getMax() {
		return new Vector3d(wx + width, wy + width, wz + width);
	}
	
	/**
	 * Saves this chunk.
	 */
	public void save() {
		if(wasChanged) {
			ChunkIO.storeChunkToFile(world, this);
			wasChanged = false;
			// Update the next lod chunk:
			if(voxelSize != 1 << Constants.HIGHEST_LOD) {
				if(world instanceof ServerWorld) {
					ReducedChunk chunk = ((ServerWorld)world).chunkManager.getOrGenerateReducedChunk(wx, wy, wz, voxelSize*2);
					chunk.updateFromLowerResolution(this);
				} else {
					Logger.error("Not implemented: ");
					Logger.error(new Exception());
				}
			}
		}
	}
	
	@Override
	public byte[] saveToByteArray() {
		byte[] data = new byte[4*blocks.length];
		for(int i = 0; i < blocks.length; i++) {
			Bits.putInt(data, i*4, blocks[i]);
		}
		return data;
	}
	
	@Override
	public boolean loadFromByteArray(byte[] data, int outputLength) {
		if(outputLength != 4*blocks.length) {
			Logger.error("Chunk is corrupted(invalid data length "+outputLength+") : " + this);
			return false;
		}
		for(int i = 0; i < blocks.length; i++) {
			blocks[i] = Bits.getInt(data, i*4);
		}
		generated = true;
		return true;
	}

	@Override
	public String fileEnding() {
		return "region";
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
		assert (x & chunkMask) == x && (y & chunkMask) == y && (z & chunkMask) == z : "Your coordinates are outside this chunk. You should be happy this assertion caught it.";
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
