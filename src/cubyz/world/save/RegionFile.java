package cubyz.world.save;

import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Arrays;
import java.util.zip.DataFormatException;
import java.util.zip.Deflater;
import java.util.zip.Inflater;

import cubyz.client.Cubyz;
import cubyz.client.GameLauncher;
import cubyz.utils.Logger;
import cubyz.utils.math.Bits;
import cubyz.world.Chunk;
import cubyz.world.ChunkData;
import cubyz.world.SavableChunk;
import cubyz.world.World;

/**
 * Multiple chunks are bundled up in regions to reduce disk reads/writes.
 */
public class RegionFile extends ChunkData {
	private static final ThreadLocal<byte[]> threadLocalInputBuffer = new ThreadLocal<byte[]>() {
		@Override
		public byte[] initialValue() {
			return new byte[4096];
		}
	};
	private static final ThreadLocal<byte[]> threadLocalOutputBuffer = new ThreadLocal<byte[]>() {
		@Override
		public byte[] initialValue() {
			return new byte[4 << Chunk.chunkShift*3];
		}
	};
	public static final int REGION_SHIFT = 3;
	public static final int REGION_SIZE = 1 << REGION_SHIFT;
	private byte[] data = new byte[0];
	private boolean[] occupancy = new boolean[REGION_SIZE*REGION_SIZE*REGION_SIZE];
	private int[] startingIndices = new int[REGION_SIZE*REGION_SIZE*REGION_SIZE + 1];
	private boolean wasChanged = false;
	private boolean storeOnChange = false;
	private final Class<?> type;
	private final String fileEnding;

	public RegionFile(World world, int wx, int wy, int wz, int voxelSize, Class<?> type, String fileEnding) {
		super(wx, wy, wz, voxelSize);
		this.type = type;
		this.fileEnding = fileEnding;
		// Load data from file:
		File file = new File("saves/"+world.getName()+"/"+voxelSize+"/"+wx+"/"+wy+"/"+wz+"."+fileEnding);
		if(!file.exists()) {
			return;
		}
		try (InputStream in = new FileInputStream(file)) {
			byte[] data = in.readAllBytes();
			if(data.length < 4) return;
			
			int offset = 0;
			int compressor = Bits.getInt(data, offset);
			offset += 4;
			if(compressor != 0) {
				Logger.error("Unknown compression algorithm "+compressor+" for save file \""+file.getAbsolutePath()+"\".");
				return;
			}
			byte[] occupancyBytes = new byte[occupancy.length/8];
			System.arraycopy(data, 4, occupancyBytes, 0, occupancyBytes.length);
			offset += occupancyBytes.length;
			int index = -1;
			for(int i = 0; i < occupancy.length; i++) {
				occupancy[i] = (occupancyBytes[i >> 3] & 1l << (i & 7)) != 0;
				if(occupancy[i]) {
					startingIndices[i] = Bits.getInt(data, offset);
					for(index++; index < i; index++) {
						startingIndices[index] = startingIndices[i];
					}
					offset += 4;
				} else if(i == 0) {
					startingIndices[i] = 0;
				} else {
					startingIndices[i] = startingIndices[i - 1];
				}
			}
			
			this.data = Arrays.copyOfRange(data, offset, data.length);
			for(index++; index < startingIndices.length; index++) {
				startingIndices[index] = this.data.length;
			}
		} catch (IOException e) {
			Logger.error("Unable to load chunk resources.");
			Logger.error(e);
		}
	}
	
	private int getChunkIndex(SavableChunk ch) {
		int chunkIndex = (ch.wx - wx)/ch.getWidth();
		chunkIndex = chunkIndex << REGION_SHIFT | (ch.wy - wy)/ch.getWidth();
		chunkIndex = chunkIndex << REGION_SHIFT | (ch.wz - wz)/ch.getWidth();
		return chunkIndex;
	}
	
	public boolean loadChunk(SavableChunk ch) {
		int chunkIndex = getChunkIndex(ch);
		
		int inputLength = startingIndices[chunkIndex + 1] - startingIndices[chunkIndex];
		if(inputLength == 0) return false;
		byte[] input = threadLocalInputBuffer.get();
		if(inputLength > input.length) {
			input = new byte[inputLength];
			threadLocalInputBuffer.set(input);
		}
		byte[] output = threadLocalOutputBuffer.get();
		System.arraycopy(data, startingIndices[chunkIndex], input, 0, inputLength);
		
		Inflater decompresser = new Inflater();
		decompresser.setInput(input, 0, inputLength);
		int outputLength = 0;
		try {
			outputLength = decompresser.inflate(output);
			while(!decompresser.finished()) {
				output = Arrays.copyOf(output, output.length*2);
				threadLocalOutputBuffer.set(output);
				outputLength += decompresser.inflate(output, outputLength, output.length - outputLength);
			}
		} catch (DataFormatException e) {
			Logger.error("Unable to load chunk data. Corrupt chunk file "+this.toString());
			Logger.error(e);
			return false;
		}
		decompresser.end();
		
		ch.loadFromByteArray(output, outputLength);
		return true;
	}
	
	public void saveChunk(SavableChunk ch) {
		synchronized(this) {
			wasChanged = true;
			int chunkIndex = getChunkIndex(ch);
			byte[] output = threadLocalOutputBuffer.get();
			byte[] input = ch.saveToByteArray();
			
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
			
			int dataInsertionIndex = startingIndices[chunkIndex];
			int oldDataLength = startingIndices[chunkIndex + 1] - dataInsertionIndex;
			byte[] newData = new byte[data.length + dataLength - oldDataLength];
			System.arraycopy(data, 0, newData, 0, dataInsertionIndex);
			System.arraycopy(output, 0, newData, dataInsertionIndex, dataLength);
			System.arraycopy(data, startingIndices[chunkIndex + 1], newData, dataInsertionIndex + dataLength, data.length - startingIndices[chunkIndex + 1]);
			data = newData;
			
			for(int i = chunkIndex + 1; i < startingIndices.length; i++) {
				startingIndices[i] += dataLength - oldDataLength;
			}
			if(oldDataLength == 0) {
				// This chunks wasn't in the list before:
				occupancy[chunkIndex] = true;
			}
			if(storeOnChange)
				unsynchronized_store();
		}
	}
	
	private void unsynchronized_store() {
		if(!wasChanged) return; // No need to save it.
		File file = new File("saves/"+Cubyz.world.getName()+"/"+voxelSize+"/"+wx+"/"+wy+"/"+wz+"."+fileEnding);
		file.getParentFile().mkdirs();
		try (BufferedOutputStream out = new BufferedOutputStream(new FileOutputStream(file))) {
			byte[] occupancyBytes = new byte[occupancy.length/8];
			int numberOfChunks = 0;
			for(int i = 0; i < occupancy.length; i++) {
				if(occupancy[i]) {
					occupancyBytes[i >> 3] |= 1l << (i & 7);
					numberOfChunks++;
				}
			}
			
			byte[] metaData = new byte[4 + occupancyBytes.length + 4*numberOfChunks];
			int offset = 0;
			Bits.putInt(metaData, offset, 0); // compressor version
			offset += 4;
			System.arraycopy(occupancyBytes, 0, metaData, 4, occupancyBytes.length);
			offset += occupancyBytes.length;
			for(int i = 0; i < occupancy.length; i++) {
				if(occupancy[i]) {
					Bits.putInt(metaData, offset, startingIndices[i]);
					offset += 4;
				}
			}
			
			out.write(metaData);
			out.write(data);
		} catch (IOException e) {
			Logger.error("Unable to store chunk resources.");
			Logger.error(e);
		}
		wasChanged = false;
	}
	
	public void clean() {
		synchronized(this) {
			storeOnChange = true;
			unsynchronized_store();
		}
	}
	
	public void store() {
		synchronized(this) {
			unsynchronized_store();
		}
	}

	/**
	 * Converts the world coordinate to the coordinate of the region file it lies in.
	 * @param worldCoordinate
	 * @param voxelSize
	 * @return
	 */
	public static int findCoordinate(int worldCoordinate, int voxelSize) {
		return worldCoordinate & ~(REGION_SIZE*voxelSize*Chunk.chunkSize - 1);
	}
	
	@Override
	public void finalize() {
		if(wasChanged) {
			Logger.crash(wx+" "+wy+" "+wz+" "+voxelSize);
			clean();
			GameLauncher.instance.exit();
		}
	}

	public static int hashCode(int hash, Class<?> type) {
		return hash ^ type.hashCode();
	}

	@Override
	public int hashCode() {
		return hashCode(super.hashCode(), type);
	}

	@Override
	public boolean equals(Object other) {
		return super.equals(other) && type == ((RegionFile)other).type;
	}
}
