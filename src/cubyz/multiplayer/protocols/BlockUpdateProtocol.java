package cubyz.multiplayer.protocols;

import cubyz.client.Cubyz;
import cubyz.multiplayer.Protocol;
import cubyz.multiplayer.UDPConnection;
import cubyz.multiplayer.server.Server;
import cubyz.multiplayer.server.User;
import cubyz.utils.math.Bits;

public class BlockUpdateProtocol extends Protocol {
	public BlockUpdateProtocol() {
		super((byte)7, true);
	}

	@Override
	public void receive(UDPConnection conn, byte[] data, int offset, int length) {
		int x = Bits.getInt(data, offset);
		int y = Bits.getInt(data, offset + 4);
		int z = Bits.getInt(data, offset + 8);
		int newBlock = Bits.getInt(data, offset + 12);
		if(conn instanceof User) {
			Server.world.updateBlock(x, y, z, newBlock);
		} else {
			Cubyz.world.remoteUpdateBlock(x, y, z, newBlock);
		}
	}

	public void send(UDPConnection conn, int x, int y, int z, int newBlock) {
		byte[] data = new byte[4*4];
		Bits.putInt(data, 0, x);
		Bits.putInt(data, 4, y);
		Bits.putInt(data, 8, z);
		Bits.putInt(data, 12, newBlock);
		conn.send(this, data);
	}
}
