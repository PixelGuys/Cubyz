package cubyz.world.entity;

import org.joml.Vector3f;

import cubyz.api.CubyzRegistries;
import cubyz.command.CommandSource;
import cubyz.world.Surface;
import cubyz.world.blocks.BlockInstance;
import cubyz.world.items.Inventory;

/**
 * Base class for both implementation and MP version of Player.
 * @author zenith391
 */

public abstract class Player extends Entity implements CommandSource {
	public static final float cameraHeight = 1.7f;
	public Player(Surface surface) {
		super(CubyzRegistries.ENTITY_REGISTRY.getByID("cubyz:player"), null, surface, 16, 16, 0.5f);
		// TODO: Take care of data files.
	}
	
	@Override
	public abstract Inventory getInventory();
	public abstract void breaking(BlockInstance bi, int slot, Surface w);
	public abstract void resetBlockBreaking();
	public abstract boolean isFlying();
	public abstract void setFlying(boolean fly);
	
	/**
	 * Throws an exception if being a multiplayer Player implementation.
	 * @param inc
	 * @param rot
	 */
	public abstract void move(Vector3f inc, Vector3f rot);
	
}
