package cubyz.client.loading;

import java.util.ArrayList;

import cubyz.client.*;
import cubyz.utils.Logger;
import cubyz.api.CubyzRegistries;
import cubyz.api.Resource;
import cubyz.api.Side;
import cubyz.gui.menu.LoadingGUI;
import cubyz.modding.ModLoader;
import cubyz.rendering.Mesh;
import cubyz.rendering.ModelLoader;
import cubyz.utils.ResourceContext;
import cubyz.utils.ResourceManager;
import cubyz.world.blocks.Blocks;
import cubyz.world.entity.EntityType;

/**
 * Loads all mods.
 */

public class LoadThread extends Thread {

	static int i = -1;
	static Runnable run;
	static ArrayList<Runnable> runnables = new ArrayList<>();
	
	public static void addOnLoadFinished(Runnable run) {
		runnables.add(run);
	}
	
	public void run() {
		setName("Load-Thread");
		Cubyz.renderDeque.add(ClientSettings::load); // run in render thread due to some graphical reasons
		LoadingGUI l = LoadingGUI.getInstance();
		l.setStep(1, 0, 0);
		// TODO: remove this step as there appears to be nothing
		
		l.setStep(2, 0, 0); // load mods
		ModLoader.load(Side.CLIENT);
		
		Object lock = new Object();
		run = () -> {
			i++;
			boolean finishedMeshes = false;
			if (i < CubyzRegistries.ENTITY_REGISTRY.size()) {
				if (i < CubyzRegistries.ENTITY_REGISTRY.size()) {
					EntityType e = CubyzRegistries.ENTITY_REGISTRY.registered(new EntityType[0])[i];
					if (!e.useDynamicEntityModel()) {
						Meshes.createEntityMesh(e);
					}
				}
				if (i < Blocks.size()-1 || i < CubyzRegistries.ENTITY_REGISTRY.size()-1) {
					Cubyz.renderDeque.add(run);
					l.setStep(4, i+1, Blocks.size());
				} else {
					finishedMeshes = true;
					synchronized (lock) {
						lock.notifyAll();
					}
				}
			} else {
				finishedMeshes = true;
				synchronized (lock) {
					lock.notifyAll();
				}
			}
			if (finishedMeshes) {
				try {
					Resource res = new Resource("cubyz:sky_body.obj");
					String path = ResourceManager.lookupPath(ResourceManager.contextToLocal(ResourceContext.MODEL3D, res));
					GameLauncher.logic.skyBodyMesh = new Mesh(ModelLoader.loadModel(res, path));
				} catch (Exception e) {
					Logger.warning(e);
				}
			}
		};
		Cubyz.renderDeque.add(run);
		try {
			synchronized (lock) {
				lock.wait();
			}
		} catch (InterruptedException e) {
			return;
		}
		l.setStep(5, 0, 0);

		l.finishLoading();
		
		for (Runnable r : runnables) {
			r.run();
		}
		
		System.gc();
	}
	
}
