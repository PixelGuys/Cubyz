package cubyz.client;

import java.util.HashMap;

import cubyz.rendering.BlockPreview;
import cubyz.rendering.Texture;
import cubyz.world.items.Item;
import cubyz.world.items.ItemBlock;
import cubyz.world.items.tools.Tool;

/**
 * Stores and manages all the item textures.
 */
public class ItemTextures {

	private static final HashMap<Item, Texture> storedTextures = new HashMap<>();
	
	/**
	 * Finds or generates the item texture.
	 * Should be called in the render thread.
	 */
	public static Texture getTexture(Item item) {
		Texture result = storedTextures.get(item);
		if(result == null) {
			if (item instanceof ItemBlock) {
				ItemBlock ib = (ItemBlock) item;
				int b = ib.getBlock();
				if (item.getTexture() != null) {
					result = Texture.loadFromFile(item.getTexture());
				} else {
					result = BlockPreview.generateTexture(b);
				}
			} else if (item instanceof Tool) {
				result = Texture.loadFromImage(((Tool)item).texture);
			} else {
				result = Texture.loadFromFile(item.getTexture());
			}
			storedTextures.put(item, result);
		}
		return result;
	}
	
	/**
	 * Clears all the textures.
	 * Should be called in the render thread.
	 */
	public static void clear() {
		storedTextures.forEach((item, texture) -> {
			texture.cleanup();
		});
		storedTextures.clear();
	}
}
