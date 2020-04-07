package io.cubyz.blocks;

import java.util.Random;

import io.cubyz.base.init.ItemInit;
import io.cubyz.items.CustomItem;
import io.cubyz.items.tools.CustomMaterial;
import io.cubyz.ndt.NDTContainer;
import io.cubyz.storage.ThingsZenithWantsInAnExtraFile;
import io.cubyz.world.CustomObject;

public class CustomOre extends Ore implements CustomObject {
	static int getIndex(char c) {
		if(c == ' ') return 0;
		if('a' <= c && c <= 'z') return 1+c-'a';
		return -1;
	}
	
	private int color;
	private String name;
	public int template;
	
	public String getName() {
		return name;
	}
	public int getColor() {
		return color;
	}
	
	private static char choose(char c1, char c2, float rand, int length) {
		try {
			int i1 = getIndex(c1);
			int i2 = getIndex(c2);
			int i3 = 0;
			if(length >= 20 && ThingsZenithWantsInAnExtraFile.chars[i1*27 + i2][i3] == ' ') { // Make sure the word ends.
				return ' ';
			}
			for(;;i3++) {
				rand -= ThingsZenithWantsInAnExtraFile.probabilities[i1*27 + i2][i3];
				if(rand <= 0 && (length >= 5 || ThingsZenithWantsInAnExtraFile.chars[i1*27 + i2][i3] != ' ')) {
					break;
				}
			}
			return ThingsZenithWantsInAnExtraFile.chars[i1*27 + i2][i3];
		} catch(ArrayIndexOutOfBoundsException e) {
			return ' ';
		}
	}
	
	private static String randomName(Random rand) {
		StringBuilder sb = new StringBuilder();
		
		char c1 = ' ', c2 = ' ', c3 = choose(c1, c2, rand.nextFloat(), 0);
		sb.append((char)(c3+'A'-'a'));
		int i = 0;
		while(true) {
			char c4 = choose(c2, c3, rand.nextFloat(), ++i);
			if(c3 == ' ') {
				if(c4 == ' ') {
					break;
				}
				sb.append(c3);
			}
			c1 = c2;
			c2 = c3;
			c3 = c4;
			if(c4 != ' ')
				sb.append(c4);
		}
		return sb.toString();
	}
	
	public static CustomOre random(int index, Random rand) {
		CustomOre ore = new CustomOre();
		ore.color = rand.nextInt(0xFFFFFF);
		ore.height = 8+rand.nextInt(160);
		ore.spawns = 1+rand.nextFloat()*20;
		ore.maxLength = 1+rand.nextFloat()*10;
		ore.maxSize = 1+rand.nextFloat()*5;
		ore.name = randomName(new Random(rand.nextLong())); // Use a new random, so an update in the name generator won't change all other facts about custom ores.
		ore.template = rand.nextInt(5)+1; // UPDATE THIS WHEN YOU ADD MORE TEMPLATES!
		ore.setHardness(rand.nextInt()*30);
		ore.setID("cubyz:" + ore.name + " Ore");
		ore.makeBlockDrop();
		boolean addTools = true; // For now.
		if(addTools) {
			int rareness = (int)(ore.spawns*ore.maxSize*ore.maxLength);
			new CustomMaterial(rand.nextInt(1000000/rareness), rand.nextInt(1000000/rareness), rand.nextInt(1000000/rareness), rand.nextFloat()*10, rand.nextFloat()*10000/rareness, ore.getColor(), ore.getBlockDrop(), 100);
		}
		return ore;
	}
	
	/*public static CustomOre fromNDT(NDTContainer ndt) {
		CustomOre ore = new CustomOre();
		ore.color = ndt.getInteger("color");
		ore.height = ndt.getInteger("height");
		ore.spawns = ndt.getFloat("spawnRate");
		ore.maxLength = ndt.getFloat("maxLength");
		ore.maxSize = ndt.getFloat("maxSize");
		ore.name = ndt.getString("name");
		ore.template = ndt.getInteger("template");
		ore.setHardness(ndt.getFloat("hardness"));
		ore.setID(ndt.getString("id"));
		ore.makeBlockDrop();
		return ore;
	}*/
	
	private void makeBlockDrop() {
		CustomItem bd = CustomItem.fromOre(this);
		ItemInit.registerCustom(bd);
		bd.setID("cubyz:"+getName());
		setBlockDrop(bd);
	}
	
	public NDTContainer toNDT() {
		NDTContainer ndt = new NDTContainer();
		ndt.setInteger("color", color);
		ndt.setInteger("height", height);
		ndt.setInteger("template", template);
		ndt.setFloat("spawnRate", spawns);
		ndt.setFloat("maxLength", maxLength);
		ndt.setFloat("maxSize", maxSize);
		ndt.setString("name", name);
		ndt.setFloat("hardness", getHardness());
		ndt.setString("id", getRegistryID().getID());
		return ndt;
	}
	
	public boolean generatesModelAtRuntime() {
		return true;
	}
	
}
