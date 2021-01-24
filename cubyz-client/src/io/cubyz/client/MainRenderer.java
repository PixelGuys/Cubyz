package io.cubyz.client;

import static org.lwjgl.opengl.GL11.GL_TEXTURE_2D;
import static org.lwjgl.opengl.GL11.glBindTexture;
import static org.lwjgl.opengl.GL13.GL_TEXTURE0;
import static org.lwjgl.opengl.GL13.glActiveTexture;
import static org.lwjgl.opengl.GL13C.*;

import org.joml.FrustumIntersection;
import org.joml.Matrix4f;
import org.joml.Vector3f;

import io.cubyz.ClientSettings;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.entity.CustomMeshProvider;
import io.cubyz.entity.CustomMeshProvider.MeshType;
import io.cubyz.entity.Entity;
import io.cubyz.entity.ItemEntityManager;
import io.cubyz.entity.Player;
import io.cubyz.items.ItemBlock;
import io.cubyz.util.FastList;
import io.cubyz.world.ChunkEntityManager;
import io.cubyz.world.NormalChunk;
import io.cubyz.world.ReducedChunk;
import io.jungle.Mesh;
import io.jungle.Spatial;
import io.jungle.Window;
import io.jungle.game.Context;
import io.jungle.renderers.Renderer;
import io.jungle.renderers.Transformation;
import io.jungle.util.DirectionalLight;
import io.jungle.util.ShaderProgram;
import io.jungle.util.Utils;

/**
 * Renderer that should be used when easyLighting is enabled.
 * Currently it is used always, simply because it's the only renderer available for now.
 */

public class MainRenderer implements Renderer {

	/**A simple shader for low resolution chunks*/
	private ShaderProgram chunkShader;
	private ShaderProgram blockShader;
	private ShaderProgram entityShader; // Entities are sometimes small and sometimes big. Therefor it would mean a lot of work to still use smooth lighting. Therefor the non-smooth shader is used for those.

	private static final float Z_NEAR = 0.01f;
	private static final float Z_FAR = 10000.0f;
	private boolean inited = false;
	private boolean doRender = true;
	private Transformation transformation;
	private String shaders = "";
	private Matrix4f prjViewMatrix = new Matrix4f();
	private FrustumIntersection frustumInt = new FrustumIntersection();

	public MainRenderer() {

	}

	public Transformation getTransformation() {
		return transformation;
	}

	public void setShaderFolder(String shaders) {
		this.shaders = shaders;
	}

	public void unloadShaders() throws Exception {
		blockShader.unbind();
		blockShader.cleanup();
		blockShader = null;
		entityShader.unbind();
		entityShader.cleanup();
		entityShader = null;
		System.gc();
	}

	public void setDoRender(boolean doRender) {
		this.doRender = doRender;
	}

	public void loadShaders() throws Exception {
		chunkShader = new ShaderProgram();
		chunkShader.createVertexShader(Utils.loadResource(shaders + "/chunk_vertex.vs"));
		chunkShader.createFragmentShader(Utils.loadResource(shaders + "/chunk_fragment.fs"));
		chunkShader.link();
		chunkShader.createUniform("projectionMatrix");
		chunkShader.createUniform("viewMatrix");
		chunkShader.createUniform("modelPosition");
		chunkShader.createUniform("ambientLight");
		chunkShader.createUniform("directionalLight");
		chunkShader.createFogUniform("fog");
		
		blockShader = new ShaderProgram();
		blockShader.createVertexShader(Utils.loadResource(shaders + "/block_vertex.vs"));
		blockShader.createFragmentShader(Utils.loadResource(shaders + "/block_fragment.fs"));
		blockShader.link();
		blockShader.createUniform("projectionMatrix");
		blockShader.createUniform("viewMatrix");
		blockShader.createUniform("texture_sampler");
		blockShader.createUniform("break_sampler");
		blockShader.createUniform("ambientLight");
		blockShader.createUniform("directionalLight");
		blockShader.createUniform("modelPosition");
		blockShader.createUniform("selectedIndex");
		blockShader.createUniform("atlasSize");
		blockShader.createFogUniform("fog");
		
		entityShader = new ShaderProgram();
		entityShader.createVertexShader(Utils.loadResource(shaders + "/entity_vertex.vs"));
		entityShader.createFragmentShader(Utils.loadResource(shaders + "/entity_fragment.fs"));
		entityShader.link();
		entityShader.createUniform("projectionMatrix");
		entityShader.createUniform("viewMatrix");
		entityShader.createUniform("texture_sampler");
		entityShader.createUniform("materialHasTexture");
		entityShader.createFogUniform("fog");
		entityShader.createUniform("light");
		
		System.gc();
	}

	@Override
	public void init(Window window) throws Exception {
		transformation = new Transformation();
		window.setProjectionMatrix(transformation.getProjectionMatrix((float) Math.toRadians(70.0f), window.getWidth(),
				window.getHeight(), Z_NEAR, Z_FAR));
		loadShaders();

		inited = true;
	}

	public void clear() {
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
	}
	
	/**
	 * Sorts the chunks based on their distance from the player to reduce complexity when sorting the transparent blocks.
	 * @param toSort
	 * @param playerX
	 * @param playerZ
	 * @return sorted chunk array
	 */
	public NormalChunk[] sortChunks(NormalChunk[] toSort, float playerX, float playerZ) {
		NormalChunk[] output = new NormalChunk[toSort.length];
		float[] distances = new float[toSort.length];
		System.arraycopy(toSort, 0, output, 0, toSort.length);
		for(int i = 0; i < output.length; i++) {
			distances[i] = (playerX - output[i].getX())*(playerX - output[i].getX()) + (playerZ - output[i].getZ())*(playerZ - output[i].getZ());
		}
		// Insert sort them:
		for(int i = 1; i < output.length; i++) {
			for(int j = i-1; j >= 0; j--) {
				if(distances[j] < distances[j+1]) {
					// Swap them:
					distances[j] += distances[j+1];
					distances[j+1] = distances[j] - distances[j+1];
					distances[j] -= distances[j+1];
					NormalChunk local = output[j+1];
					output[j+1] = output[j];
					output[j] = local;
				} else {
					break;
				}
			}
		}
		return output;
	}
	
	/**
	 * Renders a Cubyz world.
	 * @param window the window to render in
	 * @param ctx the Context object (will soon be replaced)
	 * @param ambientLight the ambient light to use
	 * @param directionalLight the directional light to use
	 * @param chunks the chunks being displayed
	 * @param reducedChunks the low-resolution far distance chunks to be displayed.
	 * @param blocks the type of blocks used (or available) in the displayed chunks
	 * @param entities the entities to render
	 * @param spatials the special objects to render (that are neither entity, neither blocks, like sun and moon, or rain)
	 * @param localPlayer The world's local player
	 */
	@Override
	public void render(Window window, Context ctx, Vector3f ambientLight, DirectionalLight directionalLight,
			NormalChunk[] chunks, ReducedChunk[] reducedChunks, Block[] blocks, Entity[] entities, Spatial[] spatials, Player localPlayer, int worldSizeX, int worldSizeZ) {
		if (window.isResized()) {
			glViewport(0, 0, window.getWidth(), window.getHeight());
			window.setResized(false);
			window.setProjectionMatrix(transformation.getProjectionMatrix((float)Math.toRadians(ClientSettings.FOV), window.getWidth(),
					window.getHeight(), Z_NEAR, Z_FAR));
		}
		if (!doRender)
			return;
		clear();
		// Clean up old chunk meshes:
		Meshes.cleanUp();
		
		ctx.getCamera().setViewMatrix(transformation.getViewMatrix(ctx.getCamera()));
		
		float breakAnim = 0;
		
		
		// Uses FrustumCulling on the chunks.
		prjViewMatrix.set(window.getProjectionMatrix());
		prjViewMatrix.mul(ctx.getCamera().getViewMatrix());

		frustumInt.set(prjViewMatrix);
		Vector3f playerPosition = null;
		if(localPlayer != null) {
			playerPosition = localPlayer.getPosition(); // Use a constant copy of the player position for the whole rendering to prevent graphics bugs on player movement.
		}
		if(playerPosition != null) {
			
			blockShader.bind();
			
			blockShader.setUniform("fog", ctx.getFog());
			blockShader.setUniform("projectionMatrix", ctx.getWindow().getProjectionMatrix());
			blockShader.setUniform("texture_sampler", 0);
			blockShader.setUniform("break_sampler", 2);
			blockShader.setUniform("viewMatrix", ctx.getCamera().getViewMatrix());

			blockShader.setUniform("ambientLight", ambientLight);
			blockShader.setUniform("directionalLight", directionalLight.getDirection());
			
			blockShader.setUniform("atlasSize", Meshes.atlasSize);
			
			// Activate first texture bank
			glActiveTexture(GL_TEXTURE0);
			// Bind the texture
			glBindTexture(GL_TEXTURE_2D, Meshes.atlas.getId());
			BlockInstance selected = null;
			if(Cubyz.instance.msd.getSelected() instanceof BlockInstance) {
				selected = (BlockInstance)Cubyz.instance.msd.getSelected();
				breakAnim = selected.getBreakingAnim();
			}
			
			if(breakAnim > 0f && breakAnim < 1f) {
				int breakStep = (int)(breakAnim*(Cubyz.breakAnimations.length - 1)) + 1;
				glActiveTexture(GL_TEXTURE2);
				glBindTexture(GL_TEXTURE_2D, Cubyz.breakAnimations[breakStep].getId());
			} else {
				glActiveTexture(GL_TEXTURE2);
				glBindTexture(GL_TEXTURE_2D, Cubyz.breakAnimations[0].getId());
			}
			
			float x0 = playerPosition.x;
			float z0 = playerPosition.z;
			FastList<NormalChunk> visibleChunks = new FastList<NormalChunk>(chunks.length, NormalChunk.class);
			for (NormalChunk ch : chunks) {
				if (!ch.isLoaded() || !frustumInt.testAab(ch.getMin(x0, z0, worldSizeX, worldSizeZ), ch.getMax(x0, z0, worldSizeX, worldSizeZ)))
					continue;
				visibleChunks.add(ch);
				blockShader.setUniform("modelPosition", ch.getMin(x0, z0, worldSizeX, worldSizeZ));
				
				if(selected != null && selected.source == ch) {
					blockShader.setUniform("selectedIndex", selected.renderIndex);
				} else {
					blockShader.setUniform("selectedIndex", -1);
				}
				
				Object mesh = ch.getChunkMesh();
				if(ch.wasUpdated() || mesh == null || !(mesh instanceof NormalChunkMesh)) {
					mesh = new NormalChunkMesh(ch);
					ch.setChunkMesh(mesh);
				}
				((NormalChunkMesh)mesh).render();		
			}
			blockShader.unbind();
			
			// Render the far away ReducedChunks:
			chunkShader.bind();
			
			chunkShader.setUniform("fog", ctx.getFog());
			chunkShader.setUniform("projectionMatrix", ctx.getWindow().getProjectionMatrix());
			
			chunkShader.setUniform("viewMatrix", ctx.getCamera().getViewMatrix());

			chunkShader.setUniform("ambientLight", ambientLight);
			chunkShader.setUniform("directionalLight", directionalLight.getDirection());
			
			for(ReducedChunk chunk : reducedChunks) {
				if(chunk != null && chunk.generated) {
					if (!frustumInt.testAab(chunk.getMin(x0, z0, worldSizeX, worldSizeZ), chunk.getMax(x0, z0, worldSizeX, worldSizeZ)))
						continue;
					Object mesh = chunk.getChunkMesh();
					chunkShader.setUniform("modelPosition", chunk.getMin(x0, z0, worldSizeX, worldSizeZ));
					if(mesh == null || !(mesh instanceof ReducedChunkMesh)) {
						chunk.setChunkMesh(mesh = new ReducedChunkMesh(chunk));
					}
					((ReducedChunkMesh)mesh).render();
				}
			}
			
			chunkShader.unbind();
			
			// Render entities:
			
			entityShader.bind();
			entityShader.setUniform("fog", ctx.getFog());
			entityShader.setUniform("projectionMatrix", ctx.getWindow().getProjectionMatrix());
			entityShader.setUniform("texture_sampler", 0);
			for (int i = 0; i < entities.length; i++) {
				Entity ent = entities[i];
				int x = (int)(ent.getPosition().x + 1.0f);
				int y = (int)(ent.getPosition().y + 1.0f);
				int z = (int)(ent.getPosition().z + 1.0f);
				if (ent != null && ent != localPlayer) { // don't render local player
					Mesh mesh = null;
					if(ent.getType().model != null) {
						entityShader.setUniform("materialHasTexture", true);
						entityShader.setUniform("light", ent.getSurface().getLight(x, y, z, ambientLight, ClientSettings.easyLighting));
						ent.getType().model.render(ctx.getCamera().getViewMatrix(), entityShader, ent);
						continue;
					}
					if (ent instanceof CustomMeshProvider) {
						CustomMeshProvider provider = (CustomMeshProvider) ent;
						MeshType type = provider.getMeshType();
						if (type == MeshType.ENTITY) {
							Entity e = (Entity) provider.getMeshId();
							mesh = Meshes.entityMeshes.get(e.getType());
						}
					} else {
						mesh = Meshes.entityMeshes.get(ent.getType());
					}
					
					if (mesh != null) {
						entityShader.setUniform("materialHasTexture", mesh.getMaterial().isTextured());
						entityShader.setUniform("light", ent.getSurface().getLight(x, y, z, ambientLight, ClientSettings.easyLighting));
						
						mesh.renderOne(() -> {
							Vector3f position = ent.getRenderPosition();
							Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(position, ent.getRotation(), ent.getScale()), ctx.getCamera().getViewMatrix());
							entityShader.setUniform("viewMatrix", modelViewMatrix);
						});
					}
				}
			}
			
			// Render item entities:
			for(ChunkEntityManager chManager : localPlayer.getSurface().getEntityManagers()) {
				NormalChunk chunk = chManager.chunk;
				if (!chunk.isLoaded() || !frustumInt.testAab(chunk.getMin(x0, z0, worldSizeX, worldSizeZ), chunk.getMax(x0, z0, worldSizeX, worldSizeZ)))
					continue;
				ItemEntityManager manager = chManager.itemEntityManager;
				for(int i = 0; i < manager.size; i++) {
					int index = i;
					int index3 = 3*i;
					int x = (int)(manager.posxyz[index3] + 1.0f);
					int y = (int)(manager.posxyz[index3+1] + 1.0f);
					int z = (int)(manager.posxyz[index3+2] + 1.0f);
					Mesh mesh = null;
					if(manager.itemStacks[i].getItem() instanceof ItemBlock) {
						Block b = ((ItemBlock)manager.itemStacks[i].getItem()).getBlock();
						mesh = Meshes.blockMeshes.get(b);
						mesh.getMaterial().setTexture(Meshes.blockTextures.get(b));
					}
					if(mesh != null) {
						entityShader.setUniform("materialHasTexture", mesh.getMaterial().isTextured());
						entityShader.setUniform("light", localPlayer.getSurface().getLight(x, y, z, ambientLight, ClientSettings.easyLighting));
						
						mesh.renderOne(() -> {
							Vector3f position = manager.getPosition(index);
							Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(position, manager.getRotation(index), ItemEntityManager.diameter), ctx.getCamera().getViewMatrix());
							entityShader.setUniform("viewMatrix", modelViewMatrix);
						});
					}
				}
			}
			
			
			entityShader.setUniform("fog.activ", 0); // manually disable the fog
			for (int i = 0; i < spatials.length; i++) {
				Spatial spatial = spatials[i];
				Mesh mesh = spatial.getMesh();
				entityShader.setUniform("light", new Vector3f(1, 1, 1));
				entityShader.setUniform("materialHasTexture", mesh.getMaterial().isTextured());
				mesh.renderOne(() -> {
					Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(
							Transformation.getModelMatrix(spatial.getPosition(), spatial.getRotation(), spatial.getScale()),
							ctx.getCamera().getViewMatrix());
					entityShader.setUniform("viewMatrix", modelViewMatrix);
				});
			}
			
			entityShader.unbind();
			
			// Render transparent chunk meshes:
			blockShader.bind();
			
			blockShader.setUniform("fog", ctx.getFog());
			blockShader.setUniform("projectionMatrix", ctx.getWindow().getProjectionMatrix());
			blockShader.setUniform("texture_sampler", 0);
			blockShader.setUniform("break_sampler", 2);
			blockShader.setUniform("viewMatrix", ctx.getCamera().getViewMatrix());

			blockShader.setUniform("ambientLight", ambientLight);
			blockShader.setUniform("directionalLight", directionalLight.getDirection());
			
			blockShader.setUniform("atlasSize", Meshes.atlasSize);
			
			// Activate first texture bank
			glActiveTexture(GL_TEXTURE0);
			// Bind the texture
			glBindTexture(GL_TEXTURE_2D, Meshes.atlas.getId());
			if(Cubyz.instance.msd.getSelected() instanceof BlockInstance) {
				selected = (BlockInstance)Cubyz.instance.msd.getSelected();
				breakAnim = selected.getBreakingAnim();
			}
			
			if(breakAnim > 0f && breakAnim < 1f) {
				int breakStep = (int)(breakAnim*(Cubyz.breakAnimations.length - 1)) + 1;
				glActiveTexture(GL_TEXTURE2);
				glBindTexture(GL_TEXTURE_2D, Cubyz.breakAnimations[breakStep].getId());
			} else {
				glActiveTexture(GL_TEXTURE2);
				glBindTexture(GL_TEXTURE_2D, Cubyz.breakAnimations[0].getId());
			}

			chunks = sortChunks(visibleChunks.toArray(), x0/16 - 0.5f, z0/16 - 0.5f);
			for (NormalChunk ch : chunks) {				
				blockShader.setUniform("modelPosition", ch.getMin(x0, z0, worldSizeX, worldSizeZ));
				
				if(selected != null && selected.source == ch) {
					blockShader.setUniform("selectedIndex", selected.renderIndex);
				} else {
					blockShader.setUniform("selectedIndex", -1);
				}
				
				Object mesh = ch.getChunkMesh();
				if(ch.wasUpdated() || mesh == null || !(mesh instanceof NormalChunkMesh)) {
					mesh = new NormalChunkMesh(ch);
					ch.setChunkMesh(mesh);
				}
				((NormalChunkMesh)mesh).renderTransparent();		
			}
			blockShader.unbind();
		}
		if (ctx.getHud() != null) {
			ctx.getHud().render(window);
		}
	}

	@Override
	public void cleanup() {
		if (blockShader != null) {
			blockShader.cleanup();
			blockShader = null;
		}
		if (entityShader != null) {
			entityShader.cleanup();
			entityShader = null;
		}
	}

	@Override
	public void setPath(String dataName, String path) {
		if (dataName.equals("shaders") || dataName.equals("shadersFolder")) {
			if (inited) {
				try {
					doRender = false;
					unloadShaders();
					shaders = path;
					loadShaders();
					doRender = true;
				} catch (Exception e) {
					e.printStackTrace();
				}
			} else {
				shaders = path;
			}
		}
	}

}
