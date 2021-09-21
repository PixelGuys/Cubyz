package cubyz.world.blocks;

import java.io.BufferedInputStream;
import java.io.DataInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Random;

import cubyz.Logger;
import cubyz.api.CurrentSurfaceRegistries;
import cubyz.utils.Utilities;
import cubyz.world.CustomObject;
import cubyz.world.items.BlockDrop;
import cubyz.world.items.CustomItem;
import cubyz.world.items.tools.CustomMaterial;

/**
 * A randomly generated ore type.
 */

public class CustomBlock extends Block implements CustomObject {
	// Nodes and leaf to generate tree structure for random ore name generator.
	private static class Node {
		byte value;
		Node[] next;
		public Node(DataInputStream is, int depth) throws IOException {
			value = is.readByte();
			if(depth == 0) return;
			next = new Node[is.readByte()];
			for(int i = 0; i < next.length; i++) {
				next[i] = new Node(is, depth-1);
			}
		}
		Node get(byte b) {
			for(Node n: next) {
				if(n.value == b) {
					return n;
				}
			}
			return null;
		}
	}
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
	
	public int color;
	private String name;
	public long seed; // The seed used to generate the texture.
	public float shinyness;
	public final TextureProvider textureProvider;
	
	private static Node tree;
	
	static {
		readOreData();
	}
	
	private static void readOreData() {
		try {
			InputStream ois = CustomBlock.class.getClassLoader().getResourceAsStream("cubyz/storage/custom_ore_names.dat");
			if (ois == null)
				ois = CustomBlock.class.getClassLoader().getResourceAsStream("classes/cubyz/storage/custom_ore_names.dat");
			DataInputStream is = new DataInputStream(new BufferedInputStream(ois));
			tree = new Node(is, 4);
			is.close();
		} catch (IOException e) {
			Logger.error(e);
		}
	}

	public CustomBlock(TextureProvider texProvider) {
		this.textureProvider = texProvider;
		super.blockClass = BlockClass.STONE;
	}
	
	public String getName() {
		return name;
	}
	
	public void makeGlow() {
		// Make the ore glow at 25% of its color:
		int r = color >>> 16;
		int g = (color >>> 8) & 255;
		int b = color & 255;
		r /= 4;
		g /= 4;
		b /= 4;
		int light = (r << 16) | (g << 8) | b;
		setLight(light);
	}
	
	private static char choose(char c1, char c2, char c3, Random rand, int length) {
		try {
			int i1 = getIndex(c1);
			int i2 = getIndex(c2);
			int i3 = getIndex(c3);
			Node[] list = tree.get((byte)i1).get((byte)i2).get((byte)i3).next;
			int i4 = rand.nextInt(list.length);
			return getChar(list[i4].value);
		} catch(ArrayIndexOutOfBoundsException e) {
			return ' ';
		}
	}
	
	private static String randomName(Random rand) {
		StringBuilder sb = new StringBuilder();
		
		char c1 = ' ', c2 = ' ', c3 = ' ', c4 = choose(c1, c2, c3, rand, 0);
		sb.append((char)(c4+'A'-'a'));
		int i = 0;
		while(true) {
			char c5 = choose(c2, c3, c4, rand, ++i);
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
		String[] words = sb.toString().split(" ");
		boolean wrongSize = false;
		for(i = 0; i < words.length; i++) {
			if(words[i].length() > 10)
				wrongSize = true;
			// The first word should not be to small.
			if(words[i].length() < 5 && i == 0)
				wrongSize = true;
		}
		if(wrongSize)
			return randomName(rand); // Repeat until a long enough name is generated.
		else
			return sb.toString();
	}
	
	public static CustomBlock random(Random rand, CurrentSurfaceRegistries registries, TextureProvider texProvider) {
		String name = randomName(rand);
		// Use a seed based on the name, so if the same ore gets generated twice in the giant world, it will have the same properties.
		// This fact could also allow an interactive wiki which displays an ores property with knowledge of only the name(TODO).
		rand = new Random(Utilities.hash(name));
		CustomBlock block = new CustomBlock(texProvider);
		Ore ore = new Ore(block, new Block[]{registries.blockRegistry.getByID("cubyz:stone")}, rand.nextInt(200) - 100, (1+rand.nextFloat()*15)/2, 1+rand.nextFloat()*9, rand.nextFloat());
		registries.oreRegistry.register(ore);
		block.name = name;
		block.color = rand.nextInt(0xFFFFFF);
		block.seed = rand.nextLong();
		block.setID("cubyz:" + block.name.toLowerCase() + "_ore");
		if(rand.nextInt(4) == 0) { // Make some ores glow.
			block.makeGlow();
		}
		block.makeBlockDrop(registries);
		boolean addTools = true; // TODO
		/* 	A little reasoning behind the choice of material properties:
			There are some important concepts when looking at the hardness of a material:
			1. mohs-hardness scale which determines how easy it is to scratch a material.
				On this scale diamond is the hardest with a 10.
				And glass(5.5) is on this scale harder than iron/steel(4)
				
				mohs-hardness influences both durability and mining speed.
				It is a lot easier to cut through a material if the tool you use can scratch it more easily.
				And when the tool can be scratched easier, it will take more damage and break sooner. This is only important for the head, because scratches on binding or handle don't really matter.
				A higher mohs-hardness also allows the sword to be sharper, so it should deal more damage.
				TODO mohs-hardness should also influence the mining level because if tool cannot scratch the material, it cannot break it easily.
			2. elasticity which basically just says how hard it is to permanently deform or break the material.
				Here glass and diamond are much worse than iron/steel. It takes a lot of energy to deform iron, while it is super easy to break glass or diamond.
				For further consideration I'll only focus on material break rather than other plastic deformations.
				
				It is quite obvious that elasticity greatly influences durability, but does not significantly influence mining speed
				(only if the deformation absorbs a lot of energy, which I will ignore here for simplicity).
				Elasticity also should influence material hardness, because breaking a block is easier if it is less elastic.
			3. density: how heavy the tool will be assuming the volume will always be the same.
				A heavier tool will be slower.
				So it will take more time to break stuff.
				It will also deal less damage because it requires less force to stop it(because the collision time is longer).
				A heavier ore is harder to mine, because it takes more energy to move heavier pieces.
				TODO
				A heavier tool has more knockback because of the higher momentum.
				A heavier armor will make you move slower.
				ODOT
			
			TODO
			4. Modifiers can a make a material powerful or just bad. Because of that every modifier has a usefulness factor and the loverall material usefulness is:
				mohs-hardness + elasticity + Σ modifier-usefulness
			ODOT
				
			Based on the considerations above, a good formula for usefulness would be:
				usefulness = mohs-hardness + elasticity - density
			
			For general purpose of progression it is important that more useful ores are less rare, so I will simply use:
				usefulness ~ 1/(1 + rareness)
			*/
		// For now mohs-hardness is limited to 2-10 and elasticity and density have a similar magnitude, so the total usefulness will be limited to 20, so the rareness needs to be mapped to 0-20:
		float usefulness = 20.0f/(ore.size*ore.veins/32 + 1);
		float mohsHardness = 2 + rand.nextFloat()*8;
		usefulness -= mohsHardness;
		// Density should be bigger than 1. Anything else would be strange.
		float density = 1;
		float elasticity = 0;
		usefulness -= 1;
		if(usefulness < 0) {
			density -= usefulness;
		} else {
			elasticity += usefulness;
		}
		usefulness = 0;
		// Now elasticity and density can be changed by a random factor:
		float factor = rand.nextFloat()*10;
		elasticity += factor;
		density += factor;

		block.setHardness(elasticity*density);
		
		if(addTools) {
			new CustomMaterial((int)(mohsHardness*10 + elasticity*20), (int)(elasticity*30), (int)(elasticity*50), mohsHardness*4.0f/density, mohsHardness*3.0f/density, block.color, block.getBlockDrops()[0].item, 100, registries);
		}
		return block;
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
	
	private void makeBlockDrop(CurrentSurfaceRegistries registries) {
		CustomItem bd = CustomItem.fromOre(this);
		registries.itemRegistry.register(bd);
		bd.setID(getRegistryID());
		addBlockDrop(new BlockDrop(bd, 1)); // TODO: custom amounts for different ores.
	}
	
	/*public NDTContainer toNDT() {
		NDTContainer ndt = new NDTContainer();
		ndt.setInteger("color", color);
		ndt.setInteger("maxHeight", maxHeight);
		ndt.setLong("seed", seed);
		ndt.setFloat("veins", veins);
		ndt.setFloat("size", size);
		ndt.setString("name", name);
		ndt.setFloat("hardness", getHardness());
		ndt.setString("id", getRegistryID().getID());
		return ndt;
	}*/
	
	public boolean generatesModelAtRuntime() {
		return true;
	}
}
