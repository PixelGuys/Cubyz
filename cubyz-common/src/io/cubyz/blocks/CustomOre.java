package io.cubyz.blocks;

import java.awt.image.BufferedImage;
import java.io.BufferedInputStream;
import java.io.DataInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Random;

import io.cubyz.Utilities;
import io.cubyz.api.CurrentSurfaceRegistries;
import io.cubyz.items.CustomItem;
import io.cubyz.items.tools.CustomMaterial;
import io.cubyz.ndt.NDTContainer;
import io.cubyz.world.CustomObject;

public class CustomOre extends Ore implements CustomObject {
	// Procedurally generated ore textures:
	public static BufferedImage generateOreTexture(BufferedImage stone, long seed, int color, float shinyness) {
		BufferedImage canvas = new BufferedImage(16, 16, BufferedImage.TYPE_INT_RGB);
		Random rand = new Random(seed);
		// Init the canvas:
		for(int px = 0; px < 16; px++) {
			for(int py = 0; py < 16; py++) {
				canvas.setRGB(px, py, stone.getRGB(px, py));
			}
		}
		// Size arguments for the semi major axis:
		double size = 1.5 + rand.nextDouble()*1.5;
		double variation = 0.5*size*rand.nextDouble();
		// Size arguments of the semi minor axis:
		double standard2 = size/3.8*0.7*rand.nextDouble();
		double variation2 = (standard2)*0.5*rand.nextDouble();
		// standard rotation and how far the rotation may differ for each spawn location:
		double rotation0 = rand.nextDouble()*2*Math.PI;
		double rotationVar = 0*rand.nextDouble()*2*Math.PI;
		// Make bigger ovals more rough:
		float roughness = (float)(size*(1-standard2)/3.0);
		int differentColors = 4 + (int)(1.5*(size-1.5));
		int [] colors = new int[differentColors]; // Use a color palette of less than 6 different colors.
		for(int i = 0; i < differentColors; i++) { //TODO: Make sure the contrast fits everywhere and maybe use hue-shifting.
			int r = (color >>> 16) & 255;
			int g = (color >>> 8) & 255;
			int b = (color >>> 0) & 255;
			// Add a brightness value to the color:
			int brightness = (int)(-100*(differentColors/2.0-i)/differentColors);
			if(brightness > 0) {
				brightness *= shinyness+1;
			}
			r += brightness;
			g += brightness;
			b += brightness;
			// make sure that once a color channel is satured the others get increased further:
			int totalDif = 0;
			if(r > 255) {
				totalDif += r-255;
			}
			if(g > 255) {
				totalDif += g-255;
			}
			if(b > 255) {
				totalDif += b-255;
			}
			totalDif = totalDif*3/2;
			r += totalDif;
			g += totalDif;
			b += totalDif;
			// Add some flavor to the color, so it's not just a scale based on lighting:
			r += rand.nextInt(32) - 16;
			g += rand.nextInt(32) - 16;
			b += rand.nextInt(32) - 16;
			// Bound checks:
			if(r > 255) r = 255;
			if(r < 0) r = 0;
			if(g > 255) g = 255;
			if(g < 0) g = 0;
			if(b > 255) b = 255;
			if(b < 0) b = 0;
			colors[i] = (r << 16) | (g << 8) | b;
		}
		// Number of ovals drawn:
		int spawns = (int)(rand.nextDouble()*4) + 8 + (int)(30.0/Math.pow(size-variation/2, 4));
		boolean isCrystal = rand.nextDouble() < 0.0; // TODO
		int tries = 0;
		outer:
		for(int i = 0; i < spawns; i++) {
			if(!isCrystal) { // Just some rotated oval shape.
				double actualSize = size - rand.nextDouble()*variation;
				double actualSizeSmall = actualSize*(1 - (standard2+variation2*(rand.nextDouble() - 0.5)));
				// Rotate the oval by a random angle:
				double angle = rotation0 + rand.nextDouble()*rotationVar;
				double xMain = Math.sin(angle)/actualSize;
				double yMain = Math.cos(angle)/actualSize;
				double xSecn = Math.cos(angle)/actualSizeSmall;
				double ySecn = -Math.sin(angle)/actualSizeSmall;
				// Make sure the ovals don't touch the border of the block texture to remove hard edges between the ore and normal stone blocks:
				double xOffset = Math.max(Math.abs(xMain*actualSize*actualSize), Math.abs(xSecn*actualSizeSmall*actualSizeSmall));
				double yOffset = Math.max(Math.abs(yMain*actualSize*actualSize), Math.abs(ySecn*actualSizeSmall*actualSizeSmall));
				double x = xOffset + rand.nextDouble()*(15 - 2*xOffset);
				double y = yOffset + rand.nextDouble()*(15 - 2*yOffset);
				int xMin = Math.max(0, (int)(x-actualSize));
				int xMax = Math.min(15, (int)(x+actualSize));
				int yMin = Math.max(0, (int)(y-actualSize));
				int yMax = Math.min(15, (int)(y+actualSize));
				// Make sure this ellipse doesn't come too close to another one:
				for(int px = xMin-1; px <= xMax+1; px++) {
					for(int py = yMin-1; py <= yMax+1; py++) {
						if(px == -1 || px == 16 || py == -1 || py == 16) continue;
						double deltaX = px-x;
						double deltaY = py-y;
						double distMain = deltaX*xMain+deltaY*yMain;
						double distSecn = deltaX*xSecn+deltaY*ySecn;
						if(distMain*distMain+distSecn*distSecn < 1.3) {
							if(stone.getRGB(px, py) != canvas.getRGB(px, py)) {
								// Give 3 tries to create the oval coordinates, then move on to the next spawn, yo the program cannot get stuck in an infinite loop.
								tries++;
								if(tries < 3)
									i--;
								continue outer;
							}
						}
					}
				}
				tries = 0;
				for(int px = xMin; px <= xMax; px++) {
					for(int py = yMin; py <= yMax; py++) {
						// Add more variety to the texture by shifting the coordinates by a random amount:
						double deltaX = px - x;
						double deltaY = py - y;
						double distMain = deltaX*xMain + deltaY*yMain;
						double distSecn = deltaX*xSecn + deltaY*ySecn;
						double dist = distMain*distMain + distSecn*distSecn;
						if(dist < 1) {
							// Light is determined as how far to the upper left the current pixel is relative to the center.
							double light = (-(distMain*xMain*actualSize + distSecn*xSecn*actualSizeSmall)*Math.sqrt(0.5) - (distMain*yMain*actualSize + distSecn*ySecn*actualSizeSmall)*Math.sqrt(0.5));
							light += (rand.nextFloat()-.5f)*roughness/4; // Randomly shift the lighting to get a more rough appearance.
							// Determine the index in the color palette that fits the pseudo-lighting conditions:
							int lightIndex = (int)Math.round((3 + light*8.0/3)*differentColors/6);
							if(lightIndex < 0) lightIndex = 0;
							if(lightIndex >= differentColors) lightIndex = differentColors-1;
							int bestColor = colors[lightIndex];
							canvas.setRGB(px, py, 0xff000000 | bestColor);
						}
					}
				}
			} else { // TODO

			}
		}
		return canvas;
	}
	
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
	
	private static Node tree;
	
	static {
		readOreData();
	}
	
	private static void readOreData() {
		try {
			InputStream ois = CustomOre.class.getClassLoader().getResourceAsStream("io/cubyz/storage/custom_ore_names.dat");
			if (ois == null)
				ois = CustomOre.class.getClassLoader().getResourceAsStream("classes/io/cubyz/storage/custom_ore_names.dat");
			DataInputStream is = new DataInputStream(new BufferedInputStream(ois));
			tree = new Node(is, 4);
			is.close();
		} catch (IOException e) {
			e.printStackTrace();
		}
	}

	public CustomOre(int maxHeight, float veins, float size) {
		super(maxHeight, veins, size);
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
	
	public static CustomOre random(Random rand, CurrentSurfaceRegistries registries) {
		String name = randomName(rand);
		// Use a seed based on the name, so if the same ore gets generated twice in the giant world, it will have the same properties.
		// This fact could also allow an interactive wiki which displays an ores property with knowledge of only the name(TODO).
		rand = new Random(Utilities.hash(name));
		CustomOre ore = new CustomOre(8+rand.nextInt(200), 1+rand.nextFloat()*15, 1+rand.nextFloat()*9);
		ore.name = name;
		ore.color = rand.nextInt(0xFFFFFF);
		ore.seed = rand.nextLong();
		ore.setID("cubyz:" + ore.name.toLowerCase() + "_ore");
		if(rand.nextInt(4) == 0) { // Make some ores glow.
			ore.makeGlow();
		}
		ore.makeBlockDrop(registries);
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

		ore.setHardness(elasticity*density);
		
		if(addTools) {
			new CustomMaterial((int)(mohsHardness*10 + elasticity*20), (int)(elasticity*30), (int)(elasticity*50), mohsHardness*4.0f/density, mohsHardness*3.0f/density, ore.color, ore.getBlockDrop(), 100, registries);
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
	
	private void makeBlockDrop(CurrentSurfaceRegistries registries) {
		CustomItem bd = CustomItem.fromOre(this);
		registries.itemRegistry.register(bd);
		bd.setID(getRegistryID());
		setBlockDrop(bd);
	}
	
	public NDTContainer toNDT() {
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
	}
	
	public boolean generatesModelAtRuntime() {
		return true;
	}
}
