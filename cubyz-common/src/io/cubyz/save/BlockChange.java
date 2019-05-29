package io.cubyz.save;

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
	public BlockChange(String[] data) {
		x = Integer.parseInt(data[0]);
		y = Integer.parseInt(data[1]);
		z = Integer.parseInt(data[2]);
		oldType = Integer.parseInt(data[3]);
		newType = Integer.parseInt(data[4]);
	}
	public void addToText(StringBuilder sb) { // appends the text to be printed in the document
		sb.append(x);
		sb.append(';');
		sb.append(y);
		sb.append(';');
		sb.append(z);
		sb.append(';');
		sb.append(oldType);
		sb.append(';');
		sb.append(newType);
	}
}
