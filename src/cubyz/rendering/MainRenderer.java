package cubyz.rendering;

import static org.lwjgl.opengl.GL11.GL_TEXTURE_2D;
import static org.lwjgl.opengl.GL11.glBindTexture;
import static org.lwjgl.opengl.GL13.GL_TEXTURE0;
import static org.lwjgl.opengl.GL13.glActiveTexture;
import static org.lwjgl.opengl.GL13C.*;

import org.joml.FrustumIntersection;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import org.joml.Vector4f;

import cubyz.Logger;
import cubyz.api.CubyzRegistries;
import cubyz.client.ChunkMesh;
import cubyz.client.ClientSettings;
import cubyz.client.Cubyz;
import cubyz.client.GameLauncher;
import cubyz.client.Meshes;
import cubyz.client.NormalChunkMesh;
import cubyz.client.ReducedChunkMesh;
import cubyz.client.entity.ClientEntity;
import cubyz.client.entity.ClientEntityManager;
import cubyz.gui.input.Keyboard;
import cubyz.utils.Utils;
import cubyz.utils.datastructures.FastList;
import cubyz.world.NormalChunk;
import cubyz.world.blocks.Block;
import cubyz.world.blocks.BlockInstance;
import cubyz.world.entity.ChunkEntityManager;
import cubyz.world.entity.CustomMeshProvider;
import cubyz.world.entity.ItemEntityManager;
import cubyz.world.entity.Player;
import cubyz.world.entity.CustomMeshProvider.MeshType;
import cubyz.world.items.ItemBlock;

/**
 * Renderer that should be used when easyLighting is enabled.
 * Currently it is used always, simply because it's the only renderer available for now.
 */

public class MainRenderer {
	public static class EntityUniforms {
		public static int loc_projectionMatrix;
		public static int loc_viewMatrix;
		public static int loc_texture_sampler;
		public static int loc_materialHasTexture;
		public static int loc_fog_activ;
		public static int loc_fog_color;
		public static int loc_fog_density;
		public static int loc_light;
	}
	
	/**The number of milliseconds after which no more chunk meshes are created. This allows the game to run smoother on movement.*/
	private static int maximumMeshTime = 1;

	private ShaderProgram entityShader; // Entities are sometimes small and sometimes big. Therefor it would mean a lot of work to still use smooth lighting. Therefor the non-smooth shader is used for those.

	private static final float Z_NEAR = 0.01f;
	private static final float Z_FAR = 10000.0f;
	private boolean inited = false;
	private boolean doRender = true;
	private Transformation transformation;
	private String shaders = "";
	private Matrix4f prjViewMatrix = new Matrix4f();
	private FrustumIntersection frustumInt = new FrustumIntersection();
	
	private float playerBobbing;
	private boolean bobbingUp;
	
	private Vector3f ambient = new Vector3f();
	private Vector3f brightAmbient = new Vector3f(1, 1, 1);
	private Vector4f clearColor = new Vector4f(0.1f, 0.7f, 0.7f, 1f);
	private DirectionalLight light = new DirectionalLight(new Vector3f(1.0f, 1.0f, 1.0f), new Vector3f(0.0f, 1.0f, 0.0f).mul(0.1f));

	private static final Block[] EMPTY_BLOCK_LIST = new Block[0];
	private static final ClientEntity[] EMPTY_ENTITY_LIST = new ClientEntity[0];
	private static final Spatial[] EMPTY_SPATIAL_LIST = new Spatial[0];
	public Spatial[] worldSpatialList;
	
	public boolean screenshot;

	public MainRenderer() {

	}

	public Transformation getTransformation() {
		return transformation;
	}

	public void setShaderFolder(String shaders) {
		this.shaders = shaders;
	}

	public void unloadShaders() throws Exception {
		entityShader.cleanup();
		entityShader = null;
		System.gc();
	}

	public void setDoRender(boolean doRender) {
		this.doRender = doRender;
	}

	public void loadShaders() throws Exception {
		entityShader = new ShaderProgram(Utils.loadResource(shaders + "/entity_vertex.vs"),
				Utils.loadResource(shaders + "/entity_fragment.fs"),
				EntityUniforms.class);
		
		System.gc();
	}

	public void init() throws Exception {
		transformation = new Transformation();
		Window.setProjectionMatrix(transformation.getProjectionMatrix((float) Math.toRadians(70.0f), Window.getWidth(),
				Window.getHeight(), Z_NEAR, Z_FAR));
		loadShaders();
		ReducedChunkMesh.init(shaders);
		NormalChunkMesh.init(shaders);

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
	public NormalChunkMesh[] sortChunks(NormalChunkMesh[] toSort, float playerX, float playerY, float playerZ) {
		NormalChunkMesh[] output = new NormalChunkMesh[toSort.length];
		float[] distances = new float[toSort.length];
		System.arraycopy(toSort, 0, output, 0, toSort.length);
		for(int i = 0; i < output.length; i++) {
			distances[i] = (playerX - output[i].wx)*(playerX - output[i].wx) + (playerY - output[i].wy)*(playerY - output[i].wy) + (playerZ - output[i].wz)*(playerZ - output[i].wz);
		}
		// Insert sort them:
		for(int i = 1; i < output.length; i++) {
			for(int j = i-1; j >= 0; j--) {
				if(distances[j] < distances[j+1]) {
					// Swap them:
					distances[j] += distances[j+1];
					distances[j+1] = distances[j] - distances[j+1];
					distances[j] -= distances[j+1];
					NormalChunkMesh local = output[j+1];
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
	 * Render the current world.
	 * @param window
	 */
	public void render() {
		if(Window.shouldClose()) {
			GameLauncher.instance.exit();
		}
		
		if(Cubyz.world != null) {
			if(Cubyz.playerInc.x != 0 || Cubyz.playerInc.z != 0) { // while walking
				if(bobbingUp) {
					playerBobbing += 0.005f;
					if(playerBobbing >= 0.05f) {
						bobbingUp = false;
					}
				} else {
					playerBobbing -= 0.005f;
					if(playerBobbing <= -0.05f) {
						bobbingUp = true;
					}
				}
			}
			if(Cubyz.playerInc.y != 0) {
				Cubyz.player.vy = Cubyz.playerInc.y;
			}
			if(Cubyz.playerInc.x != 0) {
				Cubyz.player.vx = Cubyz.playerInc.x;
			}
			Camera.setPosition(Cubyz.player.getPosition().x, Cubyz.player.getPosition().y + Player.cameraHeight + playerBobbing, Cubyz.player.getPosition().z);
		}
		
		while(!Cubyz.renderDeque.isEmpty()) {
			Cubyz.renderDeque.pop().run();
		}
		if(Cubyz.world != null) {
			// TODO: Handle colors and sun position in the surface.
			ambient.x = ambient.y = ambient.z = Cubyz.surface.getGlobalLighting();
			if(ambient.x < 0.1f) ambient.x = 0.1f;
			if(ambient.y < 0.1f) ambient.y = 0.1f;
			if(ambient.z < 0.1f) ambient.z = 0.1f;
			clearColor = Cubyz.surface.getClearColor();
			Cubyz.fog.setColor(clearColor);
			if(ClientSettings.FOG_COEFFICIENT == 0) {
				Cubyz.fog.setActive(false);
			} else {
				Cubyz.fog.setActive(true);
			}
			Cubyz.fog.setDensity(1 / (ClientSettings.EFFECTIVE_RENDER_DISTANCE*ClientSettings.FOG_COEFFICIENT));
			Player player = Cubyz.player;
			Block bi = Cubyz.surface.getBlock(Math.round(player.getPosition().x), (int)(player.getPosition().y)+3, Math.round(player.getPosition().z));
			if(bi != null && !bi.isSolid()) {
				int absorption = bi.getAbsorption();
				ambient.x *= 1.0f - Math.pow(((absorption >>> 16) & 255)/255.0f, 0.25);
				ambient.y *= 1.0f - Math.pow(((absorption >>> 8) & 255)/255.0f, 0.25);
				ambient.z *= 1.0f - Math.pow(((absorption >>> 0) & 255)/255.0f, 0.25);
			}
			light.setColor(clearColor);
			 // TODO: Make light direction and sun position depend on relative position on the torus, to get realistic day-night patterns at the poles.
			float lightY = (((float)Cubyz.world.getGameTime() % Cubyz.surface.getStellarTorus().getDayCycle()) / (float) (Cubyz.surface.getStellarTorus().getDayCycle()/2)) - 1f;
			float lightX = (((float)Cubyz.world.getGameTime() % Cubyz.surface.getStellarTorus().getDayCycle()) / (float) (Cubyz.surface.getStellarTorus().getDayCycle()/2)) - 1f;
			light.getDirection().set(lightY, 0, lightX);
			// Set intensity:
			light.setDirection(light.getDirection().mul(0.1f*Cubyz.surface.getGlobalLighting()/light.getDirection().length()));
			Window.setClearColor(clearColor);
			render(ambient, light, Cubyz.world.getBlocks(), ClientEntityManager.getEntities(), worldSpatialList, Cubyz.player);
		} else {
			clearColor.y = clearColor.z = 0.7f;
			clearColor.x = 0.1f;
			
			Window.setClearColor(clearColor);
			
			if (screenshot) {
				FrameBuffer buf = new FrameBuffer();
				buf.genColorTexture(Window.getWidth(), Window.getHeight());
				buf.genRenderbuffer(Window.getWidth(), Window.getHeight());
				Window.setRenderTarget(buf);
			}
			
			render(brightAmbient, light, EMPTY_BLOCK_LIST, EMPTY_ENTITY_LIST, EMPTY_SPATIAL_LIST, null);
			
			if (screenshot) {
				/*FrameBuffer buf = window.getRenderTarget();
				window.setRenderTarget(null);
				screenshot = false;*/
			}
		}
		Keyboard.release(); // TODO: Why is this called in the render thread???
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
	public void render(Vector3f ambientLight, DirectionalLight directionalLight, Block[] blocks, ClientEntity[] entities, Spatial[] spatials, Player localPlayer) {
		if (Window.isResized()) {
			glViewport(0, 0, Window.getWidth(), Window.getHeight());
			Window.setResized(false);
			Window.setProjectionMatrix(transformation.getProjectionMatrix((float)Math.toRadians(ClientSettings.FOV),
			Window.getWidth(), Window.getHeight(), Z_NEAR, Z_FAR));
		}
		if (!doRender)
			return;
		clear();
		long startTime = System.currentTimeMillis();
		// Clean up old chunk meshes:
		Meshes.cleanUp();
		
		Camera.setViewMatrix(transformation.getViewMatrix(Camera.getPosition(), Camera.getRotation()));
		
		float breakAnim = 0;
		
		
		// Uses FrustumCulling on the chunks.
		prjViewMatrix.set(Window.getProjectionMatrix());
		prjViewMatrix.mul(Camera.getViewMatrix());

		frustumInt.set(prjViewMatrix);
		Vector3f playerPosition = null;
		if(localPlayer != null) {
			playerPosition = localPlayer.getPosition(); // Use a constant copy of the player position for the whole rendering to prevent graphics bugs on player movement.
		}
		if(playerPosition != null) {
			ReducedChunkMesh.bindShader(ambientLight, directionalLight.getDirection()); // Update the uniforms. The uniforms are needed to render the replacement meshes.
			
			NormalChunkMesh.bindShader(ambientLight, directionalLight.getDirection());
			
			// Activate first texture bank
			glActiveTexture(GL_TEXTURE0);
			// Bind the texture
			glBindTexture(GL_TEXTURE_2D, Meshes.atlas.getId());
			BlockInstance selected = null;
			if(Cubyz.msd.getSelected() instanceof BlockInstance) {
				selected = (BlockInstance)Cubyz.msd.getSelected();
				breakAnim = selected.getBreakingAnim();
			}
			
			if(breakAnim > 0f && breakAnim < 1f) {
				int breakStep = (int)(breakAnim*(GameLauncher.logic.breakAnimations.length - 1)) + 1;
				glActiveTexture(GL_TEXTURE2);
				glBindTexture(GL_TEXTURE_2D, GameLauncher.logic.breakAnimations[breakStep].getId());
			} else {
				glActiveTexture(GL_TEXTURE2);
				glBindTexture(GL_TEXTURE_2D, GameLauncher.logic.breakAnimations[0].getId());
			}
			
			float x0 = playerPosition.x;
			float y0 = playerPosition.y;
			float z0 = playerPosition.z;
			// Update meshes:
			while(System.currentTimeMillis() - startTime <= maximumMeshTime) {
				ChunkMesh mesh = Meshes.getNextQueuedMesh();
				if(mesh == null) break;
				mesh.regenerateMesh();
			}

			FastList<NormalChunkMesh> visibleChunks = new FastList<NormalChunkMesh>(NormalChunkMesh.class);
			FastList<ReducedChunkMesh> visibleReduced = new FastList<ReducedChunkMesh>(ReducedChunkMesh.class);
			for (ChunkMesh mesh : Cubyz.chunkTree.getRenderChunks(frustumInt, x0, z0)) {
				if(mesh instanceof NormalChunkMesh) {
					visibleChunks.add((NormalChunkMesh)mesh);
					
					if(selected != null && selected.source == mesh.getChunk()) {
						NormalChunkMesh.shader.setUniform(NormalChunkMesh.loc_selectedIndex, selected.renderIndex);
					} else {
						NormalChunkMesh.shader.setUniform(NormalChunkMesh.loc_selectedIndex, -1);
					}
					mesh.render();
				} else if(mesh instanceof ReducedChunkMesh) {
					visibleReduced.add((ReducedChunkMesh)mesh);
				}
			}
			
			// Render the far away ReducedChunks:
			ReducedChunkMesh.bindShader(ambientLight, directionalLight.getDirection());
			
			for(int i = 0; i < visibleReduced.size; i++) {
				ReducedChunkMesh mesh = visibleReduced.array[i];
				mesh.render();
			}
			
			// Render entities:
			
			entityShader.bind();
			entityShader.setUniform(EntityUniforms.loc_fog_activ, Cubyz.fog.isActive());
			entityShader.setUniform(EntityUniforms.loc_fog_color, Cubyz.fog.getColor());
			entityShader.setUniform(EntityUniforms.loc_fog_density, Cubyz.fog.getDensity());
			entityShader.setUniform(EntityUniforms.loc_projectionMatrix, Window.getProjectionMatrix());
			entityShader.setUniform(EntityUniforms.loc_texture_sampler, 0);
			for (int i = 0; i < entities.length; i++) {
				ClientEntity ent = entities[i];
				int x = (int)(ent.position.x + 1.0f);
				int y = (int)(ent.position.y + 1.0f);
				int z = (int)(ent.position.z + 1.0f);
				if (ent != null && ent.id != localPlayer.id) { // don't render local player
					Mesh mesh = null;
					if(ent.type.model != null) {
						entityShader.setUniform(EntityUniforms.loc_materialHasTexture, true);
						entityShader.setUniform(EntityUniforms.loc_light, Cubyz.surface.getLight(x, y, z, ambientLight, ClientSettings.easyLighting));
						ent.type.model.render(Camera.getViewMatrix(), entityShader, ent);
						continue;
					}
					if (ent instanceof CustomMeshProvider) {
						CustomMeshProvider provider = (CustomMeshProvider) ent;
						MeshType type = provider.getMeshType();
						if (type == MeshType.ENTITY) {
							ClientEntity e = (ClientEntity) provider.getMeshId();
							mesh = Meshes.entityMeshes.get(e.type);
						}
					} else {
						mesh = Meshes.entityMeshes.get(ent.type);
					}
					
					if (mesh != null) {
						entityShader.setUniform(EntityUniforms.loc_materialHasTexture, mesh.getMaterial().isTextured());
						entityShader.setUniform(EntityUniforms.loc_light, Cubyz.surface.getLight(x, y, z, ambientLight, ClientSettings.easyLighting));
						
						mesh.renderOne(() -> {
							Vector3f position = ent.getRenderPosition();
							Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(position, ent.rotation, 1), Camera.getViewMatrix());
							entityShader.setUniform(EntityUniforms.loc_viewMatrix, modelViewMatrix);
						});
					}
				}
			}
			
			// Render item entities:
			for(ChunkEntityManager chManager : localPlayer.getSurface().getEntityManagers()) {
				NormalChunk chunk = chManager.chunk;
				if (!chunk.isLoaded() || !frustumInt.testAab(chunk.getMin(), chunk.getMax()))
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
					} else {
						Block b = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:diamond_ore");
						mesh = Meshes.blockMeshes.get(b);
						mesh.getMaterial().setTexture(Meshes.blockTextures.get(b));
					}
					if(mesh != null) {
						entityShader.setUniform(EntityUniforms.loc_materialHasTexture, mesh.getMaterial().isTextured());
						entityShader.setUniform(EntityUniforms.loc_light, localPlayer.getSurface().getLight(x, y, z, ambientLight, ClientSettings.easyLighting));
						
						mesh.renderOne(() -> {
							Vector3f position = manager.getPosition(index);
							Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(position, manager.getRotation(index), ItemEntityManager.diameter), Camera.getViewMatrix());
							entityShader.setUniform(EntityUniforms.loc_viewMatrix, modelViewMatrix);
						});
					}
				}
			}
			
			NormalChunkMesh.shader.bind();
			NormalChunkMesh.shader.setUniform(NormalChunkMesh.loc_fog_activ, 0); // manually disable the fog
			for (int i = 0; i < spatials.length; i++) {
				Spatial spatial = spatials[i];
				Mesh mesh = spatial.getMesh();
				entityShader.setUniform(EntityUniforms.loc_light, new Vector3f(1, 1, 1));
				entityShader.setUniform(EntityUniforms.loc_materialHasTexture, mesh.getMaterial().isTextured());
				mesh.renderOne(() -> {
					Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(
							Transformation.getModelMatrix(spatial.getPosition(), spatial.getRotation(), spatial.getScale()),
							Camera.getViewMatrix());
					entityShader.setUniform(EntityUniforms.loc_viewMatrix, modelViewMatrix);
				});
			}
			
			// Render transparent chunk meshes:
			NormalChunkMesh.bindShader(ambientLight, directionalLight.getDirection());
			
			// Activate first texture bank
			glActiveTexture(GL_TEXTURE0);
			// Bind the texture
			glBindTexture(GL_TEXTURE_2D, Meshes.atlas.getId());
			if(Cubyz.msd.getSelected() instanceof BlockInstance) {
				selected = (BlockInstance)Cubyz.msd.getSelected();
				breakAnim = selected.getBreakingAnim();
			}
			
			if(breakAnim > 0f && breakAnim < 1f) {
				int breakStep = (int)(breakAnim*(GameLauncher.logic.breakAnimations.length - 1)) + 1;
				glActiveTexture(GL_TEXTURE2);
				glBindTexture(GL_TEXTURE_2D, GameLauncher.logic.breakAnimations[breakStep].getId());
			} else {
				glActiveTexture(GL_TEXTURE2);
				glBindTexture(GL_TEXTURE_2D, GameLauncher.logic.breakAnimations[0].getId());
			}

			NormalChunkMesh[] meshes = sortChunks(visibleChunks.toArray(), x0/NormalChunk.chunkSize - 0.5f, y0/NormalChunk.chunkSize - 0.5f, z0/NormalChunk.chunkSize - 0.5f);
			for (NormalChunkMesh mesh : meshes) {
				
				if(selected != null && selected.source == mesh.getChunk()) {
					NormalChunkMesh.shader.setUniform(NormalChunkMesh.loc_selectedIndex, selected.renderIndex);
				} else {
					NormalChunkMesh.shader.setUniform(NormalChunkMesh.loc_selectedIndex, -1);
				}
				
				mesh.renderTransparent();		
			}
		}
		Cubyz.gameUI.render();
	}

	public void cleanup() {
		if (entityShader != null) {
			entityShader.cleanup();
			entityShader = null;
		}
	}

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
					Logger.warning(e);
				}
			} else {
				shaders = path;
			}
		}
	}

}
