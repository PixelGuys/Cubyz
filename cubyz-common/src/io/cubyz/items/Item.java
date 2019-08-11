package io.cubyz.items;

import io.cubyz.api.IRegistryElement;
import io.cubyz.api.Resource;
import io.cubyz.blocks.Block;

public class Item implements IRegistryElement {

	private int image = -1;
	
	protected String texturePath;
	protected String modelPath;
	protected String fullTexturePath;
	protected Resource id;
	protected int stackSize = 64;
	protected Block block = null;
	
	public String getTexture() {
		return texturePath;
	}
	
	public void setTexture(String texturePath) {
		this.texturePath = "./assets/cubyz/textures/items/" + texturePath;
	}
	
	public void setImage(int image) {
		this.image = image;
	}
	
	public int getImage() {
		return image;
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
	
	public Block getBlock() {
		return block;
	}
	
	public void setBlock(Block b) {
		block = b;
	}

	@Override
	public Resource getRegistryID() {
		return id;
	}

	@Override
	public void setID(int ID) {}
	
}