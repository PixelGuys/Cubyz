package io.cubyz.items.tools;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;

import io.cubyz.api.IRegistryElement;
import io.cubyz.api.Resource;
import io.cubyz.items.Item;

public class Material implements IRegistryElement {
	List<Modifier> specialModifiers;
	List<Modifier> headModifiers;
	HashMap<Item, Integer> items; 		// Items that can be used in a workbench to create a tool with those materials. The integer stores who many units of material that item contains.
										// Needed material values for base tools are 50 for handle, 50 for binding and 100 for shovelhead/400 for pickaxehead/300 for axehead.
	public int headDurability;
	public int bindingDurability;
	public int handleDurability;
	public float damage;
	public float miningSpeed;
	private Resource id = Resource.EMPTY;
	public Material(int heDur, int bDur, int haDur, float dmg, float spd) {
		headDurability = haDur;
		bindingDurability = bDur;
		handleDurability = haDur;
		damage = dmg;
		miningSpeed = spd;
		headModifiers = new ArrayList<>();
		specialModifiers = new ArrayList<>();
		items = new HashMap<>();
	}
	public Material(List<Modifier> modifiers, HashMap<Item, Integer> items, int heDur, int bDur, int haDur, float dmg, float spd) {
		specialModifiers = modifiers;
		this.items = items;
		headDurability = haDur;
		bindingDurability = bDur;
		handleDurability = haDur;
		damage = dmg;
		miningSpeed = spd;
		headModifiers = new ArrayList<>();
	}
	public void addModifier(Modifier modifier) {
		specialModifiers.add(modifier);
	}
	public void addHeadModifier(Modifier modifier) {
		specialModifiers.add(modifier);
	}
	public void addItem(Item item, int materialValue) {
		items.put(item, materialValue);
	}
	public List<Modifier> getModifiers() {
		return specialModifiers;
	}
	public HashMap<Item, Integer> getItems() {
		return items;
	}
	public void setID(String id) {
		setID(new Resource(id));
	}
	public void setID(Resource id) {
		this.id = id;
	}
	@Override
	public Resource getRegistryID() {
		return id;
	}
	@Override
	public void setID(int ID) {}
}
