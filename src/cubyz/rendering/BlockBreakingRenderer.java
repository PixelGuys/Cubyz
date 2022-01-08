package cubyz.rendering;

import org.joml.Vector3d;

import cubyz.client.BlockMeshes;
import cubyz.client.GameLauncher;
import cubyz.utils.Utils;
import cubyz.world.blocks.BlockInstance;

import static org.lwjgl.opengl.GL43.*;


/**
 * Draws the block breaking/selection texture on top of a block.
 */
public class BlockBreakingRenderer {
	// Shader stuff:
	public static int loc_projectionMatrix;
	public static int loc_viewMatrix;
	public static int loc_texture_sampler;
	public static int loc_modelPosition;

	public static ShaderProgram shader;

	public static void init(String shaderFolder) throws Exception {
		if (shader != null)
			shader.cleanup();
		shader = new ShaderProgram(Utils.loadResource(shaderFolder + "/block_breaking_vertex.vs"),
				Utils.loadResource(shaderFolder + "/block_breaking_fragment.fs"),
				BlockBreakingRenderer.class);
	}
	
	public static void render(BlockInstance selected, Vector3d playerPosition) {
		shader.bind();

		shader.setUniform(loc_projectionMatrix, Window.getProjectionMatrix());
		shader.setUniform(loc_texture_sampler, 0);
		shader.setUniform(loc_viewMatrix, Camera.getViewMatrix());
		
		float breakAnim = selected.breakAnim;
		glActiveTexture(GL_TEXTURE0);
		if (breakAnim > 0f && breakAnim < 1f) {
			int breakStep = (int)(breakAnim*(GameLauncher.logic.breakAnimations.length - 1)) + 1;
			glBindTexture(GL_TEXTURE_2D, GameLauncher.logic.breakAnimations[breakStep].getId());
		} else {
			glBindTexture(GL_TEXTURE_2D, GameLauncher.logic.breakAnimations[0].getId());
		}
		glUniform3f(loc_modelPosition, (float)(selected.x - playerPosition.x), (float)(selected.y - playerPosition.y), (float)(selected.z - playerPosition.z));
		Mesh mesh = BlockMeshes.mesh(selected.getBlock());
		glBindVertexArray(mesh.vaoId);
		glEnable(GL_POLYGON_OFFSET_FILL);
		glPolygonOffset(0.0f, -1.0f);
		mesh.render();
		glDisable(GL_POLYGON_OFFSET_FILL);
	}
}
