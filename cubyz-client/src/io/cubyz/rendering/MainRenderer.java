package io.cubyz.rendering;

import static org.lwjgl.opengl.GL11.GL_TEXTURE_2D;
import static org.lwjgl.opengl.GL11.glBindTexture;
import static org.lwjgl.opengl.GL13.GL_TEXTURE0;
import static org.lwjgl.opengl.GL13.glActiveTexture;
import static org.lwjgl.opengl.GL13C.*;

import org.joml.FrustumIntersection;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import org.joml.Vector4f;

import io.cubyz.ClientSettings;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.client.Cubyz;
import io.cubyz.client.GameLauncher;
import io.cubyz.client.Meshes;
import io.cubyz.client.NormalChunkMesh;
import io.cubyz.client.ReducedChunkMesh;
import io.cubyz.entity.CustomMeshProvider;
import io.cubyz.entity.CustomMeshProvider.MeshType;
import io.cubyz.input.Keyboard;
import io.cubyz.entity.Entity;
import io.cubyz.entity.ItemEntityManager;
import io.cubyz.entity.Player;
import io.cubyz.items.ItemBlock;
import io.cubyz.util.FastList;
import io.cubyz.utils.Utils;
import io.cubyz.world.ChunkEntityManager;
import io.cubyz.world.NormalChunk;
import io.cubyz.world.ReducedChunk;

/**
 * Renderer that should be used when easyLighting is enabled.
 * Currently it is used always, simply because it's the only renderer available for now.
 */

public class MainRenderer {
	
	/**The number of milliseconds after which no more chunk meshes are created. This allows the game to run smoother on movement.*/
	private static int maximumMeshTime = 12;

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
	
	private float playerBobbing;
	private boolean bobbingUp;
	
	private Vector3f ambient = new Vector3f();
	private Vector3f brightAmbient = new Vector3f(1, 1, 1);
	private Vector4f clearColor = new Vector4f(0.1f, 0.7f, 0.7f, 1f);
	private DirectionalLight light = new DirectionalLight(new Vector3f(1.0f, 1.0f, 1.0f), new Vector3f(0.0f, 1.0f, 0.0f).mul(0.1f));

	private static final NormalChunk[] EMPTY_CHUNK_LIST = new NormalChunk[0];
	private static final ReducedChunk[] EMPTY_REDUCED_CHUNK_LIST = new ReducedChunk[0];
	private static final Block[] EMPTY_BLOCK_LIST = new Block[0];
	private static final Entity[] EMPTY_ENTITY_LIST = new Entity[0];
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
	 * Render the current world.
	 * @param window
	 */
	public void render(Window window) {
		if(window.shouldClose()) {
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
				Cubyz.world.getLocalPlayer().vy = Cubyz.playerInc.y;
			}
			if(Cubyz.playerInc.x != 0) {
				Cubyz.world.getLocalPlayer().vx = Cubyz.playerInc.x;
			}
			Cubyz.camera.setPosition(Cubyz.world.getLocalPlayer().getPosition().x, Cubyz.world.getLocalPlayer().getPosition().y + Player.cameraHeight + playerBobbing, Cubyz.world.getLocalPlayer().getPosition().z);
		}
		
		if(!Cubyz.renderDeque.isEmpty()) {
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
			Player player = Cubyz.world.getLocalPlayer();
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
			window.setClearColor(clearColor);
			render(window, ambient, light, Cubyz.surface.getChunks(), Cubyz.surface.getReducedChunks(), Cubyz.world.getBlocks(), Cubyz.surface.getEntities(), worldSpatialList, Cubyz.world.getLocalPlayer(), Cubyz.surface.getSizeX(), Cubyz.surface.getSizeZ());
		} else {
			clearColor.y = clearColor.z = 0.7f;
			clearColor.x = 0.1f;
			
			window.setClearColor(clearColor);
			
			if (screenshot) {
				FrameBuffer buf = new FrameBuffer();
				buf.genColorTexture(window.getWidth(), window.getHeight());
				buf.genRenderbuffer(window.getWidth(), window.getHeight());
				window.setRenderTarget(buf);
			}
			
			render(window, brightAmbient, light, EMPTY_CHUNK_LIST, EMPTY_REDUCED_CHUNK_LIST, EMPTY_BLOCK_LIST, EMPTY_ENTITY_LIST, EMPTY_SPATIAL_LIST, null, -1, -1);
			
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
	public void render(Window window, Vector3f ambientLight, DirectionalLight directionalLight,
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
		long startTime = System.currentTimeMillis();
		// Clean up old chunk meshes:
		Meshes.cleanUp();
		
		Cubyz.camera.setViewMatrix(transformation.getViewMatrix(Cubyz.camera));
		
		float breakAnim = 0;
		
		
		// Uses FrustumCulling on the chunks.
		prjViewMatrix.set(window.getProjectionMatrix());
		prjViewMatrix.mul(Cubyz.camera.getViewMatrix());

		frustumInt.set(prjViewMatrix);
		Vector3f playerPosition = null;
		if(localPlayer != null) {
			playerPosition = localPlayer.getPosition(); // Use a constant copy of the player position for the whole rendering to prevent graphics bugs on player movement.
		}
		if(playerPosition != null) {
			
			blockShader.bind();
			
			blockShader.setUniform("fog", Cubyz.fog);
			blockShader.setUniform("projectionMatrix", Cubyz.window.getProjectionMatrix());
			blockShader.setUniform("texture_sampler", 0);
			blockShader.setUniform("break_sampler", 2);
			blockShader.setUniform("viewMatrix", Cubyz.camera.getViewMatrix());

			blockShader.setUniform("ambientLight", ambientLight);
			blockShader.setUniform("directionalLight", directionalLight.getDirection());
			
			blockShader.setUniform("atlasSize", Meshes.atlasSize);
			
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
					if(System.currentTimeMillis() - startTime > maximumMeshTime) {
						// Stop meshing if the frame is taking to long.
						if(!(mesh instanceof NormalChunkMesh)) continue;
					} else {
						mesh = new NormalChunkMesh(ch);
						ch.setChunkMesh(mesh);
					}
				}
				((NormalChunkMesh)mesh).render();		
			}
			blockShader.unbind();
			
			// Render the far away ReducedChunks:
			chunkShader.bind();
			
			chunkShader.setUniform("fog", Cubyz.fog);
			chunkShader.setUniform("projectionMatrix", Cubyz.window.getProjectionMatrix());
			
			chunkShader.setUniform("viewMatrix", Cubyz.camera.getViewMatrix());

			chunkShader.setUniform("ambientLight", ambientLight);
			chunkShader.setUniform("directionalLight", directionalLight.getDirection());
			
			for(ReducedChunk chunk : reducedChunks) {
				if(chunk != null && chunk.generated) {
					if (!frustumInt.testAab(chunk.getMin(x0, z0, worldSizeX, worldSizeZ), chunk.getMax(x0, z0, worldSizeX, worldSizeZ)))
						continue;
					Object mesh = chunk.getChunkMesh();
					chunkShader.setUniform("modelPosition", chunk.getMin(x0, z0, worldSizeX, worldSizeZ));
					if(mesh == null || !(mesh instanceof ReducedChunkMesh)) {
						if(System.currentTimeMillis() - startTime > maximumMeshTime) {
							// Stop meshing if the frame is taking to long.
							if(!(mesh instanceof ReducedChunkMesh)) continue;
						} else {
							chunk.setChunkMesh(mesh = new ReducedChunkMesh(chunk));
						}
					}
					((ReducedChunkMesh)mesh).render();
				}
			}
			
			chunkShader.unbind();
			
			// Render entities:
			
			entityShader.bind();
			entityShader.setUniform("fog", Cubyz.fog);
			entityShader.setUniform("projectionMatrix", Cubyz.window.getProjectionMatrix());
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
						ent.getType().model.render(Cubyz.camera.getViewMatrix(), entityShader, ent);
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
							Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(position, ent.getRotation(), ent.getScale()), Cubyz.camera.getViewMatrix());
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
							Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(position, manager.getRotation(index), ItemEntityManager.diameter), Cubyz.camera.getViewMatrix());
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
							Cubyz.camera.getViewMatrix());
					entityShader.setUniform("viewMatrix", modelViewMatrix);
				});
			}
			
			entityShader.unbind();
			
			// Render transparent chunk meshes:
			blockShader.bind();
			
			blockShader.setUniform("fog", Cubyz.fog);
			blockShader.setUniform("projectionMatrix", Cubyz.window.getProjectionMatrix());
			blockShader.setUniform("texture_sampler", 0);
			blockShader.setUniform("break_sampler", 2);
			blockShader.setUniform("viewMatrix", Cubyz.camera.getViewMatrix());

			blockShader.setUniform("ambientLight", ambientLight);
			blockShader.setUniform("directionalLight", directionalLight.getDirection());
			
			blockShader.setUniform("atlasSize", Meshes.atlasSize);
			
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
					if(System.currentTimeMillis() - startTime > maximumMeshTime) {
						// Stop meshing if the frame is taking to long.
						if(!(mesh instanceof NormalChunkMesh)) continue;
					} else {
						mesh = new NormalChunkMesh(ch);
						ch.setChunkMesh(mesh);
					}
				}
				((NormalChunkMesh)mesh).renderTransparent();		
			}
			blockShader.unbind();
		}
		Cubyz.hud.render(window);
	}

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
