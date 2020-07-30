package io.cubyz.client;

import static org.lwjgl.opengl.GL11C.GL_COLOR_BUFFER_BIT;
import static org.lwjgl.opengl.GL11C.GL_DEPTH_BUFFER_BIT;
import static org.lwjgl.opengl.GL11C.GL_STENCIL_BUFFER_BIT;
import static org.lwjgl.opengl.GL11C.glClear;
import static org.lwjgl.opengl.GL11C.glViewport;

import org.joml.Matrix4f;
import org.joml.Vector3f;
import org.joml.Vector4f;

import io.cubyz.blocks.Block;
import io.jungle.FrameBuffer;
import io.jungle.Mesh;
import io.jungle.Spatial;
import io.jungle.Window;
import io.jungle.renderers.Transformation;
import io.jungle.util.ShaderProgram;
import io.jungle.util.Utils;

// Used for rendering block preview images in the inventory.

public abstract class BlockPreview {
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
		shader = new ShaderProgram();
		shader.createVertexShader(Utils.loadResource(shaders + "/vertex.vs"));
		shader.createFragmentShader(Utils.loadResource(shaders + "/fragment.fs"));
		shader.link();
		shader.createUniform("projectionMatrix");
		shader.createUniform("viewMatrix");
		shader.createUniform("texture_sampler");
		shader.createUniform("light");
		shader.createUniform("dirLight");
		
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
	
	public static FrameBuffer generateBuffer(Window window, Vector3f ambientLight, Block b) {
		FrameBuffer buf = new FrameBuffer();
		buf.genColorTexture(64, 64);
		buf.genRenderbuffer(64, 64);
		buf.bind();
		window.setRenderTarget(buf);
		window.setClearColor(new Vector4f(0f, 0f, 0f, 0f));
		
		Spatial spatial = new Spatial(Meshes.blockMeshes.get(b));
		spatial.getMesh().getMaterial().setTexture(Meshes.blockTextures.get(b));
		
		glViewport(0, 0, 64, 64);
		Matrix4f projectionMatrix = transformation.getOrthoProjectionMatrix(0.9f, -0.9f, -0.9f, 0.9f, 0.1f, 1000.0f);
		clear();
		Matrix4f viewMatrix = transformation.getViewMatrix(new Vector3f(1, 1.5f, 1), new Vector3f((float)Math.PI/4, -(float)Math.PI/4, 0));

		shader.bind();
		shader.setUniform("projectionMatrix", projectionMatrix);
		shader.setUniform("texture_sampler", 0);
		shader.setUniform("dirLight", new Vector3f(-1, -2, -2).normalize());
		
		Mesh mesh = spatial.getMesh();
		shader.setUniform("light", new Vector3f(1, 1, 1));
		mesh.renderOne(() -> {
			Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(
					Transformation.getModelMatrix(spatial.getPosition(), spatial.getRotation(), spatial.getScale()),
					viewMatrix);
			shader.setUniform("viewMatrix", modelViewMatrix);
		});
		
		shader.unbind();
		glViewport(0, 0, window.getWidth(), window.getHeight());
		
		window.setRenderTarget(null);
		
		return buf;
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
					e.printStackTrace();
				}
			} else {
				shaders = path;
			}
		}
	}
}
