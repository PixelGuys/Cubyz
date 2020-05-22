package io.jungle.renderers;

import org.joml.Vector3f;

import io.jungle.Window;
import io.jungle.game.Context;
import io.jungle.util.DirectionalLight;
import io.jungle.util.PointLight;
import io.jungle.util.SpotLight;

public interface Renderer {

	public abstract void init(Window win) throws Exception;
	public abstract void render(Window win, Context ctx, Vector3f ambientLight,
			PointLight[] pointLightList, SpotLight[] spotLightList, DirectionalLight directionalLight);
	public abstract void cleanup();
	public abstract void setPath(String dataName, String path);
	public abstract Transformation getTransformation();
	
}
