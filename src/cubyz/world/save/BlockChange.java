package cubyz.world.save;

import cubyz.utils.math.Bits;

/**
 * Used to store the difference between the generated world and the player-edited world for easier storage.
 */

public class BlockChange {
	public int oldType, newType; // IDs of the blocks. -1 = air
	public int index; // Coordinates as index in the block array of the chunk.
	
	public BlockChange(int ot, int nt, int index) {
		oldType = ot;
		newType = nt;
		this.index = index;
	}
	
	public BlockChange(byte[] data, int off, BlockPalette blockPalette) {
		index = Bits.getInt(data, off + 0);
		
		// Convert the palette (world-specific) ID to the runtime ID
		int palId = Bits.getInt(data, off + 4);
		int runtimeId = -1;
		int b = blockPalette.getElement(palId);
		if (b == 0) {
			throw new MissingBlockException();
		}
		runtimeId = b;
		newType = runtimeId;
		oldType = -2;
	}
	
	/**
	 * Save BlockChange to array data at offset off.
	 * Data Length: 8 bytes
	 * @param data
	 * @param off
	 */
	public void save(byte[] data, int off, BlockPalette blockPalette) {
		Bits.putInt(data, off, index);
		Bits.putInt(data, off + 4, blockPalette.getIndex(newType));
	}
}
