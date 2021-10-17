package cubyz.modding.base;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.function.BiConsumer;

import cubyz.Logger;
import cubyz.api.CubyzRegistries;
import cubyz.api.EventHandler;
import cubyz.api.LoadOrder;
import cubyz.api.Mod;
import cubyz.api.NoIDRegistry;
import cubyz.api.Order;
import cubyz.api.Proxy;
import cubyz.api.Registry;
import cubyz.api.Resource;
import cubyz.utils.json.JsonObject;
import cubyz.utils.json.JsonParser;
import cubyz.utils.math.CubyzMath;
import cubyz.world.blocks.Block;
import cubyz.world.blocks.BlockEntity;
import cubyz.world.blocks.Ore;
import cubyz.world.items.BlockDrop;
import cubyz.world.items.Consumable;
import cubyz.world.items.Item;
import cubyz.world.items.ItemBlock;
import cubyz.world.items.Recipe;
import cubyz.world.terrain.biomes.Biome;
import cubyz.world.terrain.biomes.BlockStructure;
import cubyz.world.terrain.biomes.GroundPatch;
import cubyz.world.terrain.biomes.SimpleTreeModel;
import cubyz.world.terrain.biomes.SimpleVegetation;
import cubyz.world.terrain.biomes.StructureModel;

/**
 * Mod used to support add-ons: simple "mods" without any sort of coding required.<br>
 * TODO: Add more comments and maybe make a uniform parser for everything.
 */

@Mod(id = "addons-loader", name = "Addons Loader")
@LoadOrder(order = Order.AFTER, id = "cubyz")
public class AddonsMod {
	
	@Proxy(clientProxy = "cubyz.modding.base.AddonsClientProxy", serverProxy = "cubyz.modding.base.AddonsCommonProxy")
	private AddonsCommonProxy proxy;
	
	public ArrayList<File> addons = new ArrayList<>();
	private ArrayList<Item> items = new ArrayList<>();
	
	// Used to fetch block drops that aren't loaded during block loading.
	private ArrayList<Block> missingDropsBlock = new ArrayList<>();
	private ArrayList<String> missingDropsItem = new ArrayList<>();
	private ArrayList<Float> missingDropsAmount = new ArrayList<>();

	private ArrayList<Ore> ores = new ArrayList<Ore>();
	private ArrayList<String[]> oreContainers = new ArrayList<String[]>();
	
	@EventHandler(type = "init")
	public void init() {
		proxy.init(this);
		registerMissingStuff();
		registerRecipes(CubyzRegistries.RECIPE_REGISTRY);
	}

	@EventHandler(type = "preInit")
	public void preInit() {
		File dir = new File("assets");
		if (!dir.exists()) {
			dir.mkdir();
		}
		for (File addonDir : dir.listFiles()) {
			if (addonDir.isDirectory()) {
				addons.add(addonDir);
			}
		}
	}

	/**
	 * Reads all json files inside the `folder` in every addon.
	 * @param folder
	 * @param consumer function that is called for all objects found.
	 */
	public void readAllJsonObjects(String folder, BiConsumer<JsonObject, Resource> consumer) {
		// Go through all mods:
		for (File addon : addons) {
			// Find the subfolder:
			File subfolder = new File(addon, folder);
			if (subfolder.exists()) {
				// Go through all files in the subfolder:
				for (File file : subfolder.listFiles()) {
					if (file.isDirectory()) continue;
					JsonObject json = JsonParser.parseObjectFromFile(file.getPath());
					// Determine the ID from the file names:
					String fileName = file.getName();
					if (fileName.contains("."))
						fileName = fileName.substring(0, fileName.lastIndexOf('.'));
					Resource id = new Resource(addon.getName(), fileName);

					consumer.accept(json, id);
				}
			}
		}
	}
	
	@EventHandler(type = "register:item")
	public void registerItems(Registry<Item> registry) {
		readAllJsonObjects("items", (json, id) -> {
			Item item;
			if (json.map.containsKey("food")) {
				item = new Consumable(id, json);
			} else {
				item = new Item(id, json);
			}
			item.setTexture(json.getString("texture", "default.png"), id.getMod());
			registry.register(item);
		});
		// Register the block items:
		registry.registerAll(items);
	}
	
	@EventHandler(type = "register:block")
	public void registerBlocks(Registry<Block> registry) {
		readAllJsonObjects("blocks", (json, id) -> {
			System.out.println(id);
			Block block = new Block(id, json);

			// Ores:
			JsonObject oreProperties = json.getObject("ore");
			if (oreProperties != null) {
				// Extract the ids:
				String[] oreIDs = oreProperties.getArrayNoNull("sources").getStrings();
				float veins = json.getFloat("veins", 0);
				float size = json.getFloat("size", 0);
				int height = json.getInt("height", 0);
				float density = json.getFloat("density", 0.5f);
				Ore ore = new Ore(block, new Block[oreIDs.length], height, veins, size, density);
				ores.add(ore);
				CubyzRegistries.ORE_REGISTRY.register(ore);
				oreContainers.add(oreIDs);
			}

			// Block drops:
			String[] blockDrops = json.getArrayNoNull("drops").getStrings();
			for(String blockDrop : blockDrops) {
				blockDrop = blockDrop.trim();
				String[] data = blockDrop.split("\\s+");
				float amount = 1;
				String name = data[0];
				if(data.length == 2) {
					amount = Float.parseFloat(data[0]);
					name = data[1];
				}
				if(name.equals("auto")) {
					ItemBlock itemBlock = new ItemBlock(block);
					block.addBlockDrop(new BlockDrop(itemBlock, amount));
					items.add(itemBlock);
				} else if(!name.equals("none")) {
					missingDropsBlock.add(block);
					missingDropsAmount.add(amount);
					missingDropsItem.add(name);
				}
			}
			if (json.has("blockEntity")) {
				try {
					block.blockEntity = Class.forName(json.getString("blockEntity", "")).asSubclass(BlockEntity.class);
				} catch (ClassNotFoundException e) {
					Logger.error(e);
				}
			}
			registry.register(block);
		});
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
					
					float roughness = 0;
					float hills = 0;
					float mountains = 0;
					float minHeight = 0, maxHeight = 1;
					float chance = 1.0f;
					boolean supportsRivers = false;
					String type = "ETERNAL_DARKNESS";
					String preferredMusic = null;
					
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
									Logger.warning("Could not find structure \"" + line.split("\\s+")[0] + "\" specified in line " + lineNumber + " in file " + file.getPath());
								}
							} else {
								if(line.startsWith("roughness")) {
									roughness = Float.parseFloat(line.substring(9));
								} else if(line.startsWith("hills")) {
									hills = Float.parseFloat(line.substring(5));
								} else if(line.startsWith("mountains")) {
									mountains = Float.parseFloat(line.substring(9));
								} else if(line.startsWith("height")) {
									String[] heightArguments = line.substring(6).split("to");
									minHeight = Float.parseFloat(heightArguments[0].trim());
									maxHeight = Float.parseFloat(heightArguments[1].trim());
								} else if(line.startsWith("type")) {
									type = line.substring(4).trim();
								} else if(line.startsWith("chance")) {
									chance = Float.parseFloat(line.substring(6).trim());
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
								} else if (line.startsWith("music")) {
									preferredMusic = line.substring(6);
								} else if(line.startsWith("structures:")) {
									startedStructures = true;
								} else {
									Logger.warning("Could not find argument \"" + line.split("\\s+")[0] + "\" specified in line " + lineNumber + " in file " + file.getPath());
								}
							}
						}
						
						Biome biome = new Biome(res, type, minHeight, maxHeight, roughness, hills, mountains, chance, preferredMusic, new BlockStructure(underground.toArray(new BlockStructure.BlockStack[0])), supportsRivers, vegetation.toArray(new StructureModel[0]));
						reg.register(biome);
						
						buf.close();
					} catch(IOException e) {
						Logger.error(e);
					}
				}
			}
		}
	}
	
	public void registerMissingStuff() {
		for(int i = 0; i < missingDropsBlock.size(); i++) {
			missingDropsBlock.get(i).addBlockDrop(new BlockDrop(CubyzRegistries.ITEM_REGISTRY.getByID(missingDropsItem.get(i)), missingDropsAmount.get(i)));
		}
		for(int i = 0; i < ores.size(); i++) {
			for(int j = 0; j < oreContainers.get(i).length; j++) {
				ores.get(i).sources[j] = CubyzRegistries.BLOCK_REGISTRY.getByID(oreContainers.get(i)[j]);
				if(ores.get(i).sources[j] == null) {
					Logger.error("Couldn't find source block "+oreContainers.get(i)[j]+" for ore "+ores.get(i).block);
				}
			}
		}
		ores.clear();
		oreContainers.clear();
		missingDropsBlock.clear();
		missingDropsItem.clear();
		missingDropsAmount.clear();
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
									Logger.warning("Skipping unknown item \"" + parts[1].replaceAll("\\s","") + "\" in line " + lineNumber + " in \"" + file.getPath()+"\".");
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
									Logger.warning("Skipping recipe with unknown item \"" + result + "\" in line " + lineNumber + " in \"" + file.getPath()+"\".");
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
											Logger.warning("Skipping recipe with unknown item \"" + words[i] + "\" in line " + lineNumber + " in \"" + file.getPath()+"\".");
										}
									}
									items.add(item);
								}
							}
						}
						buf.close();
					} catch(IOException e) {
						Logger.error(e);
					}
				}
			}
		}
	}
}