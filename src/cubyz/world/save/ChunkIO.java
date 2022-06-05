package cubyz.world.save;

import cubyz.utils.Logger;
import cubyz.utils.datastructures.Cache;
import cubyz.world.Chunk;
import cubyz.world.SavableChunk;
import cubyz.world.World;

import java.util.Arrays;
import java.util.zip.DataFormatException;
import java.util.zip.Deflater;
import java.util.zip.Inflater;

public final class ChunkIO {
	private ChunkIO() {} // No instances allowed.

	private static final ThreadLocal<byte[]> threadLocalInputBuffer = ThreadLocal.withInitial(() -> new byte[4096]);
	private static final ThreadLocal<byte[]> threadLocalOutputBuffer = ThreadLocal.withInitial(() -> new byte[4 << Chunk.chunkShift*3]);

	// Region files generally seem to be less than 1 MB on disk. To be on the safe side the amount of cached region files is limited to 128.
	private static final int HASH_MASK = 31;
	private static final Cache<RegionFile> regionCache = new Cache<>(new RegionFile[HASH_MASK+1][4]);
	
	private static RegionFile getOrLoadRegionFile(World world, int wx, int wy, int wz, int voxelSize, String fileEnding) {
		wx = RegionFile.findCoordinate(wx, voxelSize);
		wy = RegionFile.findCoordinate(wy, voxelSize);
		wz = RegionFile.findCoordinate(wz, voxelSize);
		RegionFileCompare data = new RegionFileCompare(wx, wy, wz, voxelSize, fileEnding);
		int hash = data.hashCode() & HASH_MASK;
		RegionFile res = regionCache.find(data, hash);
		if (res != null) return res;
		synchronized(regionCache.cache[hash]) {
			res = regionCache.find(data, hash);
			if (res != null) return res;
			// Generate a new chunk:
			res = new RegionFile(world, wx, wy, wz, voxelSize, fileEnding);
			RegionFile old = regionCache.addToCache(res, hash);
			if(old != null) {
				old.clean();
			}
		}
		return res;
	}
	public static boolean loadChunkFromFile(World world, SavableChunk ch) {
		RegionFile region = getOrLoadRegionFile(world, ch.wx, ch.wy, ch.wz, ch.voxelSize, ch.fileEnding());
		return region.loadChunk(ch);
	}
	public static void storeChunkToFile(World world, SavableChunk ch) {
		RegionFile region = getOrLoadRegionFile(world, ch.wx, ch.wy, ch.wz, ch.voxelSize, ch.fileEnding());
		region.saveChunk(ch);
	}
	
	public static void save() {
		regionCache.foreach(RegionFile::clean);
	}
	
	public static void clean() {
		save();
		regionCache.clear();
	}

	public static byte[] compressChunk(byte[] input) {
		byte[] output = threadLocalOutputBuffer.get();

		Deflater compressor = new Deflater();
		compressor.setInput(input);
		compressor.finish();
		int dataLength = compressor.deflate(output);

		while(!compressor.needsInput()) { // The buffer was too small. Switching to a bigger buffer.
			output = Arrays.copyOf(output, output.length*2);
			threadLocalOutputBuffer.set(output);
			dataLength += compressor.deflate(output, output.length/2, output.length/2);
		}
		compressor.end();

		return Arrays.copyOf(output, dataLength);
	}

	public static byte[] compressChunk(SavableChunk ch) {
		return compressChunk(ch.saveToByteArray());
	}

	public static byte[] decompressChunk(byte[] in, int offset, int length) {
		byte[] input = threadLocalInputBuffer.get();
		if(length > input.length) {
			input = new byte[length];
			threadLocalInputBuffer.set(input);
		}
		byte[] output = threadLocalOutputBuffer.get();
		System.arraycopy(in, offset, input, 0, length);

		Inflater decompresser = new Inflater();
		decompresser.setInput(input, 0, length);
		int outputLength;
		try {
			outputLength = decompresser.inflate(output);
			while(!decompresser.finished()) {
				output = Arrays.copyOf(output, output.length*2);
				threadLocalOutputBuffer.set(output);
				outputLength += decompresser.inflate(output, outputLength, output.length - outputLength);
			}
		} catch (DataFormatException e) {
			Logger.error(e);
			return null;
		}
		decompresser.end();

		byte[] out = new byte[outputLength]; // TODO(post-valhalla): return an offset byte array.
		System.arraycopy(output, 0, out, 0, outputLength);
		return out;
	}
}
