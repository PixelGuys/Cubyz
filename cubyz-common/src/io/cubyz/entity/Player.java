package io.cubyz.entity;

import org.joml.Vector3f;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.command.ICommandSource;

/**
 * Base class for both implementation and MP version of Player.
 * @author zenith391
 *
 */
public abstract class Player extends Entity implements ICommandSource {

	public Player() {
		super(CubyzRegistries.ENTITY_REGISTRY.getByID("cubyz:player"));
	}
	
	public abstract boolean isFlying();
	public abstract void setFlying(boolean fly);
	
	/**
	 * Throws an exception if being a multiplayer Player implementation.
	 * @param inc
	 * @param rot
	 */
	public abstract void move(Vector3f inc, Vector3f rot);
	
}
