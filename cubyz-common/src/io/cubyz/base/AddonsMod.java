package io.cubyz.base;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map.Entry;
import java.util.Properties;

import io.cubyz.CubyzLogger;
import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.EventHandler;
import io.cubyz.api.LoadOrder;
import io.cubyz.api.Mod;
import io.cubyz.api.NoIDRegistry;
import io.cubyz.api.Order;
import io.cubyz.api.Proxy;
import io.cubyz.api.Registry;
import io.cubyz.api.Resource;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.Block.BlockClass;
import io.cubyz.blocks.Ore;
import io.cubyz.items.Item;
import io.cubyz.items.ItemBlock;
import io.cubyz.items.Recipe;
import io.cubyz.math.CubyzMath;
import jdk.jfr.internal.Logger;

/**
 * Mod used to support add-ons: simple mods without any sort of coding required
 */
@Mod(id = "addons-loader", name = "Addons Loader")
@LoadOrder(order = Order.AFTER, id = "cubyz")
public class AddonsMod {
	
	@Proxy(clientProxy = "io.cubyz.base.AddonsClientProxy", serverProxy = "io.cubyz.base.AddonsCommonProxy")
	private AddonsCommonProxy proxy;
	
	public ArrayList<File> addons = new ArrayList<>();
	private ArrayList<Item> items = new ArrayList<>();
	private HashMap<Block, String> missingBlockDrops = new HashMap<Block, String>();
	
	@EventHandler(type = "init")
	public void init() {
		proxy.init(this);
		registerBlockDrops();
		registerRecipes(CubyzRegistries.RECIPE_REGISTRY);
	}

	@EventHandler(type = "preInit")
	public void preInit() {
		File dir = new File("addons");
		if (!dir.exists()) {
			dir.mkdir();
		}
		for (File addonDir : dir.listFiles()) {
			if (addonDir.isDirectory()) {
				addons.add(addonDir);
			}
		}
	}
	
	@EventHandler(type = "register:item")
	public void registerItems(Registry<Item> registry) {
		for (File addon : addons) {
			File items = new File(addon, "items");
			if (items.exists()) {
				for (File descriptor : items.listFiles()) {
					Properties props = new Properties();
					try {
						FileReader reader = new FileReader(descriptor);
						props.load(reader);
						reader.close();
					} catch (IOException e) {
						e.printStackTrace();
					}
					
					Item item = new Item();
					String id = descriptor.getName();
					if(id.contains("."))
						id = id.substring(0, id.indexOf('.'));
					item.setID(new Resource(addon.getName(), id));
					item.setTexture(props.getProperty("texture", "default.png"));
					registry.register(item);
				}
			}
		}
		registry.registerAll(items);
	}
	
	@EventHandler(type = "register:block")
	public void registerBlocks(Registry<Block> registry) {
		for (File addon : addons) {
			File blocks = new File(addon, "blocks");
			if (blocks.exists()) {
				for (File descriptor : blocks.listFiles()) {
					Properties props = new Properties();
					try {
						FileReader reader = new FileReader(descriptor);
						props.load(reader);
						reader.close();
					} catch (IOException e) {
						e.printStackTrace();
					}
					
					Block block;
					String id = descriptor.getName();
					if(id.contains("."))
						id = id.substring(0, id.indexOf('.'));
					String blockClass = props.getProperty("class", "STONE").toUpperCase();
					if(blockClass.equals("ORE")) { // Ores:
						float veins = Float.parseFloat(props.getProperty("veins", "0"));
						float size = Float.parseFloat(props.getProperty("size", "0"));
						int height = Integer.parseUnsignedInt(props.getProperty("height", "0"));
						Ore ore = new Ore(height, veins, size);
						block = ore;
						blockClass = "STONE";
					} else {
						block = new Block();
					}
					block.setID(new Resource(addon.getName(), id));
					block.setHardness(Float.parseFloat(props.getProperty("hardness", "1")));
					block.setBlockClass(BlockClass.valueOf(blockClass));
					block.setLight(Integer.parseUnsignedInt(props.getProperty("emittedLight", "0")));
					block.setAbsorption(Integer.decode(props.getProperty("absorbedLight", "0")));
					block.setTransparent(props.getProperty("transparent", "no").equalsIgnoreCase("yes"));
					block.setDegradable(props.getProperty("degradable", "no").equalsIgnoreCase("yes"));
					block.setSelectable(props.getProperty("selectable", "yes").equalsIgnoreCase("yes"));
					block.setSolid(props.getProperty("solid", "yes").equalsIgnoreCase("yes"));
					block.setGUI(props.getProperty("GUI", null));
					String blockDrop = props.getProperty("drop", "none").toLowerCase();
					if(blockDrop.equals("auto")) {
						ItemBlock itemBlock = new ItemBlock(block);
						block.setBlockDrop(itemBlock);
						items.add(itemBlock);
					} else if(!blockDrop.equals("none")) {
						missingBlockDrops.put(block, blockDrop);
					}
					registry.register(block);
				}
			}
		}
	}
	
	public void registerBlockDrops() {
		for(Entry<Block, String> entry : missingBlockDrops.entrySet().toArray(new Entry[0])) {
			entry.getKey().setBlockDrop(CubyzRegistries.ITEM_REGISTRY.getByID(entry.getValue()));
		}
		missingBlockDrops.clear();
	}
	
	public void registerRecipes(NoIDRegistry<Recipe> recipeRegistry) {
		for (File addon : addons) {
			File recipes = new File(addon, "recipes");
			if (recipes.exists()) {
				for (File file : recipes.listFiles()) {
					HashMap<String, Item> shortCuts = new HashMap<String, Item>();
					ArrayList<Item> items = new ArrayList<>();
					ArrayList<Integer> itemsPerRow = new ArrayList<>();
					boolean shaped = false;
					boolean startedRecipe = false;
					try {
						BufferedReader buf = new BufferedReader(new FileReader(file));
						String line;
						while((line = buf.readLine())!= null) {
							line = line.trim(); // Remove whitespaces before and after the word starts.
							if(line.length() == 0) continue;
							if(line.contains("=")) {
								String[] parts = line.split("=");
								shortCuts.put(parts[0].replaceAll("\\s",""), CubyzRegistries.ITEM_REGISTRY.getByID(parts[1].replaceAll("\\s",""))); // Remove all whitespaces, wherever they might be. Not necessarily the most robust way, but it should work.
							} else if(line.startsWith("shaped")) {
								shaped = true;
								startedRecipe = true;
								items.clear();
								itemsPerRow.clear();
							} else if(line.startsWith("shapeless")) {
								shaped = false;
								startedRecipe = true;
								items.clear();
								itemsPerRow.clear();
							} else if(line.startsWith("result") && startedRecipe && itemsPerRow.size() != 0) {
								startedRecipe = false;
								String result = line.substring(6).replaceAll("\\s", ""); // Remove "result" and all space-likes.
								int number = 1;
								if(result.contains("*")) {
									String[] parts = result.split("\\*");
									result = parts[1];
									number = Integer.parseInt(parts[0]);
								}
								Item item;
								if(shortCuts.containsKey(result)) {
									item = shortCuts.get(result);
								} else {
									item = CubyzRegistries.ITEM_REGISTRY.getByID(result);
								}
								if(item == null) {
									CubyzLogger.instance.info("Cannot find result item \""+result+"\" in "+file.getPath());
								}
								if(shaped) {
									int x = CubyzMath.max(itemsPerRow);
									int y = itemsPerRow.size();
									Item[] array = new Item[x*y];
									int index = 0;
									for(int iy = 0; iy < itemsPerRow.size(); iy++) {
										for(int ix = 0; ix < itemsPerRow.get(iy); ix++) {
											array[iy*x + ix] = items.get(index);
											index++;
										}
									}
									recipeRegistry.register(new Recipe(x, y, array, number, item));
								} else {
									recipeRegistry.register(new Recipe(items.toArray(new Item[0]), number, item));
								}
							} else if(startedRecipe) {
								String[] words = line.split("\\s+"); // Split into sections that are divided by any number of whitespace characters.
								itemsPerRow.add(words.length);
								for(int i = 0; i < words.length; i++) {
									Item item;
									if(shortCuts.containsKey(words[i])) {
										item = shortCuts.get(words[i]);
									} else {
										item = CubyzRegistries.ITEM_REGISTRY.getByID(words[i]);
									}
									items.add(item);
								}
							}
						}
						buf.close();
					} catch(IOException e) {
						e.printStackTrace();
					}
				}
			}
		}
		System.out.println(recipeRegistry);
	}
}
