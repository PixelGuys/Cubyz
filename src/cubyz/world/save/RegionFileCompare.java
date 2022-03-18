package cubyz.world.save;

import cubyz.world.ChunkData;

public class RegionFileCompare extends ChunkData {
	protected final String fileEnding;

	public RegionFileCompare(int wx, int wy, int wz, int voxelSize, String fileEnding) {
		super(wx, wy, wz, voxelSize);
		this.fileEnding = fileEnding;
	}

	@Override
	public int hashCode() {
		return super.hashCode()*31 + fileEnding.hashCode();
	}

	@Override
	public boolean equals(Object other) {
		if(other instanceof RegionFileCompare) {
			RegionFileCompare otherReg = (RegionFileCompare) other;
			return super.equals(other) && fileEnding.equals(otherReg.fileEnding);
		}
		return false;
	}
}
