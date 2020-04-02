package io.cubyz.blocks;

import java.util.List;
import java.util.Random;

import io.cubyz.items.CustomItem;
import io.cubyz.items.tools.CustomMaterial;
import io.cubyz.ndt.NDTContainer;
import io.cubyz.world.CustomObject;

public class CustomOre extends Ore implements CustomObject {

	private int color;
	private String name;
	public int template;

	public static String[] prefixes = new String[] {"Al", "An", "Ar", "Be", "Bo", "Bro", "Ca", "Chlor", "Co", "Fer", "Fluo", "Gr", "Ha", "Hydro", "Ind", "Ka", "Kr", "Lith", "Magne", "Meta", "Natr", "Ni", "Osm", "Phos", "Pyr", "Rho", "Sider", "Str", "Tellur", "Thor", "Uran", "Vana", "Xanth", "Yttr", "Zinc", "Zirc"};
	public static String[] phons = new String[] {"ay", "de", "pi", "er", "op", "ha", "do", "po", "na", "ye", "si", "re"};
	
	public String getName() {
		return name;
	}
	public int getColor() {
		return color;
	}
	
	private static boolean isVowel(char c) {
		return c == 'a' || c == 'e' || c == 'i' || c == 'o' || c == 'u' || c == 'y';
	}
	
	private static boolean doesntFit(char c1, char c2, char c3) {
		if((int)c2*(int)c3 == 12705) return true; // Easy test using the ASCII table to see if i and y are following each other.
		if(c2 == c3) return true;
		if(c1 == c3) return true;
		return isVowel(c1) == isVowel(c2) && isVowel(c2) == isVowel(c3);
	}
	
	private static String randomName(Random rand) {
		StringBuilder sb = new StringBuilder();
		
		
		float randomNumber = rand.nextFloat();
		// Randomly add some common prefixes(you'll find each of them at least once in the wikipedia list of minerals).
		sb.append(prefixes[rand.nextInt(prefixes.length)]);
		
		int length = rand.nextInt(3);
		for (int i = 0; i < length; i++) {
			String next;
			do {
				next = phons[rand.nextInt(phons.length)];
			} while(doesntFit(sb.charAt(sb.length()-2), sb.charAt(sb.length()-1), next.charAt(0)));
			sb.append(next);
		}
		randomNumber = rand.nextFloat();
		
		// Randomly add some common postfixes(you'll find each of them at least once in the wikipedia list of minerals).
		if(randomNumber < 0.2) {
			if(sb.charAt(sb.length()-1) == 'i')
				sb.append("um");
			else
				sb.append("ium");
		} else if(randomNumber < 0.25) {
			sb.append("um");
		} else if(randomNumber < 0.5) {
			if(sb.charAt(sb.length()-1) == 'i')
				sb.append("te");
			else
				sb.append("ite");
		} else if(randomNumber < 0.6) {
			if(sb.charAt(sb.length()-1) == 'i')
				sb.append("ne");
			else
				sb.append("ine");
		} else if(randomNumber < 0.62) {
			sb.append("clase");
		} else if(randomNumber < 0.65) {
			sb.append("ase");
		} else if(randomNumber < 0.7) {
			sb.append("gar");
		} else if(randomNumber < 0.73) {
			sb.append("ene");
		} else if(randomNumber < 0.75) {
			sb.append("melane");
		} else if(randomNumber < 0.8) {
			sb.append("time");
		} else if(randomNumber < 0.85) {
			sb.append("sten");
		} else if(randomNumber < 0.9) {
			sb.append("on");
		} else if(randomNumber < 0.92) { // A few rarer and longer endings:
			sb.append("calcite");
		} else if(randomNumber < 0.93) {
			sb.append(" Quartz");
		} else if(randomNumber < 0.94) {
			sb.append("malachite");
		} else if(randomNumber < 0.95) {
			sb.append("uranylite");
		} else if(randomNumber < 0.96) {
			sb.append("ferrite");
		} else if(randomNumber < 0.97) {
			sb.append("chlore");
		} else if(randomNumber < 0.98) {
			sb.append("erupine");
		} else if(randomNumber < 0.99) {
			sb.append("lite");
		} else {
			sb.append("montite");
		}
		return sb.toString();
	}
	
	public static CustomOre random(int index, Random rand, List<CustomItem> customItems) {
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
		ore.makeBlockDrop(customItems);
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
	
	private void makeBlockDrop(List<CustomItem> customItems) {
		CustomItem bd = CustomItem.fromOre(this);
		customItems.add(bd);
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
