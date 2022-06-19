package cubyz.multiplayer.protocols;

import cubyz.client.Cubyz;
import cubyz.multiplayer.Protocol;
import cubyz.multiplayer.UDPConnection;
import cubyz.multiplayer.client.ServerConnection;
import cubyz.multiplayer.server.Server;
import cubyz.multiplayer.server.User;
import cubyz.utils.math.Bits;
import cubyz.world.items.Inventory;
import org.joml.Vector3d;
import pixelguys.json.JsonObject;
import pixelguys.json.JsonParser;

import java.nio.charset.StandardCharsets;

/**
 * For stuff that rarely needs an update and therefor it would be a waste to create a new protocol for each of these.
 */
public class GenericUpdateProtocol extends Protocol {
	private static final byte RENDER_DISTANCE = 0;
	private static final byte TELEPORT = 1;
	private static final byte CURE = 2;
	private static final byte INVENTORY_ADD = 3;
	private static final byte INVENTORY_FULL = 4;
	public GenericUpdateProtocol() {
		super((byte)9, true);
	}

	@Override
	public void receive(UDPConnection conn, byte[] data, int offset, int length) {
		switch(data[offset]) {
			case RENDER_DISTANCE: {
				int renderDistance = Bits.getInt(data, offset+1);
				float LODFactor = Bits.getFloat(data, offset+5);
				if(conn instanceof User) {
					User user = (User)conn;
					user.renderDistance = renderDistance;
					user.LODFactor = LODFactor;
				}
				break;
			}
			case TELEPORT: {
				Cubyz.player.setPosition(new Vector3d(
					Bits.getDouble(data, offset+1),
					Bits.getDouble(data, offset+9),
					Bits.getDouble(data, offset+17)
				));
				break;
			}
			case CURE: {
				Cubyz.player.health = Cubyz.player.maxHealth;
				Cubyz.player.hunger = Cubyz.player.maxHunger;
				break;
			}
			case INVENTORY_ADD: {
				int slot = Bits.getInt(data, offset+1);
				int amount = Bits.getInt(data, offset+5);
				((User)conn).player.getInventory().getStack(slot).add(amount);
				break;
			}
			case INVENTORY_FULL: {
				JsonObject json = JsonParser.parseObjectFromString(new String(data, offset + 1, length - 1, StandardCharsets.UTF_8));
				((User)conn).player.getInventory().loadFrom(json, Server.world.getCurrentRegistries());
				break;
			}
		}
	}

	public void sendRenderDistance(ServerConnection conn, int renderDistance, float LODFactor) {
		byte[] data = new byte[9];
		data[0] = RENDER_DISTANCE;
		Bits.putInt(data, 1, renderDistance);
		Bits.putFloat(data, 5, LODFactor);
		conn.send(this, data);
	}

	public void sendTPCoordinates(User conn, Vector3d position) {
		byte[] data = new byte[1+24];
		data[0] = TELEPORT;
		Bits.putDouble(data, 1, position.x);
		Bits.putDouble(data, 9, position.y);
		Bits.putDouble(data, 17, position.z);
		conn.send(this, data);
	}

	public void sendCure(User conn) {
		conn.send(this, new byte[]{CURE});
	}

	public void sendInventory_ItemStack_add(ServerConnection conn, int slot, int amount) {
		byte[] data = new byte[9];
		data[0] = INVENTORY_ADD;
		Bits.putInt(data, 1, slot);
		Bits.putInt(data, 5, amount);
		conn.send(this, data);
	}

	public void sendInventory_full(ServerConnection conn, Inventory inv) {
		byte[] data = inv.save().toString().getBytes(StandardCharsets.UTF_8);
		byte[] headeredData = new byte[data.length + 1];
		headeredData[0] = INVENTORY_FULL;
		System.arraycopy(data, 0, headeredData, 1, data.length);
		conn.send(this, headeredData);
	}
}
