package io.cubyz.client;

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
import io.cubyz.entity.Player;
import io.cubyz.math.CubyzMath;
import io.cubyz.util.FastList;
import io.cubyz.world.BlockSpatial;
import io.cubyz.world.NormalChunk;
import io.cubyz.world.ReducedChunk;
import io.jungle.InstancedMesh;
import io.jungle.Mesh;
import io.jungle.Spatial;
import io.jungle.Window;
import io.jungle.game.Context;
import io.jungle.renderers.Renderer;
import io.jungle.renderers.Transformation;
import io.jungle.util.DirectionalLight;
import io.jungle.util.PointLight;
import io.jungle.util.ShaderProgram;
import io.jungle.util.SpotLight;
import io.jungle.util.Utils;

/**
 * Renderer that is used when easyLighting is enabled.
 */

@SuppressWarnings("unchecked")
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
		blockShader.createUniform("materialHasTexture");
		blockShader.createUniform("hasAtlas");
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

	FastList<Spatial>[] map = (FastList<Spatial>[]) new FastList[0];
	
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
			// TODO: binary search instead of linear search.
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
		ctx.getCamera().setViewMatrix(transformation.getViewMatrix(ctx.getCamera()));
		
		// Create the mesh map. Create only one entry for the truly transparent block.
		int transparentIndex = -1;
		for(int i = blocks.length - 1; i >= 0; transparentIndex = i--) {
			if(!blocks[i].isTrulyTransparent()) break;
		}
		float breakAnim = 0f;
		if (transparentIndex + 1 != map.length) {
			map = (FastList<Spatial>[]) new FastList[transparentIndex + 1];
			int arrayListCapacity = 10;
			for (int i = 0; i < map.length; i++) {
				map[i] = new FastList<Spatial>(arrayListCapacity, Spatial.class);
			}
		}
		// Don't create a new ArrayList every time to reduce re-allocations:
		for (int i = 0; i < map.length; i++) {
			map[i].clear();
		}
		
		
		// Uses FrustumCulling on the chunks.
		prjViewMatrix.set(window.getProjectionMatrix());
		prjViewMatrix.mul(ctx.getCamera().getViewMatrix());
		// TODO: RayAabIntersection
		frustumInt.set(prjViewMatrix);
		Vector3f playerPosition = null;
		if(localPlayer != null) {
			playerPosition = localPlayer.getPosition(); // Use a constant copy of the player position for the whole rendering to prevent graphics bugs on player movement.
		}
		if(playerPosition != null) {
			Vector3f temp = new Vector3f();
			float x0 = playerPosition.x;
			float z0 = playerPosition.z;
			float y0 = playerPosition.y + Player.cameraHeight;
			chunks = sortChunks(chunks, x0/16 - 0.5f, z0/16 - 0.5f);
			for (NormalChunk ch : chunks) {
				int currentSortingIndex = map[transparentIndex].size;
				if (!frustumInt.testAab(ch.getMin(x0, z0, worldSizeX, worldSizeZ), ch.getMax(x0, z0, worldSizeX, worldSizeZ)))
					continue;
				int length = ch.getVisibles().size;
				BlockInstance[] vis = ch.getVisibles().array;
				for (int i = 0; i < length; i++) {
					BlockInstance bi = vis[i];
					if(bi != null) { // Sometimes block changes happen while rendering.
						float x = CubyzMath.match(bi.getX(), x0, worldSizeX);
						float z = CubyzMath.match(bi.getZ(), z0, worldSizeZ);
						if(frustumInt.testSphere(x, bi.getY(), z, 0.866025f)) {
							if(bi.getBlock().isTrulyTransparent()) {
								BlockSpatial[] spatial = (BlockSpatial[]) bi.getSpatials(localPlayer, worldSizeX, worldSizeZ, ch);
								if(spatial != null) {
									for(BlockSpatial tmp : spatial) {
										if (tmp.isSelected()) {
											breakAnim = bi.getBreakingAnim();
										}
										ctx.getCamera().getPosition().sub(tmp.getPosition(), temp);
										tmp.distance = temp.lengthSquared();
										// Insert sort this spatial into the list:
										map[transparentIndex].add(tmp);
									}
								}
							} else {
								x = x - x0;
								float y = bi.getY() - y0;
								z = z - z0;
								// Only draw blocks that have at least one face facing the player.
								boolean[] neighbors = bi.getNeighbors();
								if(bi.getBlock().getBlockClass() == Block.BlockClass.FLUID || // Ignore fluid blocks in the process, so their surface can still be seen from below.
										(x > 0.5001f && !neighbors[0]) ||
										(x < -0.5001f && !neighbors[1]) ||
										(y > 0.5001f && !neighbors[4]) ||
										(y < -0.5001f && !neighbors[5]) ||
										(z > 0.5001f && !neighbors[2]) ||
										(z < -0.5001f && !neighbors[3])) {
									BlockSpatial[] spatial = (BlockSpatial[]) bi.getSpatials(localPlayer, worldSizeX, worldSizeZ, ch);
									if(spatial != null) {
										for(BlockSpatial tmp : spatial) {
											if (tmp.isSelected()) {
												breakAnim = bi.getBreakingAnim();
											}
											map[bi.getID()].add(tmp);
										}
									}
								}
							}
						}
					}
				}
				Block b = blocks[transparentIndex];
				if (b != null && b.isTransparent()) {
					map[b.ID].sort((sa, sb) -> {
						return (int) -Math.signum(sa.distance - sb.distance);
					}, currentSortingIndex, map[transparentIndex].size - 1);
				}
			}
			
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
					Object mesh = chunk.mesh;
					if(mesh == null || !(mesh instanceof ReducedChunkMesh)) {
						chunk.mesh = mesh = new ReducedChunkMesh(chunk);
					}
					((ReducedChunkMesh)mesh).render();
				}
			}
			chunkShader.unbind();
		}
		
		renderScene(ctx, ambientLight, directionalLight, map, blocks, reducedChunks, entities, spatials,
				playerPosition, localPlayer, breakAnim, transparentIndex);
		if (ctx.getHud() != null) {
			ctx.getHud().render(window);
		}
	}
	
	public void renderScene(Context ctx,Vector3f ambientLight, DirectionalLight directionalLight,
			FastList<Spatial>[] map, Block[] blocks, ReducedChunk[] reducedChunks, Entity[] entities, Spatial[] spatials, Vector3f playerPosition, Player p, float breakAnim, int transparentIndex) {
		blockShader.bind();
		
		blockShader.setUniform("fog", ctx.getFog());
		blockShader.setUniform("projectionMatrix", ctx.getWindow().getProjectionMatrix());
		blockShader.setUniform("texture_sampler", 0);
		blockShader.setUniform("break_sampler", 2);
		blockShader.setUniform("viewMatrix", ctx.getCamera().getViewMatrix());

		blockShader.setUniform("ambientLight", ambientLight);
		blockShader.setUniform("directionalLight", directionalLight.getDirection());

		if(breakAnim > 0f && breakAnim < 1f) {
			int breakStep = (int)(breakAnim*Cubyz.breakAnimations.length);
			glActiveTexture(GL_TEXTURE2);
			glBindTexture(GL_TEXTURE_2D, Cubyz.breakAnimations[breakStep].getId());
		} else {
			glActiveTexture(GL_TEXTURE2);
			glBindTexture(GL_TEXTURE_2D, 0);
		}
		// Handle non-transparent blocks:
		for(int i = 0; i < transparentIndex; i++) {
			if (map[i] == null)
				continue;
			InstancedMesh mesh = Meshes.blockMeshes.get(blocks[i]);
			mesh.getMaterial().setTexture(Meshes.blockTextures.get(blocks[i]));
			blockShader.setUniform("materialHasTexture", mesh.getMaterial().isTextured());
			mesh.renderListInstanced(map[i], transformation, false);
		}
		blockShader.unbind();
		
		entityShader.bind();
		entityShader.setUniform("fog", ctx.getFog());
		entityShader.setUniform("projectionMatrix", ctx.getWindow().getProjectionMatrix());
		entityShader.setUniform("texture_sampler", 0);
		for (int i = 0; i < entities.length; i++) {
			Entity ent = entities[i];
			int x = (int)(ent.getPosition().x + 1.0f);
			int y = (int)(ent.getPosition().y + 1.0f);
			int z = (int)(ent.getPosition().z + 1.0f);
			if (ent != null && ent != p) { // don't render local player
				Mesh mesh = null;
				if(ent.getType().model != null) {
					entityShader.setUniform("materialHasTexture", true);
					entityShader.setUniform("light", ent.getSurface().getLight(x, y, z, ambientLight));
					ent.getType().model.render(ctx.getCamera().getViewMatrix(), entityShader, ent);
					continue;
				}
				if (ent instanceof CustomMeshProvider) {
					CustomMeshProvider provider = (CustomMeshProvider) ent;
					MeshType type = provider.getMeshType();
					if (type == MeshType.BLOCK) {
						Block b = (Block) provider.getMeshId();
						mesh = Meshes.blockMeshes.get(b);
						if(mesh != Meshes.transparentBlockMesh) {
							mesh.getMaterial().setTexture(Meshes.blockTextures.get(b));
						}
					} else if (type == MeshType.ENTITY) {
						Entity e = (Entity) provider.getMeshId();
						mesh = Meshes.entityMeshes.get(e.getType());
					}
				} else {
					mesh = Meshes.entityMeshes.get(ent.getType());
				}
				
				if (mesh != null) {
					entityShader.setUniform("materialHasTexture", mesh.getMaterial().isTextured());
					entityShader.setUniform("light", ent.getSurface().getLight(x, y, z, ambientLight));
					
					mesh.renderOne(() -> {
						Vector3f position = ent.getRenderPosition();
						Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(position, ent.getRotation(), ent.getScale()), ctx.getCamera().getViewMatrix());
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
		// Handle transparent blocks after everything else:
		blockShader.bind();
		if(transparentIndex >= 0) {
			InstancedMesh mesh = Meshes.blockMeshes.get(blocks[transparentIndex]);
			blockShader.setUniform("materialHasTexture", true);
			blockShader.setUniform("hasAtlas", true);
			blockShader.setUniform("atlasSize", Meshes.transparentAtlasSize);
			mesh.renderListInstanced(map[transparentIndex], transformation, true);
			blockShader.setUniform("hasAtlas", false);
		}
		blockShader.unbind();
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
	public void render(Window win, Context ctx, Vector3f ambientLight, PointLight[] pointLightList,
			SpotLight[] spotLightList, DirectionalLight directionalLight) {
		throw new UnsupportedOperationException("Cubyz Renderer doesn't support this method.");
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
