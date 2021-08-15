package cubyz.client;

import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;

import cubyz.Logger;
import cubyz.Settings;
import cubyz.gui.input.Keybindings;
import cubyz.utils.DiscordIntegration;
import cubyz.utils.translate.LanguageLoader;

/**
 * Stores are variables that can be modified in the settings.<br>
 * Also handles saving and loading them.
 */

public class ClientSettings {

	public static float FOG_COEFFICIENT = 10f;
	
	public static boolean MIPMAPPING = false;
	
	public static int RENDER_DISTANCE = 4;
	
	/**maximum quality reduction.*/
	public static int HIGHEST_LOD = 4;
	
	/**Scaling factor that scales the size of the LOD region and by that scaling the effective render distance.*/
	public static float LOD_FACTOR = 2.0f;
	
	public static float FOV = 70.0f;
	
	public static boolean easyLighting = true; // Enables the easy-lighting system.
	

	/**Not actually a setting, but stored here anyways.*/
	public static int EFFECTIVE_RENDER_DISTANCE = (ClientSettings.RENDER_DISTANCE + ((((int)(ClientSettings.RENDER_DISTANCE*ClientSettings.LOD_FACTOR) & ~1) << ClientSettings.HIGHEST_LOD)));
	
	public static final Gson GSON =
			new GsonBuilder()
			.setPrettyPrinting()
			.create();
	
	public static void save() {
		JsonObject settings = new JsonObject();
		JsonObject keyBindings = new JsonObject();
		
		for (String name : Keybindings.keyNames) {
			int keyCode = Keybindings.getKeyCode(name);
			keyBindings.addProperty(name, keyCode);
		}
		
		settings.add("keybindings", keyBindings);
		settings.addProperty("language", Settings.getLanguage().getLocale());
		settings.addProperty("discordIntegration", DiscordIntegration.isEnabled());
		settings.addProperty("fogCoefficient", ClientSettings.FOG_COEFFICIENT);
		settings.addProperty("useMipmaps", ClientSettings.MIPMAPPING);
		settings.addProperty("vsync", Cubyz.window.isVSyncEnabled());
		settings.addProperty("antiAliasSamples", Cubyz.window.getAntialiasSamples());
		settings.addProperty("easyLighting", ClientSettings.easyLighting);
		settings.addProperty("renderDistance", ClientSettings.RENDER_DISTANCE);
		settings.addProperty("highestLOD", ClientSettings.HIGHEST_LOD);
		settings.addProperty("farDistanceFactor", ClientSettings.LOD_FACTOR);
		settings.addProperty("fieldOfView", ClientSettings.FOV);
		
		try {
			FileWriter writer = new FileWriter("settings.json");
			GSON.toJson(settings, writer);
			writer.close();
		} catch (IOException e) {
			Logger.throwable(e);
		}
	}
	
	public static void load() {
		if (!new File("settings.json").exists()) {
			Settings.setLanguage(LanguageLoader.load("en_US"));
			return;
		}
		
		JsonObject settings = null;
		try {
			FileReader reader = new FileReader("settings.json");
			settings = GSON.fromJson(reader, JsonObject.class);
			reader.close();
		} catch (IOException e) {
			Logger.throwable(e);
		}
		
		if (settings.has("keybindings")) {
			JsonObject keyBindings = settings.getAsJsonObject("keybindings");
			for (String name : keyBindings.keySet()) {
				Keybindings.setKeyCode(name, keyBindings.get(name).getAsInt());
			}
		}
		
		if (!settings.has("language"))
			settings.addProperty("language", "en_US");
		Settings.setLanguage(LanguageLoader.load(settings.get("language").getAsString()));
		
		if (settings.has("discordIntegration")) {
			if (settings.get("discordIntegration").getAsBoolean()) {
				DiscordIntegration.startRPC();
			}
		}
		
		if (settings.has("fogCoefficient")) {
			ClientSettings.FOG_COEFFICIENT = settings.get("fogCoefficient").getAsFloat();
		}
		
		if (settings.has("useMipmaps")) {
			ClientSettings.MIPMAPPING = settings.get("useMipmaps").getAsBoolean();
		}
		if (settings.has("vsync")) {
			Cubyz.window.setVSyncEnabled(settings.get("vsync").getAsBoolean());
		} else { // V-Sync enabled by default
			Cubyz.window.setVSyncEnabled(true);
		}

		if (settings.has("easyLighting")) {
			ClientSettings.easyLighting = settings.get("easyLighting").getAsBoolean();
		}
		if (settings.has("renderDistance")) {
			ClientSettings.RENDER_DISTANCE = settings.get("renderDistance").getAsInt();
		}
		if (settings.has("highestLOD")) {
			ClientSettings.HIGHEST_LOD = settings.get("highestLOD").getAsInt();
		}
		if (settings.has("farDistanceFactor")) {
			ClientSettings.LOD_FACTOR = settings.get("farDistanceFactor").getAsInt();
		}
		if (settings.has("fieldOfView")) {
			ClientSettings.FOV = settings.get("fieldOfView").getAsFloat();
		}
	}
	
}
