package cubyz.world.items;

import cubyz.api.RegistryElement;
import cubyz.api.Resource;
import cubyz.utils.json.JsonObject;
import cubyz.utils.translate.TextKey;
import cubyz.world.entity.Entity;
import cubyz.world.items.tools.Material;

/**
 * "Thing" the player can store in their inventory.
 */

public class Item implements RegistryElement {
	
	protected String texturePath;
	protected String modelPath;
	protected final Resource id;
	private TextKey name;
	protected final int stackSize;

	public final Material material;

	public Item(Resource id, JsonObject json) {
		this.id = id;
		name = TextKey.createTextKey(json.getString("translationId", id.getID()));
		if (json.map.containsKey("material")) {
			material = new Material(json.getObject("material"));
		} else {
			material = null;
		}
		stackSize = json.getInt("stackSize", 64);
	}
	
	protected Item(int stackSize) {
		id = Resource.EMPTY;
		this.stackSize = stackSize;
		material = null;
	}
	
	public String getTexture() {
		return texturePath;
	}
	
	public TextKey getName() {
		return name;
	}
	
	public void setName(TextKey key) {
		this.name = key;
	}
	
	public void setTexture(String texturePath) {
		this.texturePath = texturePath;
	}
	
	public void update() {}

	@Override
	public Resource getRegistryID() {
		return id;
	}
	
	/**
	 * Returns true if this item should be consumed on use. May be accessed by non-player entities.
	 * @param user
	 * @return whether this item is consumed upon use.
	 */
	public boolean onUse(Entity user) {
		return false;
	}
}