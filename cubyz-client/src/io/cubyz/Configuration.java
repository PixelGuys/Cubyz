package io.cubyz;

import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;

import io.cubyz.client.Cubyz;
import io.cubyz.translate.LanguageLoader;
import io.cubyz.utils.DiscordIntegration;

public class Configuration {

	public static final Gson GSON =
			new GsonBuilder()
			.setPrettyPrinting()
			.create();
	
	public static void save() {
		JsonObject obj = new JsonObject();
		JsonObject kb = new JsonObject();
		
		for (String name : Keybindings.keyNames) {
			int keyCode = Keybindings.getKeyCode(name);
			kb.addProperty(name, keyCode);
		}
		
		obj.add("keybindings", kb);
		obj.addProperty("language", Cubyz.lang.getLocale());
		obj.addProperty("discordIntegration", DiscordIntegration.isEnabled());
		obj.addProperty("fogCoefficient", Settings.fogCoefficient);
		obj.addProperty("useMipmaps", Settings.mipmapping);
		obj.addProperty("vsync", Cubyz.ctx.getWindow().isVSyncEnabled());
		obj.addProperty("antiAliasSamples", Cubyz.ctx.getWindow().getAntialiasSamples());
		
		try {
			FileWriter writer = new FileWriter("configuration.json");
			GSON.toJson(obj, writer);
			writer.close();
		} catch (IOException e) {
			e.printStackTrace();
		}
	}
	
	public static void load() {
		if (!new File("configuration.json").exists()) {
			Cubyz.lang = LanguageLoader.load("en_US");
			return;
		}
		
		JsonObject obj = null;
		try {
			FileReader reader = new FileReader("configuration.json");
			obj = GSON.fromJson(reader, JsonObject.class);
			reader.close();
		} catch (IOException e) {
			e.printStackTrace();
		}
		
		if (obj.has("keybindings")) {
			JsonObject kb = obj.getAsJsonObject("keybindings");
			for (String name : kb.keySet()) {
				Keybindings.setKeyCode(name, kb.get(name).getAsInt());
			}
		}
		
		if (!obj.has("language"))
			obj.addProperty("language", "en_US");
		Cubyz.lang = LanguageLoader.load(obj.get("language").getAsString());
		
		if (obj.has("discordIntegration")) {
			if (obj.get("discordIntegration").getAsBoolean()) {
				DiscordIntegration.startRPC();
			}
		}
		
		if (obj.has("fogCoefficient")) {
			Settings.fogCoefficient = obj.get("fogCoefficient").getAsFloat(); // TODO: this shouldn't be in Settings, it's a client-only value
		}
		
		if (obj.has("useMipmaps")) {
			Settings.mipmapping = obj.get("useMipmaps").getAsBoolean();
		}
		if (obj.has("vsync")) {
			Cubyz.ctx.getWindow().setVSyncEnabled(obj.get("vsync").getAsBoolean());
		} else { // V-Sync enabled by default
			Cubyz.ctx.getWindow().setVSyncEnabled(true);
		}
	}
	
}
