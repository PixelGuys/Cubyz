package io.cubyz.save;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;

import io.cubyz.entity.Entity;

public class EntityIO {

	public static void saveEntity(Entity ent, DataOutputStream out) throws IOException {
		// written as double to prepare future conversion from floats to doubles (for very large worlds)
		out.writeUTF(ent.getRegistryName());
		out.writeDouble(ent.getPosition().x);
		out.writeDouble(ent.getPosition().y);
		out.writeDouble(ent.getPosition().z);
		out.writeDouble(ent.getRotation().x);
		out.writeDouble(ent.getRotation().y);
		out.writeDouble(ent.getRotation().z);
		out.writeDouble(ent.vx);
		out.writeDouble(ent.vy);
		out.writeDouble(ent.vz);
	}
	
	public static Entity loadEntity(DataInputStream dis) throws IOException {
		
	}
	
}
