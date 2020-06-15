package io.cubyz.save;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

import io.cubyz.entity.Entity;
import io.cubyz.entity.EntityType;
import io.cubyz.entity.ItemEntity;
import io.cubyz.items.Item;
import io.cubyz.items.ItemStack;
import io.cubyz.math.Bits;
import io.cubyz.ndt.NDTContainer;
import io.cubyz.world.Surface;

public class EntityIO {

	public static void saveEntity(Entity ent, OutputStream out) throws IOException {
		NDTContainer ndt = ent.saveTo(new NDTContainer());
		ndt.setString("id", ent.getType().getRegistryID().toString());
		if(ent instanceof ItemEntity) {
			ItemEntity itemEnt = (ItemEntity)ent;
			ndt.setString("item", itemEnt.items.getItem().getRegistryID().toString());
			ndt.setInteger("amount", itemEnt.items.getAmount());
		}
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
		if(id.equals("cubyz:item_stack")) {
			Item item = surface.getCurrentRegistries().itemRegistry.getByID(ndt.getString("item"));
			int amount = (int)ndt.getInteger("amount");
			ent = new ItemEntity(surface, new ItemStack(item, amount));
		} else {
			EntityType type = surface.getCurrentRegistries().entityRegistry.getByID(id);
			if (type == null) {
				return null;
			}
			ent = type.newEntity(surface);
		}
		ent.loadFrom(ndt);
		return ent;
	}
	
}
