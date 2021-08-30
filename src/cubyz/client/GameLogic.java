package cubyz.client;

import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.util.*;

import javax.imageio.ImageIO;
import javax.swing.JOptionPane;

import org.joml.Vector3f;
import org.joml.Vector3i;
import org.joml.Vector4f;
import org.lwjgl.Version;
import org.lwjgl.opengl.GL12;

import cubyz.*;
import cubyz.api.ClientConnection;
import cubyz.api.ClientRegistries;
import cubyz.api.Resource;
import cubyz.api.Side;
import cubyz.client.loading.LoadThread;
import cubyz.gui.GameOverlay;
import cubyz.gui.LoadingGUI;
import cubyz.gui.MenuGUI;
import cubyz.gui.audio.SoundBuffer;
import cubyz.gui.audio.SoundManager;
import cubyz.gui.audio.SoundSource;
import cubyz.gui.input.Keybindings;
import cubyz.modding.ModLoader;
import cubyz.rendering.BlockPreview;
import cubyz.rendering.FrameBuffer;
import cubyz.rendering.Material;
import cubyz.rendering.Mesh;
import cubyz.rendering.Spatial;
import cubyz.rendering.Texture;
import cubyz.rendering.Window;
import cubyz.utils.*;
import cubyz.utils.datastructures.PixelUtils;
import cubyz.world.*;
import cubyz.world.blocks.Block;
import cubyz.world.blocks.BlockInstance;
import cubyz.world.blocks.CustomBlock;
import cubyz.world.blocks.Block.BlockClass;
import cubyz.world.entity.Entity;
import cubyz.world.entity.PlayerEntity.PlayerImpl;
import cubyz.world.generator.LifelandGenerator;
import cubyz.world.items.CustomItem;
import cubyz.world.items.Inventory;
import cubyz.world.items.Item;
import cubyz.world.items.ItemBlock;
import cubyz.world.items.tools.Tool;

/**
 * A complex class that holds everything together.<br>
 * TODO: Move functionality to better suited places(like world loading should probably be handled somewhere in the World class).
 */

public class GameLogic implements ClientConnection {
	public SoundManager sound;
	private SoundBuffer music;
	private SoundSource musicSource;
	
	public Texture[] breakAnimations;
	
	public Mesh skyBodyMesh;
	private Spatial skySun;
	private Spatial skyMoon;

	private int breakCooldown = 10;
	private int buildCooldown = 10;

	public String serverIP = "localhost";
	public int serverPort = 58961;
	public int serverCapacity = 1;
	public int serverOnline = 1;

	public boolean isIntegratedServer = true;
	public boolean isOnlineServerOpened = false;

	public GameLogic() {
		Window.setSize(800, 600);
		Window.setTitle("Cubyz " + Constants.GAME_BUILD_TYPE + " " + Constants.GAME_VERSION);
	}

	public void cleanup() {
		if(Cubyz.world != null) quitWorld();
		ClientSettings.save();
		DiscordIntegration.closeRPC();
		if (sound != null) {
			try {
				sound.dispose();
			} catch (Exception e) {
				Logger.throwable(e);
			}
		}
	}
	
	public void quitWorld() {
		for (MenuGUI overlay : Cubyz.gameUI.getOverlays().toArray(new MenuGUI[0])) {
			if (overlay instanceof GameOverlay) {
				Cubyz.gameUI.removeOverlay(overlay);
			}
		}
		Cubyz.world.cleanup();
		Cubyz.world = null;
		Cubyz.chunkTree.cleanup();
		
		SoundSource ms = musicSource;
		if (ms != null) {
			if (ms.isPlaying()) {
				ms.stop();
			}
		}
		
		System.gc();
	}
	
	public void loadWorld(Surface surface) { // TODO: Seperate all the things out that are generated for the current surface.
		if (Cubyz.world != null) {
			quitWorld();
		}
		if (skySun == null || skyMoon == null) {
			Mesh sunMesh = skyBodyMesh.cloneNoMaterial();
			sunMesh.setMaterial(new Material(new Vector4f(1f, 1f, 0f, 1f), 1f)); // TODO: use textures for sun and moon
			skySun = new Spatial(sunMesh);
			skySun.setScale(50f); // TODO: Make the scale dependent on the actual distance to that star.
			skySun.setPositionRaw(-100, 1, 0);
			Mesh moonMesh = skyBodyMesh.cloneNoMaterial();
			moonMesh.setMaterial(new Material(new Vector4f(0.3f, 0.3f, 0.3f, 1f), 0.9f));
			skyMoon = new Spatial(moonMesh);
			skyMoon.setScale(100f);
			skyMoon.setPositionRaw(100, 1, 0);
			GameLauncher.renderer.worldSpatialList = new Spatial[] {skySun/*, skyMoon*/};
		}
		Cubyz.surface = surface;
		World world = surface.getStellarTorus().getWorld();
		Cubyz.player = (PlayerImpl)world.getLocalPlayer();
		if (world.isLocal()) {
			Random rnd = new Random();
			int dx = 0;
			int dz = 0;
			if (Cubyz.player.getPosition().x == 0 && Cubyz.player.getPosition().z == 0) {
				Logger.log("Finding position..");
				while (true) {
					dx = rnd.nextInt(65536);
					dz = rnd.nextInt(65536);
					Logger.log("Trying " + dx + " ? " + dz);
					if(Cubyz.surface.isValidSpawnLocation(dx, dz)) 
						break;
				}
				int startY = (int)surface.getMapFragment((int)dx, (int)dz, 1).getHeight(dx, dz);
				Cubyz.surface.seek((int)dx, startY, (int)dz, ClientSettings.RENDER_DISTANCE, ClientSettings.EFFECTIVE_RENDER_DISTANCE*NormalChunk.chunkSize*2);
				Cubyz.player.setPosition(new Vector3i(dx, startY+2, dz));
				Logger.log("OK!");
			}
		}
		// Make sure the world is null until the player position is known.
		Cubyz.world = world;
		DiscordIntegration.setStatus("Playing");
		Cubyz.gameUI.addOverlay(new GameOverlay());
		
		if (world instanceof LocalWorld) { // custom ores on multiplayer later, maybe?
			LocalSurface ts = (LocalSurface) surface;
			ArrayList<CustomBlock> customBlocks = ts.getCustomBlocks();
			for (CustomBlock block : customBlocks) {
				BufferedImage img = block.textureProvider.generateTexture(block);
				InputStream is = TextureConverter.fromBufferedImage(img);
				Texture tex = new Texture(is);
				try {
					is.close();
				} catch (IOException e) {
					Logger.throwable(e);
				}
				Meshes.blockTextures.put(block, tex);
			}
			for (Item reg : ts.getCurrentRegistries().itemRegistry.registered(new Item[0])) {
				if(!(reg instanceof CustomItem)) continue;
				CustomItem item = (CustomItem)reg;
				BufferedImage canvas;
				if(item.isGem())
					canvas = getImage("assets/cubyz/items/textures/materials/templates/"+"gem1"+".png"); // TODO: More gem types.
				else
					canvas = getImage("assets/cubyz/items/textures/materials/templates/"+"crystal1"+".png"); // TODO: More crystal types.
				PixelUtils.convertTemplate(canvas, item.getColor());
				InputStream is = TextureConverter.fromBufferedImage(canvas);
				Texture tex = new Texture(is);
				try {
					is.close();
				} catch (IOException e) {
					Logger.throwable(e);
				}
				item.setImage(tex);
			}
		}
		// Generate the texture atlas for this surface's truly transparent blocks:
		ArrayList<Block> blocks = new ArrayList<>();
		for(Block block : surface.getCurrentRegistries().blockRegistry.registered(new Block[0])) {
			blocks.add(block);
		}
		Meshes.atlasSize = (int)Math.ceil(Math.sqrt(blocks.size()));
		int maxSize = 16; // Scale all textures so they fit the size of the biggest texture.
		// Get the textures for those blocks:
		ArrayList<BufferedImage> blockTextures = new ArrayList<>();
		for(Block block : blocks) {
			BufferedImage texture = ResourceUtilities.loadBlockTextureToBufferedImage(block.getRegistryID());
			if(texture != null) {
			} else if(block instanceof CustomBlock) {
				CustomBlock ore = (CustomBlock)block;
				texture = ore.textureProvider.generateTexture(ore);
			} else {
				texture = ResourceUtilities.loadBlockTextureToBufferedImage(new Resource("cubyz", "undefined"));
			}
			maxSize = Math.max(maxSize, Math.max(texture.getWidth(), texture.getHeight()));
			blockTextures.add(texture);
		}
		// Put the textures into the atlas
		BufferedImage atlas = new BufferedImage(maxSize*Meshes.atlasSize, maxSize*Meshes.atlasSize, BufferedImage.TYPE_INT_ARGB);
		int x = 0;
		int y = 0;
		for(int i = 0; i < blockTextures.size(); i++) {
			BufferedImage img = blockTextures.get(i);
			if(img != null) {
				// Copy and scale the image onto the atlas:
				for(int x2 = 0; x2 < maxSize; x2++) {
					for(int y2 = 0; y2 < maxSize; y2++) {
						atlas.setRGB(x*maxSize + x2, y*maxSize + y2, img.getRGB(x2*img.getWidth()/maxSize, y2*img.getHeight()/maxSize));
					}
				}
			}
			blocks.get(i).atlasX = x;
			blocks.get(i).atlasY = y;
			x++;
			if(x == Meshes.atlasSize) {
				x = 0;
				y++;
			}
		}
		try {
			ImageIO.write(atlas, "png", new File("test.png"));
		} catch(Exception e) {}
		Meshes.atlas = new Texture(TextureConverter.fromBufferedImage(atlas));
		
		
		SoundSource ms = musicSource;
		if (ms != null) {
			if (!ms.isPlaying()) {
				// ms.play();
				// Music is disabled for now because right now it's annoying and kind of unrelated to the game.
				// TODO: Find a better concept for playing music in the game that preferably fits the player's current situation.
			}
		}
		
		// Call mods for this new surface. Mods sometimes need to do extra stuff for the specific surface.
		ModLoader.postSurfaceGen(surface.getCurrentRegistries());
	}

	public void init() throws Exception {
		if (!new File("assets").exists()) {
			Logger.severe("Assets not found.");
			JOptionPane.showMessageDialog(null, "Cubyz could not detect its assets.\nDid you forgot to extract the game?", "Error", JOptionPane.ERROR_MESSAGE);
			System.exit(1);
		}
		
		Logger.log("Version " + Constants.GAME_VERSION + " of brand " + Constants.GAME_BRAND);
		Logger.log("LWJGL Version: " + Version.VERSION_MAJOR + "." + Version.VERSION_MINOR + "." + Version.VERSION_REVISION);
		Logger.log("Jungle Version: " + Constants.GAME_VERSION + "-cubyz");
		Constants.setGameSide(Side.CLIENT);
		
		// Cubyz resources
		ResourcePack baserp = new ResourcePack();
		baserp.path = new File("assets");
		baserp.name = "Cubyz";
		ResourceManager.packs.add(baserp);
		
		GameLauncher.renderer.setShaderFolder(ResourceManager.lookupPath("cubyz/shaders/easyLighting"));
		
		BlockPreview.setShaderFolder(ResourceManager.lookupPath("cubyz/shaders/blockPreview"));

		ClientOnly.client = this;
		
		Meshes.initMeshCreators();
		
		try {
			GameLauncher.renderer.init();
			BlockPreview.init();
		} catch (Exception e) {
			Logger.severe("An unhandled exception occured while initiazing the renderer:");
			Logger.throwable(e);
			System.exit(1);
		}
		Logger.log("Renderer: OK!");
		
		Cubyz.gameUI.setMenu(LoadingGUI.getInstance());
		LoadThread lt = new LoadThread();
		
		LoadThread.addOnLoadFinished(() -> {
			LifelandGenerator.init();
			
			sound = new SoundManager();
			try {
				sound.init();
			} catch (Exception e) {
				Logger.throwable(e);
			}
			
			if (ResourceManager.lookupPath("cubyz/sound") != null) {
				try {
					music = new SoundBuffer(ResourceManager.lookupPath("cubyz/sound/Sincerely.ogg"));
				} catch (Exception e) {
					Logger.throwable(e);
				}
				musicSource = new SoundSource(true, true);
				musicSource.setBuffer(music.getBufferId());
				musicSource.setGain(0.3f);
			} else {
				Logger.log("Missing optional sound files. Sounds are disabled.");
			}
		});
		Cubyz.renderDeque.add(() -> {
			File[] list = new File("assets/cubyz/textures/breaking").listFiles();
			ArrayList<Texture> breakingAnims = new ArrayList<>();
			for (File file : list) {
				try {
					Texture tex = new Texture(file);
					tex.setWrapMode(GL12.GL_REPEAT);
					breakingAnims.add(tex);
				} catch (IOException e) {
					Logger.throwable(e);
				}
			}
			breakAnimations = breakingAnims.toArray(new Texture[breakingAnims.size()]);
			System.gc();
		});
		lt.start();
	}
	
	@Override
	public void openGUI(String name, Inventory inv) {
		MenuGUI gui = ClientRegistries.GUIS.getByID(name);
		if (gui == null) {
			throw new IllegalArgumentException("No such GUI registered: " + name);
		}
		gui.setInventory(inv);
		Cubyz.gameUI.setMenu(gui);
	}
	
	public FrameBuffer blockPreview(Block b) {
		return BlockPreview.generateBuffer(new Vector3f(1, 1, 1), b);
	}	
	
	public void update(float interval) {
		if (!Cubyz.gameUI.doesGUIPauseGame() && Cubyz.world != null) {
			if (!Cubyz.gameUI.doesGUIBlockInput()) {
				Cubyz.player.move(Cubyz.playerInc.mul(0.11F), Cubyz.camera.getRotation());
				if (breakCooldown > 0) {
					breakCooldown--;
				}
				if (buildCooldown > 0) {
					buildCooldown--;
				}
				if (Keybindings.isPressed("destroy")) {
					//Breaking Blocks
					if(Cubyz.player.isFlying()) { // Ignore hardness when in flying.
						if (breakCooldown == 0) {
							breakCooldown = 7;
							Object bi = Cubyz.msd.getSelected();
							if (bi != null && bi instanceof BlockInstance && ((BlockInstance)bi).getBlock().getBlockClass() != BlockClass.UNBREAKABLE) {
								Cubyz.surface.removeBlock(((BlockInstance)bi).getX(), ((BlockInstance)bi).getY(), ((BlockInstance)bi).getZ());
							}
						}
					}
					else {
						Object selected = Cubyz.msd.getSelected();
						if(selected instanceof BlockInstance) {
							Cubyz.player.breaking((BlockInstance)selected, Cubyz.inventorySelection, Cubyz.surface);
						}
					}
					// Hit entities:
					Object selected = Cubyz.msd.getSelected();
					if(selected instanceof Entity) {
						((Entity)selected).hit(Cubyz.player.getInventory().getItem(Cubyz.inventorySelection) instanceof Tool ? (Tool)Cubyz.player.getInventory().getItem(Cubyz.inventorySelection) : null, Cubyz.camera.getViewMatrix().positiveZ(Cubyz.dir).negate());
					}
				} else {
					Cubyz.player.resetBlockBreaking();
				}
				if (Keybindings.isPressed("place/use") && buildCooldown <= 0) {
					if((Cubyz.msd.getSelected() instanceof BlockInstance) && ((BlockInstance)Cubyz.msd.getSelected()).getBlock().onClick(Cubyz.world, ((BlockInstance)Cubyz.msd.getSelected()).getPosition())) {
						// Interact with block(potentially do a hand animation, in the future).
					} else if(Cubyz.player.getInventory().getItem(Cubyz.inventorySelection) instanceof ItemBlock) {
						// Build block:
						if (Cubyz.msd.getSelected() != null) {
							buildCooldown = 10;
							Cubyz.msd.placeBlock(Cubyz.player.getInventory(), Cubyz.inventorySelection, Cubyz.surface);
						}
					} else if(Cubyz.player.getInventory().getItem(Cubyz.inventorySelection) != null) {
						// Use item:
						if(Cubyz.player.getInventory().getItem(Cubyz.inventorySelection).onUse(Cubyz.player)) {
							Cubyz.player.getInventory().getStack(Cubyz.inventorySelection).add(-1);
							buildCooldown = 10;
						}
					}
				}
			}
			Cubyz.playerInc.x = Cubyz.playerInc.y = Cubyz.playerInc.z = 0.0F; // Reset positions
			NormalChunk ch = Cubyz.surface.getChunk((int)Cubyz.player.getPosition().x >> NormalChunk.chunkShift, (int)Cubyz.player.getPosition().y >> NormalChunk.chunkShift, (int)Cubyz.player.getPosition().z >> NormalChunk.chunkShift);
			if (ch != null && ch.isLoaded()) {
				Cubyz.world.update();
			}
			Cubyz.surface.seek((int)Cubyz.player.getPosition().x, (int)Cubyz.player.getPosition().y, (int)Cubyz.player.getPosition().z, ClientSettings.RENDER_DISTANCE, ClientSettings.EFFECTIVE_RENDER_DISTANCE*NormalChunk.chunkSize*2);
			Cubyz.chunkTree.update((int)Cubyz.player.getPosition().x, (int)Cubyz.player.getPosition().y, (int)Cubyz.player.getPosition().z, ClientSettings.RENDER_DISTANCE, ClientSettings.HIGHEST_LOD, ClientSettings.LOD_FACTOR);
			float lightAngle = (float)Math.PI/2 + (float)Math.PI*(((float)Cubyz.world.getGameTime() % Cubyz.surface.getStellarTorus().getDayCycle())/(Cubyz.surface.getStellarTorus().getDayCycle()/2));
			skySun.setPositionRaw((float)Math.cos(lightAngle)*500, (float)Math.sin(lightAngle)*500, 0);
			skySun.setRotation(0, 0, -lightAngle);
		}
	}

	public static int getFPS() {
		return GameLauncher.instance.getFPS();
	}
	
	public static BufferedImage getImage(String fileName) {
		try {
			return ImageIO.read(new File(fileName));
		} catch(Exception e) {
			Logger.throwable(e);
		}
		return null;
	}
}
