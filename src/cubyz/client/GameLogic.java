package cubyz.client;

import java.io.File;
import java.io.IOException;
import java.util.*;

import javax.swing.JOptionPane;

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
import cubyz.rendering.BlockPreview;
import cubyz.rendering.Material;
import cubyz.rendering.Mesh;
import cubyz.rendering.Spatial;
import cubyz.rendering.Texture;
import cubyz.rendering.Window;
import cubyz.utils.*;
import cubyz.world.*;
import cubyz.world.items.Inventory;
import cubyz.world.terrain.noise.StaticBlueNoise;
import cubyz.server.Server;

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
		if (Cubyz.world != null) quitWorld();
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
		Server.stop();
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
		
		ItemTextures.clear();
		
		System.gc();
	}
	
	public void loadWorld(World world) { // TODO: Seperate all the things out that are generated for the current world.
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
		world.generate();
		Cubyz.player = new ClientPlayer(world.getLocalPlayer());
		// Make sure the world is null until the player position is known.
		DiscordIntegration.setStatus("Playing");
		Cubyz.gameUI.addOverlay(new GameOverlay());
		
		Cubyz.world = world;

		// Generate the texture atlas for this world's blocks:
		BlockMeshes.generateTextureArray();
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
			sound = new SoundManager();
			try {
				sound.init();
			} catch (Exception e) {
				Logger.error(e);
			}
			MusicManager.init(sound);
			MusicManager.start();
		});
		Cubyz.renderDeque.add(() -> {
			ArrayList<Texture> breakingAnims = new ArrayList<>();
			for (int i = 0; true; i++) {
				try {
					Texture tex = new Texture(new File("assets/cubyz/textures/breaking/"+i+".png"));
					tex.setWrapMode(GL12.GL_REPEAT);
					breakingAnims.add(tex);
				} catch (IOException e) {
					break;
				}
			}
			if (breakingAnims.size() == 0)
				Logger.error("Couldn't find the breaking animations. Without breaking animations the game might crash.");
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
	
	public void clientUpdate() {
		MusicManager.update();
		if (Cubyz.world != null) {
			Cubyz.chunkTree.update((int)Cubyz.player.getPosition().x, (int)Cubyz.player.getPosition().y, (int)Cubyz.player.getPosition().z, ClientSettings.RENDER_DISTANCE, ClientSettings.HIGHEST_LOD, ClientSettings.LOD_FACTOR);
			// TODO: Get this in the server ping or something.
			float lightAngle = (float)Math.PI/2 + (float)Math.PI*(((float)Cubyz.gameTime % World.DAY_CYCLE)/(World.DAY_CYCLE/2));
			skySun.setPositionRaw((float)Math.cos(lightAngle)*500, (float)Math.sin(lightAngle)*500, 0);
			skySun.setRotation(0, 0, -lightAngle);
		}
	}

	public static int getFPS() {
		return GameLauncher.instance.getFPS();
	}

	@Override
	public void serverPing(long gameTime, String biome) {
		Cubyz.biome = Cubyz.world.getCurrentRegistries().biomeRegistry.getByID(biome);
		Cubyz.gameTime = gameTime;
	}

	@Override
	public void updateChunkMesh(NormalChunk mesh) {
		Cubyz.chunkTree.updateChunkMesh(mesh);
	}

	@Override
	public void updateChunkMesh(ReducedChunkVisibilityData mesh) {
		Cubyz.chunkTree.updateChunkMesh(mesh);
	}
}
