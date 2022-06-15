package cubyz.multiplayer.protocols;

import cubyz.client.entity.ClientEntityManager;
import cubyz.multiplayer.Protocol;
import cubyz.multiplayer.UDPConnection;
import cubyz.utils.Logger;
import cubyz.utils.math.Bits;
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
		short time = Bits.getShort(data, offset);
		offset += 2;
		length -= 2;
		String json = new String(data, offset, length, StandardCharsets.UTF_8);
		JsonElement array = JsonParser.parseFromString(json);
		if(!(array instanceof JsonArray)) {
			Logger.error("EntityProtocol discovered unknown json array: "+json);
			return;
		}
		ClientEntityManager.serverUpdate((JsonArray)array, time);
	}

	public void send(UDPConnection conn, JsonArray data) {
		byte[] entityData = data.toString().getBytes(StandardCharsets.UTF_8);
		byte[] withTime = new byte[entityData.length + 2];
		Bits.putShort(withTime, 0, (short)System.currentTimeMillis());
		System.arraycopy(entityData, 0, withTime, 2, entityData.length);
		conn.send(this, withTime);
	}
}
