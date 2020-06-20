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
import io.cubyz.blocks.Ore;
import io.cubyz.items.Item;
import io.cubyz.items.ItemBlock;
import io.cubyz.items.Recipe;
import io.cubyz.items.tools.Material;
import io.cubyz.items.tools.Modifier;
import io.cubyz.math.CubyzMath;
import io.cubyz.translate.TextKey;
import io.cubyz.world.cubyzgenerators.biomes.Biome;
import io.cubyz.world.cubyzgenerators.biomes.BlockStructure;
import io.cubyz.world.cubyzgenerators.biomes.GroundPatch;
import io.cubyz.world.cubyzgenerators.biomes.SimpleTreeModel;
import io.cubyz.world.cubyzgenerators.biomes.SimpleVegetation;
import io.cubyz.world.cubyzgenerators.biomes.StructureModel;

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
		registerMaterials(CubyzRegistries.TOOL_MATERIAL_REGISTRY);
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
				for (File file : items.listFiles()) {
					if(file.isDirectory()) continue;
					Properties props = new Properties();
					try {
						FileReader reader = new FileReader(file);
						props.load(reader);
						reader.close();
					} catch (IOException e) {
						e.printStackTrace();
					}
					
					Item item = new Item();
					String id = file.getName();
					if(id.contains("."))
						id = id.substring(0, id.indexOf('.'));
					item.setID(new Resource(addon.getName(), id));
					if (props.containsKey("translationId"))
						item.setName(new TextKey(props.getProperty("translationId")));
					item.setTexture(props.getProperty("texture", "default.png"), addon.getName());
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
				for (File file : blocks.listFiles()) {
					if(file.isDirectory()) continue;
					Properties props = new Properties();
					try {
						FileReader reader = new FileReader(file);
						props.load(reader);
						reader.close();
					} catch (IOException e) {
						e.printStackTrace();
					}
					
					Block block;
					String id = file.getName();
					if(id.contains("."))
						id = id.substring(0, id.indexOf('.'));
					String blockClass = props.getProperty("class", "STONE").toUpperCase();
					if(blockClass.equals("ORE")) { // Ores:
						float veins = Float.parseFloat(props.getProperty("veins", "0"));
						float size = Float.parseFloat(props.getProperty("size", "0"));
						int height = Integer.parseUnsignedInt(props.getProperty("height", "0"));
						Ore ore = new Ore(new Resource(addon.getName(), id), props, height, veins, size);
						block = ore;
						blockClass = "STONE";
					} else {
						block = new Block(new Resource(addon.getName(), id), props, blockClass);
					}
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
	@EventHandler(type = "register:biome")
	public void registerBiomes(Registry<Biome> reg) {
		for (File addon : addons) {
			File biomes = new File(addon, "biomes");
			if (biomes.exists()) {
				for (File file : biomes.listFiles()) {
					if(file.isDirectory()) continue;
					String id = file.getName();
					if(id.contains("."))
						id = id.substring(0, id.indexOf('.'));
					Resource res = new Resource(addon.getName(), id);
					ArrayList<BlockStructure.BlockStack> underground = new ArrayList<>();
					ArrayList<StructureModel> vegetation = new ArrayList<>();
					
					float roughness = 1;
					float minHeight = 0, height = 0.5f, maxHeight = 1;
					float temperature = 0.5f;
					float humidity = 0.5f;
					boolean supportsRivers = false;
					
					boolean startedStructures = false;
					try {
						BufferedReader buf = new BufferedReader(new FileReader(file));
						String line;
						int lineNumber = 0;
						while((line = buf.readLine()) != null) {
							lineNumber++;
							line = line.replaceAll("//.*", ""); // Ignore comments with "//".
							line = line.trim(); // Remove whitespaces before and after the word starts.
							if(line.length() == 0) continue;
							if(startedStructures) {
								// TODO: Proper registry of vegetational and other structures.
								if(line.startsWith("cubyz:simple_vegetation")) {
									String [] arguments = line.substring("cubyz:simple_vegetation".length()).trim().split("\\s+");
									vegetation.add(new SimpleVegetation(CubyzRegistries.BLOCK_REGISTRY.getByID(arguments[0]), Float.parseFloat(arguments[1]), Integer.parseInt(arguments[2]), Integer.parseInt(arguments[3])));
								} else if(line.startsWith("cubyz:simple_tree")) {
									String [] arguments = line.substring("cubyz:simple_tree".length()).trim().split("\\s+");
									vegetation.add(new SimpleTreeModel(CubyzRegistries.BLOCK_REGISTRY.getByID(arguments[0]), CubyzRegistries.BLOCK_REGISTRY.getByID(arguments[1]), CubyzRegistries.BLOCK_REGISTRY.getByID(arguments[2]), Float.parseFloat(arguments[3]), Integer.parseInt(arguments[4]), Integer.parseInt(arguments[5]), arguments[6].toUpperCase()));
								} else if(line.startsWith("cubyz:ground_patch")) {
									String [] arguments = line.substring("cubyz:ground_patch".length()).trim().split("\\s+");
									vegetation.add(new GroundPatch(CubyzRegistries.BLOCK_REGISTRY.getByID(arguments[0]), Float.parseFloat(arguments[1]), Float.parseFloat(arguments[2]), Float.parseFloat(arguments[3]), Float.parseFloat(arguments[4]), Float.parseFloat(arguments[5])));
								} else {
									CubyzLogger.instance.warning("Could not find structure \"" + line.split("\\s+")[0] + "\" specified in line " + lineNumber + " in file " + file.getPath());
								}
							} else {
								if(line.startsWith("roughness")) {
									roughness = Float.parseFloat(line.substring(9));
								} else if(line.startsWith("height")) {
									String[] heightArguments = line.substring(6).split("-");
									minHeight = Float.parseFloat(heightArguments[0])/256.0f;
									height    = Float.parseFloat(heightArguments[1])/256.0f;
									maxHeight = Float.parseFloat(heightArguments[2])/256.0f;
								} else if(line.startsWith("temperature")) {
									temperature = (Float.parseFloat(line.substring(11))+30.0f)/90.0f;
								} else if(line.startsWith("humidity")) {
									humidity = Float.parseFloat(line.substring(8));
								} else if(line.startsWith("rivers")) {
									supportsRivers = true;
								} else if(line.startsWith("ground_structure")) {
									String[] blocks = line.substring(16).split(",");
									for(int i = 0; i < blocks.length; i++) {
										String[] parts = blocks[i].trim().split("\\s+");
										int min = 1;
										int max = 1;
										String blockString = parts[0];
										if(parts.length == 2) {
											min = max = Integer.parseInt(parts[0]);
											blockString = parts[1];
										} else if(parts.length == 4 && parts[1].equalsIgnoreCase("to")) {
											min = Integer.parseInt(parts[0]);
											max = Integer.parseInt(parts[2]);
											blockString = parts[3];
										}
										Block block = CubyzRegistries.BLOCK_REGISTRY.getByID(blockString);
										if(block != null) {
											underground.add(new BlockStructure.BlockStack(block, min, max));
										}
									}
								} else if(line.startsWith("structures:")) {
									startedStructures = true;
								} else {
									CubyzLogger.instance.warning("Could not find argument \"" + line.split("\\s+")[0] + "\" specified in line " + lineNumber + " in file " + file.getPath());
								}
							}
						}
						
						Biome biome = new Biome(res, humidity, temperature, height, minHeight, maxHeight, roughness, new BlockStructure(underground.toArray(new BlockStructure.BlockStack[0])), supportsRivers, vegetation.toArray(new StructureModel[0]));
						reg.register(biome);
						
						buf.close();
					} catch(IOException e) {
						e.printStackTrace();
					}
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
					if(file.isDirectory()) continue;
					HashMap<String, Item> shortCuts = new HashMap<String, Item>();
					ArrayList<Item> items = new ArrayList<>();
					ArrayList<Integer> itemsPerRow = new ArrayList<>();
					boolean shaped = false;
					boolean startedRecipe = false;
					try {
						BufferedReader buf = new BufferedReader(new FileReader(file));
						String line;
						int lineNumber = 0;
						while((line = buf.readLine())!= null) {
							lineNumber++;
							line = line.replaceAll("//.*", ""); // Ignore comments with "//".
							line = line.trim(); // Remove whitespaces before and after the word starts.
							if(line.length() == 0) continue;
							if(line.contains("=")) {
								String[] parts = line.split("=");
								Item item = CubyzRegistries.ITEM_REGISTRY.getByID(parts[1].replaceAll("\\s",""));
								if(item == null) {
									CubyzLogger.instance.warning("Skipping unknown item \"" + parts[1].replaceAll("\\s","") + "\" in line " + lineNumber + " in \"" + file.getPath()+"\".");
								} else {
									shortCuts.put(parts[0].replaceAll("\\s",""), CubyzRegistries.ITEM_REGISTRY.getByID(parts[1].replaceAll("\\s",""))); // Remove all whitespaces, wherever they might be. Not necessarily the most robust way, but it should work.
								}
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
									CubyzLogger.instance.warning("Skipping recipe with unknown item \"" + result + "\" in line " + lineNumber + " in \"" + file.getPath()+"\".");
								} else {
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
								}
							} else if(startedRecipe) {
								String[] words = line.split("\\s+"); // Split into sections that are divided by any number of whitespace characters.
								itemsPerRow.add(words.length);
								for(int i = 0; i < words.length; i++) {
									Item item;
									if(words[i].equals("0")) {
										item = null;
									} else if(shortCuts.containsKey(words[i])) {
										item = shortCuts.get(words[i]);
									} else {
										item = CubyzRegistries.ITEM_REGISTRY.getByID(words[i]);
										if(item == null) {
											startedRecipe = false; // Skip unknown recipes.
											CubyzLogger.instance.warning("Skipping recipe with unknown item \"" + words[i] + "\" in line " + lineNumber + " in \"" + file.getPath()+"\".");
										}
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
	}
	
	public void registerMaterials(Registry<Material> reg) {
		for (File addon : addons) {
			File biomes = new File(addon, "materials");
			if (biomes.exists()) {
				for (File file : biomes.listFiles()) {
					if(file.isDirectory()) continue;
					String id = file.getName();
					if(id.contains("."))
						id = id.substring(0, id.indexOf('.'));
					Resource res = new Resource(addon.getName(), id);
					ArrayList<Modifier> modifiers = new ArrayList<>();
					HashMap<Item, Integer> items = new HashMap<>();
					
					int headDurability = 0, bindingDurability = 0, handleDurability = 0;
					float damage = 0, miningSpeed = 0;
					int miningLevel = 0;
					
					try {
						BufferedReader buf = new BufferedReader(new FileReader(file));
						String line;
						int lineNumber = 0;
						while((line = buf.readLine()) != null) {
							lineNumber++;
							line = line.replaceAll("//.*", ""); // Ignore comments with "//".
							line = line.trim(); // Remove whitespaces before and after the word starts.
							String[] parts = line.split("\\s+");
							if(line.length() == 0) continue;
							if(parts[0].equals("modifier")) {
								modifiers.add(CubyzRegistries.TOOL_MODIFIER_REGISTRY.getByID(parts[1]).createInstance(Integer.parseInt(parts[2])));
							} else if(parts[0].equals("head")) {
								headDurability = Integer.parseInt(line.substring(4).replaceAll("\\s",""));
							} else if(parts[0].equals("binding")) {
								bindingDurability = Integer.parseInt(line.substring(7).replaceAll("\\s",""));
							} else if(parts[0].equals("handle")) {
								handleDurability = Integer.parseInt(line.substring(6).replaceAll("\\s",""));
							} else if(parts[0].equals("damage")) {
								damage = Float.parseFloat(line.substring(6).replaceAll("\\s",""));
							} else if(parts[0].equals("speed")) {
								miningSpeed = Float.parseFloat(line.substring(5).replaceAll("\\s",""));
							} else if(parts[0].equals("level")) {
								miningLevel = Integer.parseInt(line.substring(5).replaceAll("\\s",""));
							} else {
								Item item = CubyzRegistries.ITEM_REGISTRY.getByID(parts[0]);
								if(item == null) {
									CubyzLogger.instance.warning("Could not find argument or item \"" + parts[0] + "\" specified in line " + lineNumber + " in file " + file.getPath());
								} else {
									int amount = Integer.parseInt(parts[1]);
									items.put(item, amount);
								}
							}
						}
						
						Material mat = new Material(res, modifiers, items, headDurability, bindingDurability, handleDurability, damage, miningSpeed, miningLevel);
						
						reg.register(mat);
						
						buf.close();
					} catch(IOException e) {
						e.printStackTrace();
					}
				}
			}
		}
	}
}
