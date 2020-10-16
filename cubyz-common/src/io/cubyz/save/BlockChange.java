package io.cubyz.save;

import java.util.Map;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.RegistryElement;
import io.cubyz.blocks.Block;
import io.cubyz.math.Bits;

/**
 * Used to store the difference between the generated world and the player-edited world for easier storage.
 */

public class BlockChange {
	public int oldType, newType; // IDs of the blocks. -1 = air
	public byte oldData, newData; // Data of the blocks. Mostly used for storing rotation and flow data.
	public int x, y, z; // Coordinates relative to the respective chunk.
	
	public BlockChange(int ot, int nt, int x, int y, int z, byte od, byte nd) {
		oldType = ot;
		newType = nt;
		oldData = od;
		newData = nd;
		this.x = x;
		this.y = y;
		this.z = z;
	}
	
	public BlockChange(byte[] data, int off, Map<Block, Integer> blockPalette) {
		x = Bits.getInt(data, off + 0);
		y = Bits.getInt(data, off + 4);
		z = Bits.getInt(data, off + 8);
		newData = data[off + 12];
		
		// Convert the palette (torus-specific) ID to the runtime ID
		int palId = Bits.getInt(data, off + 13);
		int runtimeId = -1;
		if (palId != -1) {
			for (Block b : blockPalette.keySet()) {
				Integer i = blockPalette.get(b);
				if (i == palId) {
					runtimeId = b.ID;
					break;
				}
			}
			if (runtimeId == -1) {
				throw new MissingBlockException();
			}
		}
		newType = runtimeId;
		oldType = -2;
	}
	
	/**
	 * Save BlockChange to array data at offset off.
	 * Data Length: 17 bytes
	 * @param data
	 * @param off
	 */
	public void save(byte[] data, int off, Map<Block, Integer> blockPalette) {
		Bits.putInt(data, off, x);
		Bits.putInt(data, off + 4, y);
		Bits.putInt(data, off + 8, z);
		data[off + 12] = newData;
		if (newType == -1) {
			Bits.putInt(data, off + 13, -1);
		} else {
			Block b = null;
			for (RegistryElement elem : CubyzRegistries.BLOCK_REGISTRY.registered()) {
				b = (Block) elem;
				if (b.ID == newType) {
					break;
				}
			}
			if (b == null) {
				throw new RuntimeException("newType is invalid: " + newType);
			}
			if (!blockPalette.containsKey(b)) {
				blockPalette.put(b, blockPalette.size());
			}
			Bits.putInt(data, off + 13, blockPalette.get(b));
		}
	}
}
