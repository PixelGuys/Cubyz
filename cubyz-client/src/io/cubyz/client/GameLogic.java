package io.cubyz.client;

import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.util.*;
import java.util.logging.*;

import javax.imageio.ImageIO;
import javax.swing.JOptionPane;

import org.joml.Vector3f;
import org.joml.Vector3i;
import org.joml.Vector4f;
import org.lwjgl.Version;
import org.lwjgl.opengl.GL12;

import io.cubyz.*;
import io.cubyz.api.ClientConnection;
import io.cubyz.api.ClientRegistries;
import io.cubyz.api.RegistryElement;
import io.cubyz.api.Resource;
import io.cubyz.api.Side;
import io.cubyz.audio.SoundBuffer;
import io.cubyz.audio.SoundManager;
import io.cubyz.audio.SoundSource;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.CustomBlock;
import io.cubyz.blocks.Block.BlockClass;
import io.cubyz.client.loading.LoadThread;
import io.cubyz.entity.Entity;
import io.cubyz.entity.PlayerEntity.PlayerImpl;
import io.cubyz.input.Keybindings;
import io.cubyz.items.CustomItem;
import io.cubyz.items.Inventory;
import io.cubyz.items.ItemBlock;
import io.cubyz.items.tools.Tool;
import io.cubyz.multiplayer.GameProfile;
import io.cubyz.multiplayer.LoginToken;
import io.cubyz.multiplayer.client.MPClient;
import io.cubyz.multiplayer.client.PingResponse;
import io.cubyz.rendering.FrameBuffer;
import io.cubyz.rendering.Material;
import io.cubyz.rendering.Mesh;
import io.cubyz.rendering.Spatial;
import io.cubyz.rendering.Texture;
import io.cubyz.rendering.Window;
import io.cubyz.ui.*;
import io.cubyz.util.PixelUtils;
import io.cubyz.utils.*;
import io.cubyz.world.*;
import io.cubyz.world.generator.LifelandGenerator;

import static io.cubyz.CubyzLogger.logger;

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

	public GameProfile profile;
	public MPClient mpClient;
	public boolean isIntegratedServer = true;
	public boolean isOnlineServerOpened = false;

	public GameLogic() {
		Cubyz.window.setSize(800, 600);
		Cubyz.window.setTitle("Cubyz " + Constants.GAME_BUILD_TYPE + " " + Constants.GAME_VERSION);
	}

	public void cleanup() {
		for (Handler handler : logger.getHandlers()) {
			handler.close();
		}
		if(Cubyz.world != null) quitWorld();
		ClientSettings.save();
		DiscordIntegration.closeRPC();
		if (sound != null) {
			try {
				sound.dispose();
			} catch (Exception e) {
				e.printStackTrace();
			}
		}
		Cubyz.chunkTree.cleanup();
	}
	
	public void quitWorld() {
		for (MenuGUI overlay : Cubyz.gameUI.getOverlays().toArray(new MenuGUI[0])) {
			if (overlay instanceof GameOverlay) {
				Cubyz.gameUI.removeOverlay(overlay);
			}
		}
		Cubyz.world.cleanup();
		Cubyz.world = null;
		
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
				int highestY;
				logger.info("Finding position..");
				while (true) {
					dx = rnd.nextInt(surface.getSizeX());
					dz = rnd.nextInt(surface.getSizeZ());
					logger.info("Trying " + dx + " ? " + dz);
					if(Cubyz.surface.isValidSpawnLocation(dx, dz)) 
						break;
				}
				Cubyz.surface.seek((int)dx, 256/*TODO: Start height that works always*/, (int)dz, ClientSettings.RENDER_DISTANCE, ClientSettings.EFFECTIVE_RENDER_DISTANCE*NormalChunk.chunkSize*2);
				highestY = 512;
				while(highestY >= 0) {
					if(Cubyz.surface.getBlock(dx, highestY, dz) != null && Cubyz.surface.getBlock(dx, highestY, dz).isSolid()) break;
					highestY--;
				}
				Cubyz.player.setPosition(new Vector3i(dx, highestY+2, dz));
				logger.info("OK!");
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
					e.printStackTrace();
				}
				Meshes.blockTextures.put(block, tex);
			}
			for (RegistryElement reg : ts.getCurrentRegistries().itemRegistry.registered()) {
				if(!(reg instanceof CustomItem)) continue;
				CustomItem item = (CustomItem)reg;
				BufferedImage canvas;
				if(item.isGem())
					canvas = getImage("addons/cubyz/items/textures/materials/templates/"+"gem1"+".png"); // TODO: More gem types.
				else
					canvas = getImage("addons/cubyz/items/textures/materials/templates/"+"crystal1"+".png"); // TODO: More crystal types.
				PixelUtils.convertTemplate(canvas, item.getColor());
				InputStream is = TextureConverter.fromBufferedImage(canvas);
				Texture tex = new Texture(is);
				try {
					is.close();
				} catch (IOException e) {
					e.printStackTrace();
				}
				item.setImage(NGraphics.nvgImageFrom(tex));
			}
		}
		// Generate the texture atlas for this surface's truly transparent blocks:
		ArrayList<Block> blocks = new ArrayList<>();
		for(RegistryElement element : surface.getCurrentRegistries().blockRegistry.registered()) {
			blocks.add((Block)element);
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
				ms.play();
			}
		}
	}

	public void requestJoin(String host) {
		requestJoin(host, 58961);
	}

	public void requestJoin(String host, int port) {
		if (mpClient != null) {
			mpClient.connect(host, port);
			mpClient.join(profile);
			serverIP = host;
			serverPort = port;
		} else {
			throw new IllegalStateException("Attempted to join a server while Cubyz is not initialized.");
		}
	}
	
	public PingResponse pingServer(String host) {
		return pingServer(host, 58961);
	}
	
	public PingResponse pingServer(String host, int port) {
		requestJoin(host, port);
		PingResponse resp = mpClient.ping();
		System.out.println("Ping response:");
		System.out.println("\tMOTD: " + resp.motd);
		System.out.println("\tPlayers: " + resp.onlinePlayers + "/" + resp.maxPlayers);
		mpClient.disconnect();
		return resp;
	}

	public void init(Window window) throws Exception {
		if (!new File("assets").exists()) {
			logger.severe("Assets not found.");
			JOptionPane.showMessageDialog(null, "Cubyz could not detect its assets.\nDid you forgot to extract the game?", "Error", JOptionPane.ERROR_MESSAGE);
			System.exit(1);
		}
		
		Cubyz.gameUI.init(window);
		Cubyz.hud = Cubyz.gameUI;
		logger.info("Version " + Constants.GAME_VERSION + " of brand " + Constants.GAME_BRAND);
		logger.info("LWJGL Version: " + Version.VERSION_MAJOR + "." + Version.VERSION_MINOR + "." + Version.VERSION_REVISION);
		logger.info("Jungle Version: " + Constants.GAME_VERSION + "-cubyz");
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
		
		ClientOnly.onBorderCrossing = (p) -> {
			// Simply remake all the spatial data of this surface. Not the most efficient way, but the event of border crossing can be considered rare.
			NormalChunk[] chunks = Cubyz.surface.getChunks();
			for(NormalChunk ch : chunks) {
				for(int i = 0; i < ch.getVisibles().size; i++) {
					BlockInstance bi = ch.getVisibles().array[i];
					bi.setData(bi.getData());
				}
			}
		};
		
		try {
			GameLauncher.renderer.init(window);
			BlockPreview.init();
		} catch (Exception e) {
			logger.log(Level.SEVERE, e, () -> {
				return "An unhandled exception occured while initiazing the renderer:";
			});
			e.printStackTrace();
			System.exit(1);
		}
		logger.info("Renderer: OK!");
		
		Cubyz.gameUI.setMenu(LoadingGUI.getInstance());
		LoadThread lt = new LoadThread();
		
		if (System.getProperty("account.password") == null) {
			profile = new GameProfile("xX_DemoGuy_Xx");
		} else if (System.getProperty("account.password") != null){
			profile = new GameProfile(System.getProperty("account.username"), System.getProperty("account.password").toCharArray());
		} else if (System.getProperty("login.token") != null) {
			UUID player = UUID.fromString(System.getProperty("login.playerUUID"));
			UUID tokenUUID = UUID.fromString(System.getProperty("login.token"));
			String username = System.getProperty("login.username");
			LoginToken token = new LoginToken(tokenUUID, player, username, Long.MAX_VALUE);
			profile = new GameProfile(token);
		}
		
		try {
			mpClient = new MPClient();
		} catch (Exception e) {
			e.printStackTrace();
		}
		
		LoadThread.addOnLoadFinished(() -> {
			LifelandGenerator.init();
			
			sound = new SoundManager();
			try {
				sound.init();
			} catch (Exception e) {
				e.printStackTrace();
			}
			
			if (ResourceManager.lookupPath("cubyz/sound") != null) {
				try {
					music = new SoundBuffer(ResourceManager.lookupPath("cubyz/sound/Sincerely.ogg"));
				} catch (Exception e) {
					e.printStackTrace();
				}
				musicSource = new SoundSource(true, true);
				musicSource.setBuffer(music.getBufferId());
				musicSource.setGain(0.3f);
			} else {
				logger.info("Missing optional sound files. Sounds are disabled.");
			}
			
			Cubyz.renderDeque.add(() -> {
				File[] list = new File("assets/cubyz/textures/breaking").listFiles();
				ArrayList<Texture> breakingAnims = new ArrayList<>();
				for (File file : list) {
					try {
						Texture tex = new Texture(file);
						tex.setWrapMode(GL12.GL_REPEAT);
						breakingAnims.add(tex);
					} catch (IOException e) {
						e.printStackTrace();
					}
				}
				breakAnimations = breakingAnims.toArray(new Texture[breakingAnims.size()]);
				System.gc();
			});
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
		return BlockPreview.generateBuffer(Cubyz.window, new Vector3f(1, 1, 1), b);
	}	
	
	public void update(float interval) {
		if (!Cubyz.gameUI.doesGUIPauseGame() && Cubyz.world != null) {
			if (!Cubyz.gameUI.doesGUIBlockInput()) {
				Cubyz.player.move(Cubyz.playerInc.mul(0.11F), Cubyz.camera.getRotation(), Cubyz.surface.getSizeX(), Cubyz.surface.getSizeZ());
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
		} catch(Exception e) {}//e.printStackTrace();}
		return null;
	}
}
