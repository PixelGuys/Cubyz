package io.cubyz.items.tools;

import java.util.ArrayList;
import java.util.List;

import io.cubyz.blocks.Block;
import io.cubyz.items.Item;

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
		modifiers.addAll(head.headModifiers);
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
	
}
