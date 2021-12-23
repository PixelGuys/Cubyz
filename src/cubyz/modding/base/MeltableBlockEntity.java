package cubyz.modding.base;

import org.joml.Vector3i;

import cubyz.world.World;
import cubyz.world.blocks.BlockEntity;
import cubyz.world.blocks.Updateable;

/**
 * A block that can turn into water block when a temperature threshold is met.<br>
 * TODO: Make accessible to all block types with different thresholds and allow definition of those in addon files.
 */

public class MeltableBlockEntity extends BlockEntity implements Updateable {
	
	int heatCount;

	public MeltableBlockEntity(World world, Vector3i pos) {
		super(world, pos);
	}

	@Override
	public boolean randomUpdates() {
		return true;
	}

	@Override
	public void update(boolean isRandomUpdate) {
		if (isRandomUpdate) {
			/*float temp = world.getBiome(position.x, position.z).temperature - position.y*0; TODO: measure temperature in the new biome system.
			if (temp > 0.45f) {
				heatCount++;
			}
			if (heatCount == 5) {
				world.placeBlock(position.x, position.y, position.z, CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:water"), (byte) 0);
			}*/
		}
	}

}
