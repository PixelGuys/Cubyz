package cubyz.client.entity;

import cubyz.api.CubyzRegistries;
import cubyz.utils.interpolation.TimeDifference;
import org.joml.Vector3d;
import org.joml.Vector3f;
import pixelguys.json.JsonArray;
import pixelguys.json.JsonElement;

public final class ClientEntityManager {
	private static short lastTime;

	private static ClientEntity[] entities = new ClientEntity[0];

	private static final TimeDifference timeDifference = new TimeDifference();

	public static ClientEntity[] getEntities() {
		return entities;
	}

	public static void update() {
		short time = (short)(System.currentTimeMillis() - 200);
		time -= timeDifference.difference;
		for(ClientEntity ent : entities) {
			ent.update(time, lastTime);
		}
		lastTime = time;
	}

	// TODO: Use raw data.
	public static void serverUpdate(JsonArray serverEntities, short time) {
		timeDifference.addDataPoint(time);
		ClientEntity[] newEntities = new ClientEntity[serverEntities.array.size()];
		outer:
		for(int i = 0; i < serverEntities.array.size(); i++) {
			JsonElement entity = serverEntities.array.get(i);
			int id = entity.getInt("id", 0);
			Vector3d position = new Vector3d(
				entity.getDouble("x", 0),
				entity.getDouble("y", 0),
				entity.getDouble("z", 0)
			);
			Vector3d velocity = new Vector3d(
				entity.getDouble("vx", 0),
				entity.getDouble("vy", 0),
				entity.getDouble("vz", 0)
			);
			Vector3f rotation = new Vector3f(
				entity.getFloat("rot_x", 0),
				entity.getFloat("rot_y", 0),
				entity.getFloat("rot_z", 0)
			);
			for(int j = 0; j < entities.length; j++) {
				if (entities[j].id == id) {
					newEntities[i] = entities[j];
					newEntities[i].updatePosition(position, velocity, rotation, time);
					continue outer;
				}
			}
			newEntities[i] = new ClientEntity(
				position, rotation, id,
				CubyzRegistries.ENTITY_REGISTRY.getByID(entity.getString("type", null)),
				entity.getFloat("height", 2),
				entity.getString("name", "")
			);
		}
		entities = newEntities;
	}
}
