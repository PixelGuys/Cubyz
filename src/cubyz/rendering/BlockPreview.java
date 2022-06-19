package cubyz.rendering;

import static org.lwjgl.opengl.GL43.*;

import org.joml.Matrix4f;
import org.joml.Vector3f;
import org.joml.Vector4f;

import cubyz.utils.Logger;
import cubyz.client.BlockMeshes;
import cubyz.client.Meshes;
import cubyz.utils.Utils;
import cubyz.world.Neighbors;
import cubyz.world.blocks.Blocks;

/**
 * Used for rendering block preview images in the inventory.
 */

public abstract class BlockPreview {
	// Uniform locations:
	public static int loc_projectionMatrix;
	public static int loc_viewMatrix;
	public static int loc_texture_sampler;
	public static int loc_emissionSampler;
	public static int loc_light;
	public static int loc_dirLight;
	public static int loc_texPosX;
	public static int loc_texNegX;
	public static int loc_texPosY;
	public static int loc_texNegY;
	public static int loc_texPosZ;
	public static int loc_texNegZ;
	
	private static ShaderProgram shader;

	private static boolean inited = false;
	private static Transformation transformation;
	private static String shaders = "";

	public static void setShaderFolder(String shaders) {
		BlockPreview.shaders = shaders;
	}

	public static void unloadShader() {
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
	
	public static Texture generateTexture(int block) {
		Mesh mesh = BlockMeshes.mesh(block & Blocks.TYPE_MASK);
		if(mesh == null) {
			BlockMeshes.loadMeshes(); // Loads all meshes that weren't loaded yet.
			mesh = BlockMeshes.mesh(block & Blocks.TYPE_MASK);
		}

		glEnable(GL_DEPTH_TEST);
		glEnable(GL_CULL_FACE);
		FrameBuffer buffer = new FrameBuffer();
		buffer.genColorTexture(64, 64, GL_NEAREST, GL_REPEAT);
		buffer.genRenderBuffer(64, 64);
		buffer.bind();
		Window.setRenderTarget(buffer);
		Window.setClearColor(new Vector4f(0, 0, 0, 0));

		Spatial spatial = new Spatial(mesh);
		
		glViewport(0, 0, 64, 64);
		Matrix4f projectionMatrix = new Matrix4f();
		Transformation.updateProjectionMatrix(projectionMatrix, 0.013f, 1, 1, 60, 200.0f);
		clear();
		Matrix4f viewMatrix = transformation.getViewMatrix(new Vector3f(64, 90.3f, 64), new Vector3f(3*(float)Math.PI/4, 3*(float)Math.PI/4, 0));

		shader.bind();
		shader.setUniform(loc_projectionMatrix, projectionMatrix);
		shader.setUniform(loc_texture_sampler, 0);
		shader.setUniform(loc_emissionSampler, 1);
		shader.setUniform(loc_dirLight, new Vector3f(2, -2, 1.5f).normalize());
		
		shader.setUniform(loc_light, new Vector3f(1, 1, 1));
		glActiveTexture(GL_TEXTURE0);
		Meshes.blockTextureArray.bind();
		glActiveTexture(GL_TEXTURE1);
		Meshes.emissionTextureArray.bind();
		mesh.setTexture(null);
		shader.setUniform(loc_texNegX, BlockMeshes.textureIndices(block)[Neighbors.DIR_NEG_X]);
		shader.setUniform(loc_texPosX, BlockMeshes.textureIndices(block)[Neighbors.DIR_POS_X]);
		shader.setUniform(loc_texNegY, BlockMeshes.textureIndices(block)[Neighbors.DIR_DOWN]);
		shader.setUniform(loc_texPosY, BlockMeshes.textureIndices(block)[Neighbors.DIR_UP]);
		shader.setUniform(loc_texNegZ, BlockMeshes.textureIndices(block)[Neighbors.DIR_NEG_Z]);
		shader.setUniform(loc_texPosZ, BlockMeshes.textureIndices(block)[Neighbors.DIR_POS_Z]);
		mesh.renderOne(() -> {
			Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(
					Transformation.getModelMatrix(spatial.getPosition(), spatial.getRotation(), spatial.getScale()),
					viewMatrix);
			shader.setUniform(loc_viewMatrix, modelViewMatrix);
		});
		
		shader.unbind();
		glViewport(0, 0, Window.getWidth(), Window.getHeight());
		
		Window.setRenderTarget(null);
		glDisable(GL_CULL_FACE);
		glDisable(GL_DEPTH_TEST);
		Texture result = buffer.getColorTextureAndTakeResponsibilityToDeleteIt();
		buffer.delete();
		return result;
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
					Logger.error(e);
				}
			} else {
				shaders = path;
			}
		}
	}
}
