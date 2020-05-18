package io.cubyz.blocks;

import java.awt.image.BufferedImage;
import java.io.BufferedInputStream;
import java.io.DataInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Random;

import io.cubyz.base.init.ItemInit;
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
			next = new Node[is.readByte()];
			for(int i = 0; i < next.length; i++) {
				if(depth == 0) {
					next[i] = new EndNode(is);
				} else {
					next[i] = new Node(is, depth-1);
				}
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
		public Node() {}
	}
	private static class EndNode extends Node {
		float valuef;
		public EndNode(DataInputStream is) throws IOException {
			value = is.readByte();
			valuef = is.readFloat();
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
			tree = new Node(is, 3);
			is.close();
		} catch (IOException e) {
			e.printStackTrace();
		}
	}

	public CustomOre(int maxHeight, float veins, float size) {
		super(maxHeight, veins, size);
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
	
	private static char choose(char c1, char c2, char c3, float rand, int length) {
		try {
			int i1 = getIndex(c1);
			int i2 = getIndex(c2);
			int i3 = getIndex(c3);
			int i4 = 0;
			Node[] list = tree.get((byte)i1).get((byte)i2).get((byte)i3).next;
			if(length >= 10 && list[0].value == 0) { // Make sure the word ends.
				return ' ';
			}
			for(;;i4++) {
				rand -= ((EndNode)list[i4]).valuef;
				if(rand <= 0) {
					break;
				}
			}
			return getChar(list[i4].value);
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
		if(sb.length() <= 15 && sb.length() >= 5)
			return sb.toString();
		else
			return randomName(rand); // Repeat until a long enough name is generated.
	}
	
	public static CustomOre random(Random rand) {
		CustomOre ore = new CustomOre(8+rand.nextInt(200), 1+rand.nextFloat()*15, 1+rand.nextFloat()*9);
		ore.color = rand.nextInt(0xFFFFFF);
		ore.name = randomName(new Random(rand.nextLong())); // Use a new random, so an update in the name generator won't change all other facts about custom ores.
		ore.seed = rand.nextLong();
		ore.setHardness(rand.nextInt()*30);
		ore.setID("cubyz:" + ore.name + " Ore");
		if(rand.nextInt(4) == 0) { // Make some ores glow.
			ore.makeGlow();
		}
		ore.makeBlockDrop();
		boolean addTools = true; // TODO
		if(addTools) {
			int rareness = (int)(ore.size*ore.veins); // TODO: Balance material stats!
			new CustomMaterial(rand.nextInt(1000000/rareness), rand.nextInt(1000000/rareness), rand.nextInt(1000000/rareness), rand.nextFloat()*10, rand.nextFloat()*10000/rareness, ore.color, ore.getBlockDrop(), 100);
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
