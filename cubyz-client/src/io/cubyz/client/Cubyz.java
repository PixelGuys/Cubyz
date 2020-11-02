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
import org.lwjgl.glfw.GLFW;
import org.lwjgl.opengl.GL12;

import io.cubyz.*;
import io.cubyz.api.ClientConnection;
import io.cubyz.api.ClientRegistries;
import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.RegistryElement;
import io.cubyz.api.Resource;
import io.cubyz.api.Side;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.CustomOre;
import io.cubyz.blocks.Block.BlockClass;
import io.cubyz.client.loading.LoadThread;
import io.cubyz.entity.Entity;
import io.cubyz.entity.EntityType;
import io.cubyz.entity.Player;
import io.cubyz.items.CustomItem;
import io.cubyz.items.Inventory;
import io.cubyz.items.ItemBlock;
import io.cubyz.items.tools.Tool;
import io.cubyz.multiplayer.GameProfile;
import io.cubyz.multiplayer.LoginToken;
import io.cubyz.multiplayer.client.MPClient;
import io.cubyz.multiplayer.client.PingResponse;
import io.cubyz.ui.*;
import io.cubyz.ui.mods.InventoryGUI;
import io.cubyz.utils.*;
import io.cubyz.utils.ResourceUtilities.BlockModel;
import io.cubyz.utils.ResourceUtilities.BlockSubModel;
import io.cubyz.world.*;
import io.cubyz.world.cubyzgenerators.TerrainGenerator;
import io.cubyz.world.generator.LifelandGenerator;
import io.jungle.*;
import io.jungle.audio.SoundBuffer;
import io.jungle.audio.SoundManager;
import io.jungle.audio.SoundSource;
import io.jungle.game.*;
import io.jungle.util.*;

import static io.cubyz.CubyzLogger.logger;

/**
 * A complex class that holds everything together.<br>
 * TODO: Move functionality to better suited places(like world loading should probably be handled somewhere in the World class).
 */

public class Cubyz implements GameLogic, ClientConnection {

	public static Context ctx;
	private Window win;
	public static MainRenderer renderer;
	public Game game;
	private DirectionalLight light;
	private Vector3f playerInc;
	public static MouseInput mouse;
	public static UISystem gameUI;
	public static World world;
	public static Surface surface;
	public static SoundManager sound;
	private SoundBuffer music;
	private SoundSource musicSource;
	private int worldSeason = 0;
	
	public static Texture[] breakAnimations;
	
	public static Mesh skyBodyMesh;
	private static Spatial skySun;
	private static Spatial skyMoon;
	
	public static int inventorySelection = 0; // Selected slot in inventory

	private MeshSelectionDetector msd;

	private int breakCooldown = 10;
	private int buildCooldown = 10;

	public static String serverIP = "localhost";
	public static int serverPort = 58961;
	public static int serverCapacity = 1;
	public static int serverOnline = 1;

	public static GameProfile profile;
	public static MPClient mpClient;
	public static boolean isIntegratedServer = true;
	public static boolean isOnlineServerOpened = false;

	public static boolean clientShowDebug = false;

	public static Cubyz instance;
	
	public static Deque<Runnable> renderDeque = new ArrayDeque<>();
	
	public boolean screenshot;

	public Cubyz() {
		instance = this;
	}

	@Override
	public void bind(Game g) {
		game = g;
		win = g.getWindow();
		win.setSize(800, 600);
		win.setTitle("Cubyz " + Constants.GAME_BUILD_TYPE + " " + Constants.GAME_VERSION);
	}

	@Override
	public void cleanup() {
		renderer.cleanup();
		for (Handler handler : logger.getHandlers()) {
			handler.close();
		}
		ClientSettings.save();
		DiscordIntegration.closeRPC();
		if (sound != null) {
			try {
				sound.dispose();
			} catch (Exception e) {
				e.printStackTrace();
			}
		}
	}
	
	public static void quitWorld() {
		for (MenuGUI overlay : gameUI.getOverlays().toArray(new MenuGUI[0])) {
			if (overlay instanceof GameOverlay) {
				gameUI.removeOverlay(overlay);
			}
		}
		Cubyz.world.cleanup();
		Cubyz.world = null;
		
		SoundSource ms = Cubyz.instance.musicSource;
		if (ms != null) {
			if (ms.isPlaying()) {
				ms.stop();
			}
		}
		// TODO: unload custom ore models
		System.gc();
	}
	
	public static void loadWorld(Surface surface) { // TODO: Seperate all the things out that are generated for the current surface.
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
			worldSpatialList = new Spatial[] {skySun/*, skyMoon*/};
		}
		Cubyz.surface = surface;
		Cubyz.world = surface.getStellarTorus().getWorld();
		if (world.isLocal()) {
			Random rnd = new Random();
			int dx = 0;
			int dz = 0;
			if (world.getLocalPlayer().getPosition().x == 0 && world.getLocalPlayer().getPosition().z == 0) {
				int highestY;
				logger.info("Finding position..");
				while (true) {
					dx = rnd.nextInt(surface.getSize());
					dz = rnd.nextInt(surface.getSize());
					logger.info("Trying " + dx + " ? " + dz);
					world.getCurrentTorus().synchronousSeek(dx, dz, ClientSettings.RENDER_DISTANCE);
					highestY = world.getCurrentTorus().getHeight(dx, dz);
					if(highestY >= TerrainGenerator.SEA_LEVEL) // TODO: Take care about other SurfaceGenerators.
						break;
				}
				world.getLocalPlayer().setPosition(new Vector3i(dx, highestY+2, dz));
				logger.info("OK!");
			}
		}
		DiscordIntegration.setStatus("Playing");
		Cubyz.gameUI.addOverlay(new GameOverlay());
		
		if (world instanceof LocalWorld) { // custom ores on multiplayer later, maybe?
			LocalSurface ts = (LocalSurface) surface;
			ArrayList<CustomOre> customOres = ts.getCustomOres();
			for (CustomOre ore : customOres) {
				BufferedImage stone = getImage("addons/cubyz/blocks/textures/stone.png");
				BufferedImage img = CustomOre.generateOreTexture(stone, ore.seed, ore.color, ore.shinyness);
				InputStream is = TextureConverter.fromBufferedImage(img);
				Texture tex = new Texture(is);
				try {
					is.close();
				} catch (IOException e) {
					e.printStackTrace();
				}
				Meshes.blockTextures.put(ore, tex);
			}
			for (RegistryElement reg : ts.getCurrentRegistries().itemRegistry.registered()) {
				if(!(reg instanceof CustomItem)) continue;
				CustomItem item = (CustomItem)reg;
				BufferedImage canvas;
				if(item.isGem())
					canvas = getImage("addons/cubyz/items/textures/materials/templates/"+"gem1"+".png"); // TODO: More gem types.
				else
					canvas = getImage("addons/cubyz/items/textures/materials/templates/"+"crystal1"+".png"); // TODO: More crystal types.
				TextureConverter.convertTemplate(canvas, item.getColor());
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
		ArrayList<Block> trulyTransparents = new ArrayList<>();
		Meshes.transparentBlockMesh = Meshes.cachedDefaultModels.get("cubyz:plane.obj");
		for(RegistryElement element : surface.getCurrentRegistries().blockRegistry.registered()) {
			Block block = (Block)element;
			if(Meshes.blockMeshes.get(block) == Meshes.transparentBlockMesh) {
				trulyTransparents.add(block);
			}
		}
		Meshes.transparentAtlasSize = (int)Math.ceil(Math.sqrt(trulyTransparents.size()));
		int maxSize = 16; // Scale all textures so they fit the size of the biggest texture.
		// Get the textures for those blocks:
		ArrayList<BufferedImage> blockTextures = new ArrayList<>();
		for(Block block : trulyTransparents) {
			BufferedImage texture = ResourceUtilities.loadBlockTextureToBufferedImage(block.getRegistryID());
			if(texture != null) {
				maxSize = Math.max(maxSize, Math.max(texture.getWidth(), texture.getHeight()));
				blockTextures.add(texture);
			}
		}
		// Put the textures into the atlas
		BufferedImage atlas = new BufferedImage(maxSize*Meshes.transparentAtlasSize, maxSize*Meshes.transparentAtlasSize, BufferedImage.TYPE_INT_ARGB);
		int x = 0, y = 0;
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
			trulyTransparents.get(i).atlasX = x;
			trulyTransparents.get(i).atlasY = y;
			x++;
			if(x == Meshes.transparentAtlasSize) {
				x = 0;
				y++;
			}
		}
		Meshes.transparentBlockMesh.getMaterial().setTexture(new Texture(TextureConverter.fromBufferedImage(atlas)));
		
		
		SoundSource ms = Cubyz.instance.musicSource;
		if (ms != null) {
			if (!ms.isPlaying()) {
				ms.play();
			}
		}
	}

	public static void requestJoin(String host) {
		requestJoin(host, 58961);
	}

	public static void requestJoin(String host, int port) {
		if (mpClient != null) {
			mpClient.connect(host, port);
			mpClient.join(profile);
			serverIP = host;
			serverPort = port;
		} else {
			throw new IllegalStateException("Attempted to join a server while Cubyz is not initialized.");
		}
	}
	
	public static PingResponse pingServer(String host) {
		return pingServer(host, 58961);
	}
	
	public static PingResponse pingServer(String host, int port) {
		requestJoin(host, port);
		PingResponse resp = mpClient.ping();
		System.out.println("Ping response:");
		System.out.println("\tMOTD: " + resp.motd);
		System.out.println("\tPlayers: " + resp.onlinePlayers + "/" + resp.maxPlayers);
		mpClient.disconnect();
		return resp;
	}

	@Override
	public void init(Window window) throws Exception {
		if (!new File("assets").exists()) {
			logger.severe("Assets not found.");
			JOptionPane.showMessageDialog(null, "Cubyz could not detect its assets.\nDid you forgot to extract the game?", "Error", JOptionPane.ERROR_MESSAGE);
			System.exit(1);
		}
		
		gameUI = new UISystem();
		gameUI.init(window);
		playerInc = new Vector3f();
		renderer = new MainRenderer();
		ctx = new Context(game, new Camera());
		ctx.setHud(gameUI);
		ctx.setFog(new Fog(true, new Vector3f(0.5f, 0.5f, 0.5f), 0.025f));
		light = new DirectionalLight(new Vector3f(1.0f, 1.0f, 1.0f), new Vector3f(0.0f, 1.0f, 0.0f).mul(0.1f));
		mouse = new MouseInput();
		mouse.init(window);
		logger.info("Version " + Constants.GAME_VERSION + " of brand " + Constants.GAME_BRAND);
		logger.info("LWJGL Version: " + Version.VERSION_MAJOR + "." + Version.VERSION_MINOR + "." + Version.VERSION_REVISION);
		logger.info("Jungle Version: " + Constants.GAME_VERSION + "-cubyz");
		Constants.setGameSide(Side.CLIENT);
		msd = new MeshSelectionDetector();
		
		// Cubyz resources
		ResourcePack baserp = new ResourcePack();
		baserp.path = new File("assets");
		baserp.name = "Cubyz";
		ResourceManager.packs.add(baserp);
		
		renderer.setShaderFolder(ResourceManager.lookupPath("cubyz/shaders/easyLighting"));
		
		BlockPreview.setShaderFolder(ResourceManager.lookupPath("cubyz/shaders/blockPreview"));

		ClientOnly.client = this;
		
		Meshes.initMeshCreators();
		
		ClientOnly.onBorderCrossing = (p) -> {
			// Simply remake all the spatial data of this surface. Not the most efficient way, but the event of border crossing can be considered rare.
			NormalChunk[] chunks = Cubyz.surface.getChunks();
			for(NormalChunk ch : chunks) {
				for(int i = 0; i < ch.getVisibles().size; i++) {
					BlockInstance bi = ch.getVisibles().array[i];
					bi.setData(bi.getData(), world.getLocalPlayer(), surface.getSize());
				}
			}
		};
		
		try {
			renderer.init(window);
			BlockPreview.init();
		} catch (Exception e) {
			logger.log(Level.SEVERE, e, () -> {
				return "An unhandled exception occured while initiazing the renderer:";
			});
			e.printStackTrace();
			System.exit(1);
		}
		logger.info("Renderer: OK!");
		
		gameUI.setMenu(LoadingGUI.getInstance());
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
			
			renderDeque.add(() -> {
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
		gameUI.setMenu(gui);
	}

	private Vector3f dir = new Vector3f();
	
	@Override
	public void input(Window window) {
		mouse.input(window);
		if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_F3)) {
			Cubyz.clientShowDebug = !Cubyz.clientShowDebug;
			Keyboard.setKeyPressed(GLFW.GLFW_KEY_F3, false);
		}
		if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_F11)) {
			renderDeque.push(() -> {
				window.setFullscreen(!window.isFullscreen());
			});
			Keyboard.setKeyPressed(GLFW.GLFW_KEY_F11, false);
		}
		if (!gameUI.doesGUIBlockInput() && world != null) {
			if (Keybindings.isPressed("forward")) {
				if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_LEFT_CONTROL)) {
					if (world.getLocalPlayer().isFlying()) {
						playerInc.z = -8;
					} else {
						playerInc.z = -2;
					}
				} else {
					playerInc.z = -1;
				}
			}
			if (Keybindings.isPressed("backward")) {
				playerInc.z = 1;
			}
			if (Keybindings.isPressed("left")) {
				playerInc.x = -1;
			}
			if (Keybindings.isPressed("right")) {
				playerInc.x = 1;
			}
			if (Keybindings.isPressed("jump")) {
				Player localPlayer = world.getLocalPlayer();
				if (localPlayer.isFlying()) {
					world.getLocalPlayer().vy = 0.25F;
				} else if (world.getLocalPlayer().isOnGround()) {
					world.getLocalPlayer().vy = 0.25F;
				}
			}
			if (Keybindings.isPressed("fall")) {
				if (world.getLocalPlayer().isFlying()) {
					world.getLocalPlayer().vy = -0.25F;
				}
			}
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_F)) {
				world.getLocalPlayer().setFlying(!world.getLocalPlayer().isFlying());
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_F, false);
			}
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_P)) {
				// debug: spawn a pig
				Vector3f pos = new Vector3f(world.getLocalPlayer().getPosition());
				EntityType pigType = CubyzRegistries.ENTITY_REGISTRY.getByID("cubyz:pig");
				if (pigType == null) return;
				Entity pig = pigType.newEntity(world.getCurrentTorus());
				pig.setPosition(pos);
				world.getCurrentTorus().addEntity(pig);
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_P, false);
			}
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_C)) {
				int mods = Keyboard.getKeyMods();
				if ((mods & GLFW.GLFW_MOD_CONTROL) == GLFW.GLFW_MOD_CONTROL) {
					if ((mods & GLFW.GLFW_MOD_SHIFT) == GLFW.GLFW_MOD_SHIFT) { // Control + Shift + C
						if (gameUI.getMenuGUI() == null) {
							gameUI.setMenu(new ConsoleGUI());
						}
					}
				}
			}
			if (Keybindings.isPressed("inventory")) {
				gameUI.setMenu(new InventoryGUI());
				Keyboard.setKeyPressed(Keybindings.getKeyCode("inventory"), false);
			}
			if ((mouse.isLeftButtonPressed() || mouse.isRightButtonPressed()) && !mouse.isGrabbed() && gameUI.getMenuGUI() == null) {
				mouse.setGrabbed(true);
				mouse.clearPos(window.getWidth() / 2, window.getHeight() / 2);
				breakCooldown = 10;
			}
			
			if (mouse.isGrabbed()) {
				ctx.getCamera().moveRotation(mouse.getDisplVec().x * 0.0089F, mouse.getDisplVec().y * 0.0089F, 5F);
				mouse.clearPos(win.getWidth() / 2, win.getHeight() / 2);
			}
			
			// inventory related
			inventorySelection = (inventorySelection + (int) mouse.getScrollOffset()) & 7;
			if (Keybindings.isPressed("hotbar 1")) {
				inventorySelection = 0;
			}
			if (Keybindings.isPressed("hotbar 2")) {
				inventorySelection = 1;
			}
			if (Keybindings.isPressed("hotbar 3")) {
				inventorySelection = 2;
			}
			if (Keybindings.isPressed("hotbar 4")) {
				inventorySelection = 3;
			}
			if (Keybindings.isPressed("hotbar 5")) {
				inventorySelection = 4;
			}
			if (Keybindings.isPressed("hotbar 6")) {
				inventorySelection = 5;
			}
			if (Keybindings.isPressed("hotbar 7")) {
				inventorySelection = 6;
			}
			if (Keybindings.isPressed("hotbar 8")) {
				inventorySelection = 7;
			}
			
			// render distance
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_MINUS)) {
				if(ClientSettings.RENDER_DISTANCE >= 2)
					ClientSettings.RENDER_DISTANCE--;
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_MINUS, false);
				System.gc();
			}
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_EQUAL)) {
				ClientSettings.RENDER_DISTANCE++;
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_EQUAL, false);
				System.gc();
			}
			msd.selectSpatial(world.getCurrentTorus().getChunks(), world.getLocalPlayer().getPosition(), ctx.getCamera().getViewMatrix().positiveZ(dir).negate(), surface.getStellarTorus().getWorld().getLocalPlayer(), surface.getSize(), surface);
		}
		if (world != null) {
			if (Keybindings.isPressed("menu")) {
				if (gameUI.getMenuGUI() != null) {
					gameUI.setMenu(null);
					mouse.setGrabbed(true);
					Keyboard.setKeyPressed(Keybindings.getKeyCode("menu"), false);
				} else {
					Keyboard.setKeyPressed(Keybindings.getKeyCode("menu"), false);
					gameUI.setMenu(new PauseGUI(), TransitionStyle.NONE);
				}
			}
		}
		mouse.clearScroll();
	}

	public static final NormalChunk[] EMPTY_CHUNK_LIST = new NormalChunk[0];
	public static final ReducedChunk[] EMPTY_REDUCED_CHUNK_LIST = new ReducedChunk[0];
	public static final Block[] EMPTY_BLOCK_LIST = new Block[0];
	public static final Entity[] EMPTY_ENTITY_LIST = new Entity[0];
	public static final Spatial[] EMPTY_SPATIAL_LIST = new Spatial[0];
	
	private Vector3f ambient = new Vector3f();
	private Vector3f brightAmbient = new Vector3f(1, 1, 1);
	private Vector4f clearColor = new Vector4f(0.1f, 0.7f, 0.7f, 1f);
	
	public FrameBuffer blockPreview(Block b) {
		return BlockPreview.generateBuffer(game.getWindow(), new Vector3f(1, 1, 1), b);
	}
	
	public void seasonUpdateDynamodels() {
		
		String season = null;
		switch (worldSeason) {
		case 0:
			season = "spring";
			break;
		case 1:
			season = "summer";
			break;
		case 2:
			season = "autumn";
			break;
		case 3:
			season = "winter";
			break;
		default:
			return;
		}
		
		for (RegistryElement elem : CubyzRegistries.BLOCK_REGISTRY.registered()) {
			Block block = (Block) elem;
			Resource rsc = block.getRegistryID();
			try {
				Texture tex = null;
				InstancedMesh mesh = null;
				BlockModel bm = null;
				try {
					bm = ResourceUtilities.loadModel(rsc);
				} catch (IOException e) {
					logger.warning(rsc + " model not found");
					//e.printStackTrace();
					bm = ResourceUtilities.loadModel(new Resource("cubyz:undefined"));
				}
				
				// Cached meshes
				InstancedMesh defaultMesh = null;
				for (String key : Meshes.cachedDefaultModels.keySet()) {
					if (key.equals(bm.subModels.get("default").model)) {
						defaultMesh = Meshes.cachedDefaultModels.get(key);
					}
				}
				BlockSubModel subModel = bm.subModels.get("default");
				if (bm.dynaModelPurposes.contains("seasons")) {
					if (bm.subModels.containsKey(season)) {
						subModel = bm.subModels.get(season);
					}
				}
				if (defaultMesh == null) {
					Resource rs = new Resource(subModel.model);
					defaultMesh = (InstancedMesh)OBJLoader.loadMesh("assets/" + rs.getMod() + "/models/3d/" + rs.getID(), true); // Blocks are always instanced.
					defaultMesh.setBoundingRadius(2.0f);
					Meshes.cachedDefaultModels.put(subModel.model, defaultMesh);
				}
				Resource texResource = new Resource(subModel.texture);
				String texture = texResource.getID();
				if (!new File("assets/" + texResource.getMod() + "/textures/" + texture + ".png").exists()) {
					logger.warning(texResource + " texture not found");
					texture = "blocks/undefined";
				}
				tex = new Texture("assets/" + texResource.getMod() + "/textures/" + texture + ".png");
				
				mesh = (InstancedMesh)defaultMesh.cloneNoMaterial();
				Material material = new Material(tex, 0.6F);
				mesh.setMaterial(material);
				
				Meshes.blockMeshes.put(block, mesh);
			} catch (Exception e) {
				e.printStackTrace();
			}
		}
	}
	
	float playerBobbing;
	boolean bobbingUp;
	static Spatial[] worldSpatialList;
	
	@Override
	public void render(Window window) {
		if (window.shouldClose()) {
			game.exit();
		}
		
		if (world != null) {
			if (playerInc.x != 0 || playerInc.z != 0) { // while walking
				if (bobbingUp) {
					playerBobbing += 0.005f;
					if (playerBobbing >= 0.05f) {
						bobbingUp = false;
					}
				} else {
					playerBobbing -= 0.005f;
					if (playerBobbing <= -0.05f) {
						bobbingUp = true;
					}
				}
			}
			if (playerInc.y != 0) {
				world.getLocalPlayer().vy = playerInc.y;
			}
			if (playerInc.x != 0) {
				world.getLocalPlayer().vx = playerInc.x;
			}
			ctx.getCamera().setPosition(world.getLocalPlayer().getPosition().x, world.getLocalPlayer().getPosition().y + Player.cameraHeight + playerBobbing, world.getLocalPlayer().getPosition().z);
		}
		
		if (!renderDeque.isEmpty()) {
			renderDeque.pop().run();
		}
		if (world != null) {
			if (worldSeason != world.getCurrentTorus().getStellarTorus().getSeason()) {
				worldSeason = world.getCurrentTorus().getStellarTorus().getSeason();
				seasonUpdateDynamodels();
				logger.info("Updated season to ID " + worldSeason);
			}
			ambient.x = ambient.y = ambient.z = world.getCurrentTorus().getGlobalLighting();
			if(ambient.x < 0.1f) ambient.x = 0.1f;
			if(ambient.y < 0.1f) ambient.y = 0.1f;
			if(ambient.z < 0.1f) ambient.z = 0.1f;
			clearColor = world.getCurrentTorus().getClearColor();
			ctx.getFog().setColor(clearColor);
			if (ClientSettings.FOG_COEFFICIENT == 0) {
				ctx.getFog().setActive(false);
			} else {
				ctx.getFog().setActive(true);
			}
			ctx.getFog().setDensity(1 / (ClientSettings.RENDER_DISTANCE*ClientSettings.FOG_COEFFICIENT));
			Player player = world.getLocalPlayer();
			Block bi = world.getCurrentTorus().getBlock(Math.round(player.getPosition().x), (int)(player.getPosition().y)+3, Math.round(player.getPosition().z));
			if(bi != null && !bi.isSolid()) {
				int absorption = bi.getAbsorption();
				ambient.x *= 1.0f - Math.pow(((absorption >>> 16) & 255)/255.0f, 0.25);
				ambient.y *= 1.0f - Math.pow(((absorption >>> 8) & 255)/255.0f, 0.25);
				ambient.z *= 1.0f - Math.pow(((absorption >>> 0) & 255)/255.0f, 0.25);
			}
			light.setColor(clearColor);
			float lightY = (((float)world.getGameTime() % world.getCurrentTorus().getStellarTorus().getDayCycle()) / (float) (world.getCurrentTorus().getStellarTorus().getDayCycle()/2)) - 1f; // TODO: work on it more
			float lightX = (((float)world.getGameTime() % world.getCurrentTorus().getStellarTorus().getDayCycle()) / (float) (world.getCurrentTorus().getStellarTorus().getDayCycle()/2)) - 1f;
			light.getDirection().set(lightY, 0, lightX);
			// Set intensity:
			light.setDirection(light.getDirection().mul(0.1f*world.getCurrentTorus().getGlobalLighting()/light.getDirection().length()));
			window.setClearColor(clearColor);
			renderer.render(window, ctx, ambient, light, world.getCurrentTorus().getChunks(), world.getCurrentTorus().getReducedChunks(), world.getBlocks(), world.getCurrentTorus().getEntities(), worldSpatialList, world.getLocalPlayer(), world.getCurrentTorus().getSize());
		} else {
			clearColor.y = clearColor.z = 0.7f;
			clearColor.x = 0.1f;
			
			window.setClearColor(clearColor);
			
			if (screenshot) {
				FrameBuffer buf = new FrameBuffer();
				buf.genColorTexture(window.getWidth(), window.getHeight());
				buf.genRenderbuffer(window.getWidth(), window.getHeight());
				window.setRenderTarget(buf);
			}
			
			renderer.render(window, ctx, brightAmbient, light, EMPTY_CHUNK_LIST, EMPTY_REDUCED_CHUNK_LIST, EMPTY_BLOCK_LIST, EMPTY_ENTITY_LIST, EMPTY_SPATIAL_LIST, null, -1);
			
			if (screenshot) {
				/*FrameBuffer buf = window.getRenderTarget();
				window.setRenderTarget(null);
				screenshot = false;*/
			}
		}
		
		Keyboard.releaseCodePoint();
		Keyboard.releaseKeyCode();
	}
	
	@Override
	public void update(float interval) {
		if (!gameUI.doesGUIPauseGame() && world != null) {
			Player lp = world.getLocalPlayer();
			if (!gameUI.doesGUIBlockInput()) {
				lp.move(playerInc.mul(0.11F), ctx.getCamera().getRotation(), world.getCurrentTorus().getSize());
				if (breakCooldown > 0) {
					breakCooldown--;
				}
				if (buildCooldown > 0) {
					buildCooldown--;
				}
				if (Keybindings.isPressed("destroy")) {
					//Breaking Blocks
					if(world.getLocalPlayer().isFlying()) { // Ignore hardness when in flying.
						if (breakCooldown == 0) {
							breakCooldown = 7;
							Object bi = msd.getSelected();
							if (bi != null && bi instanceof BlockInstance && ((BlockInstance)bi).getBlock().getBlockClass() != BlockClass.UNBREAKABLE) {
								world.getCurrentTorus().removeBlock(((BlockInstance)bi).getX(), ((BlockInstance)bi).getY(), ((BlockInstance)bi).getZ());
							}
						}
					}
					else {
						Object selected = msd.getSelected();
						if(selected instanceof BlockInstance) {
							world.getLocalPlayer().breaking((BlockInstance)selected, inventorySelection, world.getCurrentTorus());
						}
					}
					// Hit entities:
					Object selected = msd.getSelected();
					if(selected instanceof Entity) {
						((Entity)selected).hit(world.getLocalPlayer().getInventory().getItem(inventorySelection) instanceof Tool ? (Tool)world.getLocalPlayer().getInventory().getItem(inventorySelection) : null, ctx.getCamera().getViewMatrix().positiveZ(dir).negate());
					}
				} else {
					world.getLocalPlayer().resetBlockBreaking();
				}
				if (Keybindings.isPressed("place/use") && buildCooldown <= 0) {
					if((msd.getSelected() instanceof BlockInstance) && ((BlockInstance)msd.getSelected()).getBlock().onClick(world, ((BlockInstance)msd.getSelected()).getPosition())) {
						// Interact with block(potentially do a hand animation, in the future).
					} else if(world.getLocalPlayer().getInventory().getItem(inventorySelection) instanceof ItemBlock) {
						// Build block:
						if (msd.getSelected() != null) {
							buildCooldown = 10;
							if(msd.getSelected() instanceof BlockInstance) {
								Vector3i pos = new Vector3i(0, 0, 0);
								Vector3i dir = new Vector3i(0, 0, 0);
								msd.getEmptyPlace(pos, dir);
								Block b = world.getLocalPlayer().getInventory().getBlock(inventorySelection);
								if (b != null && pos != null) {
									boolean dataOnlyUpdate = world.getCurrentTorus().getBlock(pos.x, pos.y, pos.z) == b;
									byte data = b.mode.generateData(dir, dataOnlyUpdate ? world.getCurrentTorus().getBlockData(pos.x, pos.y, pos.z) : 0);
									if(dataOnlyUpdate) {
										world.getCurrentTorus().updateBlockData(pos.x, pos.y, pos.z, data);
									} else {
										world.getCurrentTorus().placeBlock(pos.x, pos.y, pos.z, b, data);
									}
									world.getLocalPlayer().getInventory().getStack(inventorySelection).add(-1);
								}
							}
						}
					} else if(world.getLocalPlayer().getInventory().getItem(inventorySelection) != null) {
						// Use item:
						if(world.getLocalPlayer().getInventory().getItem(inventorySelection).onUse(world.getLocalPlayer())) {
							world.getLocalPlayer().getInventory().getStack(inventorySelection).add(-1);
							buildCooldown = 10;
						}
					}
				}
			}
			playerInc.x = playerInc.y = playerInc.z = 0.0F; // Reset positions
			NormalChunk ch = world.getCurrentTorus().getChunk((int)lp.getPosition().x >> 4, (int)lp.getPosition().z >> 4);
			if (ch != null && ch.isLoaded()) {
				world.update();
			}
			world.getCurrentTorus().seek((int)lp.getPosition().x, (int)lp.getPosition().z, ClientSettings.RENDER_DISTANCE, ClientSettings.MAX_RESOLUTION, ClientSettings.FAR_DISTANCE_FACTOR);
			float lightAngle = (float)Math.PI/2 + (float)Math.PI*(((float)world.getGameTime() % world.getCurrentTorus().getStellarTorus().getDayCycle())/(world.getCurrentTorus().getStellarTorus().getDayCycle()/2));
			skySun.setPositionRaw((float)Math.cos(lightAngle)*500, (float)Math.sin(lightAngle)*500, 0);
			skySun.setRotation(0, 0, -lightAngle);
		}
	}

	public static int getFPS() {
		return Cubyz.instance.game.getFPS();
	}
	
	public static BufferedImage getImage(String fileName) {
		try {
			return ImageIO.read(new File(fileName));
		} catch(Exception e) {}//e.printStackTrace();}
		return null;
	}
}
