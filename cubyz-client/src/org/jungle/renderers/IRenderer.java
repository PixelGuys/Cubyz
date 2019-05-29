package org.jungle.renderers;

import org.joml.Vector3f;
import org.jungle.Window;
import org.jungle.game.Context;
import org.jungle.util.DirectionalLight;
import org.jungle.util.PointLight;
import org.jungle.util.SpotLight;

public interface IRenderer {

	public abstract void init(Window win) throws Exception;
	public abstract void render(Window win, Context ctx, Vector3f ambientLight,
			PointLight[] pointLightList, SpotLight[] spotLightList, DirectionalLight directionalLight);
	public abstract void cleanup();
	public abstract void setPath(String dataName, String path);
	public abstract Transformation getTransformation();
	
}
