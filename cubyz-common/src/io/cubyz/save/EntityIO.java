package io.cubyz.save;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.util.Objects;

import org.joml.Vector3f;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.entity.Entity;
import io.cubyz.entity.EntityType;
import io.cubyz.math.Vector3fi;

public class EntityIO {

	public static void saveEntity(Entity ent, DataOutputStream out) throws IOException {
		// written as double to prepare future conversion from floats to doubles (for very large worlds)
		out.writeUTF(ent.getType().getRegistryID().toString());
		out.writeDouble(ent.getPosition().x);
		out.writeDouble(ent.getPosition().y);
		out.writeDouble(ent.getPosition().z);
		out.writeDouble(ent.getPosition().relX);
		out.writeDouble(ent.getPosition().relZ);
		out.writeDouble(ent.getRotation().x);
		out.writeDouble(ent.getRotation().y);
		out.writeDouble(ent.getRotation().z);
		out.writeDouble(ent.vx);
		out.writeDouble(ent.vy);
		out.writeDouble(ent.vz);
	}
	
	public static Entity loadEntity(DataInputStream dis) throws IOException {
		EntityType entityType = CubyzRegistries.ENTITY_REGISTRY.getByID(dis.readUTF());
		Objects.requireNonNull(entityType, "invalid entity type");
		Entity ent = entityType.newEntity();
		Vector3fi entPos = new Vector3fi(dis.readInt(), (float)dis.readDouble(), dis.readInt());
		entPos.relX = (float)dis.readDouble();
		entPos.relZ = (float)dis.readDouble();
		ent.setPosition(entPos);
		ent.setRotation(new Vector3f((float)dis.readDouble(), (float)dis.readDouble(), (float)dis.readDouble()));
		ent.vx = (float) dis.readDouble();
		ent.vy = (float) dis.readDouble();
		ent.vz = (float) dis.readDouble();
		return ent;
	}
	
}
