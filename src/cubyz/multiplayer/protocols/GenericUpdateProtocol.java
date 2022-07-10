package cubyz.multiplayer.protocols;

import cubyz.client.Cubyz;
import cubyz.multiplayer.Protocol;
import cubyz.multiplayer.UDPConnection;
import cubyz.multiplayer.client.ServerConnection;
import cubyz.multiplayer.server.Server;
import cubyz.multiplayer.server.User;
import cubyz.rendering.Camera;
import cubyz.utils.math.Bits;
import cubyz.world.items.Inventory;
import cubyz.world.items.Item;
import cubyz.world.items.ItemStack;
import org.joml.Vector3d;
import org.joml.Vector3f;
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
	private static final byte INVENTORY_CLEAR = 5;
	private static final byte ITEM_STACK_DROP = 6;
	private static final byte ITEM_STACK_COLLECT = 7;
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
			case INVENTORY_CLEAR: {
				if(conn instanceof User) {
					Inventory inv = ((User)conn).player.getInventory();
					for (int i = 0; i < inv.getCapacity(); i++) {
						inv.getStack(i).clear();
					}
				} else {
					Inventory inv = Cubyz.player.getInventory_AND_DONT_FORGET_TO_SEND_CHANGES_TO_THE_SERVER();
					for (int i = 0; i < inv.getCapacity(); i++) {
						inv.getStack(i).clear();
					}
					clearInventory(conn); // Needs to send changes back to server, to ensure correct order.
				}
				break;
			}
			case ITEM_STACK_DROP: {
				JsonObject json = JsonParser.parseObjectFromString(new String(data, offset + 1, length - 1, StandardCharsets.UTF_8));
				Item item = Item.load(json, Cubyz.world.registries);
				if (item == null) {
					break;
				}
				Server.world.drop(
					new ItemStack(item, json.getInt("amount", 1)),
					new Vector3d(json.getDouble("x", 0), json.getDouble("y", 0), json.getDouble("z", 0)),
					new Vector3f(json.getFloat("dirX", 0), json.getFloat("dirY", 0), json.getFloat("dirZ", 0)),
					json.getFloat("vel", 0),
					Server.UPDATES_PER_SEC*5
				);
				break;
			}
			case ITEM_STACK_COLLECT: {
				JsonObject json = JsonParser.parseObjectFromString(new String(data, offset + 1, length - 1, StandardCharsets.UTF_8));
				Item item = Item.load(json, Cubyz.world.registries);
				if (item == null) {
					break;
				}
				int remaining = Cubyz.player.getInventory_AND_DONT_FORGET_TO_SEND_CHANGES_TO_THE_SERVER().addItem(item, json.getInt("amount", 1));
				sendInventory_full(Cubyz.world.serverConnection, Cubyz.player.getInventory_AND_DONT_FORGET_TO_SEND_CHANGES_TO_THE_SERVER());
				if(remaining != 0) {
					// Couldn't collect everything → drop it again.
					itemStackDrop(Cubyz.world.serverConnection, new ItemStack(item, remaining), Cubyz.player.getPosition(), Camera.getDirection(), 0);
				}
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

	public void clearInventory(UDPConnection conn) {
		conn.send(this, new byte[]{INVENTORY_CLEAR});
	}

	public void itemStackDrop(ServerConnection conn, ItemStack stack, Vector3d pos, Vector3f dir, float vel) {
		JsonObject json = stack.store();
		json.put("x", pos.x);
		json.put("y", pos.y);
		json.put("z", pos.z);
		json.put("dirX", dir.x);
		json.put("dirY", dir.y);
		json.put("dirZ", dir.z);
		json.put("vel", vel);
		byte[] data = json.toString().getBytes(StandardCharsets.UTF_8);
		byte[] headeredData = new byte[data.length + 1];
		headeredData[0] = ITEM_STACK_DROP;
		System.arraycopy(data, 0, headeredData, 1, data.length);
		conn.send(this, headeredData);
	}

	public void itemStackCollect(User user, ItemStack stack) {
		byte[] data = stack.store().toString().getBytes(StandardCharsets.UTF_8);
		byte[] headeredData = new byte[data.length + 1];
		headeredData[0] = ITEM_STACK_COLLECT;
		System.arraycopy(data, 0, headeredData, 1, data.length);
		user.send(this, headeredData);
	}
}
