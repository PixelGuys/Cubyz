package io.jungle.renderers;

import org.joml.Vector3f;

import io.cubyz.blocks.Block;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.world.NormalChunk;
import io.cubyz.world.ReducedChunk;
import io.jungle.Spatial;
import io.jungle.Window;
import io.jungle.game.Context;
import io.jungle.util.DirectionalLight;

public interface Renderer {

	public abstract void init(Window win) throws Exception;
	public abstract void render(Window window, Context ctx, Vector3f ambientLight, DirectionalLight directionalLight,
			NormalChunk[] chunks, ReducedChunk[] reducedChunks, Block[] blocks, Entity[] entities, Spatial[] spatials, Player localPlayer, int worldSizeX, int worldSizeZ);
	public abstract void cleanup();
	public abstract void setPath(String dataName, String path);
	public abstract Transformation getTransformation();
	
}
