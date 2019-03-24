package io.cubyz.client.loading;

import java.io.File;
import java.io.IOException;
import java.net.MalformedURLException;
import java.net.URL;
import java.net.URLClassLoader;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.Set;

import javax.swing.text.Utilities;

import org.reflections.Reflections;

import io.cubyz.Constants;
import io.cubyz.CubyzLogger;
import io.cubyz.api.CubzRegistries;
import io.cubyz.api.Mod;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.modding.ModLoader;

public class LoadThread extends Thread {

	static int i = -1;
	static Runnable run;
	
	public void run() {
		LoadingGUI l = LoadingGUI.getInstance();
		CubyzLogger log = CubyzLogger.instance;
		l.setStep(1, 0, 0);
		
		// RPC temporaly disabled
		//DiscordIntegration.startRPC();
		// Clean cache
		File cacheDir = new File("cache");
		if (cacheDir.exists()) {
			for (File f : cacheDir.listFiles()) {
				f.delete();
			}
			cacheDir.delete();
		}
		
		l.setStep(2, 0, 0); // load mods
		
		// Load Mods (via reflection)
		ArrayList<Object> mods = new ArrayList<>();
		ArrayList<File> modSearchPath = new ArrayList<>();
		modSearchPath.add(new File("mods"));
		modSearchPath.add(new File("mods/" + Constants.GAME_BUILD_TYPE + "_" + Constants.GAME_VERSION));
		ArrayList<URL> modUrl = new ArrayList<>();
		
		for (File sp : modSearchPath) {
			if (!sp.exists()) {
				sp.mkdirs();
			}
			for (File mod : sp.listFiles()) {
				if (mod.isFile()) {
					try {
						modUrl.add(mod.toURI().toURL());
						System.out.println("- Add " + mod.toURI().toURL());
					} catch (MalformedURLException e) {
						e.printStackTrace();
					}
				}
			}
		}
		
		URLClassLoader loader = new URLClassLoader(modUrl.toArray(new URL[modUrl.size()]), LoadThread.class.getClassLoader());
		log.info("Seeking mods..");
		try {
			//Enumeration<URL> urls = loader.findResources("CubeComputers");
			//System.out.println("URLs");
			//while (urls.hasMoreElements()) {
			//	URL url = urls.nextElement();
			//	System.out.println("URL - " + url);
			//}
		} catch (IOException e1) {
			e1.printStackTrace();
		}
		long start = System.currentTimeMillis();
		Reflections reflections = new Reflections("", loader); // load all mods
		Set<Class<?>> allClasses = reflections.getTypesAnnotatedWith(Mod.class);
		long end = System.currentTimeMillis();
		log.info("Took " + (end - start) + "ms for reflection");
		for (Class<?> cl : allClasses) {
			log.info("Mod class present: " + cl.getName());
			try {
				mods.add(cl.getConstructor().newInstance());
			} catch (Exception e) {
				log.warning("Error while loading mod:");
				e.printStackTrace();
			}
		}
		log.info("Mod list complete");
		
		// TODO re-add pre-init
		l.setStep(2, 0, mods.size());
		for (int i = 0; i < mods.size(); i++) {
			l.setStep(2, i+1, mods.size());
			Object mod = mods.get(i);
			log.info("Pre-initiating " + mod);
			//ModLoader.preInit(mod);
		}
		
		// Between pre-init and init code
		l.setStep(3, 0, mods.size());
		
		for (int i = 0; i < mods.size(); i++) {
			l.setStep(3, i+1, mods.size());
			Object mod = mods.get(i);
			log.info("Initiating " + mod);
			ModLoader.init(mod);
		}
		
		// TODO better account system
		//System.out.println("Loading UserProfile....");
		//Cubz.setProfile(new UserProfile(new UserSession("CubzPublicTest", "publictest@cubz.io", "@zka71a".toCharArray())));
		//System.out.println("UserProfile Loaded: UserProfile Name = '" + Cubz.getProfile().getName() + "' , UserProfile UUID = '" + Cubz.getProfile().getUUID() + "'.");
		
		// TODO Pre-loading meshes
		run = new Runnable() {
			public void run() {
				i++;
				Block b = (Block) CubzRegistries.BLOCK_REGISTRY.registered()[i];
				System.out.println("Creating mesh of " + b.getRegistryID());
				BlockInstance bi = new BlockInstance(b);
				bi.getMesh();
				if (i < CubzRegistries.BLOCK_REGISTRY.registered().length-1) {
					//Cubz.renderDeque.add(run);
					l.setStep(4, i+1, CubzRegistries.BLOCK_REGISTRY.registered().length);
				} else {
					l.finishLoading();
				}
			}
		};
		//Cubz.renderDeque.add(run);
		System.gc();
	}
	
}
