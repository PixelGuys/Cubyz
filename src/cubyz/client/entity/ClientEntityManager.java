package cubyz.client.entity;

import cubyz.api.CubyzRegistries;
import cubyz.utils.Logger;
import org.joml.Vector3d;
import org.joml.Vector3f;
import pixelguys.json.JsonArray;
import pixelguys.json.JsonElement;

public final class ClientEntityManager {
	private ClientEntityManager() {} // No instances allowed.

	private static ClientEntity[] entities = new ClientEntity[0];

	public static ClientEntity[] getEntities() {
		for(ClientEntity ent : entities) {
			ent.update();
		}
		return entities;
	}

	// TODO: Use raw data.
	public static void serverUpdate(JsonArray serverEntities) {
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
			Vector3f rotation = new Vector3f(
					entity.getFloat("rot_x", 0),
					entity.getFloat("rot_y", 0),
					entity.getFloat("rot_z", 0)
			);
			for(int j = 0; j < entities.length; j++) {
				if (entities[j].id == id) {
					newEntities[i] = entities[j];
					newEntities[i].updatePosition(position, rotation);
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
