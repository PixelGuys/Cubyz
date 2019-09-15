package io.cubyz.base;

import org.lwjgl.glfw.GLFW;

import io.cubyz.Keybindings;
import io.cubyz.api.GameRegistry;

public class ClientProxy extends CommonProxy {

	public void init() {
		super.init();
		GameRegistry.registerGUI("cubyz:workbench", new WorkbenchGUI());
	}
	
}
