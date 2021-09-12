package cubyz.client;

import java.util.ArrayDeque;
import java.util.Deque;

import org.joml.Vector3f;

import cubyz.gui.UISystem;
import cubyz.rendering.Fog;
import cubyz.rendering.RenderOctTree;
import cubyz.world.Surface;
import cubyz.world.World;
import cubyz.world.entity.PlayerEntity.PlayerImpl;

/**
 * A simple data holder for all static data that is needed for basic game functionality.
 */
public class Cubyz {
	// stuff for rendering:
	public static Fog fog = new Fog(true, new Vector3f(0.5f, 0.5f, 0.5f), 0.025f);
	public static UISystem gameUI = new UISystem();
	public static Deque<Runnable> renderDeque = new ArrayDeque<>();
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
