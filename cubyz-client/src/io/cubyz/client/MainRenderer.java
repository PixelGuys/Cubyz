package io.cubyz.client;

import static org.lwjgl.opengl.GL13C.*;

import org.joml.FrustumIntersection;
import org.joml.Matrix4f;
import org.joml.Vector3f;

import io.cubyz.ClientSettings;
import io.cubyz.Settings;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.entity.CustomMeshProvider;
import io.cubyz.entity.CustomMeshProvider.MeshType;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.math.CubyzMath;
import io.cubyz.util.FastList;
import io.cubyz.world.BlockSpatial;
import io.cubyz.world.Chunk;
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

// Renderer that is used when easyLighting is enabled.

@SuppressWarnings("unchecked")
public class MainRenderer implements Renderer {

	private ShaderProgram blockShader;
	private ShaderProgram entityShader; // Entities are sometimes small and sometimes big. Therefor it would mean a lot of work to still use smooth lighting. Therefor the non-smooth shader is used for those.

	private static final float Z_NEAR = 0.01f;
	private static final float Z_FAR = 1000.0f;
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
		blockShader = new ShaderProgram();
		blockShader.createVertexShader(Utils.loadResource(shaders + "/block_vertex.vs"));
		blockShader.createFragmentShader(Utils.loadResource(shaders + "/block_fragment.fs"));
		blockShader.link();
		blockShader.createUniform("projectionMatrix");
		blockShader.createUniform("viewMatrix");
		blockShader.createUniform("texture_sampler");
		blockShader.createUniform("break_sampler");
		blockShader.createUniform("ambientLight");
		blockShader.createUniform("materialHasTexture");
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
	 * Renders a Cubyz world.
	 * @param window the window to render in
	 * @param ctx the Context object (will soon be replaced)
	 * @param ambientLight the ambient light to use
	 * @param directionalLight the directional light to use
	 * @param chunks the chunks being displayed
	 * @param blocks the type of blocks used (or available) in the displayed chunks
	 * @param entities the entities to render
	 * @param spatials the special objects to render (that are neither entity, neither blocks, like sun and moon, or rain)
	 * @param localPlayer The world's local player
	 */
	public void render(Window window, Context ctx, Vector3f ambientLight, DirectionalLight directionalLight,
			Chunk[] chunks, Block[] blocks, Entity[] entities, Spatial[] spatials, Player localPlayer, int worldSize) {
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
		
		float breakAnim = 0f;
		if (blocks.length != map.length) {
			map = (FastList<Spatial>[]) new FastList[blocks.length];
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
			float x0 = playerPosition.x;
			float z0 = playerPosition.z;
			float y0 = playerPosition.y + Player.cameraHeight;
			for (Chunk ch : chunks) {
				if (!frustumInt.testAab(ch.getMin(x0, z0, worldSize), ch.getMax(x0, z0, worldSize)))
					continue;
				int length = ch.getVisibles().size;
				BlockInstance[] vis = ch.getVisibles().array;
				for (int i = 0; i < length; i++) {
					BlockInstance bi = vis[i];
					if(bi != null) { // Sometimes block changes happen while rendering.
						float x = CubyzMath.match(bi.getX(), x0, worldSize);
						float z = CubyzMath.match(bi.getZ(), z0, worldSize);
						if(frustumInt.testSphere(x, bi.getY(), z, 0.866025f)) {
							x = x - x0;
							float y = bi.getY() - y0;
							z = z - z0;
							// Only draw blocks that have at least one face facing the player.
							if(bi.getBlock().getBlockClass() == Block.BlockClass.FLUID || // Ignore fluid blocks in the process, so their surface can still be seen from below.
									(x > 0.5001f && !bi.neighborEast) ||
									(x < -0.5001f && !bi.neighborWest) ||
									(y > 0.5001f && !bi.neighborDown) ||
									(y < -0.5001f && !bi.neighborUp) ||
									(z > 0.5001f && !bi.neighborSouth) ||
									(z < -0.5001f && !bi.neighborNorth)) {
								BlockSpatial[] spatial = (BlockSpatial[]) bi.getSpatials();
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
		}
		
		// sort distances for correct render of transparent blocks
		Vector3f tmpa = new Vector3f();
		Vector3f tmpb = new Vector3f();
		for (int i = 0; i < blocks.length; i++) {
			Block b = blocks[i];
			if (b != null && b.isTransparent()) {
				map[b.ID].sort((sa, sb) -> {
					ctx.getCamera().getPosition().sub(sa.getPosition(), tmpa);
					ctx.getCamera().getPosition().sub(sb.getPosition(), tmpb);
					return (int) Math.signum(tmpa.lengthSquared() - tmpb.lengthSquared());
				});
			}
		}
		
		renderScene(ctx, ambientLight, map, blocks, entities, spatials,
				playerPosition, localPlayer, breakAnim);
		if (ctx.getHud() != null) {
			ctx.getHud().render(window);
		}
	}
	
	public void renderScene(Context ctx, Vector3f ambientLight,
			FastList<Spatial>[] map, Block[] blocks, Entity[] entities, Spatial[] spatials, Vector3f playerPosition, Player p, float breakAnim) {
		blockShader.bind();
		
		blockShader.setUniform("fog", ctx.getFog());
		blockShader.setUniform("projectionMatrix", ctx.getWindow().getProjectionMatrix());
		blockShader.setUniform("texture_sampler", 0);
		blockShader.setUniform("break_sampler", 2);
		
		Matrix4f viewMatrix = ctx.getCamera().getViewMatrix();
		blockShader.setUniform("viewMatrix", viewMatrix);

		blockShader.setUniform("ambientLight", ambientLight);

		if (breakAnim > 0f && breakAnim < 1f) {
			int breakStep = (int)(breakAnim*Cubyz.breakAnimations.length);
			glActiveTexture(GL_TEXTURE2);
			glBindTexture(GL_TEXTURE_2D, Cubyz.breakAnimations[breakStep].getId());
		} else {
			glActiveTexture(GL_TEXTURE2);
			glBindTexture(GL_TEXTURE_2D, 0);
		}
		for (int i = 0; i < blocks.length; i++) {
			if (map[i] == null)
				continue;
			Mesh mesh = Meshes.blockMeshes.get(blocks[i]);
			mesh.getMaterial().setTexture(Meshes.blockTextures.get(blocks[i]));
			blockShader.setUniform("materialHasTexture", mesh.getMaterial().isTextured());
			InstancedMesh ins = (InstancedMesh) mesh; // Blocks are always instanced.
			ins.renderListInstanced(map[i], transformation);
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
					entityShader.setUniform("light", ent.getStellarTorus().getWorld().getCurrentTorus().getLight(x, y, z, ambientLight));
					ent.getType().model.render(viewMatrix, entityShader, ent);
					continue;
				}
				if (ent instanceof CustomMeshProvider) {
					CustomMeshProvider provider = (CustomMeshProvider) ent;
					MeshType type = provider.getMeshType();
					if (type == MeshType.BLOCK) {
						Block b = (Block) provider.getMeshId();
						mesh = Meshes.blockMeshes.get(b);
						mesh.getMaterial().setTexture(Meshes.blockTextures.get(b));
					} else if (type == MeshType.ENTITY) {
						Entity e = (Entity) provider.getMeshId();
						mesh = Meshes.entityMeshes.get(e);
					}
				} else {
					mesh = Meshes.entityMeshes.get(ent.getType());
				}
				
				if (mesh != null) {
					entityShader.setUniform("materialHasTexture", mesh.getMaterial().isTextured());
					entityShader.setUniform("light", ent.getStellarTorus().getWorld().getCurrentTorus().getLight(x, y, z, ambientLight));
					
					mesh.renderOne(() -> {
						Vector3f position = ent.getRenderPosition();
						Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(position, ent.getRotation(), ent.getScale()), viewMatrix);
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
						viewMatrix);
				entityShader.setUniform("viewMatrix", modelViewMatrix);
			});
		}
		
		entityShader.unbind();
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
