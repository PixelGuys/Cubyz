package cubyz.multiplayer.protocols;

import cubyz.client.Cubyz;
import cubyz.client.entity.ClientEntityManager;
import cubyz.client.entity.InterpolatedItemEntityManager;
import cubyz.multiplayer.Protocol;
import cubyz.multiplayer.UDPConnection;
import cubyz.utils.math.Bits;

public class EntityPositionProtocol extends Protocol {
	private static final byte ENTITY = 0, ITEM = 1;
	public EntityPositionProtocol() {
		super((byte)6, false);
	}

	@Override
	public void receive(UDPConnection conn, byte[] data, int offset, int length) {
		if(Cubyz.world == null) return;
		short time = Bits.getShort(data, offset+1);
		if(data[offset] == ENTITY) {
			offset += 3;
			length -= 3;
			ClientEntityManager.serverUpdate(time, data, offset, length);
		} else if(data[offset] == ITEM) {
			offset += 3;
			length -= 3;
			((InterpolatedItemEntityManager)Cubyz.world.itemEntityManager).readPosition(data, offset, length, time);
		}
	}

	public void send(UDPConnection conn, byte[] entityData, byte[] itemData) {
		byte[] fullData = new byte[entityData.length + 3];
		fullData[0] = ENTITY;
		Bits.putShort(fullData, 1, (short)System.currentTimeMillis());
		System.arraycopy(entityData, 0, fullData, 3, entityData.length);
		conn.send(this, fullData);

		fullData = new byte[itemData.length + 3];
		fullData[0] = ITEM;
		Bits.putShort(fullData, 1, (short)System.currentTimeMillis());
		System.arraycopy(itemData, 0, fullData, 3, itemData.length);
		conn.send(this, fullData);
	}
}
