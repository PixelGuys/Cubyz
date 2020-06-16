package io.cubyz.entity;

import org.joml.Vector3f;
import org.joml.Vector3i;

import io.cubyz.api.Resource;
import io.cubyz.items.ItemBlock;
import io.cubyz.items.ItemStack;
import io.cubyz.world.Surface;

public class ItemEntity extends Entity implements CustomMeshProvider {
	
	public ItemStack items;
	
	public ItemEntity(Surface surface, ItemStack items) {
		super(new EntityType(new Resource("cubyz:item_stack")) {
			@Override
			public Entity newEntity(Surface surface) {
				return null;
			}
			
		}, surface);
		
		this.items = items;
		super.height = super.width = super.depth = 0.2f;
		super.minBlock = 0.1f;
		super.maxBlock = 0.9f;
		scale = 0.2f;
		super.rotation = new Vector3f((float)(2*Math.random()*Math.PI), (float)(2*Math.random()*Math.PI), (float)(2*Math.random()*Math.PI)); // Not uniform, but should be good enough.
	}
	
	public ItemEntity(Surface surface, ItemStack items, Vector3i position) {
		super(new EntityType(new Resource("cubyz:item_stack")) {
			@Override
			public Entity newEntity(Surface surface) {
				return null;
			}
			
		}, surface);
		this.items = items;
		height = super.width = super.depth = 0.2f;
		minBlock = 0.1f;
		maxBlock = 0.9f;
		super.position.x = position.x;
		super.position.y = position.y;
		super.position.z = position.z;
		super.position.relX = (float)Math.random() - 0.5f;
		if(super.position.relX < 0) {
			super.position.relX += 1;
			super.position.x -= 1;
		}
		super.position.relZ = (float)Math.random() - 0.5f;
		if(super.position.relZ < 0) {
			super.position.relZ += 1;
			super.position.z -= 1;
		}
		scale = 0.2f;
		super.position.y += (float)Math.random() - 0.5f;
		rotation = new Vector3f(
				(float)(2*Math.random()*Math.PI),
				(float)(2*Math.random()*Math.PI),
				(float)(2*Math.random()*Math.PI)); // Not uniform, but should be good enough.
	}
	
	@Override
	public void update() {
		vy -= surface.getStellarTorus().getGravity();
		super.update();
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
