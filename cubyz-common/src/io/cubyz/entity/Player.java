package io.cubyz.entity;

import org.joml.Vector3f;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.command.ICommandSource;
import io.cubyz.items.Inventory;
import io.cubyz.world.World;

/**
 * Base class for both implementation and MP version of Player.
 * @author zenith391
 *
 */
public abstract class Player extends Entity implements ICommandSource {

	public Player() {
		super(CubyzRegistries.ENTITY_REGISTRY.getByID("cubyz:player"));
	}
	
	public abstract Inventory getInventory();
	public abstract void breaking(BlockInstance bi, int slot, World w);
	public abstract boolean isFlying();
	public abstract void setFlying(boolean fly);
	
	/**
	 * Throws an exception if being a multiplayer Player implementation.
	 * @param inc
	 * @param rot
	 */
	public abstract void move(Vector3f inc, Vector3f rot, int worldAnd);
	
}
