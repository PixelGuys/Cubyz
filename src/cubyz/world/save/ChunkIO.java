package cubyz.world.save;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.zip.DeflaterOutputStream;
import java.util.zip.InflaterInputStream;

import cubyz.client.Cubyz;
import cubyz.utils.Logger;
import cubyz.utils.math.Bits;
import cubyz.world.NormalChunk;

public class ChunkIO {
	public static boolean loadChunkFromFile(NormalChunk ch, int[] blocks, BlockPalette blockPalette) {
		File file = new File("saves/"+Cubyz.world.getName()+"/"+ch.voxelSize+"/"+ch.wx+"/"+ch.wy+"/"+ch.wz+".chunk");
		if(!file.exists()) return false;
		try (InputStream in = new BufferedInputStream(new InflaterInputStream(new FileInputStream(file)))) {
			byte[] data = in.readAllBytes();
			if(data.length < 4) return false;
			int compressor = Bits.getInt(data, 0);
			if(compressor == 0) { // The first int is reserved for future compressors and compatibility with future versions.
				if(data.length == blocks.length*4 + 4) {
					for(int i = 0; i < blocks.length; i++) {
						// Convert the palette (world-specific) ID to the runtime ID
						int palId = Bits.getInt(data, i*4 + 4);
						blocks[i] = blockPalette.getElement(palId);
					}
				} else {
					Logger.error("Chunk file of "+ch+" has unexpected length. Seems like the file is corrupted.");
				}
			}
		} catch (IOException e) {
			Logger.error("Unable to load chunk resources.");
			Logger.error(e);
			return false;
		}
		return true;
	}
	public static void storeChunkToFile(NormalChunk ch, int[] blocks, BlockPalette blockPalette) {
		File file = new File("saves/"+Cubyz.world.getName()+"/"+ch.voxelSize+"/"+ch.wx+"/"+ch.wy+"/"+ch.wz+".chunk");
		file.getParentFile().mkdirs();
		try (BufferedOutputStream out = new BufferedOutputStream(new DeflaterOutputStream(new FileOutputStream(file)))) {
			byte[] data = new byte[blocks.length*4 + 4];
			Bits.putInt(data, 0, 0);
			for(int i = 0; i < blocks.length; i++) {
				// Convert the palette (world-specific) ID to the runtime ID
				int palId = blockPalette.getIndex(blocks[i]);
				Bits.putInt(data, i*4 + 4, palId);
			}
			out.write(data);
		} catch (IOException e) {
			Logger.error("Unable to store chunk resources.");
			Logger.error(e);
		}
	}
}
