package cubyz.world.items.tools;

import java.util.ArrayList;
import java.util.List;

import cubyz.api.CurrentSurfaceRegistries;
import cubyz.api.Registry;
import cubyz.utils.ndt.NDTContainer;
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
	
	public NDTContainer saveTo(NDTContainer container) {
		if(this instanceof Axe)
			container.setString("type", "Axe");
		else if(this instanceof Pickaxe)
			container.setString("type", "Pickaxe");
		else if(this instanceof Shovel)
			container.setString("type", "Shovel");
		else if(this instanceof Sword)
			container.setString("type", "Sword");
		container.setString("head", head.getRegistryID().toString());
		container.setString("binding", binding.getRegistryID().toString());
		container.setString("handle", handle.getRegistryID().toString());
		container.setInteger("durability", durability);
		// The following can be changed by modifiers, so they need to be stored, too:
		container.setInteger("maxDurability", maxDurability);
		container.setFloat("speed", speed);
		container.setFloat("damage", damage);
		return container;
	}
	
	public static Tool loadFrom(NDTContainer container, CurrentSurfaceRegistries registries) {
		String type = container.getString("type");
		Tool tool = null;
		Registry<Material> matReg = registries.materialRegistry;
		if(type.equals("Axe")) {
			tool = new Axe(matReg.getByID(container.getString("head")), matReg.getByID(container.getString("binding")), matReg.getByID(container.getString("handle")));
		} else if(type.equals("Pickaxe")) {
			tool = new Pickaxe(matReg.getByID(container.getString("head")), matReg.getByID(container.getString("binding")), matReg.getByID(container.getString("handle")));
		} else if(type.equals("Shovel")) {
			tool = new Shovel(matReg.getByID(container.getString("head")), matReg.getByID(container.getString("binding")), matReg.getByID(container.getString("handle")));
		} else if(type.equals("Sword")) {
			tool = new Sword(matReg.getByID(container.getString("head")), matReg.getByID(container.getString("binding")), matReg.getByID(container.getString("handle")));
		}
		tool.durability = container.getInteger("durability");
		tool.maxDurability = container.getInteger("maxDurability");
		tool.speed = container.getFloat("speed");
		tool.damage = container.getFloat("damage");
		return tool;
	}
	
}
