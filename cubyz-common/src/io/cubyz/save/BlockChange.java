package io.cubyz.save;

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
	public BlockChange(byte[] data, int off) {
		x = Bits.getInt(data, off + 0);
		y = Bits.getInt(data, off + 4);
		z = Bits.getInt(data, off + 8);
		oldType = Bits.getInt(data, off + 12);
		newType = Bits.getInt(data, off + 16);
	}
	
	/**
	 * Save BlockChange to array data att offset off.
	 * Data Length: 20 bytes
	 * @param data
	 * @param off
	 */
	public void save(byte[] data, int off) {
		Bits.putInt(data, off, x);
		Bits.putInt(data, off + 4, y);
		Bits.putInt(data, off + 8, z);
		Bits.putInt(data, off + 12, oldType);
		Bits.putInt(data, off + 16, newType);
	}
}
