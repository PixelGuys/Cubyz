package cubyz.multiplayer.protocols;

import cubyz.client.entity.ClientEntityManager;
import cubyz.multiplayer.Protocol;
import cubyz.multiplayer.UDPConnection;
import cubyz.utils.Logger;
import pixelguys.json.JsonArray;
import pixelguys.json.JsonElement;
import pixelguys.json.JsonParser;

import java.nio.charset.StandardCharsets;

public class EntityProtocol extends Protocol {
	public EntityProtocol() {
		super((byte)6, false);
	}

	@Override
	public void receive(UDPConnection conn, byte[] data, int offset, int length) {
		String json = new String(data, offset, length, StandardCharsets.UTF_8);
		JsonElement array = JsonParser.parseFromString(json);
		if(!(array instanceof JsonArray)) {
			Logger.error("EntityProtocol discovered unknown json array: "+json);
			return;
		}
		ClientEntityManager.serverUpdate((JsonArray)array);
	}

	public void send(UDPConnection conn, JsonArray data) {
		conn.send(this, data.toString().getBytes(StandardCharsets.UTF_8));
	}
}
