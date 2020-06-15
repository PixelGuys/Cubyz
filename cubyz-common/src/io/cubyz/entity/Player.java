package io.cubyz.entity;

import org.joml.Vector3f;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.command.CommandSource;
import io.cubyz.items.Inventory;
import io.cubyz.world.Surface;

/**
 * Base class for both implementation and MP version of Player.
 * @author zenith391
 *
 */
public abstract class Player extends Entity implements CommandSource {
	public static final float cameraHeight = 1.7f;
	public Player(Surface surface) {
		super(CubyzRegistries.ENTITY_REGISTRY.getByID("cubyz:player"), surface);
		// TODO: Take care of data files.
		health = maxHealth = 16;
		hunger = maxHunger = 16;
	}
	
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
	public abstract void move(Vector3f inc, Vector3f rot, int worldAnd);
	
}
