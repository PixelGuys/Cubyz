package io.cubyz.client;

import java.io.File;
import java.io.IOException;
import java.util.*;
import java.util.logging.*;

import javax.imageio.ImageIO;
import javax.swing.JOptionPane;

import org.joml.Vector3f;
import org.joml.Vector3i;
import org.joml.Vector4f;
import org.jungle.*;
import org.jungle.audio.SoundBuffer;
import org.jungle.audio.SoundManager;
import org.jungle.audio.SoundSource;
import org.jungle.game.*;
import org.jungle.util.*;
import org.lwjgl.Version;
import org.lwjgl.glfw.GLFW;

import io.cubyz.*;
import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.IRegistryElement;
import io.cubyz.api.Resource;
import io.cubyz.api.Side;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.Ore;
import io.cubyz.client.loading.LoadThread;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.multiplayer.GameProfile;
import io.cubyz.multiplayer.LoginToken;
import io.cubyz.multiplayer.client.MPClient;
import io.cubyz.multiplayer.client.PingResponse;
import io.cubyz.translate.Language;
import io.cubyz.translate.LanguageLoader;
import io.cubyz.ui.*;
import io.cubyz.ui.mods.InventoryGUI;
import io.cubyz.utils.*;
import io.cubyz.utils.ResourceUtilities.BlockModel;
import io.cubyz.world.*;
import io.cubyz.world.generator.LifelandGenerator;

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
		DiscordIntegration.closeRPC();
	}
	
	public static void quitWorld() {
		for (MenuGUI overlay : gameUI.getOverlays().toArray(new MenuGUI[0])) {
			if (overlay instanceof GameOverlay) {
				gameUI.removeOverlay(overlay);
			}
		}
		Cubyz.world.cleanup();
		Cubyz.world = null;
		System.gc();
	}

	public static void loadWorld(World world) {
		if (Cubyz.world != null) {
			quitWorld();
		}
		Cubyz.instance.musicSource.play();
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
				//dx = dz = Integer.MIN_VALUE+2048;
				CubyzLogger.i.info("Trying " + dx + " ? " + dz);
				world.synchronousSeek(dx, dz);
				highestY = world.getHighestBlock(dx, dz);
				if (highestY > LifelandGenerator.SEA_LEVEL) { // TODO: always true if generator isn't lifeland
					break;
				}
			}
			CubyzLogger.i.info("OK!");
			if (world.getLocalPlayer().getPosition().x == 0 && world.getLocalPlayer().getPosition().z == 0) { // temporary solution to only TP on spawn
				world.getLocalPlayer().setPosition(new Vector3i(dx, highestY+2, dz));
			}
		}
		world.synchronousSeek(0, 0);
		DiscordIntegration.setStatus("Playing");
		Cubyz.gameUI.addOverlay(new GameOverlay());
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
		
		lang = LanguageLoader.load("en_US");
		
		ClientOnly.createBlockMesh = (block) -> {
			Resource rsc = block.getRegistryID();
			try {
				IRenderablePair pair = block.getBlockPair();
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
					if (key.equals(bm.model)) {
						defaultMesh = cachedDefaultModels.get(key);
					}
				}
				if (defaultMesh == null) {
					Resource rs = new Resource(bm.model);
					defaultMesh = OBJLoader.loadMesh("assets/" + rs.getMod() + "/models/3d/" + rs.getID(), false);
					defaultMesh.setBoundingRadius(2.0f);
					cachedDefaultModels.put(bm.model, defaultMesh);
				}
				Resource texResource = new Resource(bm.texture);
				String texture = texResource.getID();
				if (!new File("assets/" + texResource.getMod() + "/textures/" + texture + ".png").exists()) {
					CubyzLogger.i.warning(texResource + " texture not found");
					texture = "blocks/undefined";
				}
				
				if (bm.texture_converted == (Boolean) true) {
					tex = new Texture("assets/" + texResource.getMod() + "/textures/" + texture + ".png");
				} else {
					tex = new Texture(TextureConverter.fromBufferedImage(
							TextureConverter.convert(ImageIO.read(new File("assets/" + texResource.getMod() + "/textures/" + texture + ".png")),
									block.getRegistryID().toString())));
				}
				
				mesh = defaultMesh.cloneNoMaterial();
				Material material = new Material(tex, 0.6F);
				mesh.setMaterial(material);
				
				pair.set("textureCache", tex);
				pair.set("meshCache", mesh);
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
					if (key.equals(bm.model)) {
						defaultMesh = cachedDefaultModels.get(key);
					}
				}
				if (defaultMesh == null) {
					Resource rs = new Resource(bm.model);
					//defaultMesh = OBJLoader.loadMesh("assets/" + rs.getMod() + "/models/3d/" + rs.getID(), false);
					defaultMesh = StaticMeshesLoader.load("assets/" + rs.getMod() + "/models/3d/" + rs.getID(),
							"assets/" + rs.getMod() + "/models/3d/")[0];
					defaultMesh.setBoundingRadius(2.0f);
					cachedDefaultModels.put(bm.model, defaultMesh);
				}
				Resource texResource = new Resource(bm.texture);
				String texture = texResource.getID();
				if (!new File("assets/" + texResource.getMod() + "/textures/" + texture + ".png").exists()) {
					CubyzLogger.i.warning(texResource + " texture not found");
					texture = "blocks/undefined";
				}
				
				if (bm.texture_converted == (Boolean) true) {
					tex = new Texture("assets/" + texResource.getMod() + "/textures/" + texture + ".png");
				} else {
					tex = new Texture(TextureConverter.fromBufferedImage(
							TextureConverter.convert(ImageIO.read(new File("assets/" + texResource.getMod() + "/textures/" + texture + ".png")),
									type.getRegistryID().toString())));
				}
				
				mesh = defaultMesh.cloneNoMaterial();
				Material material = new Material(tex, 1.0F);
				mesh.setMaterial(material);
				
				//pair.set("textureCache", tex);
				//pair.set("meshCache", mesh);
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
		lt.start();
		
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
			int ID = 0;
			ArrayList<Ore> ores = new ArrayList<Ore>();
			for (IRegistryElement ire : CubyzRegistries.BLOCK_REGISTRY.registered()) {
				Block b = (Block) ire;
				if(!b.isTransparent()) {
					b.ID = ID;
					ID++;
				}
			}
			for (IRegistryElement ire : CubyzRegistries.BLOCK_REGISTRY.registered()) {
				Block b = (Block) ire;
				if(b.isTransparent()) {
					b.ID = ID;
					ID++;
				}
				try {
					ores.add((Ore)b);
				}
				catch(Exception e) {}
			}
			LifelandGenerator.init(ores.toArray(new Ore[ores.size()]));
			
			sound = new SoundManager();
			try {
				sound.init();
			} catch (Exception e) {
				e.printStackTrace();
			}
			
			try {
				music = new SoundBuffer("assets/cubyz/sound/KingBoard.ogg");
			} catch (Exception e) {
				e.printStackTrace();
			}
			
			musicSource = new SoundSource(true, true);
			musicSource.setBuffer(music.getBufferId());
			
			System.gc();
		});
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
			if (Keybindings.isPressed("jump") && world.getLocalPlayer().vy == 0) {
				world.getLocalPlayer().vy = 0.25F;
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
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_RIGHT)) {
				light.getDirection().x += 0.01F;
				if (light.getDirection().x > 1.0F) {
					light.getDirection().x = 0.0F;
				}
			}
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_C)) {
				int mods = Keyboard.getKeyMods();
				if ((mods & GLFW.GLFW_MOD_CONTROL) == GLFW.GLFW_MOD_CONTROL) {
					if ((mods & GLFW.GLFW_MOD_SHIFT) == GLFW.GLFW_MOD_SHIFT) {
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
	
	float playerBobbing;
	boolean bobbingUp;
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
			ctx.getCamera().setPosition(0, world.getLocalPlayer().getPosition().y + 1.5f + playerBobbing, 0);
		}
		
		if (!renderDeque.isEmpty()) {
			Runnable run = renderDeque.pop();
			run.run();
		}
		
		if (world != null) {
			ambient.x = ambient.y = ambient.z = world.getGlobalLighting();
			clearColor = world.getClearColor();
			Player player = world.getLocalPlayer();
			BlockInstance bi = world.getBlock(player.getPosition().x+Math.round(player.getPosition().relX), (int)(player.getPosition().y)+3, player.getPosition().z+Math.round(player.getPosition().relZ));
			if(bi != null && !bi.getBlock().isSolid()) {
				Vector3f lightingAdjust = bi.getBlock().getLightAdjust();
				ambient.x *= lightingAdjust.x;
				ambient.y *= lightingAdjust.y;
				ambient.z *= lightingAdjust.z;
			}
			light.setColor(new Vector3f(clearColor.x, clearColor.y, clearColor.z)); // maybe not make instances every render
			window.setClearColor(clearColor);
			renderer.render(window, ctx, ambient, light, world.getVisibleChunks(), world.getBlocks(), world.getEntities(), world.getLocalPlayer());
		} else {
			clearColor.y = clearColor.z = 0.7f;
			clearColor.x = 0.1f;
			
			window.setClearColor(clearColor);
			renderer.render(window, ctx, brightAmbient, light, EMPTY_CHUNK_LIST, EMPTY_BLOCK_LIST, EMPTY_ENTITY_LIST, null);
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
				if (breakCooldown == 0) {
					breakCooldown = 7;
					BlockInstance bi = msd.getSelectedBlockInstance();
					if (bi != null && bi.getBlock().getHardness() != -1f) {
						world.removeBlock(bi.getX(), bi.getY(), bi.getZ());
						if(world.getLocalPlayer().getInventory().addItem(bi.getBlock().getBlockDrop(), 1) != 0) {
							//DropItemOnTheGround(); //TODO: Add this function.
						}
					}
				}
			}
			if (Keybindings.isPressed("place")) {
				//Building Blocks
				if (buildCooldown == 0 && msd.getSelectedBlockInstance() != null) {
					buildCooldown = 10;
					if(msd.getSelectedBlockInstance().getBlock().onClick(world, msd.getSelectedBlockInstance().getPosition(), msd.getSelectedBlockInstance())) {
						// potentially do a hand animation, in the future
					} else {
						Vector3i pos = msd.getEmptyPlace(world.getLocalPlayer().getPosition(), ctx.getCamera().getViewMatrix().positiveZ(dir).negate());
						Block b = world.getLocalPlayer().getInventory().getBlock(inventorySelection);
						if (b != null && pos != null) {
							if (world.getBlock(pos) != null) {
								pos.y++; // happens sometimes, for now the bug fix works perfectly
							}
							world.placeBlock(pos.x, pos.y, pos.z, b);
							world.getLocalPlayer().getInventory().getStack(inventorySelection).add(-1);
						}
					}
				}
			}
			if (mouse.isGrabbed()) {
				ctx.getCamera().moveRotation(mouse.getDisplVec().x() * 0.51F, mouse.getDisplVec().y() * 0.51F, 0.0F);
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

}