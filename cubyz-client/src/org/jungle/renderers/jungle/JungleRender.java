package org.jungle.renderers.jungle;

import static org.lwjgl.opengl.GL11.*;

import org.joml.Matrix4f;
import org.joml.Vector3f;
import org.joml.Vector4f;
import org.jungle.Mesh;
import org.jungle.Spatial;
import org.jungle.Window;
import org.jungle.game.Context;
import org.jungle.renderers.IRenderer;
import org.jungle.renderers.Transformation;
import org.jungle.util.DirectionalLight;
import org.jungle.util.PointLight;
import org.jungle.util.ShaderProgram;
import org.jungle.util.SpotLight;
import org.jungle.util.Utils;
import org.jungle.viewport.ViewportManager;

public class JungleRender implements IRenderer {

	private ShaderProgram shaderProgram;
	
	private static final float Z_NEAR = 0.01f;
	private static final float Z_FAR = 1000.0f;
	private boolean inited = false;
	private boolean orthogonal = false;
	private Transformation transformation;
	private String shaders = "example/shaders/default";
	private FrustumCullingFilter filter;

	public static int MAX_POINT_LIGHTS = 5;
	public static int MAX_SPOT_LIGHTS = 5;
	private float specularPower = 16f;
	
	public void setOrthogonal(boolean ortho) {
		orthogonal = ortho;
	}
	
	public void setMaxLights(int max) {
		MAX_POINT_LIGHTS = max;
		MAX_SPOT_LIGHTS = max;
	}
	
	public Transformation getTransformation() {
		return transformation;
	}
	
	public void setShaderFolder(String shaders) {
		if (inited)
			throw new UnsupportedOperationException();
		this.shaders = shaders;
	}

	@Override
	public void init(Window window) throws Exception {
		transformation = new JungleTransformation();
		if (!orthogonal) {
			window.setProjectionMatrix(transformation.getProjectionMatrix((float) Math.toRadians(70.0f), window.getWidth(), window.getHeight(), Z_NEAR, Z_FAR));
		} else {
			window.setProjectionMatrix(transformation.getOrthoProjectionMatrix(window.getWidth()/2, window.getWidth()/2, window.getHeight()/2, window.getHeight()/2));
		}
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
		
		if (window.getOptions().frustumCulling) {
			filter = new FrustumCullingFilter();
		}
		
		inited = true;
	}

	public void clear() {
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
	}

	@Override
	public void render(Window window, Context ctx, Vector3f ambientLight,
			PointLight[] pointLightList, SpotLight[] spotLightList, DirectionalLight directionalLight) {
		clear();
		if (window.isResized()) {
			ViewportManager manager = window.getViewportManager();
			glViewport(manager.getX(window), manager.getY(window), manager.getWidth(window), manager.getHeight(window));
			window.setResized(false);
			if (orthogonal) {
				window.setProjectionMatrix(transformation.getOrthoProjectionMatrix(-1, 1, -1, 1));
			} else {
				window.setProjectionMatrix(transformation.getProjectionMatrix(ctx.getCamera().getFov(), window.getWidth(), window.getHeight(), Z_NEAR, Z_FAR));
			}
		}
		ctx.getCamera().setViewMatrix(transformation.getViewMatrix(ctx.getCamera()));
		if (filter != null) {
			filter.updateFrustum(window.getProjectionMatrix(), ctx.getCamera().getViewMatrix());
			filter.filter(ctx.getMeshMap());
		}
		renderScene(window, ctx, ambientLight, pointLightList, spotLightList, directionalLight);
		ctx.getHud().render(window);
	}
	
	public void renderScene(Window window, Context ctx, Vector3f ambientLight, PointLight[] pointLightList, SpotLight[] spotLightList, DirectionalLight directionalLight) {
		shaderProgram.bind();

		
		shaderProgram.setUniform("projectionMatrix", ctx.getWindow().getProjectionMatrix());
		shaderProgram.setUniform("texture_sampler", 0);

		Matrix4f viewMatrix = ctx.getCamera().getViewMatrix();
		
		renderLights(viewMatrix, ambientLight, pointLightList, spotLightList, directionalLight);

		for (Mesh mesh : ctx.getMeshMap().keySet()) {
		    shaderProgram.setUniform("material", mesh.getMaterial());
		    mesh.renderList(ctx.getMeshMap().get(mesh), (Spatial gameItem) -> {
		    	if (!mesh.supportsFrustumCulling() || gameItem.isInFrustum() || filter == null) {
		    		Matrix4f modelViewMatrix = null;
		    		if (orthogonal) {
		    			modelViewMatrix = transformation.getOrtoProjModelMatrix(gameItem, window.getProjectionMatrix());
		    		} else {
		    			modelViewMatrix = transformation.getModelViewMatrix(gameItem, viewMatrix);
		    		}
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
	public void setPath(String dataName, String path) {
		if (dataName.equals("shaderFolder")) {
			setShaderFolder(path);
		}
	}

}
