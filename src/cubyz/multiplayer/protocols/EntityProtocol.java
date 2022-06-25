package cubyz.multiplayer.protocols;

import cubyz.client.entity.ClientEntityManager;
import cubyz.multiplayer.Protocol;
import cubyz.multiplayer.Protocols;
import cubyz.multiplayer.UDPConnection;
import cubyz.multiplayer.server.Server;
import cubyz.multiplayer.server.User;
import cubyz.utils.math.Bits;
import cubyz.world.entity.Entity;
import pixelguys.json.*;

import java.nio.charset.StandardCharsets;

/**
 * Used for all the constant or semi-constant parameters, such as entity name, type and existence.
 */
public class EntityProtocol extends Protocol {
	public EntityProtocol() {
		super((byte)11, true);
	}

	@Override
	public void receive(UDPConnection conn, byte[] data, int offset, int length) {
		JsonArray array = (JsonArray)JsonParser.parseFromString(new String(data, offset, length, StandardCharsets.UTF_8));
		for(JsonElement json: array.array) {
			if(json instanceof JsonInt) {
				ClientEntityManager.removeEntity(json.asInt(0));
			} else if(json instanceof JsonObject) {
				ClientEntityManager.addEntity((JsonObject)json);
			}
		}
	}

	public void send(UDPConnection conn, String msg) {
		byte[] data = msg.getBytes(StandardCharsets.UTF_8);
		conn.send(this, data);
	}

	public void sendToClients(Entity[] currentEntities, Entity[] lastSentEntities) {
		byte[] data = new byte[2 + currentEntities.length*(4 + 3*8 + 3*8 + 3*4)];
		Bits.putShort(data, 0, (short)System.currentTimeMillis());
		int offset = 2;
		JsonArray entityChanges = new JsonArray();
		outer:
		for(Entity ent : currentEntities) {
			Bits.putInt(data, offset, ent.id);
			offset += 4;
			Bits.putDouble(data, offset, ent.getPosition().x);
			offset += 8;
			Bits.putDouble(data, offset, ent.getPosition().y);
			offset += 8;
			Bits.putDouble(data, offset, ent.getPosition().z);
			offset += 8;
			Bits.putDouble(data, offset, ent.vx);
			offset += 8;
			Bits.putDouble(data, offset, ent.vy);
			offset += 8;
			Bits.putDouble(data, offset, ent.vz);
			offset += 8;
			Bits.putFloat(data, offset, ent.getRotation().x);
			offset += 4;
			Bits.putFloat(data, offset, ent.getRotation().y);
			offset += 4;
			Bits.putFloat(data, offset, ent.getRotation().z);
			offset += 4;
			for(int i = 0; i < lastSentEntities.length; i++) {
				if(lastSentEntities[i] == ent) {
					lastSentEntities[i] = null;
					continue outer;
				}
			}
			JsonObject entityData = new JsonObject();
			entityData.put("id", ent.id);
			entityData.put("type", ent.getType().getRegistryID().toString());
			entityData.put("height", ent.height);
			entityData.put("name", ent.name);
			entityChanges.add(entityData);
		}
		assert offset == data.length;
		for(Entity ent : lastSentEntities) {
			if(ent != null) {
				entityChanges.add(new JsonInt(ent.id));
			}
		}
		if(!entityChanges.array.isEmpty()) {
			for(User user : Server.users) {
				if(user.receivedFirstEntityData) {
					user.send(this, entityChanges.toString().getBytes(StandardCharsets.UTF_8));
				}
			}
		}
		for(User user : Server.users) {
			if(!user.isConnected()) continue;
			if(!user.receivedFirstEntityData) {
				JsonArray fullEntityData = new JsonArray();
				for(Entity ent : currentEntities) {
					JsonObject entityData = new JsonObject();
					entityData.put("id", ent.id);
					entityData.put("type", ent.getType().getRegistryID().toString());
					entityData.put("height", ent.height);
					entityData.put("name", ent.name);
					fullEntityData.add(entityData);
				}
				user.send(this, fullEntityData.toString().getBytes(StandardCharsets.UTF_8));
				user.receivedFirstEntityData = true;
			}
			Protocols.ENTITY_POSITION.send(user, data);
		}
	}
}
