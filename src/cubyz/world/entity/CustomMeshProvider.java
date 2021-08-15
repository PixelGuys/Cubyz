package cubyz.world.entity;

public interface CustomMeshProvider {

	/**
	 * This is invoked at runtime when mesh is needed.
	 * The registry where the resource identifier should be used is returned by {@link #getMeshType()}.<br/>
	 * <b>Note:</b> A block mesh should return a {@link cubyz.world.blocks.Block}, an entity mesh should return
	 * a {@link cubyz.world.entity.EntityType}.
	 * @return an object that have a mesh linked
	 */
	public Object getMeshId();
	
	/**
	 * The type (registry) in which to search the model returned by {@link #getMeshId()}.
	 * @return mesh type
	 */
	public MeshType getMeshType();
	
	
	public static enum MeshType {
		ENTITY;
	}
	
}
