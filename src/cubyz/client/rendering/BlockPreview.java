package cubyz.client.rendering;

import static org.lwjgl.opengl.GL11C.GL_COLOR_BUFFER_BIT;
import static org.lwjgl.opengl.GL11C.GL_DEPTH_BUFFER_BIT;
import static org.lwjgl.opengl.GL11C.GL_STENCIL_BUFFER_BIT;
import static org.lwjgl.opengl.GL11C.glClear;
import static org.lwjgl.opengl.GL11C.glViewport;

import org.joml.Matrix4f;
import org.joml.Vector3f;
import org.joml.Vector4f;

import cubyz.Logger;
import cubyz.client.Meshes;
import cubyz.utils.Utils;
import cubyz.world.blocks.Block;

/**
 * Used for rendering block preview images in the inventory.
 */

public abstract class BlockPreview {
	// Uniform locations:
	public static int loc_projectionMatrix;
	public static int loc_viewMatrix;
	public static int loc_texture_sampler;
	public static int loc_light;
	public static int loc_dirLight;
	
	private static ShaderProgram shader;

	private static boolean inited = false;
	private static Transformation transformation;
	private static String shaders = "";

	public static void setShaderFolder(String shaders) {
		BlockPreview.shaders = shaders;
	}

	public static void unloadShader() throws Exception {
		shader.unbind();
		shader.cleanup();
		shader = null;
		System.gc();
	}

	public static void loadShader() throws Exception {
		shader = new ShaderProgram(Utils.loadResource(shaders + "/vertex.vs"),
				Utils.loadResource(shaders + "/fragment.fs"),
				BlockPreview.class);
		
		System.gc();
	}

	public static void init() throws Exception {
		transformation = new Transformation();
		loadShader();

		inited = true;
	}

	public static void clear() {
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
	}
	
	public static FrameBuffer generateBuffer(Window window, Vector3f ambientLight, Block block) {
		FrameBuffer buffer = new FrameBuffer();
		buffer.genColorTexture(64, 64);
		buffer.genRenderbuffer(64, 64);
		buffer.bind();
		window.setRenderTarget(buffer);
		window.setClearColor(new Vector4f(0f, 0f, 0f, 0f));
		
		Mesh mesh = Meshes.blockMeshes.get(block);
		Spatial spatial = new Spatial(mesh);
		
		glViewport(0, 0, 64, 64);
		Matrix4f projectionMatrix = transformation.getProjectionMatrix(0.013f, 1f, 1f, 0.1f, 10000.0f);//.getOrthoProjectionMatrix(0.9f, -0.9f, -0.9f, 0.9f, 0.1f, 1000.0f);
		clear();
		Matrix4f viewMatrix = transformation.getViewMatrix(new Vector3f(64, 90.3f, 64), new Vector3f(3*(float)Math.PI/4, 3*(float)Math.PI/4, 0));

		shader.bind();
		shader.setUniform(loc_projectionMatrix, projectionMatrix);
		shader.setUniform(loc_texture_sampler, 0);
		shader.setUniform(loc_dirLight, new Vector3f(2, -2, 1.5f).normalize());
		
		shader.setUniform(loc_light, new Vector3f(1, 1, 1));
		mesh.getMaterial().setTexture(Meshes.blockTextures.get(block));
		mesh.renderOne(() -> {
			Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(
					Transformation.getModelMatrix(spatial.getPosition(), spatial.getRotation(), spatial.getScale()),
					viewMatrix);
			shader.setUniform(loc_viewMatrix, modelViewMatrix);
		});
		
		shader.unbind();
		glViewport(0, 0, window.getWidth(), window.getHeight());
		
		window.setRenderTarget(null);
		return buffer;
	}

	public static void cleanup() {
		if (shader != null) {
			shader.cleanup();
			shader = null;
		}
	}

	public static void setPath(String dataName, String path) {
		if (dataName.equals("shaders") || dataName.equals("shadersFolder")) {
			if (inited) {
				try {
					unloadShader();
					shaders = path;
					loadShader();
				} catch (Exception e) {
					Logger.throwable(e);
				}
			} else {
				shaders = path;
			}
		}
	}
}
