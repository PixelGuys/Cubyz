package cubyz.client;

import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.util.*;

import javax.imageio.ImageIO;
import javax.swing.JOptionPane;

import org.joml.Vector3f;
import org.joml.Vector4f;
import org.lwjgl.Version;
import org.lwjgl.opengl.GL12;

import cubyz.*;
import cubyz.api.ClientConnection;
import cubyz.api.ClientRegistries;
import cubyz.api.Side;
import cubyz.client.entity.ClientPlayer;
import cubyz.client.loading.LoadThread;
import cubyz.gui.MenuGUI;
import cubyz.gui.audio.MusicManager;
import cubyz.gui.audio.SoundManager;
import cubyz.gui.game.GameOverlay;
import cubyz.gui.menu.LoadingGUI;
import cubyz.modding.ModLoader;
import cubyz.rendering.BlockPreview;
import cubyz.rendering.FrameBuffer;
import cubyz.rendering.Material;
import cubyz.rendering.Mesh;
import cubyz.rendering.Spatial;
import cubyz.rendering.Texture;
import cubyz.rendering.TextureArray;
import cubyz.rendering.Window;
import cubyz.utils.*;
import cubyz.utils.datastructures.PixelUtils;
import cubyz.world.*;
import cubyz.world.blocks.Block;
import cubyz.world.blocks.CustomBlock;
import cubyz.world.items.CustomItem;
import cubyz.world.items.Inventory;
import cubyz.world.items.Item;
import cubyz.world.terrain.noise.StaticBlueNoise;
import cubyz.world.terrain.worldgenerators.LifelandGenerator;
import server.Server;

/**
 * A complex class that holds everything together.<br>
 * TODO: Move functionality to better suited places(like world loading should probably be handled somewhere in the World class).
 */

public class GameLogic implements ClientConnection {
	public SoundManager sound;
	
	public Texture[] breakAnimations;
	
	public Mesh skyBodyMesh;
	private Spatial skySun;
	private Spatial skyMoon;

	public String serverIP = "localhost";
	public int serverPort = 58961;
	public int serverCapacity = 1;
	public int serverOnline = 1;

	public boolean isIntegratedServer = true;
	public boolean isOnlineServerOpened = false;

	public GameLogic() {
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
				Logger.error(e);
			}
		}
	}
	
	public void quitWorld() {
		Server.running = false;
		for (MenuGUI overlay : Cubyz.gameUI.getOverlays()) {
			if (overlay instanceof GameOverlay) {
				Cubyz.gameUI.removeOverlay(overlay);
			}
		}
		Cubyz.world.cleanup();
		Cubyz.player = null;
		Cubyz.world = null;
		Cubyz.chunkTree.cleanup();
		MusicManager.stop();
		
		System.gc();
	}
	
	public void loadWorld(ServerWorld world) { // TODO: Seperate all the things out that are generated for the current world.
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
		Cubyz.player = new ClientPlayer(world.getLocalPlayer());
		// Make sure the world is null until the player position is known.
		DiscordIntegration.setStatus("Playing");
		Cubyz.gameUI.addOverlay(new GameOverlay());
		
		for (Item reg : world.getCurrentRegistries().itemRegistry.registered(new Item[0])) {
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
				Logger.warning(e);
			}
			item.setImage(tex);
		}
		// Generate the texture atlas for this world's truly transparent blocks:
		ArrayList<Block> blocks = new ArrayList<>();
		for(Block block : world.getCurrentRegistries().blockRegistry.registered(new Block[0])) {
			blocks.add(block);
		}
		// Get the textures for those blocks:
		ArrayList<BufferedImage> blockTextures = new ArrayList<>();
		ArrayList<String> blockIDs = new ArrayList<>();
		for(Block block : blocks) {
			if(block instanceof CustomBlock) {
				CustomBlock ore = (CustomBlock)block;
				ore.textureProvider.generateTexture(ore, blockTextures, blockIDs);
			} else {
				ResourceUtilities.loadBlockTexturesToBufferedImage(block, blockTextures, blockIDs);
			}
		}
		Cubyz.world = world;
		// Put the textures into the atlas
		TextureArray textures = Meshes.blockTextureArray;
		textures.clear();
		for(int i = 0; i < blockTextures.size(); i++) {
			BufferedImage img = blockTextures.get(i);
			textures.addTexture(img);
		}
		textures.generate();
		
		MusicManager.init(sound);
		MusicManager.start();
		
		// Call mods for this new world. Mods sometimes need to do extra stuff for the specific world.
		ModLoader.postWorldGen(world.getCurrentRegistries());
	}

	public void init() throws Exception {
		if (!new File("assets").exists()) {
			Logger.error("Assets not found.");
			JOptionPane.showMessageDialog(null, "Cubyz could not detect its assets.\nDid you forgot to extract the game?", "Error", JOptionPane.ERROR_MESSAGE);
			System.exit(1);
		}
		
		Logger.info("Version " + Constants.GAME_VERSION + " of brand " + Constants.GAME_BRAND);
		Logger.info("LWJGL Version: " + Version.VERSION_MAJOR + "." + Version.VERSION_MINOR + "." + Version.VERSION_REVISION);
		Logger.info("Jungle Version: " + Constants.GAME_VERSION + "-cubyz");
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
			Logger.error("An unhandled exception occured while initiazing the renderer:");
			Logger.error(e);
			System.exit(1);
		}
		Logger.info("Renderer: OK!");
		
		Cubyz.gameUI.setMenu(LoadingGUI.getInstance());
		LoadThread lt = new LoadThread();
		
		LoadThread.addOnLoadFinished(() -> {
			LifelandGenerator.init();
			
			sound = new SoundManager();
			try {
				sound.init();
			} catch (Exception e) {
				Logger.error(e);
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
					Logger.warning(e);
				}
			}
			breakAnimations = breakingAnims.toArray(new Texture[breakingAnims.size()]);
			System.gc();
		});
		lt.start();

		// Load some other resources in the background:
		new Thread(new Runnable() {
			@Override
			public void run() {
				StaticBlueNoise.load();
			}
		}).start();
	}
	
	@Override
	public void openGUI(String name, Inventory inv) {
		MenuGUI gui = ClientRegistries.GUIS.getByID(name);
		if (gui == null) {
			throw new IllegalArgumentException("No such GUI registered: " + name);
		}
		Cubyz.gameUI.setMenu(gui);
		gui.setInventory(inv);
	}
	
	public FrameBuffer blockPreview(Block b) {
		return BlockPreview.generateBuffer(new Vector3f(1, 1, 1), b);
	}	
	
	public void clientUpdate() {
		if(Cubyz.world != null) {
			MusicManager.update();
			Cubyz.chunkTree.update((int)Cubyz.player.getPosition().x, (int)Cubyz.player.getPosition().y, (int)Cubyz.player.getPosition().z, ClientSettings.RENDER_DISTANCE, ClientSettings.HIGHEST_LOD, ClientSettings.LOD_FACTOR);
			// TODO: Get this in the server ping or something.
			float lightAngle = (float)Math.PI/2 + (float)Math.PI*(((float)Cubyz.gameTime % ServerWorld.DAY_CYCLE)/(ServerWorld.DAY_CYCLE/2));
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
			Logger.warning(e);
		}
		return null;
	}

	@Override
	public void serverPing(long gameTime, String biome) {
		Cubyz.biome = Cubyz.world.getCurrentRegistries().biomeRegistry.getByID(biome);
		Cubyz.gameTime = gameTime;
	}
}
