package io.cubyz.client;

import java.io.File;
import java.util.ArrayDeque;
import java.util.Deque;
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
import io.cubyz.api.Resource;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.client.loading.LoadThread;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.items.Inventory;
import io.cubyz.modding.ModLoader;
import io.cubyz.multiplayer.client.CubzClient;
import io.cubyz.multiplayer.client.PingResponse;
import io.cubyz.multiplayer.server.CubzServer;
import io.cubyz.ui.DebugOverlay;
import io.cubyz.ui.LoadingGUI;
import io.cubyz.ui.MainMenuGUI;
import io.cubyz.ui.PauseGUI;
import io.cubyz.ui.ToastManager;
import io.cubyz.ui.ToastManager.Toast;
import io.cubyz.ui.UISystem;
import io.cubyz.utils.DiscordIntegration;
import io.cubyz.utils.ResourceManager;
import io.cubyz.utils.ResourcePack;
import io.cubyz.utils.ResourceUtilities;
import io.cubyz.utils.ResourceUtilities.BlockModel;
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
	
	public static int inventorySelection = 0; // Selected slot in inventory
	public static Inventory inventory;

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
	
	public static Deque<Runnable> renderDeque = new ArrayDeque<>();

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
		int dx = rnd.nextInt(10);
		int dz = rnd.nextInt(10);
		//dx = dz = Integer.MIN_VALUE+20000;
		world.synchronousSeek(dx, dz);
		int highestY = world.getHighestBlock(dx, dz);
		world.getLocalPlayer().setPosition(new Vector3i(dx, highestY+2, dz));
		inventory = new Inventory();
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
		// Delete cache
		File cache = new File("cache");
		if (cache.exists()) {
			for (File f : cache.listFiles()) {
				f.delete();
			}
		}
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
		
		// Cubyz resources
		ResourcePack baserp = new ResourcePack();
		baserp.path = new File("assets/cubyz");
		baserp.name = "Cubyz";
		//ResourceManager.packs.add(baserp);
		
		MainMenuGUI mmg = new MainMenuGUI();
		gameUI.setMenu(mmg);
		gameUI.addOverlay(new DebugOverlay());
		
		ClientOnly.createBlockMesh = (block) -> {
			Resource rsc = block.getRegistryID();
			try {
				BlockModel bm = null;
				//bm = ResourceUtilities.loadModel(rsc);
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
		
		gameUI.setMenu(LoadingGUI.getInstance());
		LoadThread lt = new LoadThread();
		lt.start();
		
		CubzServer server = new CubzServer(serverPort);
		//server.start(true);
		mpClient = new CubzClient();
		
		//pingServer("127.0.0.1");
		
		System.gc();
		
		System.out.println("Resource 2.0 System Test:");
		ResourceUtilities.BlockModel model = ResourceUtilities.loadModel(new Resource("cubyz:grass"));
		System.out.println("Grass block texture : " + model.texture);
		System.out.println("Grass block model   : "   + model.model);
		
		ToastManager.queuedToasts.add(new Toast("Woohoo", "Welcome to 0.3.1, with brand new toasts!"));
		System.out.println("Pushed toast");
	}

	private Vector3f dir = new Vector3f();
	
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
			msd.selectSpatial(world.getVisibleChunks(), world.getLocalPlayer().getPosition(), ctx.getCamera().getViewMatrix().positiveZ(dir).negate());
		}
		mouse.input(window);
	}

	public static final Chunk[] EMPTY_CHUNK_LIST = new Chunk[0];
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
			ctx.getCamera().setPosition(/*world.getLocalPlayer().getPosition().x*/0, world.getLocalPlayer().getPosition().y + 1.5f + playerBobbing, /*world.getLocalPlayer().getPosition().z*/0);
		}
		
		if (!renderDeque.isEmpty()) {
			Runnable run = renderDeque.pop();
			run.run();
		}
		
		if (world != null) {
			renderer.render(window, ctx, new Vector3f(0.3F, 0.3F, 0.3F), light, world.getVisibleChunks(), world.getBlocks(), world.getLocalPlayer());
		} else {
			renderer.render(window, ctx, new Vector3f(0.3F, 0.3F, 0.3F), light, EMPTY_CHUNK_LIST, EMPTY_BLOCK_LIST, null);
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
						world.removeBlock(bi.getX(), bi.getY(), bi.getZ());
						inventory.addItem(bi.getBlock().getBlockDrop(), 1);
					}
				}
			}
			if (mouse.isRightButtonPressed() && mouse.isGrabbed()) {
				//Building Blocks
				if (buildCooldown == 0) {
					buildCooldown = 10;
					Vector3i pos = msd.getEmptyPlace(ctx.getCamera().getPosition());
					Block b = inventory.getBlock(inventorySelection);
					if (b != null && pos != null) {
						world.placeBlock(pos.x, pos.y, pos.z, b);
						inventory.addItem(b.getBlockDrop(), -1);
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