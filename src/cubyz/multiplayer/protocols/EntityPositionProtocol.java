package cubyz.multiplayer.protocols;

import cubyz.client.entity.ClientEntityManager;
import cubyz.multiplayer.Protocol;
import cubyz.multiplayer.UDPConnection;
import cubyz.utils.math.Bits;

public class EntityPositionProtocol extends Protocol {
	public EntityPositionProtocol() {
		super((byte)6, false);
	}

	@Override
	public void receive(UDPConnection conn, byte[] data, int offset, int length) {
		short time = Bits.getShort(data, offset);
		offset += 2;
		length -= 2;
		ClientEntityManager.serverUpdate(time, data, offset, length);
	}

	public void send(UDPConnection conn, byte[] data) {
		conn.send(this, data);
	}
}
