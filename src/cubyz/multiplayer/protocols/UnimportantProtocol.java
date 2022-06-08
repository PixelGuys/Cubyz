package cubyz.multiplayer.protocols;

import cubyz.client.Cubyz;
import cubyz.multiplayer.Protocol;
import cubyz.multiplayer.UDPConnection;
import cubyz.multiplayer.server.User;
import cubyz.world.ServerWorld;
import pixelguys.json.JsonObject;
import pixelguys.json.JsonParser;

import java.nio.charset.StandardCharsets;

/**
 * Used to exchange unimportant information such as game time and current biome the player is in.
 * This data doesn't update often and doesn't need to be reliable.
 */
public class UnimportantProtocol extends Protocol {
	public UnimportantProtocol() {
		super((byte)8, false);
	}

	@Override
	public void receive(UDPConnection conn, byte[] data, int offset, int length) {
		String str = new String(data, offset, length, StandardCharsets.UTF_8);
		JsonObject json = JsonParser.parseObjectFromString(str);
		Cubyz.world.gameTime = json.getLong("time", 0);
		Cubyz.world.playerBiome = Cubyz.world.registries.biomeRegistry.getByID(json.getString("biome", ""));
	}

	public void send(User user, ServerWorld world) {
		JsonObject data = new JsonObject();
		data.put("time", world.gameTime);
		data.put("biome", world.getBiome((int)user.player.getPosition().x, (int)user.player.getPosition().y, (int)user.player.getPosition().z).getRegistryID().toString());
		user.send(this, data.toString().getBytes(StandardCharsets.UTF_8));
	}
}
