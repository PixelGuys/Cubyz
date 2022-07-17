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
		assert length % 16 == 0;
		int end = offset + length;
		while(offset < end) {
			ChunkData request = new ChunkData(
				Bits.getInt(data, offset),
				Bits.getInt(data, offset + 4),
				Bits.getInt(data, offset + 8),
				Bits.getInt(data, offset + 12)
			);
			Server.world.queueChunk(request, (User)conn);
			offset += 16;
		}
	}

	public void sendRequest(UDPConnection conn, ChunkData[] requests) {
		byte[] data = new byte[16*requests.length];
		int off = 0;
		for(int i = 0; i < requests.length; i++) {
			Bits.putInt(data, off, requests[i].wx);
			off += 4;
			Bits.putInt(data, off, requests[i].wy);
			off += 4;
			Bits.putInt(data, off, requests[i].wz);
			off += 4;
			Bits.putInt(data, off, requests[i].voxelSize);
			off += 4;
		}
		conn.send(this, data);
	}
}
