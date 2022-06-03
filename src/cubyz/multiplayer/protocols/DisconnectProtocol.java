package cubyz.multiplayer.protocols;

import cubyz.multiplayer.Protocol;
import cubyz.multiplayer.UDPConnection;

public class DisconnectProtocol extends Protocol {
	public static final byte[] NO_DATA = new byte[0];

	public DisconnectProtocol() {
		super((byte)5, false);
	}

	@Override
	public void receive(UDPConnection conn, byte[] data, int offset, int length) {
		conn.disconnect();
	}

	public void disconnect(UDPConnection conn) {
		conn.send(this, NO_DATA);
	}
}
