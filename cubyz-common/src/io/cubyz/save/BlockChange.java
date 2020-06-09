package io.cubyz.save;

import java.util.Map;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.RegistryElement;
import io.cubyz.api.Resource;
import io.cubyz.blocks.Block;
import io.cubyz.math.Bits;

public class BlockChange {
	// TODO: make it possible for the user to add/remove mods without completely shifting the auto-generated ids.
	public int oldType, newType; // IDs of the blocks. -1 = air
	public int x, y, z; // Coordinates relative to the respective chunk.
	
	public BlockChange(int ot, int nt, int x, int y, int z) {
		oldType = ot;
		newType = nt;
		this.x = x;
		this.y = y;
		this.z = z;
	}
	
	public BlockChange(byte[] data, int off, Map<Block, Integer> blockPalette) {
		x = Bits.getInt(data, off + 0);
		y = Bits.getInt(data, off + 4);
		z = Bits.getInt(data, off + 8);
		
		// Convert the palette (torus-specific) ID to the runtime ID
		int palId = Bits.getInt(data, off + 12);
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
	 * Data Length: 16 bytes
	 * @param data
	 * @param off
	 */
	public void save(byte[] data, int off, Map<Block, Integer> blockPalette) {
		Bits.putInt(data, off, x);
		Bits.putInt(data, off + 4, y);
		Bits.putInt(data, off + 8, z);
		if (newType == -1) {
			Bits.putInt(data, off + 12, -1);
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
			Bits.putInt(data, off + 12, blockPalette.get(b));
		}
	}
}
