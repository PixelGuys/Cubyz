package io.cubyz.client;

import java.util.ArrayDeque;
import java.util.Deque;

import org.joml.Vector3f;

import io.cubyz.entity.PlayerEntity.PlayerImpl;
import io.cubyz.rendering.Camera;
import io.cubyz.rendering.Fog;
import io.cubyz.rendering.Hud;
import io.cubyz.rendering.Window;
import io.cubyz.ui.UISystem;
import io.cubyz.world.RenderOctTree;
import io.cubyz.world.Surface;
import io.cubyz.world.World;

/**
 * A simple data holder for all static data that is needed for basic game functionality.
 */
public class Cubyz {
	// stuff for rendering:
	public static Camera camera = new Camera();
	public static Fog fog = new Fog(true, new Vector3f(0.5f, 0.5f, 0.5f), 0.025f);
	public static UISystem gameUI = new UISystem();
	public static Hud hud = new Hud();
	public static Deque<Runnable> renderDeque = new ArrayDeque<>();
	public static Window window = new Window();
	public static RenderOctTree chunkTree = new RenderOctTree();
	
	// World related stuff:
	public static Surface surface;
	public static World world;
	public static PlayerImpl player;
	
	// Other:
	public static Vector3f playerInc = new Vector3f();
	/**Selected slot in hotbar*/
	public static int inventorySelection = 0;
	public static Vector3f dir = new Vector3f();
	public static MeshSelectionDetector msd = new MeshSelectionDetector();
}
