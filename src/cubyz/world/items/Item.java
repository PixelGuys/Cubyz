package cubyz.world.items;

import cubyz.api.RegistryElement;
import cubyz.api.Resource;
import cubyz.rendering.Texture; //#line CLIENTONLY
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
	protected String fullTexturePath;
	protected Resource id = Resource.EMPTY;
	private TextKey name;
	protected int stackSize = 64;

	public Material material;

	public Item(Resource id, JsonObject json) {
		this.id = id;
		name = TextKey.createTextKey(json.getString("translationId", id.getID()));
		if (json.map.containsKey("material")) {
			material = new Material(json.getObject("material"));
		} else {
			material = null;
		}
	}

	public Item() {
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

	
	//#start CLIENTONLY ----------------------
	private Texture image = null;

	/**
	 * This is used for rendering only.
	 * @param image image id
	 */
	public void setImage(Texture image) {
		this.image = image;
	}
	
	/**
	 * This is used for rendering only.
	 * @return image id
	 */
	public Texture getImage() {
		return image;
	}
	//#end -----------------------------------
}