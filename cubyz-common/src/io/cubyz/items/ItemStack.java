package io.cubyz.items;

import org.jungle.Mesh;
import org.jungle.Spatial;
import org.jungle.Texture;
import org.jungle.util.Material;
import org.jungle.util.OBJLoader;

import io.cubyz.blocks.Block;

public class ItemStack {

	private Item item;
	private Block block;
	private Spatial spatial;
	int number = 0;
	
	public ItemStack(Item item) {
		this.item = item;
	}
	
	public ItemStack(Block block) {
		this.block = block;
		item = new Item();
		item.setTexture(block.getTexture());
	}
	
	public void update() {}
	
	public Mesh getMesh() {
		if (item._textureCache == null) {
			try {
				if (item.fullTexturePath == null) {
					item._textureCache = new Texture("./res/textures/items/" + item.getTexture() + ".png");
				} else {
					item._textureCache = new Texture("./res/textures/" + item.fullTexturePath + ".png");
				}
				item._meshCache = OBJLoader.loadMesh("res/models/cube.obj");
				Material material = new Material(item._textureCache, 1.0F);
				item._meshCache.setMaterial(material);
			} catch (Exception e) {
				e.printStackTrace();
			}
		}
		return item._meshCache;
	}
	
	public boolean filled() {
		return number >= item.stackSize;
	}
	
	public boolean empty() {
		return number <= 0;
	}
	
	public int add(int number) {
		this.number += number;
		if(this.number > item.stackSize) {
			number = number-this.number+item.stackSize;
			this.number = item.stackSize;
		}
		if(this.number < 0) {
			number = number-this.number;
			this.number = 0;
		}
		return number;
	}
	
	public Item getItem() {
		return item;
	}
	
	public Block getBlock() {
		return block;
	}
	
	public Spatial getSpatial() {
		if (spatial == null) {
			spatial = new Spatial(getMesh());
		}
		return spatial;
	}
	
}