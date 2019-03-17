package io.cubyz.client;

import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;
import java.util.logging.Level;
import java.util.logging.Logger;

import javax.imageio.ImageIO;

import org.joml.Vector3f;
import org.joml.Vector4f;
import org.jungle.Camera;
import org.jungle.Jungle;
import org.jungle.Mesh;
import org.jungle.MouseInput;
import org.jungle.Texture;
import org.jungle.Window;
import org.jungle.game.Context;
import org.jungle.game.Game;
import org.jungle.game.IGameLogic;
import org.jungle.util.DirectionalLight;
import org.jungle.util.Material;
import org.jungle.util.MeshSelectionDetector;
import org.jungle.util.OBJLoader;
import org.lwjgl.Version;
import org.lwjgl.glfw.GLFW;
import org.reflections.Reflections;

import io.cubyz.ClientOnly;
import io.cubyz.Constants;
import io.cubyz.CubzLogger;
import io.cubyz.api.Mod;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.modding.ModLoader;
import io.cubyz.multiplayer.client.CubzClient;
import io.cubyz.multiplayer.server.CubzServer;
import io.cubyz.ui.DebugGUI;
import io.cubyz.ui.MainMenuGUI;
import io.cubyz.ui.UISystem;
import io.cubyz.utils.DiscordIntegration;
import io.cubyz.utils.TextureConverter;
import io.cubyz.world.BlockSpatial;
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
	private static long lastFPSCheck = 0;
	private static int currentFrames = 0;
	private static int currentFPS = 0;
	public static World world;

	private MeshSelectionDetector msd;

	private int breakCooldown = 10;

	public static Logger log = CubzLogger.i;

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
		win.setTitle("Spacy Cubyd!");
	}

	@Override
	public void cleanup() {
		renderer.cleanup();
		DiscordIntegration.closeRPC();
	}

	public static void load(World world) {
		Cubyz.world = world;
		int dx = 256;
		int dz = 256;
		world.entityGenerate(dx, dz);
		int highestY = world.getHighestY(dx, dz);
		world.getLocalPlayer().setPosition(new Vector3f(dx, highestY, dz));
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
		//CubzLogger.useDefaultHandler = true;
		gameUI = new UISystem();
		gameUI.init(window);
		playerInc = new Vector3f();
		renderer = new MainRenderer();
		ctx = new Context(game, new Camera());
		ctx.setHud(gameUI);
		light = new DirectionalLight(new Vector3f(1.0F, 1.0F, 0.7F), new Vector3f(0.0F, 1.0F, 1.0F), 1.0F); //NOTE: Normal > 1.0F || 1.0F || 0.7F || 0.0F || 1.0F || 1.0F || 1.0F
		mouse = new MouseInput();
		mouse.init(window);
		log.info("Version " + Constants.GAME_VERSION + " of brand " + Constants.GAME_BRAND);
		log.info("LWJGL Version: " + Version.VERSION_MAJOR + "." + Version.VERSION_MINOR + "." + Version.VERSION_REVISION);
		log.info("Jungle Version: " + Jungle.getVersion());
		renderer.setShaderFolder("res/shaders/default");
		try {
			renderer.init(window);
		} catch (Exception e) {
			log.log(Level.SEVERE, e, () -> {
				return "An unhandled exception occured while initiazing the renderer:";
			});
			e.printStackTrace();
			System.exit(1);
		}
		msd = new MeshSelectionDetector(renderer);
		window.setClearColor(new Vector4f(0.1F, 0.7F, 0.7F, 1.0F)); //NOTE: Normal > 0.1F || 0.7F || 0.7F || 1.0F
		log.info("Renderer: OK!");
		
		MainMenuGUI mmg = new MainMenuGUI();
		gameUI.setMenu(mmg);
		gameUI.addOverlay(new DebugGUI());

		CubzServer server = new CubzServer(58961);
		server.start(true);
		mpClient = new CubzClient();
		requestJoin("127.0.0.1");
		//DiscordIntegration.startRPC();
		System.gc();

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
					block.getBlockPair().set("textureCache", new Texture("./res/textures/blocks/" + block.getTexture() + ".png"));
				} else {
					block.getBlockPair().set("textureCache", new Texture(TextureConverter.fromBufferedImage(
							TextureConverter.convert(ImageIO.read(new File("./res/textures/blocks/" + block.getTexture() + ".png")),
									block.getTexture()))));
				}
				// Assuming mesh too is empty
				block.getBlockPair().set("meshCache", OBJLoader.loadMesh("res/models/cube.obj"));
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
		for (Block b : ModLoader.block_registry.getRegisteredBlocks()) {
			b.setBlockPair(new ClientBlockPair());
			ClientOnly.createBlockMesh.accept(b);
		}
	}

	@Override
	public void input(Window window) {
		if (window.isKeyPressed(GLFW.GLFW_KEY_F3)) {
			try {
				Thread.sleep(100);
			} catch (InterruptedException e) {
				e.printStackTrace();
			}
			Cubyz.clientShowDebug = !Cubyz.clientShowDebug;
		}
		if (!gameUI.isGUIFullscreen()) {
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
				playerInc.y = -1; //NOTE: Normal > 1
			}
			if (window.isKeyPressed(GLFW.GLFW_KEY_RIGHT)) {
				light.getDirection().x += 0.01F;
				if (light.getDirection().x > 1.0F) {
					light.getDirection().x = 0.0F;
				}
			}
			if (window.isKeyPressed(GLFW.GLFW_KEY_ESCAPE) && mouse.isGrabbed()) {
				mouse.setGrabbed(false);
			}
			if (mouse.isLeftButtonPressed() && !mouse.isGrabbed()) {
				mouse.setGrabbed(true);
				mouse.clearPos(window.getWidth() / 2, window.getHeight() / 2);
				breakCooldown = 10;
			}
			//msd.selectSpatial(ctx.getSpatials(), ctx.getCamera());
		}
		mouse.input(window);
	}

	public static final Map<Block, ArrayList<BlockInstance>> EMPTY_BLOCK_LIST = new HashMap<>();
	
	@Override
	public void render(Window window) {
		if (window.shouldClose()) {
			game.exit();
		}
		
		if (world != null) {
			if (playerInc.y != 0) {
				world.getLocalPlayer().vy = playerInc.y;
			}
			if (playerInc.x != 0) {
				world.getLocalPlayer().vx = playerInc.x;
			}
			ctx.getCamera().setPosition(world.getLocalPlayer().getPosition().x, world.getLocalPlayer().getPosition().y + 1.76f, world.getLocalPlayer().getPosition().z);
			if (world.isEdited()) {
				//				ctx.setSpatials(world.__visibleSpatials().toArray(new Spatial[world.__visibleSpatials().size()]));
				//				//System.out.println("Cubes: " + world.__visibleSpatials().size());
				world.receivedEdited();
				//				for (Entity en : world.getEntities()) {
				//					ctx.addSpatial(en.getSpatial());
				//				}
			}
		}
		if (world != null) {
			renderer.render(window, ctx, new Vector3f(0.3F, 0.3F, 0.3F), light, world.visibleBlocks());
		} else {
			renderer.render(window, ctx, new Vector3f(0.3F, 0.3F, 0.3F), light, EMPTY_BLOCK_LIST);
		}
		countFPS();
		gameUI.updateUI();
	}

	@Override
	public void update(float interval) {
		if (!gameUI.isGUIFullscreen()) {
			Player lp = world.getLocalPlayer();
			lp.move(playerInc.mul(0.11F), ctx.getCamera().getRotation()); //NOTE: Normal > 0.11F
			if (breakCooldown > 0) { //NOTE: Normal > 0
				breakCooldown--;
			}
			if (mouse.isLeftButtonPressed() && mouse.isGrabbed()) {
				//Breaking Blocks
				if (breakCooldown == 0) {
					breakCooldown = 10;
					if (msd.getSelectedSpatial() instanceof BlockSpatial) {
						BlockInstance bi = ((BlockSpatial) msd.getSelectedSpatial()).getBlock();
						world.removeBlock(bi.getX(), bi.getY(), bi.getZ());
					}
				}
			}
			if (mouse.isGrabbed()) {
				ctx.getCamera().moveRotation(mouse.getDisplVec().x() * 0.51F, mouse.getDisplVec().y() * 0.51F, 0.0F);
				mouse.clearPos(win.getWidth() / 2, win.getHeight() / 2);
			}
			playerInc.x = playerInc.y = playerInc.z = 0.0F; // Reset positions || NOTE: Normal > 0.0F
			for (Entity en : world.getEntities()) {
				en.update();
			}
			//System.out.println(lp.getPosition());
			//ctx.getCamera().setPosition(lp.getPosition().x, lp.getPosition().y, lp.getPosition().z);
			world.entityGenerate((int) lp.getPosition().x, (int) lp.getPosition().z);
			if (ctx.getCamera().getRotation().x > 90.0F) { //NOTE: Normal > 90.0F
				ctx.getCamera().setRotation(90.0F, ctx.getCamera().getRotation().y, ctx.getCamera().getRotation().z); //NOTE: Normal > 90.0F
			}
			if (ctx.getCamera().getRotation().x < -90.0F) { //NOTE: Normal > 90.0F
				ctx.getCamera().setRotation(-90.0F, ctx.getCamera().getRotation().y, ctx.getCamera().getRotation().z); //NOTE: Normal > 90.0F
			}
		}
	}

	private void countFPS() {
		currentFrames++;
		if (System.nanoTime() > lastFPSCheck + 1000000000) { //NOTE: Normal > 1B ( 1000000000 )
			lastFPSCheck = System.nanoTime();
			currentFPS = currentFrames;
			currentFrames = 0; //NOTE: Normal > 0
		}
	}

	public static int getFPS() {
		return currentFPS;
	}

}