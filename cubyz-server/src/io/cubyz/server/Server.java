package io.cubyz.server;

import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.lang.reflect.InvocationTargetException;
import java.net.MalformedURLException;
import java.net.URL;
import java.net.URLClassLoader;
import java.util.ArrayList;
import java.util.Properties;
import java.util.Scanner;
import java.util.Set;

import org.reflections.Reflections;

import io.cubyz.Constants;
import io.cubyz.CubyzLogger;
import io.cubyz.api.Mod;
import io.cubyz.command.CommandExecutor;
import io.cubyz.command.ICommandSource;
import io.cubyz.modding.ModLoader;
import io.cubyz.multiplayer.server.CubyzServer;
import io.cubyz.multiplayer.server.ServerHandler;
import io.cubyz.world.World;

public class Server {

	static Properties serverProperties = new Properties();
	static CubyzServer server;
	
	public static void propertyDefault(String key, Object def) {
		serverProperties.setProperty(key, serverProperties.getOrDefault(key, def).toString());
	}
	
	public static void loadProperties() throws IOException {
		File f = new File("server.properties");
		if (f.exists()) {
			FileReader r = new FileReader(f);
			serverProperties.load(r);
			r.close();
		}
		
		propertyDefault("max-players", 20);
		propertyDefault("ping-time", 5000);
		propertyDefault("max-ping-time", 5000);
		propertyDefault("port", 58961);
		
		FileWriter writer = new FileWriter(f);
		serverProperties.store(writer, null);
		writer.close();
	}
	
	public static void loadGame() {
		CubyzLogger.instance.info("Searching mods..");
		ArrayList<Object> mods = new ArrayList<>();
		ArrayList<File> modSearchPath = new ArrayList<>();
		modSearchPath.add(new File("mods"));
		modSearchPath.add(new File("mods/" + Constants.GAME_VERSION));
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
		
		URLClassLoader loader = new URLClassLoader(modUrl.toArray(new URL[modUrl.size()]), Server.class.getClassLoader());
		
		CubyzLogger.instance.info("Searching Java classes..");
		Reflections reflections = new Reflections("", loader); // load all mods
		Set<Class<?>> allClasses = reflections.getTypesAnnotatedWith(Mod.class);
		
		for (Class<?> cl : allClasses) {
			try {
				mods.add(cl.getConstructor().newInstance());
			} catch (InstantiationException | IllegalAccessException | IllegalArgumentException
					| InvocationTargetException | NoSuchMethodException | SecurityException e) {
				e.printStackTrace();
			}
		}
		
		for (int i = 0; i < mods.size(); i++) {
			Object mod = mods.get(i);
			Mod modA = mod.getClass().getAnnotation(Mod.class);
			CubyzLogger.instance.info("Pre-initiating " + modA.name() + " (" + modA.id() + ")");
			ModLoader.preInit(mod);
		}
		
		for (int i = 0; i < mods.size(); i++) {
			Object mod = mods.get(i);
			Mod modA = mod.getClass().getAnnotation(Mod.class);
			CubyzLogger.instance.info("Initiating " + modA.name() + " (" + modA.id() + ")");
			ModLoader.init(mod);
		}
		
		for (int i = 0; i < mods.size(); i++) {
			Object mod = mods.get(i);
			Mod modA = mod.getClass().getAnnotation(Mod.class);
			CubyzLogger.instance.info("Post-initiating " + modA.name() + " (" + modA.id() + ")");
			ModLoader.postInit(mod);
		}
	}
	
	public static void main(String[] args) {
		CubyzLogger.instance.info("Loading configuration..");
		try {
			loadProperties();
		} catch (IOException e) {
			CubyzLogger.instance.severe("Error while loading configuration");
			e.printStackTrace();
		}
		
		loadGame();
		
		CubyzLogger.instance.info("Running server on port " + Integer.parseInt(serverProperties.getProperty("port")));
		
		server = new CubyzServer(Integer.parseInt(serverProperties.getProperty("port")));
		
		Thread th = new Thread(() -> {
			try {
				server.start(false);
			} catch (Exception e) {
				CubyzLogger.instance.severe("Error while starting the server");
				e.printStackTrace();
			}
			CubyzLogger.instance.info("Server stopped");
		});
		th.start();
		
		Scanner scan = new Scanner(System.in);
		
		ICommandSource console = new ICommandSource() {

			@Override
			public void feedback(String info) {
				CubyzLogger.instance.info(info);
			}

			@Override
			public World getWorld() {
				return ServerHandler.world;
			}
			
		};
		
		while (true) {
			String line = scan.nextLine();
			String[] parts = line.split(" ");
			
			if (parts[0].equals("stop")) {
				try {
					CubyzLogger.instance.info("Server stopping..");
					server.stop();
				} catch (Exception e) {
					CubyzLogger.instance.severe("Error while stopping the server");
					e.printStackTrace();
				}
				break;
			}
			else {
				CommandExecutor.execute(line, console);
			}
		}
		scan.close();
	}

}
