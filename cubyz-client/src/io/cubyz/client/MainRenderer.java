package io.cubyz.client;

import static org.lwjgl.opengl.GL11.*;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import org.joml.Vector4f;
import org.jungle.Mesh;
import org.jungle.Spatial;
import org.jungle.Window;
import org.jungle.game.Context;
import org.jungle.renderers.IRenderer;
import org.jungle.renderers.Transformation;
import org.jungle.renderers.jungle.FrustumCullingFilter;
import org.jungle.renderers.jungle.JungleTransformation;
import org.jungle.util.DirectionalLight;
import org.jungle.util.PointLight;
import org.jungle.util.ShaderProgram;
import org.jungle.util.SpotLight;
import org.jungle.util.Utils;

import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.world.Chunk;

/**
 * 
 * @author zenith391
 *
 */
public class MainRenderer implements IRenderer {

	private ShaderProgram shaderProgram;
	
	private static final float Z_NEAR = 0.01f;
	private static final float Z_FAR = 1000.0f;
	private boolean inited = false;
	private boolean doRender = true;
	private Transformation transformation;
	private String shaders = "res/shaders/default";
	private FrustumCullingFilter filter;

	public static final int MAX_POINT_LIGHTS = 5;
	public static final int MAX_SPOT_LIGHTS = 5;
	private float specularPower = 16f;

	public MainRenderer() {

	}
	
	public Transformation getTransformation() {
		return transformation;
	}
	
	public void setShaderFolder(String shaders) {
		this.shaders = shaders;
	}
	
	public void unloadShaders() throws Exception {
		shaderProgram.unbind();
		shaderProgram.cleanup();
		shaderProgram = null;
		System.gc();
	}
	
	public void setDoRender(boolean doRender) {
		this.doRender = doRender;
	}
	
	public void loadShaders() throws Exception {
		shaderProgram = new ShaderProgram();
		shaderProgram.createVertexShader(Utils.loadResource(shaders + "/vertex.vs"));
		shaderProgram.createFragmentShader(Utils.loadResource(shaders + "/fragment.fs"));
		shaderProgram.link();
		shaderProgram.createUniform("projectionMatrix");
		shaderProgram.createUniform("modelViewMatrix");
		shaderProgram.createUniform("texture_sampler");
		shaderProgram.createUniform("ambientLight");
		shaderProgram.createUniform("selected");
		shaderProgram.createUniform("specularPower");
		shaderProgram.createMaterialUniform("material");
		shaderProgram.createPointLightListUniform("pointLights", MAX_POINT_LIGHTS);
		shaderProgram.createSpotLightListUniform("spotLights", MAX_SPOT_LIGHTS);
		shaderProgram.createDirectionalLightUniform("directionalLight");
	}

	@Override
	public void init(Window window) throws Exception {
		transformation = new JungleTransformation();
		window.setProjectionMatrix(transformation.getProjectionMatrix((float) Math.toRadians(70.0f), window.getWidth(), window.getHeight(), Z_NEAR,
				Z_FAR));
		loadShaders();
		
		if (window.getOptions().frustumCulling) {
			filter = new FrustumCullingFilter();
		}
		
		inited = true;
	}

	public void clear() {
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
	}

	
	@SuppressWarnings("unchecked")
	public void render(Window window, Context ctx, Vector3f ambientLight, DirectionalLight directionalLight, Chunk[] chunks, Block [] blocks) {
		if (window.isResized()) {
			glViewport(0, 0, window.getWidth(), window.getHeight());
			window.setResized(false);
			window.setProjectionMatrix(transformation.getProjectionMatrix(ctx.getCamera().getFov(), window.getWidth(), window.getHeight(), Z_NEAR,
					Z_FAR));
		}
		if (!doRender)
			return;
		clear();
		ctx.getCamera().setViewMatrix(transformation.getViewMatrix(ctx.getCamera()));
		List<Spatial> [] map;
		map = (List<Spatial>[])new List[blocks.length];
		for(int i = 0; i < map.length; i++) {
			map[i] = new ArrayList<Spatial>();
		}
		for (Chunk ch : chunks) {
			List<BlockInstance> vis = ch.getVisibles();
		    for (int i = 0; i < vis.size(); i++) {
		    	map[vis.get(i).getID()].add((Spatial) vis.get(i).getSpatial());
		    }
		}
		if (filter != null) {
			filter.updateFrustum(window.getProjectionMatrix(), ctx.getCamera().getViewMatrix());
			HashMap<Mesh, List<Spatial>> m = new HashMap<>();
			for (int i = 0; i < blocks.length; i++) {
				m.put((Mesh) blocks[i].getBlockPair().get("meshCache"), map[i]);
			}
			filter.filter(m);
		}
		renderScene(ctx, ambientLight, null /* point light */, null /* spot light */, directionalLight, map, blocks);
		ctx.getHud().render(window);
	}
	
	public void renderScene(Context ctx, Vector3f ambientLight, PointLight[] pointLightList, SpotLight[] spotLightList, DirectionalLight directionalLight, List<Spatial> [] map, Block [] blocks) {
		shaderProgram.bind();

		shaderProgram.setUniform("projectionMatrix", ctx.getWindow().getProjectionMatrix());
		shaderProgram.setUniform("texture_sampler", 0);

		Matrix4f viewMatrix = ctx.getCamera().getViewMatrix();
		
		renderLights(viewMatrix, ambientLight, pointLightList, spotLightList, directionalLight);

		for (int i = 0; i < blocks.length; i++) {
			Mesh mesh = (Mesh) blocks[i].getBlockPair().get("meshCache");
		    shaderProgram.setUniform("material", mesh.getMaterial());
		    mesh.renderList(map[i], (Spatial gameItem) -> {
		    	if (gameItem.isInFrustum() || filter == null) {
		    		Matrix4f modelViewMatrix = transformation.getModelViewMatrix(gameItem, viewMatrix);
			        shaderProgram.setUniform("selected", gameItem.isSelected() ? 1f : 0f);
			        shaderProgram.setUniform("modelViewMatrix", modelViewMatrix);
			        return true;
		    	}
		    	return false;
		    });
		}
		
		shaderProgram.unbind();
	}

	private void renderLights(Matrix4f viewMatrix, Vector3f ambientLight, PointLight[] pointLightList,
			SpotLight[] spotLightList, DirectionalLight directionalLight) {

		shaderProgram.setUniform("ambientLight", ambientLight);
		shaderProgram.setUniform("specularPower", specularPower);

		// Process Point Lights
		int numLights = pointLightList != null ? pointLightList.length : 0;
		for (int i = 0; i < numLights; i++) {
			// Get a copy of the point light object and transform its position to view
			// coordinates
			PointLight currPointLight = new PointLight(pointLightList[i]);
			Vector3f lightPos = currPointLight.getPosition();
			Vector4f aux = new Vector4f(lightPos, 1);
			aux.mul(viewMatrix);
			lightPos.x = aux.x;
			lightPos.y = aux.y;
			lightPos.z = aux.z;
			shaderProgram.setUniform("pointLights", currPointLight, i);
		}

		// Process Spot Ligths
		numLights = spotLightList != null ? spotLightList.length : 0;
		for (int i = 0; i < numLights; i++) {
			// Get a copy of the spot light object and transform its position and cone
			// direction to view coordinates
			SpotLight currSpotLight = new SpotLight(spotLightList[i]);
			Vector4f dir = new Vector4f(currSpotLight.getConeDirection(), 0);
			dir.mul(viewMatrix);
			currSpotLight.setConeDirection(new Vector3f(dir.x, dir.y, dir.z));
			Vector3f lightPos = currSpotLight.getPointLight().getPosition();

			Vector4f aux = new Vector4f(lightPos, 1);
			aux.mul(viewMatrix);
			lightPos.x = aux.x;
			lightPos.y = aux.y;
			lightPos.z = aux.z;

			shaderProgram.setUniform("spotLights", currSpotLight, i);
		}

		// Get a copy of the directional light object and transform its position to view
		// coordinates
		DirectionalLight currDirLight = new DirectionalLight(directionalLight);
		Vector4f dir = new Vector4f(currDirLight.getDirection(), 0);
		//dir.mul(viewMatrix);
		currDirLight.setDirection(new Vector3f(dir.x, dir.y, dir.z));
		shaderProgram.setUniform("directionalLight", currDirLight);

	}

	@Override
	public void cleanup() {
		if (shaderProgram != null) {
			shaderProgram.cleanup();
		}
	}

	@Override
	public void render(Window win, Context ctx, Vector3f ambientLight, PointLight[] pointLightList,
			SpotLight[] spotLightList, DirectionalLight directionalLight) {
		// do nothing
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
