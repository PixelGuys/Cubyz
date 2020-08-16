package io.cubyz.client;

import java.util.HashMap;
import java.util.Map;

import io.cubyz.blocks.Block;
import io.cubyz.entity.EntityType;
import io.jungle.Mesh;
import io.jungle.Texture;

public class Meshes {

	public static Map<Block, Mesh> blockMeshes = new HashMap<>();
	public static Map<EntityType, Mesh> entityMeshes = new HashMap<>();
	public static Map<Block, Texture> blockTextures = new HashMap<>();
	
	public static Mesh transparentBlockMesh;
	public static int transparentAtlasSize;
	
}
