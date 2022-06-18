package cubyz.multiplayer.protocols;

import cubyz.multiplayer.Protocol;
import cubyz.multiplayer.UDPConnection;
import cubyz.multiplayer.server.Server;
import cubyz.multiplayer.server.User;
import cubyz.utils.math.Bits;
import cubyz.world.ChunkData;

public class ChunkRequestProtocol extends Protocol {
	public ChunkRequestProtocol() {
		super((byte)2, true);
	}

	@Override
	public void receive(UDPConnection conn, byte[] data, int offset, int length) {
		ChunkData request = new ChunkData(
			Bits.getInt(data, offset),
			Bits.getInt(data, offset + 4),
			Bits.getInt(data, offset + 8),
			Bits.getInt(data, offset + 12)
		);
		Server.world.queueChunk(request, (User)conn);
	}

	public void sendRequest(UDPConnection conn, ChunkData request) {
		byte[] data = new byte[4*4];
		Bits.putInt(data, 0, request.wx);
		Bits.putInt(data, 4, request.wy);
		Bits.putInt(data, 8, request.wz);
		Bits.putInt(data, 12, request.voxelSize);
		conn.send(this, data);
	}
}
