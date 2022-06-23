package cubyz.client;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

import cubyz.Constants;
import cubyz.utils.Logger;
import cubyz.Settings;
import cubyz.gui.input.Keybindings;
import cubyz.rendering.Window;
import cubyz.utils.DiscordIntegration;
import cubyz.utils.translate.LanguageLoader;
import pixelguys.json.JsonObject;
import pixelguys.json.JsonParser;

/**
 * Stores are variables that can be modified in the settings.<br>
 * Also handles saving and loading them.
 */

public final class ClientSettings {
	private ClientSettings() {} // No instances allowed.

	public static float FOG_COEFFICIENT = 10f;

	public static boolean BLOOM = true;
	
	public static boolean MIPMAPPING = false;
	
	public static int RENDER_DISTANCE = 4;
	
	/**Scaling factor that scales the size of the LOD region and by that scaling the effective render distance.*/
	public static float LOD_FACTOR = 2.0f;
	
	public static float FOV = 70.0f;

	public static boolean easyLighting = true; // Enables the easy-lighting system.

	public static int GUI_SCALE = 2;

	public static boolean musicOnOff = true; //Turn on or off the music

	public static float mouseSensitivity = 1;

	public static String playerName = null;

	public static String lastUsedIPAddress = "localhost";
	

	/**Not actually a setting, but stored here anyways.*/
	public static int EFFECTIVE_RENDER_DISTANCE = calculatedEffectiveRenderDistance();
	
	public static int calculatedEffectiveRenderDistance() {
		return RENDER_DISTANCE + (((int)(RENDER_DISTANCE*LOD_FACTOR) & ~1) << Constants.HIGHEST_LOD);
	}

	public static void save() {
		JsonObject settings = new JsonObject();
		JsonObject keyBindings = new JsonObject();
		
		for (String name : Keybindings.keyNames) {
			int keyCode = Keybindings.getKeyCode(name);
			keyBindings.put(name, keyCode);
		}
		
		settings.put("keybindings", keyBindings);
		settings.put("language", Settings.getLanguage().getLocale());
		settings.put("discordIntegration", DiscordIntegration.isEnabled());
		settings.put("fogCoefficient", ClientSettings.FOG_COEFFICIENT);
		settings.put("bloom", ClientSettings.BLOOM);
		settings.put("useMipmaps", ClientSettings.MIPMAPPING);
		settings.put("vsync", Window.isVSyncEnabled());
		settings.put("antiAliasSamples", Window.getAntialiasSamples());
		settings.put("easyLighting", ClientSettings.easyLighting);
		settings.put("renderDistance", ClientSettings.RENDER_DISTANCE);
		settings.put("farDistanceFactor", ClientSettings.LOD_FACTOR);
		settings.put("fieldOfView", ClientSettings.FOV);
		settings.put("musicOnOff", ClientSettings.musicOnOff);
		settings.put("mouseSensitivity", ClientSettings.mouseSensitivity);
		if(ClientSettings.playerName != null)
			settings.put("playerName", ClientSettings.playerName);
		settings.put("lastUsedIPAddress", ClientSettings.lastUsedIPAddress);

		try {
			FileWriter writer = new FileWriter("settings.json", StandardCharsets.UTF_8);
			writer.append(settings.toString());
			writer.close();
		} catch (IOException e) {
			Logger.warning(e);
		}
	}
	
	public static void load() {
		if (!new File("settings.json").exists()) {
			Settings.setLanguage(LanguageLoader.load("en_US"));
			return;
		}
		
		JsonObject settings = JsonParser.parseObjectFromFile("settings.json");
		
		JsonObject keyBindings = settings.getObject("keybindings");
		if (keyBindings != null) {
			for (String name : keyBindings.map.keySet()) {
				Keybindings.setKeyCode(name, keyBindings.getInt(name, Keybindings.getKeyCode(name)));
			}
		}
		
		Settings.setLanguage(LanguageLoader.load(settings.getString("language", "en_US")));
		
		if (settings.getBool("discordIntegration", false)) {
			DiscordIntegration.startRPC();
		}

		FOG_COEFFICIENT = settings.getFloat("fogCoefficient", FOG_COEFFICIENT);

		BLOOM = settings.getBool("fogCoefficient", BLOOM);
		
		MIPMAPPING = settings.getBool("useMipmaps", MIPMAPPING);

		Window.setVSyncEnabled(settings.getBool("vsync", true));

		easyLighting = settings.getBool("easyLighting", easyLighting);

		RENDER_DISTANCE = settings.getInt("renderDistance", RENDER_DISTANCE);
		
		LOD_FACTOR = settings.getFloat("farDistanceFactor", LOD_FACTOR);
		
		FOV = settings.getFloat("fieldOfView", FOV);

		EFFECTIVE_RENDER_DISTANCE = calculatedEffectiveRenderDistance();

		musicOnOff = settings.getBool("musicOnOff", musicOnOff);

		mouseSensitivity = settings.getFloat("mouseSensitivity", mouseSensitivity);

		playerName = settings.getString("playerName", playerName);

		lastUsedIPAddress = settings.getString("lastUsedIPAddress", lastUsedIPAddress);
	}
	
}
