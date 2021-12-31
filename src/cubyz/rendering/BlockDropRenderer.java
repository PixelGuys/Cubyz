package cubyz.rendering;

import java.awt.image.BufferedImage;
import java.io.IOException;
import java.util.ArrayList;

import org.joml.FrustumIntersection;
import org.joml.Matrix4f;
import org.joml.Vector3d;
import org.joml.Vector3f;

import cubyz.client.BlockMeshes;
import cubyz.client.ClientSettings;
import cubyz.client.Cubyz;
import cubyz.client.Meshes;
import cubyz.utils.Utils;
import cubyz.utils.datastructures.Cache;
import cubyz.utils.datastructures.IntFastList;
import cubyz.world.Neighbors;
import cubyz.world.NormalChunk;
import cubyz.world.blocks.Blocks;
import cubyz.world.blocks.TextureProvider;
import cubyz.world.entity.ChunkEntityManager;
import cubyz.world.entity.ItemEntityManager;
import cubyz.world.items.Item;
import cubyz.world.items.ItemBlock;
import cubyz.world.items.tools.Tool;

import static org.lwjgl.opengl.GL43.*;

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
	
	public static class ItemDropUniforms {
		public static int loc_modelMatrix;
		public static int loc_projectionMatrix;
		public static int loc_viewMatrix;
		public static int loc_modelPosition;
		public static int loc_ambientLight;
		public static int loc_directionalLight;
		public static int loc_fog_activ;
		public static int loc_fog_color;
		public static int loc_fog_density;
		public static int loc_modelIndex;
		public static int loc_sizeScale;
	};

	private static ShaderProgram shader;
	private static ShaderProgram itemShader;
	private static SSBO itemModelSSBO;
	private static int itemVAO = -1;

	public static void init(String shaders) throws IOException {
		if (shader != null) {
			shader.cleanup();
		}
		shader = new ShaderProgram(Utils.loadResource(shaders + "/block_drop.vs"),
				Utils.loadResource(shaders + "/block_drop.fs"),
				BlockDropRenderer.class);
		if (itemShader != null) {
			itemShader.cleanup();
		}
		itemShader = new ShaderProgram(Utils.loadResource(shaders + "/item_drop.vs"),
				Utils.loadResource(shaders + "/item_drop.fs"),
				ItemDropUniforms.class);
		if(itemModelSSBO == null) {
			itemModelSSBO = new SSBO(2);
			itemModelSSBO.bufferData(new int[] {1, 1, 1});
		}
		if(itemVAO == -1) {
			int[] position = new int[] {
				0b000,
				0b001,
				0b010,
				0b011,
				0b100,
				0b101,
				0b110,
				0b111,
			};
			int[] indices = new int[] {
				0, 1, 3,
				0, 3, 2,
				0, 5, 1,
				0, 4, 5,
				0, 2, 6,
				0, 6, 4,
				
				4, 7, 5,
				4, 6, 7,
				2, 3, 7,
				2, 7, 6,
				1, 7, 3,
				1, 5, 7,
			};
			
			itemVAO = glGenVertexArrays();
			glBindVertexArray(itemVAO);
			glEnableVertexAttribArray(0);
			
			int vbo = glGenBuffers();
			glBindBuffer(GL_ARRAY_BUFFER, vbo);
			glBufferData(GL_ARRAY_BUFFER, position, GL_STATIC_DRAW);
			glVertexAttribPointer(0, 1, GL_FLOAT, false, 1*4, 0);
			
			vbo = glGenBuffers();
			glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, vbo);
			glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices, GL_STATIC_DRAW);
			
			glBindVertexArray(0);
		}
	}
	
	private static final IntFastList modelData = new IntFastList();
	private static final ArrayList<ItemVoxelModel> freeIndices = new ArrayList<>();
	
	private static class ItemVoxelModel {
		int index = -1;
		int sizeX, sizeY, sizeZ;
		final Item item;
		ItemVoxelModel(Item item) {
			this.item = item;
		}
		void init() {
			if(index != -1) return;
			// Find sizes and free index:
			BufferedImage img;
			if (item instanceof Tool) {
				img = ((Tool)item).texture;
			} else {
				img = TextureProvider.getImage(item.getTexture());
			}
			if(img == null) {
				return;
			}
			sizeX = img.getWidth();
			sizeY = 1;
			sizeZ = img.getHeight();
			ItemVoxelModel freeIndex = null;
			// Find free index:
			for(ItemVoxelModel model : freeIndices) {
				if(model.sizeX == sizeX && model.sizeY == sizeY && model.sizeZ == sizeZ) {
					freeIndex = model;
					break;
				}
			}
			if(freeIndex != null) {
				freeIndices.remove(freeIndex);
				index = freeIndex.index;
				int index = this.index;
				modelData.set(index++, sizeX);
				modelData.set(index++, sizeY);
				modelData.set(index++, sizeZ);
				for(int y = 0; y < sizeY; y++) {
					for(int x = 0; x < sizeX; x++) {
						for(int z = 0; z < sizeZ; z++) {
							modelData.set(index++, img.getRGB(x, z));
						}
					}
				}
			} else {
				index = modelData.size;
				modelData.add(sizeX);
				modelData.add(sizeY);
				modelData.add(sizeZ);
				for(int y = 0; y < sizeY; y++) {
					for(int x = 0; x < sizeX; x++) {
						for(int z = 0; z < sizeZ; z++) {
							int argb = img.getRGB(x, z);
							if(img.getColorModel().hasAlpha()) {
								if((argb & 0xff000000) == 0)
									argb = 0;
							} else {
								argb |= 0xff000000;
							}
							modelData.add(argb);
						}
					}
				}
			}
			modelData.trimToSize();
			itemModelSSBO.bufferData(modelData.array);
		}
		
		@Override
		public int hashCode() {
			return item.hashCode();
		}
		
		@Override
		public boolean equals(Object other) {
			return other instanceof ItemVoxelModel && ((ItemVoxelModel)other).item == item;
		}
	}
	
	private static Cache<ItemVoxelModel> voxelModels = new Cache<ItemVoxelModel>(new ItemVoxelModel[32][32]);
	
	private static int getModelIndex(Item item) {
		ItemVoxelModel compareObject = new ItemVoxelModel(item);
		int hash = compareObject.hashCode() & voxelModels.cache.length-1;
		synchronized(voxelModels.cache[hash]) {
			// Check if it's already inside:
			ItemVoxelModel result = voxelModels.find(compareObject, hash);
			if(result != null) return result.index;
			compareObject.init();
			ItemVoxelModel replace = voxelModels.addToCache(compareObject, hash);
			if(replace != null && replace.index != -1)
				freeIndices.add(replace);
			return compareObject.index;
		}
	}
	
	private static void renderItemDrops(FrustumIntersection frustumInt, Vector3f ambientLight, DirectionalLight directionalLight, Vector3d playerPosition) {
		itemShader.bind();
		itemShader.setUniform(ItemDropUniforms.loc_fog_activ, Cubyz.fog.isActive());
		itemShader.setUniform(ItemDropUniforms.loc_fog_color, Cubyz.fog.getColor());
		itemShader.setUniform(ItemDropUniforms.loc_fog_density, Cubyz.fog.getDensity());
		itemShader.setUniform(ItemDropUniforms.loc_projectionMatrix, Window.getProjectionMatrix());
		itemShader.setUniform(ItemDropUniforms.loc_ambientLight, ambientLight);
		itemShader.setUniform(ItemDropUniforms.loc_directionalLight, directionalLight.getDirection());
		itemShader.setUniform(ItemDropUniforms.loc_viewMatrix, Camera.getViewMatrix());
		itemShader.setUniform(ItemDropUniforms.loc_sizeScale, ItemEntityManager.diameter/4);
		for(ChunkEntityManager chManager : Cubyz.world.getEntityManagers()) {
			NormalChunk chunk = chManager.chunk;
			Vector3d min = chunk.getMin().sub(playerPosition);
			Vector3d max = chunk.getMax().sub(playerPosition);
			if (!chunk.isLoaded() || !frustumInt.testAab((float)min.x, (float)min.y, (float)min.z, (float)max.x, (float)max.y, (float)max.z))
				continue;
			ItemEntityManager manager = chManager.itemEntityManager;
			for(int i = 0; i < manager.size; i++) {
				Item item = manager.itemStacks[i].getItem();
				if (!(item instanceof ItemBlock)) {
					int index3 = 3*i;
					int x = (int)(manager.posxyz[index3] + 1.0f);
					int y = (int)(manager.posxyz[index3+1] + 1.0f);
					int z = (int)(manager.posxyz[index3+2] + 1.0f);
					
					int light = Cubyz.world.getLight(x, y, z, ambientLight, ClientSettings.easyLighting);
					itemShader.setUniform(ItemDropUniforms.loc_ambientLight, new Vector3f(light >>> 16 & 255, light >>> 8 & 255, light & 255).max(new Vector3f(ambientLight).mul(light >>> 24)).div(255.0f));
					Vector3d position = manager.getPosition(i).sub(playerPosition);
					Matrix4f modelMatrix = Transformation.getModelMatrix(new Vector3f((float)position.x, (float)position.y, (float)position.z), manager.getRotation(i), 1);
					itemShader.setUniform(ItemDropUniforms.loc_modelMatrix, modelMatrix);
					int index = getModelIndex(item);
					if(index == -1) continue; // model was not found.
					itemShader.setUniform(ItemDropUniforms.loc_modelIndex, index);
					
					glBindVertexArray(itemVAO);
					glDrawElements(GL_TRIANGLES, 36, GL_UNSIGNED_INT, 0);
				}
			}
		}
	}
	
	private static void renderBlockDrops(FrustumIntersection frustumInt, Vector3f ambientLight, DirectionalLight directionalLight, Vector3d playerPosition) {
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
				if (manager.itemStacks[i].getItem() instanceof ItemBlock) {
					int index = i;
					int index3 = 3*i;
					int x = (int)(manager.posxyz[index3] + 1.0f);
					int y = (int)(manager.posxyz[index3+1] + 1.0f);
					int z = (int)(manager.posxyz[index3+2] + 1.0f);
					int block = ((ItemBlock)manager.itemStacks[i].getItem()).getBlock();
					Mesh mesh = BlockMeshes.mesh(block & Blocks.TYPE_MASK);
					mesh.getMaterial().setTexture(null);
					shader.setUniform(loc_texNegX, BlockMeshes.textureIndices(block)[Neighbors.DIR_NEG_X]);
					shader.setUniform(loc_texPosX, BlockMeshes.textureIndices(block)[Neighbors.DIR_POS_X]);
					shader.setUniform(loc_texNegY, BlockMeshes.textureIndices(block)[Neighbors.DIR_DOWN]);
					shader.setUniform(loc_texPosY, BlockMeshes.textureIndices(block)[Neighbors.DIR_UP]);
					shader.setUniform(loc_texNegZ, BlockMeshes.textureIndices(block)[Neighbors.DIR_NEG_Z]);
					shader.setUniform(loc_texPosZ, BlockMeshes.textureIndices(block)[Neighbors.DIR_POS_Z]);
					if (mesh != null) {
						shader.setUniform(loc_light, Cubyz.world.getLight(x, y, z, ambientLight, ClientSettings.easyLighting));
						Vector3d position = manager.getPosition(index).sub(playerPosition);
						Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(new Vector3f((float)position.x, (float)position.y, (float)position.z), manager.getRotation(index), ItemEntityManager.diameter), Camera.getViewMatrix());
						shader.setUniform(loc_viewMatrix, modelViewMatrix);
						glBindVertexArray(mesh.vaoId);
						mesh.render();
					}
				}
			}
		}
	}
	
	public static void render(FrustumIntersection frustumInt, Vector3f ambientLight, DirectionalLight directionalLight, Vector3d playerPosition) {
		renderBlockDrops(frustumInt, ambientLight, directionalLight, playerPosition);
		renderItemDrops(frustumInt, ambientLight, directionalLight, playerPosition);
	}
}
