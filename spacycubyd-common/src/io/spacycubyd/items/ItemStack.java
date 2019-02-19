package io.spacycubyd.items;

import org.jungle.Mesh;
import org.jungle.Spatial;
import org.jungle.Texture;
import org.jungle.util.Material;
import org.jungle.util.OBJLoader;

@SuppressWarnings("deprecation")
public class ItemStack {

	private Item item;
	private Spatial spatial;
	
	public ItemStack(Item item) {
		this.item = item;
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
				Material material = new Material(item._textureCache, 1.0F); //NOTE: Normal > 1.0F
				item._meshCache.setMaterial(material);
			} catch (Exception e) {
				e.printStackTrace();
			}
		}
		return item._meshCache;
	}
	
	public Item getItem() {
		return item;
	}
	
	public Spatial getSpatial() {
		if (spatial == null) {
			spatial = new Spatial(getMesh());
		}
		return spatial;
	}
	
}