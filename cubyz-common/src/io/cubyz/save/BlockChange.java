package io.cubyz.save;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.blocks.Block;
import io.cubyz.math.Bits;

/**
 * Used to store the difference between the generated world and the player-edited world for easier storage.
 */

public class BlockChange {
	public int oldType, newType; // IDs of the blocks. -1 = air
	public byte oldData, newData; // Data of the blocks. Mostly used for storing rotation and flow data.
	public int index; // Coordinates as index in the block array of the chunk.
	
	public BlockChange(int ot, int nt, int index, byte od, byte nd) {
		oldType = ot;
		newType = nt;
		oldData = od;
		newData = nd;
		this.index = index;
	}
	
	public BlockChange(byte[] data, int off, Palette<Block> blockPalette) {
		index = Bits.getInt(data, off + 0);
		newData = data[off + 4];
		
		// Convert the palette (torus-specific) ID to the runtime ID
		int palId = Bits.getInt(data, off + 5);
		int runtimeId = -1;
		if (palId != -1) {
			Block b = blockPalette.getElement(palId);
			if(b == null) {
				throw new MissingBlockException();
			}
			runtimeId = b.ID;
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
	public void save(byte[] data, int off, Palette<Block> blockPalette) {
		Bits.putInt(data, off, index);
		data[off + 4] = newData;
		if (newType == -1) {
			Bits.putInt(data, off + 5, -1);
		} else {
			Block b = null;
			for (Block block : CubyzRegistries.BLOCK_REGISTRY.registered(new Block[0])) {
				b = block;
				if (b.ID == newType) {
					break;
				}
			}
			if (b == null) {
				throw new RuntimeException("newType is invalid: " + newType);
			}
			Bits.putInt(data, off + 5, blockPalette.getIndex(b));
		}
	}
}
