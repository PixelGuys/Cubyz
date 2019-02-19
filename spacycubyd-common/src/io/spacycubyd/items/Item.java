package io.spacycubyd.items;

import org.jungle.Mesh;
import org.jungle.Texture;

public class Item {

	Texture _textureCache;
	Mesh _meshCache;
	
	protected String texturePath;
	protected String modelPath;
	protected String fullTexturePath;
	protected String itemDisplayName;
	protected int stackSize = 64;
	
	public String getItemName() {
		return itemDisplayName;
	}
	
	public String getTexture() {
		return texturePath;
	}
	
	protected void setTexture(String texturePath) {
		this.texturePath = "./res/textures/items/" + texturePath;
	}
	
	protected void setItemName(String name) {
		this.itemDisplayName = name;
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
	
}