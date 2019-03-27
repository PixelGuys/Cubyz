package io.cubyz.client;

import java.io.File;
import java.util.ArrayList;
import java.util.Random;
import java.util.Set;
import java.util.logging.Level;
import java.util.logging.Logger;

import javax.imageio.ImageIO;

import org.joml.Vector3f;
import org.joml.Vector3i;
import org.joml.Vector4f;
import org.jungle.Camera;
import org.jungle.Jungle;
import org.jungle.Keyboard;
import org.jungle.Mesh;
import org.jungle.MouseInput;
import org.jungle.Texture;
import org.jungle.Window;
import org.jungle.game.Context;
import org.jungle.game.Game;
import org.jungle.game.IGameLogic;
import org.jungle.util.DirectionalLight;
import org.jungle.util.Material;
import org.jungle.util.OBJLoader;
import org.lwjgl.Version;
import org.lwjgl.glfw.GLFW;
import org.reflections.Reflections;

import io.cubyz.ClientOnly;
import io.cubyz.Constants;
import io.cubyz.CubyzLogger;
import io.cubyz.Utilities;
import io.cubyz.api.CubzRegistries;
import io.cubyz.api.IRegistryElement;
import io.cubyz.api.Mod;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.modding.ModLoader;
import io.cubyz.multiplayer.client.CubzClient;
import io.cubyz.ui.DebugGUI;
import io.cubyz.ui.MainMenuGUI;
import io.cubyz.ui.PauseGUI;
import io.cubyz.ui.UISystem;
import io.cubyz.utils.DiscordIntegration;
import io.cubyz.utils.TextureConverter;
import io.cubyz.world.BlockSpatial;
import io.cubyz.world.Chunk;
import io.cubyz.world.World;

/**
 * Main class for Cubyz game
 * @author zenith391
 */
public class Cubyz implements IGameLogic {

	public static Context ctx;
	private Window win;
	private MainRenderer renderer;
	private Game game;
	private DirectionalLight light;
	private Vector3f playerInc;
	public static MouseInput mouse;
	public static UISystem gameUI;
	public static World world;
	
	private int inventorySelection = 1; // Selected slot in inventory

	private CubyzMeshSelectionDetector msd;

	private int breakCooldown = 10;
	private int buildCooldown = 10;

	public static Logger log = CubyzLogger.i;

	public static String serverIP = "localhost";
	public static int serverPort = 58961;
	public static int serverCapacity = 2;
	public static int serverOnline = 1;

	private static CubzClient mpClient;
	public static boolean isIntegratedServer = true;
	public static boolean isOnlineServerOpened = false;

	public static boolean clientShowDebug = true;

	public static Cubyz instance;

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
		log.getHandlers()[0].close();
		DiscordIntegration.closeRPC();
	}

	public static void loadWorld(World world) {
		Cubyz.world = world;
		Random rnd = new Random();
		int dx = rnd.nextInt(1024);
		int dz = rnd.nextInt(1024);
		world.synchronousSeek(dx, dz);
		int highestY = world.getHighestBlock(dx, dz);
		world.getLocalPlayer().setPosition(new Vector3f(dx, highestY+2, dz));
	}

	public static void requestJoin(String host) {
		requestJoin(host, 58961);
	}

	public static void requestJoin(String host, int port) {
		if (mpClient != null) {
			mpClient.connect(host, port);
			serverIP = host;
			serverPort = port;
		} else {
			throw new IllegalStateException("Attempted to join a server while Cubz is not initialized.");
		}
	}

	@Override
	public void init(Window window) throws Exception {
		// Delete cache
		File cache = new File("cache");
		if (cache.exists()) {
			for (File f : cache.listFiles()) {
				f.delete();
			}
		}
		//CubzLogger.useDefaultHandler = true;
		gameUI = new UISystem();
		gameUI.init(window);
		playerInc = new Vector3f();
		renderer = new MainRenderer();
		ctx = new Context(game, new Camera());
		ctx.setHud(gameUI);
		light = new DirectionalLight(new Vector3f(1.0F, 1.0F, 0.7F), new Vector3f(0.0F, 1.0F, 1.0F), 1.0F);
		mouse = new MouseInput();
		mouse.init(window);
		log.info("Version " + Constants.GAME_VERSION + " of brand " + Constants.GAME_BRAND);
		log.info("LWJGL Version: " + Version.VERSION_MAJOR + "." + Version.VERSION_MINOR + "." + Version.VERSION_REVISION);
		log.info("Jungle Version: " + Jungle.getVersion());
		renderer.setShaderFolder("assets/cubyz/shaders/default");
		try {
			renderer.init(window);
		} catch (Exception e) {
			log.log(Level.SEVERE, e, () -> {
				return "An unhandled exception occured while initiazing the renderer:";
			});
			e.printStackTrace();
			System.exit(1);
		}
		msd = new CubyzMeshSelectionDetector(renderer);
		window.setClearColor(new Vector4f(0.1F, 0.7F, 0.7F, 1.0F));
		log.info("Renderer: OK!");
		
		MainMenuGUI mmg = new MainMenuGUI();
		gameUI.setMenu(mmg);
		gameUI.addOverlay(new DebugGUI());

		System.out.println("-=-=- Loading Mods -=-=-");
		long start = System.currentTimeMillis();
		Reflections reflections = new Reflections(""); // load all mods
		Set<Class<?>> allClasses = reflections.getTypesAnnotatedWith(Mod.class);
		long end = System.currentTimeMillis();
		log.info("[ModClassLoader] Took " + (end - start) + "ms for reflection");
		for (Class<?> cl : allClasses) {
			log.info("[ModClassLoader] Mod class present: " + cl.getName());
			Object mod = cl.getConstructor().newInstance();
			ModLoader.init(mod);
		}
		System.out.println("-=-=- Mods Loaded  -=-=-");
		
		ClientOnly.createBlockMesh = (block) -> {
			try {
				if (block.isTextureConverted()) { // block.texConverted
					block.getBlockPair().set("textureCache", new Texture("assets/cubyz/textures/blocks/" + block.getTexture() + ".png"));
				} else {
					block.getBlockPair().set("textureCache", new Texture(TextureConverter.fromBufferedImage(
							TextureConverter.convert(ImageIO.read(new File("assets/cubyz/textures/blocks/" + block.getTexture() + ".png")),
									block.getTexture()))));
				}
				// Assuming mesh too is empty
				block.getBlockPair().set("meshCache", OBJLoader.loadMesh("assets/cubyz/models/cube.obj"));
				((Mesh) block.getBlockPair().get("meshCache")).setBoundingRadius(2.0F);
				Material material = new Material((Texture) block.getBlockPair().get("textureCache"), 1.0F);
				((Mesh) block.getBlockPair().get("meshCache")).setMaterial(material);
			} catch (Exception e) {
				e.printStackTrace();
			}
		};
		
		ClientOnly.createBlockSpatial = (bi) -> {
			return new BlockSpatial(bi);
		};
		
		// client-side init
		for (IRegistryElement ire : CubzRegistries.BLOCK_REGISTRY.registered()) {
			Block b = (Block) ire;
			b.setBlockPair(new ClientBlockPair());
			ClientOnly.createBlockMesh.accept(b);
		}
		
		//CubzServer server = new CubzServer(58961);
		//server.start(true);
		//mpClient = new CubzClient();
		//requestJoin("127.0.0.1");
		//System.gc();
	}

	@Override
	public void input(Window window) {
		if (window.isKeyPressed(GLFW.GLFW_KEY_F3)) {
			Cubyz.clientShowDebug = !Cubyz.clientShowDebug;
			Keyboard.setKeyPressed(GLFW.GLFW_KEY_F3, false);
		}
		if (window.isKeyPressed(GLFW.GLFW_KEY_F11)) {
			window.setFullscreen(!window.isFullscreen());
			Keyboard.setKeyPressed(GLFW.GLFW_KEY_F11, false);
		}
		if (!gameUI.isGUIFullscreen() && world != null) {
			if (window.isKeyPressed(GLFW.GLFW_KEY_W)) {
				playerInc.z = -1;
			}
			if (window.isKeyPressed(GLFW.GLFW_KEY_LEFT_CONTROL)) {
				playerInc.z = -2;
			}
			if (window.isKeyPressed(GLFW.GLFW_KEY_S)) {
				playerInc.z = 1;
			}
			if (window.isKeyPressed(GLFW.GLFW_KEY_A)) {
				playerInc.x = -1;
			}
			if (window.isKeyPressed(GLFW.GLFW_KEY_D)) {
				playerInc.x = 1;
			}
			if (window.isKeyPressed(GLFW.GLFW_KEY_SPACE) && world.getLocalPlayer().vy == 0) {
				world.getLocalPlayer().vy = 0.25F;
			}
			if (window.isKeyPressed(GLFW.GLFW_KEY_LEFT_SHIFT)) {
				if (world.getLocalPlayer().isFlying()) {
					world.getLocalPlayer().vy = -0.25F;
				}
			}
			if (window.isKeyPressed(GLFW.GLFW_KEY_LEFT_SHIFT)) {
				playerInc.y = -1;
			}
			if (window.isKeyPressed(GLFW.GLFW_KEY_RIGHT)) {
				light.getDirection().x += 0.01F;
				if (light.getDirection().x > 1.0F) {
					light.getDirection().x = 0.0F;
				}
			}
			if (window.isKeyPressed(GLFW.GLFW_KEY_ESCAPE) && mouse.isGrabbed()) {
				if (gameUI.getMenuGUI() == null) {
					Keyboard.setKeyPressed(GLFW.GLFW_KEY_ESCAPE, false);
					gameUI.setMenu(new PauseGUI());
				}
			}
			if (mouse.isLeftButtonPressed() && !mouse.isGrabbed()) {
				mouse.setGrabbed(true);
				mouse.clearPos(window.getWidth() / 2, window.getHeight() / 2);
				breakCooldown = 10;
			}
			if (mouse.isRightButtonPressed() && !mouse.isGrabbed()) {
				mouse.setGrabbed(true);
				mouse.clearPos(window.getWidth() / 2, window.getHeight() / 2);
				buildCooldown = 10;
			}
			//inventorySelection = mouse.getMouseWheelPosition() & 7; TODO(@zenith391): Update Jungle Engine to handle mousewheel.
			if (window.isKeyPressed(GLFW.GLFW_KEY_1)) {
				inventorySelection = 0;
			}
			if (window.isKeyPressed(GLFW.GLFW_KEY_2)) {
				inventorySelection = 1;
			}
			if (window.isKeyPressed(GLFW.GLFW_KEY_3)) {
				inventorySelection = 2;
			}
			if (window.isKeyPressed(GLFW.GLFW_KEY_4)) {
				inventorySelection = 3;
			}
			if (window.isKeyPressed(GLFW.GLFW_KEY_5)) {
				inventorySelection = 4;
			}
			if (window.isKeyPressed(GLFW.GLFW_KEY_6)) {
				inventorySelection = 5;
			}
			if (window.isKeyPressed(GLFW.GLFW_KEY_7)) {
				inventorySelection = 6;
			}
			if (window.isKeyPressed(GLFW.GLFW_KEY_8)) {
				inventorySelection = 7;
			}
			msd.selectSpatial(world.getChunks(), ctx.getCamera());
		}
		mouse.input(window);
	}

	public static final ArrayList<Chunk> EMPTY_CHUNK_LIST = new ArrayList<Chunk>();
	public static final Block[] EMPTY_BLOCK_LIST = new Block[0];
	
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
			} else {
				//System.out.println("no bobbing");
				//playerBobbing = 0;
			}
			if (playerInc.y != 0) {
				world.getLocalPlayer().vy = playerInc.y;
			}
			if (playerInc.x != 0) {
				world.getLocalPlayer().vx = playerInc.x;
			}
			ctx.getCamera().setPosition(world.getLocalPlayer().getPosition().x, world.getLocalPlayer().getPosition().y + 1.5f + playerBobbing, world.getLocalPlayer().getPosition().z);
		}
		if (world != null) {
			renderer.render(window, ctx, new Vector3f(0.3F, 0.3F, 0.3F), light, world.getChunks(), world.getBlocks());
		} else {
			renderer.render(window, ctx, new Vector3f(0.3F, 0.3F, 0.3F), light, EMPTY_CHUNK_LIST, EMPTY_BLOCK_LIST);
		}
		gameUI.updateUI();
	}

	@Override
	public void update(float interval) {
		if (!gameUI.isGUIFullscreen() && world != null) {
			Player lp = world.getLocalPlayer();
			lp.move(playerInc.mul(0.11F), ctx.getCamera().getRotation());
			if (breakCooldown > 0) {
				breakCooldown--;
			}
			if (buildCooldown > 0) {
				buildCooldown--;
			}
			if (mouse.isLeftButtonPressed() && mouse.isGrabbed()) {
				//Breaking Blocks
				if (breakCooldown == 0) {
					breakCooldown = 10;
					BlockInstance bi = msd.getSelectedBlockInstance();
					if (bi != null && bi.getBlock().getHardness() != -1f) {
						inventorySelection = bi.getID();// To be able to build that block again
						world.removeBlock(bi.getX(), bi.getY(), bi.getZ());
					}
				}
			}
			if (mouse.isRightButtonPressed() && mouse.isGrabbed()) {
				//Building Blocks
				if (buildCooldown == 0) {
					buildCooldown = 10;
					Vector3i pos = msd.getEmptyPlace(ctx.getCamera().getPosition());
					Block b = world.getBlocks()[inventorySelection];	// TODO: add inventory
					if (b != null && pos != null) {
						world.placeBlock(pos.x, pos.y, pos.z, b);
					}
				}
			}
			if (mouse.isGrabbed()) {
				ctx.getCamera().moveRotation(mouse.getDisplVec().x() * 0.51F, mouse.getDisplVec().y() * 0.51F, 0.0F);
				mouse.clearPos(win.getWidth() / 2, win.getHeight() / 2);
			}
			playerInc.x = playerInc.y = playerInc.z = 0.0F; // Reset positions
			for (Entity en : world.getEntities()) {
				en.update();
			}
			world.seek((int) lp.getPosition().x, (int) lp.getPosition().z);
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