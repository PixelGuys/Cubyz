package io.cubyz.entity;

import org.joml.Vector3f;
import org.joml.Vector3i;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.Resource;
import io.cubyz.items.ItemBlock;
import io.cubyz.items.ItemStack;
import io.cubyz.ndt.NDTContainer;
import io.cubyz.world.Surface;

public class ItemEntity extends Entity implements CustomMeshProvider {
	
	public static class ItemEntityType extends EntityType {

		public ItemEntityType() {
			super(new Resource("cubyz:item_stack"));
		}
		
		public Entity newEntity(Surface surface) {
			return new ItemEntity(this, surface, null);
		}
		
		public boolean useDynamicEntityModel() {
			return true;
		}
		
	}
	
	public ItemStack items;
	
	public ItemEntity(EntityType t, Surface surface, ItemStack items) {
		super(CubyzRegistries.ENTITY_REGISTRY.getByID("cubyz:item_stack"), surface, 30*300/1000/*5 minutes until they despawn, unless dropped from a big height.*/, 0, 0);
		
		this.items = items;
		super.height = 0.2f;
		super.width = 0.1f;
		scale = 0.2f;
		super.rotation = new Vector3f((float)(2*Math.random()*Math.PI), (float)(2*Math.random()*Math.PI), (float)(2*Math.random()*Math.PI)); // Not uniform, but should be good enough.
	}
	
	public ItemEntity(EntityType t, Surface surface, ItemStack items, Vector3i position) {
		super(CubyzRegistries.ENTITY_REGISTRY.getByID("cubyz:item_stack"), surface, 30*300/1000/*5 minutes until they despawn, unless dropped from a big height.*/, 0, 0);
		this.items = items;
		height = 0.2f;
		width = 0.1f;
		super.position.x = position.x;
		super.position.y = position.y;
		super.position.z = position.z;
		super.position.x += (float)Math.random() - 0.5f;
		super.position.z += (float)Math.random() - 0.5f;
		scale = 0.2f;
		super.position.y += (float)Math.random() - 0.5f;
		rotation = new Vector3f(
				(float)(2*Math.random()*Math.PI),
				(float)(2*Math.random()*Math.PI),
				(float)(2*Math.random()*Math.PI)); // Not uniform, but should be good enough.
	}
	
	public ItemEntity(EntityType t, Surface surface, ItemStack items, Vector3f position) {
		super(CubyzRegistries.ENTITY_REGISTRY.getByID("cubyz:item_stack"), surface, 30*300/1000/*5 minutes until they despawn, unless dropped from a big height.*/, 0, 0);
		this.items = items;
		height = 0.2f;
		width = 0.1f;
		super.position.x = position.x;
		super.position.y = position.y;
		super.position.z = position.z;
		rotation = new Vector3f(
				(float)(2*Math.random()*Math.PI),
				(float)(2*Math.random()*Math.PI),
				(float)(2*Math.random()*Math.PI)); // Not uniform, but should be good enough.
	}
	
	@Override
	public void update() {
		vy -= surface.getStellarTorus().getGravity();
		takeDamage(0.001f);
		super.update();
	}
	
	public NDTContainer saveTo(NDTContainer ndt) {
		ndt = super.saveTo(ndt);
		NDTContainer stack = new NDTContainer();
		items.saveTo(stack);
		ndt.setContainer("stack", stack);
		return ndt;
	}
	
	public void loadFrom(NDTContainer ndt) {
		super.loadFrom(ndt);
		items = new ItemStack();
		items.loadFrom(ndt.getContainer("stack"), surface.getCurrentRegistries());
	}
	
	@Override
	public Object getMeshId() {
		if (items.getItem() instanceof ItemBlock) {
			return items.getBlock();
		}
		return null;
	}
	
	@Override
	public MeshType getMeshType() {
		if (items.getItem() instanceof ItemBlock) {
			return MeshType.BLOCK;
		}
		return null;
	}
}
