package cubyz.world.save;

import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Arrays;

import cubyz.client.GameLauncher;
import cubyz.multiplayer.server.Server;
import cubyz.utils.Logger;
import cubyz.utils.math.Bits;
import cubyz.world.Chunk;
import cubyz.world.SavableChunk;
import cubyz.world.World;

/**
 * Multiple chunks are bundled up in regions to reduce disk reads/writes.
 */
public class RegionFile extends RegionFileCompare {
	public static final int REGION_SHIFT = 3;
	public static final int REGION_SIZE = 1 << REGION_SHIFT;
	private byte[] data = new byte[0];
	private final boolean[] occupancy = new boolean[REGION_SIZE*REGION_SIZE*REGION_SIZE];
	private final int[] startingIndices = new int[REGION_SIZE*REGION_SIZE*REGION_SIZE + 1];
	private boolean wasChanged = false;
	private boolean storeOnChange = false;

	public RegionFile(World world, int wx, int wy, int wz, int voxelSize, String fileEnding) {
		super(wx, wy, wz, voxelSize, fileEnding);
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
				occupancy[i] = (occupancyBytes[i >> 3] & 1L << (i & 7)) != 0;
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
		assert ch.fileEnding().equals(fileEnding) : "Wrong RegionFile: Uses file ending ."+fileEnding+"  instead of ."+ch.fileEnding();
		int chunkIndex = getChunkIndex(ch);
		
		int inputLength = startingIndices[chunkIndex + 1] - startingIndices[chunkIndex];
		if(inputLength == 0) return false;
		
		byte[] out = ChunkIO.decompressChunk(data, startingIndices[chunkIndex], inputLength);

		if(out == null) return false;
		
		return ch.loadFromByteArray(out, out.length);
	}
	
	public void saveChunk(SavableChunk ch) {
		assert ch.fileEnding().equals(fileEnding) : "Wrong RegionFile: Uses file ending ."+fileEnding+"  instead of ."+ch.fileEnding();
		synchronized(this) {
			wasChanged = true;
			int chunkIndex = getChunkIndex(ch);
			
			int dataInsertionIndex = startingIndices[chunkIndex];
			int oldDataLength = startingIndices[chunkIndex + 1] - dataInsertionIndex;

			byte[] output = ChunkIO.compressChunk(ch);

			byte[] newData = new byte[data.length + output.length - oldDataLength];
			System.arraycopy(data, 0, newData, 0, dataInsertionIndex);
			System.arraycopy(output, 0, newData, dataInsertionIndex, output.length);
			System.arraycopy(data, startingIndices[chunkIndex + 1], newData, dataInsertionIndex + output.length, data.length - startingIndices[chunkIndex + 1]);
			data = newData;
			
			for(int i = chunkIndex + 1; i < startingIndices.length; i++) {
				startingIndices[i] += output.length - oldDataLength;
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
		File file = new File("saves/"+ Server.world.getName()+"/"+voxelSize+"/"+wx+"/"+wy+"/"+wz+"."+fileEnding);
		file.getParentFile().mkdirs();
		try (BufferedOutputStream out = new BufferedOutputStream(new FileOutputStream(file))) {
			byte[] occupancyBytes = new byte[occupancy.length/8];
			int numberOfChunks = 0;
			for(int i = 0; i < occupancy.length; i++) {
				if(occupancy[i]) {
					occupancyBytes[i >> 3] |= 1L << (i & 7);
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
}
