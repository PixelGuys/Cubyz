package io.cubyz.client;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.util.*;
import java.util.function.Consumer;
import java.util.logging.*;

import javax.imageio.ImageIO;
import javax.swing.JOptionPane;

import org.joml.Vector3f;
import org.joml.Vector3i;
import org.joml.Vector4f;
import org.lwjgl.Version;
import org.lwjgl.glfw.GLFW;
import org.lwjgl.opengl.GL11;

import io.cubyz.*;
import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.IRegistryElement;
import io.cubyz.api.Resource;
import io.cubyz.api.Side;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.CustomOre;
import io.cubyz.blocks.Ore;
import io.cubyz.blocks.Block.BlockClass;
import io.cubyz.client.loading.LoadThread;
import io.cubyz.entity.Entity;
import io.cubyz.entity.EntityType;
import io.cubyz.entity.Player;
import io.cubyz.handler.BlockVisibilityChangeHandler;
import io.cubyz.items.CustomItem;
import io.cubyz.math.Vector3fi;
import io.cubyz.multiplayer.GameProfile;
import io.cubyz.multiplayer.LoginToken;
import io.cubyz.multiplayer.client.MPClient;
import io.cubyz.multiplayer.client.PingResponse;
import io.cubyz.save.BlockChange;
import io.cubyz.translate.Language;
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

public class Cubyz implements IGameLogic {

	public static Context ctx;
	private Window win;
	public static MainRenderer renderer;
	public Game game;
	private DirectionalLight light;
	private Vector3f playerInc;
	public static MouseInput mouse;
	public static UISystem gameUI;
	public static World world;
	public static Language lang;
	public static SoundManager sound;
	private SoundBuffer music;
	private SoundSource musicSource;
	private int worldSeason = 0;
	
	public static int inventorySelection = 0; // Selected slot in inventory

	private CubyzMeshSelectionDetector msd;

	private int breakCooldown = 10;
	private int buildCooldown = 10;

	public static Logger log = CubyzLogger.i;

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
	public static HashMap<String, Mesh> cachedDefaultModels = new HashMap<>();

	public static int GUIKey = -1;
	
	private static HashMap<String, MenuGUI> userGUIs = new HashMap<>();
	
	public boolean screenshot;

	public Cubyz() {
		instance = this;
	}

	@Override
	public void bind(Game g) {
		game = g;
		win = g.getWindow();
		win.setSize(800, 600);
		win.setTitle("Cubyz " + Utilities.capitalize(Constants.GAME_BUILD_TYPE) + " " + Constants.GAME_VERSION);
	}

	@Override
	public void cleanup() {
		renderer.cleanup();
		for (Handler handler : log.getHandlers()) {
			handler.close();
		}
		Configuration.save();
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
	
	public static void loadWorld(World world) {
		if (Cubyz.world != null) {
			quitWorld();
		}
		
		Cubyz.world = world;
		if (world.isLocal()) {
			Random rnd = new Random();
			int dx = 0;
			int dz = 0;
			int highestY = 0;
			CubyzLogger.i.info("Finding position..");
			while (true) {
				dx = rnd.nextInt(10000) - 5000;
				dz = rnd.nextInt(10000) - 5000;
				//dx = dz = Integer.MIN_VALUE+512;
				CubyzLogger.i.info("Trying " + dx + " ? " + dz);
				world.synchronousSeek(dx, dz);
				highestY = world.getHighestBlock(dx, dz);
				if (highestY > TerrainGenerator.SEA_LEVEL) { // TODO: always true if generator doesn't use standard TerrainGenerator.
					break;
				}
			}
			if (world.getLocalPlayer().getPosition().x == 0 && world.getLocalPlayer().getPosition().z == 0) { // temporary solution to only TP on spawn
				world.getLocalPlayer().setPosition(new Vector3i(dx, highestY+2, dz));
			}
			CubyzLogger.i.info("OK!");
		}
		world.synchronousSeek(0, 0);
		DiscordIntegration.setStatus("Playing");
		Cubyz.gameUI.addOverlay(new GameOverlay());
		
		if (world instanceof LocalWorld) { // custom ores on multiplayer later, maybe?
			LocalWorld lw = (LocalWorld) world;
			ArrayList<CustomOre> customOres = lw.getCustomOres();
			for (CustomOre ore : customOres) {
				BufferedImage canvas = new BufferedImage(32, 32, BufferedImage.TYPE_INT_RGB);
				BufferedImage stone = getImage("assets/cubyz/textures/blocks/stone.png");
				BufferedImage templateImg = getImage("assets/cubyz/textures/blocks/ore_templates/template"+ore.template+".png");
				for(int x = 0; x < 32; x++) {
					for(int y = 0; y < 32; y++) {
						int color = stone.getRGB(x%16, y%16);
						int a = templateImg.getRGB(x%16, y%16) >>> 24;
						int rBG = (color >>> 16) & 255;
						int gBG = (color >>> 8) & 255;
						int bBG = color & 255;
						int r = (ore.getColor() >>> 16) & 255;
						int g = (ore.getColor() >>> 8) & 255;
						int b = ore.getColor() & 255;
						r = (a*r+(255-a)*rBG)/255;
						g = (a*g+(255-a)*gBG)/255;
						b = (a*b+(255-a)*bBG)/255;
						canvas.setRGB(x, y, new Color(r, g, b).getRGB());
					}
				}
				InputStream is = TextureConverter.fromBufferedImage(canvas);
				Texture tex = new Texture(is);
				try {
					is.close();
				} catch (IOException e) {
					e.printStackTrace();
				}
				Material material = new Material(tex, 0.6F);
				Meshes.blockMeshes.get(ore).setMaterial(material);
			}
			ArrayList<CustomItem> customItems = lw.getCustomItems();
			for (CustomItem item : customItems) {
				BufferedImage canvas;
				if(item.isGem())
					canvas = getImage("assets/cubyz/textures/items/materials/templates/"+"gem1"+".png"); // TODO: More gem types.
				else
					canvas = getImage("assets/cubyz/textures/items/materials/templates/"+"crystal1"+".png"); // TODO: More crystal types.
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
			log.severe("Assets not found.");
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
		light = new DirectionalLight(new Vector3f(1.0f, 1.0f, 1.0f), new Vector3f(0.0f, 1.0f, 0.0f), 0.4f);
		mouse = new MouseInput();
		mouse.init(window);
		log.info("Version " + Constants.GAME_VERSION + " of brand " + Constants.GAME_BRAND);
		log.info("LWJGL Version: " + Version.VERSION_MAJOR + "." + Version.VERSION_MINOR + "." + Version.VERSION_REVISION);
		log.info("Jungle Version: " + Constants.GAME_VERSION + "-cubyz");
		Constants.setGameSide(Side.CLIENT);
		msd = new CubyzMeshSelectionDetector(renderer);
		
		// Cubyz resources
		ResourcePack baserp = new ResourcePack();
		baserp.path = new File("assets");
		baserp.name = "Cubyz";
		ResourceManager.packs.add(baserp);
		
		renderer.setShaderFolder(ResourceManager.lookupPath("cubyz/shaders/default"));
		
		ClientOnly.createBlockMesh = (block) -> {
			Resource rsc = block.getRegistryID();
			try {
				Texture tex = null;
				Mesh mesh = null;
				BlockModel bm = null;
				if (block.generatesModelAtRuntime()) {
					bm = ResourceUtilities.loadModel(new Resource("cubyz:undefined"));
				} else {
					try {
						bm = ResourceUtilities.loadModel(rsc);
					} catch (IOException e) {
						CubyzLogger.i.warning(rsc + " model not found");
						bm = ResourceUtilities.loadModel(new Resource("cubyz:undefined"));
					}
				}
				
				// Cached meshes
				Mesh defaultMesh = null;
				for (String key : cachedDefaultModels.keySet()) {
					if (key.equals(bm.subModels.get("default").model)) {
						defaultMesh = cachedDefaultModels.get(key);
					}
				}
				if (defaultMesh == null) {
					Resource rs = new Resource(bm.subModels.get("default").model);
					defaultMesh = OBJLoader.loadMesh("assets/" + rs.getMod() + "/models/3d/" + rs.getID(), true);
					defaultMesh.setBoundingRadius(2.0f);
					cachedDefaultModels.put(bm.subModels.get("default").model, defaultMesh);
				}
				Resource texResource = new Resource(bm.subModels.get("default").texture);
				String texture = texResource.getID();
				if (!new File("assets/" + texResource.getMod() + "/textures/" + texture + ".png").exists()) {
					CubyzLogger.i.warning(texResource + " texture not found");
					texture = "blocks/undefined";
				}
				if (bm.subModels.get("default").texture_converted == (Boolean) true) {
					tex = new Texture("assets/" + texResource.getMod() + "/textures/" + texture + ".png");
				} else {
					tex = new Texture(TextureConverter.fromBufferedImage(
							TextureConverter.convert(ImageIO.read(new File("assets/" + texResource.getMod() + "/textures/" + texture + ".png")),
									block.getRegistryID().toString())));
				}
				
				mesh = defaultMesh.cloneNoMaterial();
				if (mesh instanceof InstancedMesh) {
					((InstancedMesh) mesh).setInstances(256);
				}
				Material material = new Material(tex, 0.6F);
				mesh.setMaterial(material);
				
				Meshes.blockMeshes.put(block, mesh);
			} catch (Exception e) {
				e.printStackTrace();
			}
		};
		
		ClientOnly.createEntityMesh = (type) -> {
			Resource rsc = type.getRegistryID();
			try {
				Texture tex = null;
				Mesh mesh = null;
				BlockModel bm = null;
				try {
					bm = ResourceUtilities.loadModel(rsc);
				} catch (IOException e) {
					CubyzLogger.i.warning(rsc + " model not found");
					//e.printStackTrace();
					bm = ResourceUtilities.loadModel(new Resource("cubyz:undefined"));
				}
				
				// Cached meshes
				Mesh defaultMesh = null;
				for (String key : cachedDefaultModels.keySet()) {
					if (key.equals(bm.subModels.get("default").model)) {
						defaultMesh = cachedDefaultModels.get(key);
					}
				}
				if (defaultMesh == null) {
					Resource rs = new Resource(bm.subModels.get("default").model);
					//defaultMesh = OBJLoader.loadMesh("assets/" + rs.getMod() + "/models/3d/" + rs.getID(), false);
					defaultMesh = StaticMeshesLoader.load("assets/" + rs.getMod() + "/models/3d/" + rs.getID(),
							"assets/" + rs.getMod() + "/models/3d/")[0];
					defaultMesh.setBoundingRadius(2.0f);
					cachedDefaultModels.put(bm.subModels.get("default").model, defaultMesh);
				}
				Resource texResource = new Resource(bm.subModels.get("default").texture);
				String texture = texResource.getID();
				if (!new File("assets/" + texResource.getMod() + "/textures/" + texture + ".png").exists()) {
					CubyzLogger.i.warning(texResource + " texture not found");
					texture = "blocks/undefined";
				}
				
				if (bm.subModels.get("default").texture_converted == true) {
					tex = new Texture("assets/" + texResource.getMod() + "/textures/" + texture + ".png");
				} else {
					tex = new Texture(TextureConverter.fromBufferedImage(
							TextureConverter.convert(ImageIO.read(new File("assets/" + texResource.getMod() + "/textures/" + texture + ".png")),
									type.getRegistryID().toString())));
				}
				
				mesh = defaultMesh.cloneNoMaterial();
				Material material = new Material(tex, 1.0F);
				mesh.setMaterial(material);
				
				Meshes.entityMeshes.put(type, mesh);
			} catch (Exception e) {
				e.printStackTrace();
			}
		};
		
		ClientOnly.createBlockSpatial = (bi) -> {
			return new BlockSpatial(bi);
		};
		
		ClientOnly.registerGui = (name, gui) -> {
			if (userGUIs.containsKey(name)) {
				throw new IllegalArgumentException("GUI already registered: " + name);
			}
			if (!(gui instanceof MenuGUI)) {
				throw new IllegalArgumentException("GUI Object must be a MenuGUI");
			}
			userGUIs.put(name, (MenuGUI) gui);
		};
		
		ClientOnly.openGui = (name, inv) -> {
			if (!userGUIs.containsKey(name)) {
				throw new IllegalArgumentException("No such GUI registered: " + name);
			}
			gameUI.setMenu(userGUIs.get(name).setInventory(inv));
		};
		
		try {
			renderer.init(window);
		} catch (Exception e) {
			log.log(Level.SEVERE, e, () -> {
				return "An unhandled exception occured while initiazing the renderer:";
			});
			e.printStackTrace();
			System.exit(1);
		}
		log.info("Renderer: OK!");
		
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
					music = new SoundBuffer(ResourceManager.lookupPath("cubyz/sound/KingBoard.ogg"));
				} catch (Exception e) {
					e.printStackTrace();
				}
				musicSource = new SoundSource(true, true);
				musicSource.setBuffer(music.getBufferId());
			} else {
				CubyzLogger.instance.info("Missing optional sound files. Sounds are disabled.");
			}
			
			System.gc();
		});
		lt.start();
	}

	private Vector3f dir = new Vector3f();
	
	@Override
	public void input(Window window) {
		if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_F3)) {
			Cubyz.clientShowDebug = !Cubyz.clientShowDebug;
			Keyboard.setKeyPressed(GLFW.GLFW_KEY_F3, false);
		}
		if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_F11)) {
			window.setFullscreen(!window.isFullscreen());
			Keyboard.setKeyPressed(GLFW.GLFW_KEY_F11, false);
		}
		if (!gameUI.doesGUIPauseGame() && world != null) {
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
				Vector3fi pos = world.getLocalPlayer().getPosition().clone();
				pos.y += 2f;
				EntityType pigType = CubyzRegistries.ENTITY_REGISTRY.getByID("cubyz:pig");
				if (pigType == null) return;
				Entity pig = pigType.newEntity();
				pig.setPosition(pos);
				pig.setWorld(world);
				world.addEntity(pig);
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
			if (Keybindings.isPressed("menu")) {
				if (gameUI.getMenuGUI() != null) {
					gameUI.setMenu(null);
					mouse.setGrabbed(true);
					Keyboard.setKeyPressed(Keybindings.getKeyCode("menu"), false);
				} else {
					Keyboard.setKeyPressed(Keybindings.getKeyCode("menu"), false);
					gameUI.setMenu(new PauseGUI());
				}
			}
			if ((mouse.isLeftButtonPressed() || mouse.isRightButtonPressed()) && !mouse.isGrabbed() && gameUI.getMenuGUI() == null) {
				mouse.setGrabbed(true);
				mouse.clearPos(window.getWidth() / 2, window.getHeight() / 2);
				breakCooldown = 10;
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
				if(world.getRenderDistance() >= 2)
					world.setRenderDistance(world.getRenderDistance()-1);
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_MINUS, false);
				System.gc();
			}
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_EQUAL)) {
				world.setRenderDistance(world.getRenderDistance()+1);
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_EQUAL, false);
				System.gc();
			}
			light.getDirection().x+=0.1f;
			if (light.getDirection().x == 100) light.getDirection().x = 0;
			msd.selectSpatial(world.getVisibleChunks(), world.getLocalPlayer().getPosition(), ctx.getCamera().getViewMatrix().positiveZ(dir).negate());
		}
		mouse.input(window);
	}

	public static final Chunk[] EMPTY_CHUNK_LIST = new Chunk[0];
	public static final Block[] EMPTY_BLOCK_LIST = new Block[0];
	public static final Entity[] EMPTY_ENTITY_LIST = new Entity[0];
	
	private Vector3f ambient = new Vector3f();
	private Vector3f brightAmbient = new Vector3f(1, 1, 1);
	private Vector4f clearColor = new Vector4f(0.1f, 0.7f, 0.7f, 1f);
	
	@SuppressWarnings("deprecation")
	public FrameBuffer blockPreview(Block b) {
		Window window = game.getWindow();
		Chunk ck = new Chunk(0, 0, null, new ArrayList<BlockChange>());
		BlockInstance binst = new BlockInstance(b);
		binst.setPosition(new Vector3i(0, 0, 0));
		ck.createBlocksForOverlay();
		ck.rawAddBlock(0, 0, 0, binst);
		ck.revealBlock(binst);
		Vector3fi pos = world.getLocalPlayer().getPosition();
		Vector3f rot = ctx.getCamera().getRotation();
		world.getLocalPlayer().setPosition(new Vector3fi(1f, 0f, -5f));
		ctx.getCamera().setRotation(0, 225, 0);
		
		FrameBuffer buf = new FrameBuffer();
		buf.genColorTexture(128, 128);
		buf.genRenderbuffer(128, 128);
		window.setRenderTarget(buf);
		window.setClearColor(new Vector4f(0f, 0f, 0f, 0f));
		GL11.glViewport(0, 0, 128, 128);
		
		ctx.setHud(null);
		renderer.orthogonal = true;
		window.setResized(true); // update projection matrix
		renderer.render(window, ctx, new Vector3f(1, 1, 1), light, new Chunk[] {ck}, world.getBlocks(), EMPTY_ENTITY_LIST, world.getLocalPlayer());
		renderer.orthogonal = false;
		window.setResized(true); // update projection matrix for next render
		ctx.setHud(gameUI);
		
		GL11.glViewport(0, 0, window.getWidth(), window.getHeight());
		window.setRenderTarget(null);
		
		world.getLocalPlayer().setPosition(pos);
		ctx.getCamera().setRotation(rot.x, rot.y, rot.z);
		
		return buf;
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
		
		for (IRegistryElement elem : CubyzRegistries.BLOCK_REGISTRY.registered()) {
			Block block = (Block) elem;
			Resource rsc = block.getRegistryID();
			try {
				Texture tex = null;
				Mesh mesh = null;
				BlockModel bm = null;
				try {
					bm = ResourceUtilities.loadModel(rsc);
				} catch (IOException e) {
					CubyzLogger.i.warning(rsc + " model not found");
					//e.printStackTrace();
					bm = ResourceUtilities.loadModel(new Resource("cubyz:undefined"));
				}
				
				// Cached meshes
				Mesh defaultMesh = null;
				for (String key : cachedDefaultModels.keySet()) {
					if (key.equals(bm.subModels.get("default").model)) {
						defaultMesh = cachedDefaultModels.get(key);
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
					defaultMesh = OBJLoader.loadMesh("assets/" + rs.getMod() + "/models/3d/" + rs.getID(), false);
					defaultMesh.setBoundingRadius(2.0f);
					cachedDefaultModels.put(subModel.model, defaultMesh);
				}
				Resource texResource = new Resource(subModel.texture);
				String texture = texResource.getID();
				if (!new File("assets/" + texResource.getMod() + "/textures/" + texture + ".png").exists()) {
					CubyzLogger.i.warning(texResource + " texture not found");
					texture = "blocks/undefined";
				}
				if (bm.subModels.get("default").texture_converted == (Boolean) true) {
					tex = new Texture("assets/" + texResource.getMod() + "/textures/" + texture + ".png");
				} else {
					tex = new Texture(TextureConverter.fromBufferedImage(
							TextureConverter.convert(ImageIO.read(new File("assets/" + texResource.getMod() + "/textures/" + texture + ".png")),
									block.getRegistryID().toString())));
				}
				
				mesh = defaultMesh.cloneNoMaterial();
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
	InstancedMesh[] meshes = new InstancedMesh[0];
	
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
			ctx.getCamera().setPosition(0, playerBobbing, 0);
		}
		
		if (!renderDeque.isEmpty()) {
			renderDeque.pop().run();
		}
		if (world != null) {
			if (worldSeason != world.getSeason()) {
				worldSeason = world.getSeason();
				seasonUpdateDynamodels();
				CubyzLogger.i.info("Updated season to ID " + worldSeason);
			}
			//ambient.x = ambient.y = ambient.z = world.getGlobalLighting();
			light.setIntensity(world.getGlobalLighting());
			clearColor = world.getClearColor();
			ctx.getFog().setColor(clearColor);
			ctx.getFog().setDensity(1 / (world.getRenderDistance()*8f));
			Player player = world.getLocalPlayer();
			Block bi = world.getBlock(player.getPosition().x+Math.round(player.getPosition().relX), (int)(player.getPosition().y)+3, player.getPosition().z+Math.round(player.getPosition().relZ));
			if(bi != null && !bi.isSolid()) {
				Vector3f lightingAdjust = bi.getLightAdjust();
				ambient.x *= lightingAdjust.x;
				ambient.y *= lightingAdjust.y;
				ambient.z *= lightingAdjust.z;
			}
			light.setColor(clearColor);
			window.setClearColor(clearColor);
			
			renderer.render(window, ctx, ambient, light, world.getVisibleChunks(), world.getBlocks(), world.getEntities(), world.getLocalPlayer());
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
			
			renderer.render(window, ctx, brightAmbient, light, EMPTY_CHUNK_LIST, EMPTY_BLOCK_LIST, EMPTY_ENTITY_LIST, null);
			
			if (screenshot) {
				FrameBuffer buf = window.getRenderTarget();
				window.setRenderTarget(null);
				screenshot = false;
			}
		}
		
		Keyboard.releaseCodePoint();
		Keyboard.releaseKeyCode();
		mouse.clearScroll();
	}
	
	@Override
	public void update(float interval) {
		if (!gameUI.doesGUIPauseGame() && world != null) {
			Player lp = world.getLocalPlayer();
			lp.move(playerInc.mul(0.11F), ctx.getCamera().getRotation());
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
						BlockInstance bi = msd.getSelectedBlockInstance();
						if (bi != null && bi.getBlock().getBlockClass() != BlockClass.UNBREAKABLE) {
							world.removeBlock(bi.getX(), bi.getY(), bi.getZ());
							if(world.getLocalPlayer().getInventory().addItem(bi.getBlock().getBlockDrop(), 1) != 0) {
								//DropItemOnTheGround(); //TODO: Add this function.
							}
						}
					}
				}
				else {
					BlockInstance bi = msd.getSelectedBlockInstance();
					world.getLocalPlayer().breaking(bi, inventorySelection, world);
				}
			}
			if (Keybindings.isPressed("place")) {
				//Building Blocks
				if (buildCooldown == 0 && msd.getSelectedBlockInstance() != null) {
					buildCooldown = 10;
					if(msd.getSelectedBlockInstance().getBlock().onClick(world, msd.getSelectedBlockInstance().getPosition())) {
						// potentially do a hand animation, in the future
					} else {
						Vector3i pos = msd.getEmptyPlace(world.getLocalPlayer().getPosition(), ctx.getCamera().getViewMatrix().positiveZ(dir).negate());
						Block b = world.getLocalPlayer().getInventory().getBlock(inventorySelection);
						if (b != null && pos != null) {
							world.placeBlock(pos.x, pos.y, pos.z, b);
							world.getLocalPlayer().getInventory().getStack(inventorySelection).add(-1);
						}
					}
				}
			}
			if (mouse.isGrabbed()) {
				ctx.getCamera().moveRotation(mouse.getDisplVec().x * 0.51F, mouse.getDisplVec().y * 0.51F, 5F);
				mouse.clearPos(win.getWidth() / 2, win.getHeight() / 2);
			}
			playerInc.x = playerInc.y = playerInc.z = 0.0F; // Reset positions
			world.update();
			world.seek(lp.getPosition().x, lp.getPosition().z);
			if (ctx.getCamera().getRotation().x > 90.0F) {
				ctx.getCamera().setRotation(90.0F, ctx.getCamera().getRotation().y, ctx.getCamera().getRotation().z);
			}
			if (ctx.getCamera().getRotation().x < -90.0F) {
				ctx.getCamera().setRotation(-90.0F, ctx.getCamera().getRotation().y, ctx.getCamera().getRotation().z);
			}
		}
	}

	public static int getFPS() {
		return Cubyz.instance.game.getFPS();
	}




	
	/*static { // Algorithm for automatically generating an ore template from the ore image. Uses the reverse-engineered color erase algorithm from gimp. Uncomment to automatically generate it on game startup.
		int averageT = 2000; // average temperature of the star in the image. Needs to be determined seperately.
		for(int deltaT = 0; deltaT <= 10000-averageT; deltaT += 200) {
			BufferedImage stone = (BufferedImage)getImage("assets/cubyz/textures/blocks/stone.png");
			BufferedImage ore = (BufferedImage)getImage("assets/cubyz/textures/blocks/ruby_ore.png");
			for(int i = 0; i < 16; i++) {
				for(int j = 0; j < 16; j++) {
					int colorStone = stone.getRGB(i, j);
					int bS = colorStone & 255;
					int gS = (colorStone >> 8) & 255;
					int rS = (colorStone >> 16) & 255;
					int colorOre = ore.getRGB(i, j);
					int bO = colorOre & 255;
					int gO = (colorOre >> 8) & 255;
					int rO = (colorOre >> 16) & 255;

					// Color erase algorithm:
					// O = a*I+(1-a)*S → a*(I-S) = O-S → a = (O-S)/(I-S)
					int ar, ag, ab;
					if(rO == rS) {
						ar = 0;
					} else if(rO < rS) {
						ar = -255*(rO-rS)/rS;
					} else {
						ar = 255*(rO-rS)/(255-rS);
					}
					if(gO == gS) {
						ag = 0;
					} else if(gO < gS) {
						ag = -255*(gO-gS)/gS;
					} else {
						ag = 255*(gO-gS)/(255-gS);
					}
					if(bO == bS) {
						ab = 0;
					} else if(bO < bS) {
						ab = -255*(bO-bS)/bS;
					} else {
						ab = 255*(bO-bS)/(255-bS);
					}
					// O = a*I+(1-a)*S → a*I = O+(a-1)*S → I = O/a+S-S/a
					int a = Math.max(ar, Math.max(ag,  ab)); // Erase as much color as possible.
					if(a >= 255) a = 255;
					if(a < 0) a = 0;
					System.out.println(a);
					int rI, gI, bI;
					if(a == 0) {
						rI = gI = bI = 0;
					} else {
						rI = 255*rO/a+rS-255*rS/a;
						gI = 255*gO/a+gS-255*gS/a;
						bI = 255*bO/a+bS-255*bS/a;
						if(rI < 0) rI = 0;
						if(rI > 255) rI = 255;
						if(gI < 0) gI = 0;
						if(gI > 255) gI = 255;
						if(bI < 0) bI = 0;
						if(bI > 255) bI = 255;
					}
					
					ore.setRGB(i, j, new Color(rI, gI, bI, a).getRGB());
				}
			}
			
			File outputfile = new File("assets/cubyz/textures/blocks/ruby_ore_template.png");
			try {
				ImageIO.write(ore, "png", outputfile);
			} catch (IOException e) {}
		}
	}//*/
	
	
	/*static { // Algorithm for automatically generating an item templates from the material image. Uses the reverse-engineered color erase algorithm from gimp. Uncomment to automatically generate it on game startup.
		BufferedImage ore = (BufferedImage)getImage("assets/cubyz/textures/items/parts/sword/stone_sword_head.png");
		for(int i = 0; i < 16; i++) {
			for(int j = 0; j < 16; j++) {
				int color = 0x767676;
				int hsv = TextureConverter.getHSV(color);
				int colorOre = ore.getRGB(i, j);
				int hsvOre = TextureConverter.getHSV(colorOre);
				int a = colorOre >>> 24;
				int h1 = (hsv >>> 16) & 255;
				int s1 = (hsv >>> 8) & 255;
				int v1 = (hsv >>> 0) & 255;
				int h2 = (hsvOre >>> 16) & 255;
				int s2 = (hsvOre >>> 8) & 255;
				int v2 = (hsvOre >>> 0) & 255;
				h2 -= h1;
				s2 -= s1;
				v2 -= v1;
				h2 &= 255;
				s2 &= 255;
				v2 &= 255;
				int res = (a << 24) | (h2 << 16) | (s2 << 8) | v2;
				
				ore.setRGB(i, j, res);
			}
		}
		
		File outputfile = new File("assets/cubyz/textures/items/parts/template.png");
		try {
			ImageIO.write(ore, "png", outputfile);
		} catch (IOException e) {}
	}//*/
	public static BufferedImage getImage(String fileName) {
		try {
			return ImageIO.read(new File(fileName));
		} catch(Exception e) {}//e.printStackTrace();}
		return null;
	}
}
