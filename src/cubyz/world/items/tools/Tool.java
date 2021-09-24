package cubyz.world.items.tools;

import java.util.ArrayList;
import java.util.List;

import cubyz.api.CurrentWorldRegistries;
import cubyz.api.Registry;
import cubyz.utils.json.JsonObject;
import cubyz.world.blocks.Block;
import cubyz.world.items.Item;

/**
 * An item that can break blocks faster on use or does damage to entities.
 */

public abstract class Tool extends Item {
	
	Material head, binding, handle;
	List<Modifier> modifiers = new ArrayList<>();
	int durability, maxDurability;
	float speed;
	float damage;
	
	public Tool(Material head, Material binding, Material handle, float speed, float damage) {
		this.head = head;
		this.binding = binding;
		this.handle = handle;
		this.speed = speed;
		this.damage = damage;
		durability = maxDurability = head.headDurability + binding.bindingDurability + handle.handleDurability;
		stackSize = 1;
		modifiers.addAll(head.specialModifiers);
		modifiers.addAll(binding.specialModifiers);
		modifiers.addAll(handle.specialModifiers);
	}
	
	public boolean used() {
		durability--;
		for (Modifier m : modifiers) {
			m.onUse(this);
		}
		return durability <= 0;
	}
	
	public float durability() {
		return (float)durability/maxDurability;
	}
	
	public abstract boolean canBreak(Block b);
	
	public Material getHeadMaterial() {
		return head;
	}
	
	public Material getBindingMaterial() {
		return binding;
	}
	
	public Material getHandleMaterial() {
		return handle;
	}
	
	public float getSpeed() {
		return speed;
	}
	
	public float getDamage() {
		return damage;
	}
	
	public int getDurability() {
		return durability;
	}
	
	public void setDurability(int durability) {
		this.durability = durability;
	}
	
	public void setMaxDurability(int maxDurability) {
		this.maxDurability = maxDurability;
	}

	public void setSpeed(float speed) {
		this.speed = speed;
	}

	public void setDamage(float damage) {
		this.damage = damage;
	}

	public int getMaxDurability() {
		return maxDurability;
	}
	
	public List<Modifier> getModifiers() {
		return modifiers;
	}
	
	public JsonObject save() {
		JsonObject json = new JsonObject();
		if(this instanceof Axe)
			json.put("type", "Axe");
		else if(this instanceof Pickaxe)
			json.put("type", "Pickaxe");
		else if(this instanceof Shovel)
			json.put("type", "Shovel");
		else if(this instanceof Sword)
			json.put("type", "Sword");
		json.put("head", head.getRegistryID().toString());
		json.put("binding", binding.getRegistryID().toString());
		json.put("handle", handle.getRegistryID().toString());
		json.put("durability", durability);
		// The following can be changed by modifiers, so they need to be stored, too:
		json.put("maxDurability", maxDurability);
		json.put("speed", speed);
		json.put("damage", damage);
		return json;
	}
	
	public static Tool loadFrom(JsonObject json, CurrentWorldRegistries registries) {
		String type = json.getString("type", "none");
		Tool tool = null;
		Registry<Material> matReg = registries.materialRegistry;
		if(type.equals("Axe")) {
			tool = new Axe(matReg.getByID(json.getString("head", "")), matReg.getByID(json.getString("binding", "")), matReg.getByID(json.getString("handle", "")));
		} else if(type.equals("Pickaxe")) {
			tool = new Pickaxe(matReg.getByID(json.getString("head", "")), matReg.getByID(json.getString("binding", "")), matReg.getByID(json.getString("handle", "")));
		} else if(type.equals("Shovel")) {
			tool = new Shovel(matReg.getByID(json.getString("head", "")), matReg.getByID(json.getString("binding", "")), matReg.getByID(json.getString("handle", "")));
		} else if(type.equals("Sword")) {
			tool = new Sword(matReg.getByID(json.getString("head", "")), matReg.getByID(json.getString("binding", "")), matReg.getByID(json.getString("handle", "")));
		}
		tool.durability = json.getInt("durability", 0);
		tool.maxDurability = json.getInt("maxDurability", 0);
		tool.speed = json.getFloat("speed", 0);
		tool.damage = json.getFloat("damage", 0);
		return tool;
	}
	
}
