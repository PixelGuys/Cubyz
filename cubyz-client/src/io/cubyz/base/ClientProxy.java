package io.cubyz.base;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.GameRegistry;
import io.cubyz.api.Registry;
import io.cubyz.base.rotation.LogRotation;
import io.cubyz.base.rotation.NoRotation;
import io.cubyz.base.rotation.TorchRotation;
import io.cubyz.blocks.RotationMode;

public class ClientProxy extends CommonProxy {

	public void init() {
		super.init();
		GameRegistry.registerGUI("cubyz:workbench", new WorkbenchGUI());
	}
	
	public void preInit() {
		registerRotationModes(CubyzRegistries.ROTATION_MODE_REGISTRY);
	}

	private void registerRotationModes(Registry<RotationMode> reg) {
		reg.register(new NoRotation());
		reg.register(new TorchRotation());
		reg.register(new LogRotation());
	}
	
}
