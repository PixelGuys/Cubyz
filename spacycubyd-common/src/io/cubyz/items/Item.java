package io.cubyz.items;

import org.jungle.Mesh;
import org.jungle.Texture;

import io.cubyz.api.IRegistryElement;
import io.cubyz.api.Resource;

public class Item implements IRegistryElement {

	Texture _textureCache;
	Mesh _meshCache;
	
	protected String texturePath;
	protected String modelPath;
	protected String fullTexturePath;
	protected Resource id;
	protected int stackSize = 64;
	
	public String getTexture() {
		return texturePath;
	}
	
	protected void setTexture(String texturePath) {
		this.texturePath = "./res/textures/items/" + texturePath;
	}
	
	/**
	 * Sets the maximum stack size of an item.<br/>
	 * Should be between <i>1</i> and <i>64</i>
	 * @param NOINAS
	 */
	protected void setStackSize(int stackSize) {
		if (stackSize < 1 || stackSize > 64) {
			throw new IllegalArgumentException("stackSize out of bounds");
		}
		this.stackSize = stackSize;
	}
	
	public void update() {}
	
	/**
	 * Returns the Number of Items allowed in a single Item stack
	 * @return NOINAS
	 */
	public int getStackSize() {
		return stackSize;
	}
	
	public Item setID(String id) {
		return setID(new Resource(id));
	}
	
	public Item setID(Resource res) {
		id = res;
		return this;
	}

	@Override
	public String getID() {
		return id.getID();
	}

	@Override
	public Resource getRegistryID() {
		return id;
	}
	
}