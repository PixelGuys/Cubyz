package cubyz.world.save;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

import cubyz.Logger;
import cubyz.utils.math.Bits;
import cubyz.utils.ndt.NDTContainer;
import cubyz.world.ServerWorld;
import cubyz.world.entity.Entity;
import cubyz.world.entity.EntityType;

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
	
	public static Entity loadEntity(InputStream in, ServerWorld world) throws IOException {
		byte[] lenBytes = new byte[4];
		in.read(lenBytes);
		int len = Bits.getInt(lenBytes, 0);
		byte[] buf = new byte[len];
		in.read(buf);
		NDTContainer ndt = new NDTContainer(buf);
		String id = ndt.getString("id");
		Entity ent;
		EntityType type = world.getCurrentRegistries().entityRegistry.getByID(id);
		if (type == null) {
			Logger.warning("Could not load entity with id " + id.toString());
			return null;
		}
		ent = type.newEntity(world);
		ent.loadFrom(ndt);
		return ent;
	}
	
}
