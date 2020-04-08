package io.cubyz.blocks;

import java.io.BufferedInputStream;
import java.io.DataInputStream;
import java.io.IOException;
import java.util.Random;

import io.cubyz.base.init.ItemInit;
import io.cubyz.items.CustomItem;
import io.cubyz.items.tools.CustomMaterial;
import io.cubyz.ndt.NDTContainer;
import io.cubyz.world.CustomObject;

public class CustomOre extends Ore implements CustomObject {
	static int getIndex(char c) {
		if(c == ' ') return 0;
		if('a' <= c && c <= 'z') return 1+c-'a';
		return -1;
	}
	static char getChar(int i) {
		if(i == 0) return ' ';
		if(i <= 26) return (char)('a'+i-1);
		System.err.println("Unknown "+i);
		System.exit(1);
		return '0';
	}
	
	private int color;
	private String name;
	public int template;
	
	private static byte[][] chars;
	private static float[][] probabilities;
	
	static {
		readOreData();
	}
	
	private static void readOreData() {
		try {
			DataInputStream is = new DataInputStream(new BufferedInputStream(CustomOre.class.getClassLoader().getResourceAsStream("io/cubyz/storage/custom_ore_names.dat")));
			chars = new byte[27*27*27][0];
			for (int i = 0; i < 27*27*27; i++) {
				byte len = is.readByte();
				chars[i] = new byte[len];
				for(int j = 0; j < len; j++) {
					chars[i][j] = is.readByte();
				}
			}
			probabilities = new float[27*27*27][0];
			for (int i = 0; i < 27*27*27; i++) {
				byte length = is.readByte();
				float[] array = new float[length];
				for (int j = 0; j < length; j++) {
					array[j] = is.readFloat();
				}
				probabilities[i] = array;
			}
			is.close();
		} catch (IOException e) {
			e.printStackTrace();
		}
	}
	
	public String getName() {
		return name;
	}
	public int getColor() {
		return color;
	}
	
	private static char choose(char c1, char c2, char c3, float rand, int length) {
		try {
			int i1 = getIndex(c1);
			int i2 = getIndex(c2);
			int i3 = getIndex(c3);
			int i4 = 0;
			if(length >= 20 && chars[i1*27*27 + i2*27 + i3][i4] == 0) { // Make sure the word ends.
				return ' ';
			}
			for(;;i4++) {
				rand -= probabilities[i1*27*27 + i2*27 + i3][i4];
				if(rand <= 0) {
					break;
				}
			}
			return getChar(chars[i1*27*27 + i2*27 + i3][i4]);
		} catch(ArrayIndexOutOfBoundsException e) {
			return ' ';
		}
	}
	
	private static String randomName(Random rand) {
		StringBuilder sb = new StringBuilder();
		
		char c1 = ' ', c2 = ' ', c3 = ' ', c4 = choose(c1, c2, c3, rand.nextFloat(), 0);
		sb.append((char)(c4+'A'-'a'));
		int i = 0;
		while(true) {
			char c5 = choose(c2, c3, c4, rand.nextFloat(), ++i);
			if(c4 == ' ') {
				if(c5 == ' ') {
					break;
				}
				sb.append(c4);
			}
			c1 = c2;
			c2 = c3;
			c3 = c4;
			c4 = c5;
			if(c5 != ' ')
				sb.append(c5);
		}
		if(sb.length() <= 15)
			return sb.toString();
		else
			return randomName(rand); // Repeat until a long enought name is generated.
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
