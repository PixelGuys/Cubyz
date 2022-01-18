package cubyz.rendering;

import static org.lwjgl.opengl.GL43.*;

import org.joml.FrustumIntersection;
import org.joml.Matrix4f;
import org.joml.Vector3d;
import org.joml.Vector3f;
import org.joml.Vector4f;

import cubyz.utils.Logger;
import cubyz.client.BlockMeshes;
import cubyz.client.ChunkMesh;
import cubyz.client.ClientSettings;
import cubyz.client.Cubyz;
import cubyz.client.GameLauncher;
import cubyz.client.Meshes;
import cubyz.client.NormalChunkMesh;
import cubyz.client.ReducedChunkMesh;
import cubyz.gui.input.Keyboard;
import cubyz.utils.Utils;
import cubyz.utils.datastructures.FastList;
import cubyz.world.World;
import cubyz.world.Chunk;
import cubyz.world.blocks.BlockInstance;
import cubyz.world.blocks.Blocks;
import cubyz.world.entity.Player;

/**
 * Renderer that should be used when easyLighting is enabled.
 * Currently it is used always, simply because it's the only renderer available for now.
 */

public class MainRenderer {
	public static class DeferredUniforms {
		public static int loc_position;
		public static int loc_color;
	}
	public static class FogUniforms {
		public static int loc_fog_activ;
		public static int loc_fog_color;
		public static int loc_fog_density;

		public static int loc_position;
		public static int loc_color;
	}
	
	/**The number of milliseconds after which no more chunk meshes are created. This allows the game to run smoother on movement.*/
	private static int maximumMeshTime = 12;

	private ShaderProgram fogShader;
	private ShaderProgram deferredRenderPassShader;

	public static final float Z_NEAR = 0.1f;
	public static final float Z_FAR = 10000.0f;
	private boolean inited = false;
	private boolean doRender = true;
	private Transformation transformation;
	private String shaders = "";
	private Matrix4f prjViewMatrix = new Matrix4f();
	private FrustumIntersection frustumInt = new FrustumIntersection();
	
	private float playerBobbing;
	private boolean bobbingUp;
	
	private Vector3f ambient = new Vector3f();
	private Vector4f clearColor = new Vector4f(0.1f, 0.7f, 0.7f, 1f);
	private DirectionalLight light = new DirectionalLight(new Vector3f(1.0f, 1.0f, 1.0f), new Vector3f(0.0f, 1.0f, 0.0f).mul(0.1f));

	private BufferManager buffers;

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

	public void setDoRender(boolean doRender) {
		this.doRender = doRender;
	}

	public void loadShaders() throws Exception {
		if (fogShader != null)
			fogShader.cleanup();
		fogShader = new ShaderProgram(Utils.loadResource(shaders + "/fog_vertex.vs"),
				Utils.loadResource(shaders + "/fog_fragment.fs"),
				FogUniforms.class);
		if (deferredRenderPassShader != null)
			deferredRenderPassShader.cleanup();
		deferredRenderPassShader = new ShaderProgram(Utils.loadResource(shaders + "/deferred_render_pass.vs"),
				Utils.loadResource(shaders + "/deferred_render_pass.fs"),
				DeferredUniforms.class);
		
		ReducedChunkMesh.init(shaders);
		NormalChunkMesh.init(shaders);
		EntityRenderer.init(shaders);
		BlockDropRenderer.init(shaders);
		BlockBreakingRenderer.init(shaders);
		
		System.gc();
	}

	private void createFrameBuffer() {
		glGenFramebuffers();

		buffers = new BufferManager();
	}

	public void init() throws Exception {
		transformation = new Transformation();
		loadShaders();
		createFrameBuffer();
		updateViewport(Window.getWidth(), Window.getHeight(), ClientSettings.FOV);
		inited = true;
	}
	
	/**
	 * Sorts the chunks based on their distance from the player to reduce complexity when sorting the transparent blocks.
	 * @param toSort
	 * @param playerX
	 * @param playerZ
	 * @return sorted chunk array
	 */
	public NormalChunkMesh[] sortChunks(NormalChunkMesh[] toSort, double playerX, double playerY, double playerZ) {
		NormalChunkMesh[] output = new NormalChunkMesh[toSort.length];
		double[] distances = new double[toSort.length];
		System.arraycopy(toSort, 0, output, 0, toSort.length);
		for(int i = 0; i < output.length; i++) {
			distances[i] = (playerX - output[i].wx)*(playerX - output[i].wx) + (playerY - output[i].wy)*(playerY - output[i].wy) + (playerZ - output[i].wz)*(playerZ - output[i].wz);
		}
		// Insert sort them:
		for(int i = 1; i < output.length; i++) {
			for(int j = i-1; j >= 0; j--) {
				if (distances[j] < distances[j+1]) {
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

	public void updateViewport(int width, int height, float fov) {
		glViewport(0, 0, width, height);
		Transformation.updateProjectionMatrix(Window.getProjectionMatrix(), (float)Math.toRadians(fov), width, height, Z_NEAR, Z_FAR);
		// Use a projection matrix that prevent z-fighting:
		Transformation.updateProjectionMatrix(ReducedChunkMesh.projMatrix, (float)Math.toRadians(fov), width, height, 2.0f, 16384.0f);
		
		buffers.updateBufferSize(width, height);
	}
	
	/**
	 * Render the current world.
	 * @param window
	 */
	public void render() {
		long startTime = System.currentTimeMillis();
		if (Window.shouldClose()) {
			GameLauncher.instance.exit();
		}
		if (Window.isResized()) {
			Window.setResized(false);
			updateViewport(Window.getWidth(), Window.getHeight(), ClientSettings.FOV);
		}

		BlockMeshes.loadMeshes(); // Loads all meshes that weren't loaded yet.
		Vector3d playerPosition = null;
		if(Cubyz.player != null)
			playerPosition = new Vector3d(Cubyz.player.getPosition());
		
		if (Cubyz.player != null) {
			if (Cubyz.playerInc.x != 0 || Cubyz.playerInc.z != 0) { // while walking
				if (bobbingUp) {
					playerBobbing += 0.005f;
					if (playerBobbing >= 0.05f) {
						bobbingUp = false;
					}
				} else {
					playerBobbing -= 0.005f;
					if (playerBobbing <= -0.05f) {
						bobbingUp = true;
					}
				}
			}
			if (Cubyz.playerInc.y != 0) {
				Cubyz.player.vy = Cubyz.playerInc.y;
			}
			if (Cubyz.playerInc.x != 0) {
				Cubyz.player.vx = Cubyz.playerInc.x;
			}
			playerPosition.y += Player.cameraHeight + playerBobbing;
		}
		
		while (!Cubyz.renderDeque.isEmpty()) {
			Cubyz.renderDeque.pop().run();
		}
		if (Cubyz.world != null) {
			// TODO: Handle colors and sun position in the world.
			ambient.x = ambient.y = ambient.z = Cubyz.world.getGlobalLighting();
			if (ambient.x < 0.1f) ambient.x = 0.1f;
			if (ambient.y < 0.1f) ambient.y = 0.1f;
			if (ambient.z < 0.1f) ambient.z = 0.1f;
			clearColor = Cubyz.world.getClearColor();
			Cubyz.fog.setColor(clearColor);
			if (ClientSettings.FOG_COEFFICIENT == 0) {
				Cubyz.fog.setActive(false);
			} else {
				Cubyz.fog.setActive(true);
			}
			Cubyz.fog.setDensity(1 / (ClientSettings.EFFECTIVE_RENDER_DISTANCE*ClientSettings.FOG_COEFFICIENT));
			
			light.setColor(clearColor);
			
			float lightY = (((float)Cubyz.gameTime % World.DAY_CYCLE) / (float) (World.DAY_CYCLE/2)) - 1f;
			float lightX = (((float)Cubyz.gameTime % World.DAY_CYCLE) / (float) (World.DAY_CYCLE/2)) - 1f;
			light.getDirection().set(lightY, 0, lightX);
			// Set intensity:
			light.setDirection(light.getDirection().mul(0.1f*Cubyz.world.getGlobalLighting()/light.getDirection().length()));
			Window.setClearColor(clearColor);
			render(ambient, light, worldSpatialList, playerPosition);
			
			// Update meshes:
			// The meshes need to be updated after everything is rendered. Otherwise the vbos get corrupted on some hardware.
			// See https://cdn.discordapp.com/attachments/574185221939789855/931591596175147038/unknown.png for an example.
			do { // A do while loop is used so even when the framerate is low at least one mesh gets updated per frame.
				ChunkMesh mesh = Meshes.getNextQueuedMesh();
				if (mesh == null) break;
				mesh.regenerateMesh();
			} while (System.currentTimeMillis() - startTime <= maximumMeshTime);
		} else {
			clearColor.y = clearColor.z = 0.7f;
			clearColor.x = 0.1f;
			
			Window.setClearColor(clearColor);

			BackgroundScene.renderBackground();
		}
		Cubyz.gameUI.render();
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
	public void render(Vector3f ambientLight, DirectionalLight directionalLight, Spatial[] spatials, Vector3d playerPosition) {
		if (!doRender)
			return;
		buffers.bind();
		buffers.clearAndBind(Window.getClearColor());
		// Clean up old chunk meshes:
		Meshes.cleanUp();
		
		Camera.setViewMatrix(transformation.getViewMatrix(new Vector3f(), Camera.getRotation()));
		
		
		// Uses FrustumCulling on the chunks.
		prjViewMatrix.set(Window.getProjectionMatrix());
		prjViewMatrix.mul(Camera.getViewMatrix());

		frustumInt.set(prjViewMatrix);

		int time = (int) (System.currentTimeMillis() & Integer.MAX_VALUE);
		if (playerPosition != null) {
			Fog waterFog = new Fog(true, new Vector3f(0.0f, 0.1f, 0.2f), 0.1f);

			 // Update the uniforms. The uniforms are needed to render the replacement meshes.
			ReducedChunkMesh.bindShader(ambientLight, directionalLight.getDirection(), time);
			ReducedChunkMesh.shader.setUniform(ReducedChunkMesh.loc_projectionMatrix, Window.getProjectionMatrix()); // Use the same matrix for replacement meshes.

			NormalChunkMesh.bindShader(ambientLight, directionalLight.getDirection(), time);
			
			// Activate first texture bank
			glActiveTexture(GL_TEXTURE0);
			// Bind the texture
			Meshes.blockTextureArray.bind();

			BlockInstance selected = null;
			if (Cubyz.msd.getSelected() instanceof BlockInstance) {
				selected = (BlockInstance)Cubyz.msd.getSelected();
			}
			
			double x0 = playerPosition.x;
			double y0 = playerPosition.y;
			double z0 = playerPosition.z;

			glDepthRangef(0, 0.05f);

			FastList<NormalChunkMesh> visibleChunks = new FastList<NormalChunkMesh>(NormalChunkMesh.class);
			FastList<ReducedChunkMesh> visibleReduced = new FastList<ReducedChunkMesh>(ReducedChunkMesh.class);
			for (ChunkMesh mesh : Cubyz.chunkTree.getRenderChunks(frustumInt, x0, y0, z0)) {
				if (mesh instanceof NormalChunkMesh) {
					visibleChunks.add((NormalChunkMesh)mesh);
					
					mesh.render(playerPosition);
				} else if (mesh instanceof ReducedChunkMesh) {
					visibleReduced.add((ReducedChunkMesh)mesh);
				}
			}
			if(selected != null && !Blocks.transparent(selected.getBlock())) {
				BlockBreakingRenderer.render(selected, playerPosition);
				Meshes.blockTextureArray.bind();
			}
			
			// Render the far away ReducedChunks:
			glDepthRangef(0.05f, 1.0f); // ← Used to fix z-fighting.
			ReducedChunkMesh.bindShader(ambientLight, directionalLight.getDirection(), time);
			ReducedChunkMesh.shader.setUniform(ReducedChunkMesh.loc_waterFog_activ, waterFog.isActive());
			ReducedChunkMesh.shader.setUniform(ReducedChunkMesh.loc_waterFog_color, waterFog.getColor());
			ReducedChunkMesh.shader.setUniform(ReducedChunkMesh.loc_waterFog_density, waterFog.getDensity());
			
			for(int i = 0; i < visibleReduced.size; i++) {
				ReducedChunkMesh mesh = visibleReduced.array[i];
				mesh.render(playerPosition);
			}
			glDepthRangef(0, 0.05f);
			
			EntityRenderer.render(ambientLight, directionalLight, playerPosition);

			BlockDropRenderer.render(frustumInt, ambientLight, directionalLight, playerPosition);
			
			/*NormalChunkMesh.shader.bind();
			NormalChunkMesh.shader.setUniform(NormalChunkMesh.loc_fog_activ, 0); // manually disable the fog
			for (int i = 0; i < spatials.length; i++) {
				Spatial spatial = spatials[i];
				Mesh mesh = spatial.getMesh();
				EntityRenderer.entityShader.setUniform(EntityRenderer.loc_light, new Vector3f(1, 1, 1));
				EntityRenderer.entityShader.setUniform(EntityRenderer.loc_materialHasTexture, mesh.getMaterial().isTextured());
				mesh.renderOne(() -> {
					Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(
							Transformation.getModelMatrix(spatial.getPosition(), spatial.getRotation(), spatial.getScale()),
							Camera.getViewMatrix());
					EntityRenderer.entityShader.setUniform(EntityRenderer.loc_viewMatrix, modelViewMatrix);
				});
			}*/ // TODO: Draw the sun.
			
			// Render transparent chunk meshes:
			NormalChunkMesh.bindTransparentShader(ambientLight, directionalLight.getDirection(), time);

			buffers.bindTextures();

			NormalChunkMesh.transparentShader.setUniform(NormalChunkMesh.TransparentUniforms.loc_waterFog_activ, waterFog.isActive());
			NormalChunkMesh.transparentShader.setUniform(NormalChunkMesh.TransparentUniforms.loc_waterFog_color, waterFog.getColor());
			NormalChunkMesh.transparentShader.setUniform(NormalChunkMesh.TransparentUniforms.loc_waterFog_density, waterFog.getDensity());

			NormalChunkMesh[] meshes = sortChunks(visibleChunks.toArray(), x0/Chunk.chunkSize - 0.5f, y0/Chunk.chunkSize - 0.5f, z0/Chunk.chunkSize - 0.5f);
			for (NormalChunkMesh mesh : meshes) {
				NormalChunkMesh.transparentShader.setUniform(NormalChunkMesh.TransparentUniforms.loc_drawFrontFace, false);
				glCullFace(GL_FRONT);
				mesh.renderTransparent(playerPosition);

				NormalChunkMesh.transparentShader.setUniform(NormalChunkMesh.TransparentUniforms.loc_drawFrontFace, true);
				glCullFace(GL_BACK);
				mesh.renderTransparent(playerPosition);
			}

			if(selected != null && Blocks.transparent(selected.getBlock())) {
				BlockBreakingRenderer.render(selected, playerPosition);
				Meshes.blockTextureArray.bind();
			}

			fogShader.bind();
			// Draw the water fog if the player is underwater:
			Player player = Cubyz.player;
			int block = Cubyz.world.getBlock((int)Math.round(player.getPosition().x), (int)(player.getPosition().y + player.height), (int)Math.round(player.getPosition().z));
			if (block != 0 && !Blocks.solid(block)) {
				if (Blocks.id(block).toString().equals("cubyz:water")) {
					fogShader.setUniform(FogUniforms.loc_fog_activ, waterFog.isActive());
					fogShader.setUniform(FogUniforms.loc_fog_color, waterFog.getColor());
					fogShader.setUniform(FogUniforms.loc_fog_density, waterFog.getDensity());
					glUniform1i(FogUniforms.loc_color, 3);
					glUniform1i(FogUniforms.loc_position, 4);

					glBindVertexArray(Graphics.rectVAO);
					glDisable(GL_DEPTH_TEST);
					glDisable(GL_CULL_FACE);
					glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
				}
			}
		}
		buffers.unbind();
		buffers.bindTextures();
		deferredRenderPassShader.bind();
		glUniform1i(DeferredUniforms.loc_color, 4);
		glUniform1i(DeferredUniforms.loc_position, 3);

		if(Window.getRenderTarget() != null)
			Window.getRenderTarget().bind();

		glBindVertexArray(Graphics.rectVAO);
		glDisable(GL_DEPTH_TEST);
		glDisable(GL_CULL_FACE);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

		if(Window.getRenderTarget() != null)
			Window.getRenderTarget().unbind();
	}

	public void setPath(String dataName, String path) {
		if (dataName.equals("shaders") || dataName.equals("shadersFolder")) {
			if (inited) {
				try {
					doRender = false;
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
