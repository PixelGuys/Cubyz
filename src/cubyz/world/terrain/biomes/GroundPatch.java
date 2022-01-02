package cubyz.world.terrain.biomes;

import java.util.Random;

import cubyz.api.Resource;
import cubyz.utils.json.JsonObject;
import cubyz.world.Chunk;
import cubyz.world.blocks.Blocks;
import cubyz.world.terrain.MapFragment;

/**
 * A small oval of different ground terrain.
 */

public class GroundPatch extends StructureModel {
	private final int newGround;
	private final float width, variation, depth, smoothness;

	public GroundPatch() {
		super(new Resource("cubyz", "ground_patch"), 0);
		this.newGround = 0;
		this.width = 0;
		this.variation = 0;
		this.depth = 0;
		this.smoothness = 0;
	}
	
	public GroundPatch(JsonObject json) {
		super(new Resource("cubyz", "ground_patch"), json.getFloat("chance", 0.5f));
		int block = Blocks.getByID(json.getString("block", "cubyz:soil"));
		this.newGround  = Blocks.mode(block).getNaturalStandard(block);
		this.width      = json.getFloat("width", 5);
		this.variation  = json.getFloat("variation", 1);
		this.depth      = json.getFloat("depth", 2);
		this.smoothness = json.getFloat("smoothness", 0);
	}

	@Override
	public void generate(int x, int z, int height, Chunk chunk, MapFragment map, Random rand) {
		int y = chunk.wy;
		float width = this.width + (rand.nextFloat() - 0.5f)*this.variation;
		float orientation = 2*(float)Math.PI*rand.nextFloat();
		float ellipseParam = 1 + rand.nextFloat(); 

		// Orientation of the major and minor half axis of the ellipse.
		// For now simply use a minor axis 1/ellipseParam as big as the major.
		float xMain = (float)Math.sin(orientation)/width;
		float zMain = (float)Math.cos(orientation)/width;
		float xSecn = ellipseParam*(float)Math.cos(orientation)/width;
		float zSecn = -ellipseParam*(float)Math.sin(orientation)/width;
		int xMin = (int)(x - width);
		if (xMin < 0) xMin = 0;
		int xMax = (int)(x + width);
		if (xMax >= chunk.getWidth()) xMax = chunk.getWidth() - 1;
		int zMin = (int)(z - width);
		if (zMin < 0) zMin = 0;
		int zMax = (int)(z + width);
		if (zMax >= chunk.getWidth()) zMax = chunk.getWidth() - 1;
		for(int px = chunk.startIndex(xMin); px <= xMax; px++) {
			for(int pz = chunk.startIndex(zMin); pz <= zMax; pz++) {
				float main = xMain*(x - px) + zMain*(z - pz);
				float secn = xSecn*(x - px) + zSecn*(z - pz);
				float dist = main*main + secn*secn;
				if (dist <= 1) {
					int startHeight = (int)map.getHeight(px + chunk.wx, pz + chunk.wz);
					for(int py = chunk.startIndex((int)(startHeight - depth + 1)); py <= startHeight; py += chunk.voxelSize) {
						if (dist <= smoothness || (dist - smoothness)/(1 - smoothness) < rand.nextFloat()) {
							if (chunk.liesInChunk(px, py-y, pz)) {
								chunk.updateBlockInGeneration(px, py-y, pz, newGround);
							}
						}
					}
				}
			}
		}
	}

	@Override
	public StructureModel loadStructureModel(JsonObject json) {
		return new GroundPatch(json);
	}
}
