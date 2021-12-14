package cubyz.client.entity;

import cubyz.world.entity.Entity;

public class ClientEntityManager {
	private static ClientEntity[] entities = new ClientEntity[0];

	public static ClientEntity[] getEntities() {
		for(ClientEntity ent : entities) {
			ent.update();
		}
		return entities;
	}

	// TODO: Use raw data.
	public static void serverUpdate(Entity[] serverEntities) {
		ClientEntity[] newEntities = new ClientEntity[serverEntities.length];
		outer:
		for(int i = 0; i < serverEntities.length; i++) {
			for(int j = 0; j < entities.length; j++) {
				if (entities[j].id == serverEntities[i].id) {
					newEntities[i] = entities[j];
					newEntities[i].updatePosition(serverEntities[i].getPosition(), serverEntities[i].getRotation());
					continue outer;
				}
			}
			newEntities[i] = new ClientEntity(serverEntities[i].getPosition(), serverEntities[i].getRotation(), serverEntities[i].id, serverEntities[i].getType(), serverEntities[i].height);
		}
		entities = newEntities;
	}
}
