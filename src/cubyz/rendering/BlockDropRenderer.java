package cubyz.rendering;

import java.io.IOException;

import org.joml.FrustumIntersection;
import org.joml.Matrix4f;
import org.joml.Vector3d;
import org.joml.Vector3f;

import cubyz.client.ClientSettings;
import cubyz.client.Cubyz;
import cubyz.client.Meshes;
import cubyz.utils.Utils;
import cubyz.world.Neighbors;
import cubyz.world.NormalChunk;
import cubyz.world.blocks.Blocks;
import cubyz.world.entity.ChunkEntityManager;
import cubyz.world.entity.ItemEntityManager;
import cubyz.world.items.ItemBlock;

public class BlockDropRenderer {
	// uniform locations:
	public static int loc_projectionMatrix;
	public static int loc_viewMatrix;
	public static int loc_texture_sampler;
	public static int loc_fog_activ;
	public static int loc_fog_color;
	public static int loc_fog_density;
	public static int loc_ambientLight;
	public static int loc_directionalLight;
	public static int loc_light;
	public static int loc_texPosX;
	public static int loc_texNegX;
	public static int loc_texPosY;
	public static int loc_texNegY;
	public static int loc_texPosZ;
	public static int loc_texNegZ;

	private static ShaderProgram shader;

	public static void init(String shaders) throws IOException {
		if(shader != null)
		shader.cleanup();
		shader = new ShaderProgram(Utils.loadResource(shaders + "/block_drop.vs"),
				Utils.loadResource(shaders + "/block_drop.fs"),
				BlockDropRenderer.class);
	}
	
	public static void render(FrustumIntersection frustumInt, Vector3f ambientLight, DirectionalLight directionalLight, Vector3d playerPosition) {
		Meshes.blockTextureArray.bind();
		shader.bind();
		shader.setUniform(loc_fog_activ, Cubyz.fog.isActive());
		shader.setUniform(loc_fog_color, Cubyz.fog.getColor());
		shader.setUniform(loc_fog_density, Cubyz.fog.getDensity());
		shader.setUniform(loc_projectionMatrix, Window.getProjectionMatrix());
		shader.setUniform(loc_texture_sampler, 0);
		shader.setUniform(loc_ambientLight, ambientLight);
		shader.setUniform(loc_directionalLight, directionalLight.getDirection());
		for(ChunkEntityManager chManager : Cubyz.world.getEntityManagers()) {
			NormalChunk chunk = chManager.chunk;
			Vector3d min = chunk.getMin().sub(playerPosition);
			Vector3d max = chunk.getMax().sub(playerPosition);
			if (!chunk.isLoaded() || !frustumInt.testAab((float)min.x, (float)min.y, (float)min.z, (float)max.x, (float)max.y, (float)max.z))
				continue;
			ItemEntityManager manager = chManager.itemEntityManager;
			for(int i = 0; i < manager.size; i++) {
				int index = i;
				int index3 = 3*i;
				int x = (int)(manager.posxyz[index3] + 1.0f);
				int y = (int)(manager.posxyz[index3+1] + 1.0f);
				int z = (int)(manager.posxyz[index3+2] + 1.0f);
				Mesh mesh = null;
				int block;
				if(manager.itemStacks[i].getItem() instanceof ItemBlock) {
					block = ((ItemBlock)manager.itemStacks[i].getItem()).getBlock();
					mesh = Meshes.blockMeshes.get(block & Blocks.TYPE_MASK);
					mesh.getMaterial().setTexture(null);
				} else {
					block = Blocks.getByID("cubyz:diamond_ore");
					mesh = Meshes.blockMeshes.get(block & Blocks.TYPE_MASK);
					mesh.getMaterial().setTexture(null);
				}
				shader.setUniform(loc_texNegX, Blocks.textureIndices(block)[Neighbors.DIR_NEG_X]);
				shader.setUniform(loc_texPosX, Blocks.textureIndices(block)[Neighbors.DIR_POS_X]);
				shader.setUniform(loc_texNegY, Blocks.textureIndices(block)[Neighbors.DIR_DOWN]);
				shader.setUniform(loc_texPosY, Blocks.textureIndices(block)[Neighbors.DIR_UP]);
				shader.setUniform(loc_texNegZ, Blocks.textureIndices(block)[Neighbors.DIR_NEG_Z]);
				shader.setUniform(loc_texPosZ, Blocks.textureIndices(block)[Neighbors.DIR_POS_Z]);
				if(mesh != null) {
					shader.setUniform(loc_light, Cubyz.world.getLight(x, y, z, ambientLight, ClientSettings.easyLighting));
					
					mesh.renderOne(() -> {
						Vector3d position = manager.getPosition(index).sub(playerPosition);
						Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(new Vector3f((float)position.x, (float)position.y, (float)position.z), manager.getRotation(index), ItemEntityManager.diameter), Camera.getViewMatrix());
						shader.setUniform(loc_viewMatrix, modelViewMatrix);
					});
				}
			}
		}
	}
}
