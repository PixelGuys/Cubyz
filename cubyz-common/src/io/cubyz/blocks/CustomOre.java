package io.cubyz.blocks;

import java.util.Random;

import io.cubyz.items.Item;
import io.cubyz.ndt.NDTContainer;

public class CustomOre extends Ore {

	private int color;
	private String name;
	
	public static String[] phons = new String[] {"ay", "de", "pi", "er", "op", "ha", "do", "po", "na", "ye", "si", "re"};
	
	public int getColor() {
		return color;
	}
	
	public static String randomName(Random rand) {
		StringBuilder sb = new StringBuilder();
		int length = rand.nextInt(3) + 1;
		for (int i = 0; i < length; i++) {
			sb.append(phons[rand.nextInt(phons.length)]);
		}
		return sb.toString();
	}
	
	public static CustomOre random(int index, Random rand) {
		CustomOre ore = new CustomOre();
		ore.color = rand.nextInt(0xFFFFFF);
		ore.height = rand.nextInt(160);
		ore.spawns = rand.nextFloat()*20;
		ore.maxLength = rand.nextFloat()*10;
		ore.maxSize = rand.nextFloat()*5;
		ore.name = randomName(rand);
		ore.setHardness(rand.nextInt()*30);
		ore.setID("cubyz:custom_ore_" + index);
		ore.makeBlockDrop();
		return ore;
	}
	
	public static CustomOre fromNDT(NDTContainer ndt) {
		CustomOre ore = new CustomOre();
		ore.color = ndt.getInteger("color");
		ore.height = ndt.getInteger("height");
		ore.spawns = ndt.getFloat("spawnRate");
		ore.maxLength = ndt.getFloat("maxLength");
		ore.maxSize = ndt.getFloat("maxSize");
		ore.name = ndt.getString("name");
		ore.setHardness(ndt.getFloat("hardness"));
		ore.setID(ndt.getString("id"));
		ore.makeBlockDrop();
		return ore;
	}
	
	private void makeBlockDrop() {
		Item bd = new Item();
		bd.setID(getRegistryID());
		bd.setTexture("materials/ruby.png"); // TODO: generate a proper texture
		setBlockDrop(bd);
	}
	
	public NDTContainer toNDT() {
		NDTContainer ndt = new NDTContainer();
		ndt.setInteger("color", color);
		ndt.setInteger("height", height);
		ndt.setFloat("spawnRate", spawns);
		ndt.setFloat("maxLength", maxLength);
		ndt.setFloat("maxSize", maxSize);
		ndt.setString("name", name);
		ndt.setFloat("hardness", getHardness());
		ndt.setString("id", getRegistryID().getID());
		return ndt;
	}
	
}
