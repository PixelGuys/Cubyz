package io.cubyz.items.tools;

import io.cubyz.items.Item;

public class Tool extends Item {
	
	Material head, binding, handle;
	int durability, maxDurability;
	float speed;
	float damage;
	
	public Tool(Material head, Material binding, Material handle, float speed, float damage) {
		this.head = head;
		this.binding = binding;
		this.handle = handle;
		this.speed = speed;
		this.damage = damage;
	}
	
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
