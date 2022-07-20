package cubyz.client.entity;

import cubyz.Constants;
import cubyz.api.CubyzRegistries;
import cubyz.utils.datastructures.SimpleList;
import cubyz.utils.interpolation.TimeDifference;
import cubyz.utils.math.Bits;
import pixelguys.json.JsonObject;

public final class ClientEntityManager {
	private static short lastTime;

	private static final SimpleList<ClientEntity> entities = new SimpleList<>(new ClientEntity[16]);

	private static final TimeDifference timeDifference = new TimeDifference();

	public static ClientEntity[] getEntities() {
		return entities.toArray();
	}

	public static void update() {
		short time = (short)(System.currentTimeMillis() - Constants.ENTITY_LOOKBACK);
		time -= timeDifference.difference;
		for(ClientEntity ent : entities.toArray()) {
			ent.update(time, lastTime);
		}
		lastTime = time;
	}

	public static void addEntity(JsonObject json) {
		entities.add(new ClientEntity(
			json.getInt("id", -1),
			CubyzRegistries.ENTITY_REGISTRY.getByID(json.getString("type", null)),
			json.getFloat("height", 2),
			json.getString("name", "")
		));
	}

	public static void removeEntity(int id) {
		for(ClientEntity entity : entities.toArray()) {
			if(entity.id == id) {
				entities.remove(entity);
			}
		}
	}

	public static void clear() {
		entities.clear();
		timeDifference.reset();
	}

	public static void serverUpdate(short time, byte[] data, int offset, int length) {
		timeDifference.addDataPoint(time);
		int num = length/(4+24+12+24);
		for(int i = 0; i < num; i++) {
			int id = Bits.getInt(data, offset);
			offset += 4;
			double[] position = new double[]{
				Bits.getDouble(data, offset),
				Bits.getDouble(data, offset + 8),
				Bits.getDouble(data, offset + 16),
				Bits.getFloat(data, offset + 24),
				Bits.getFloat(data, offset + 28),
				Bits.getFloat(data, offset + 32),
			};
			offset += 36;
			double[] velocity = new double[]{
				Bits.getDouble(data, offset),
				Bits.getDouble(data, offset + 8),
				Bits.getDouble(data, offset + 16),
				0, 0, 0,
			};
			offset += 24;
			for(ClientEntity ent : entities.toArray()) {
				if(ent.id == id) {
					ent.updatePosition(position, velocity, time);
				}
			}
		}
	}
}
