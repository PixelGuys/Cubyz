package cubyz.client;

import java.util.function.Consumer;

import cubyz.world.entity.EntityType;

/**
 * A collection of mostly functions that are only available in the client context.
 */

public final class ClientOnly {
	private ClientOnly() {} // No instances allowed.

	public static Consumer<EntityType> createEntityMesh;
	
}
