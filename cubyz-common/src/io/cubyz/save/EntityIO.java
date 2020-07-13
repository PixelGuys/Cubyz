package io.cubyz.save;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

import io.cubyz.entity.Entity;
import io.cubyz.entity.EntityType;
import io.cubyz.math.Bits;
import io.cubyz.ndt.NDTContainer;
import io.cubyz.world.Surface;

import static io.cubyz.CubyzLogger.logger;

public class EntityIO {

	public static void saveEntity(Entity ent, OutputStream out) throws IOException {
		NDTContainer ndt = ent.saveTo(new NDTContainer());
		ndt.setString("id", ent.getType().getRegistryID().toString());
		byte[] data = ndt.getData();
		byte[] lenBytes = new byte[4];
		Bits.putInt(lenBytes, 0, data.length);
		out.write(lenBytes);
		out.write(data);
	}
	
	public static Entity loadEntity(InputStream in, Surface surface) throws IOException {
		byte[] lenBytes = new byte[4];
		in.read(lenBytes);
		int len = Bits.getInt(lenBytes, 0);
		byte[] buf = new byte[len];
		in.read(buf);
		NDTContainer ndt = new NDTContainer(buf);
		String id = ndt.getString("id");
		Entity ent;
		EntityType type = surface.getCurrentRegistries().entityRegistry.getByID(id);
		if (type == null) {
			logger.warning("Could not load entity with id " + id.toString());
			return null;
		}
		ent = type.newEntity(surface);
		ent.loadFrom(ndt);
		return ent;
	}
	
}
