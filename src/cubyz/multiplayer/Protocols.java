package cubyz.multiplayer;

public final class Protocols {
	public static final Protocol[] list = new Protocol[256];

	public static final KeepAliveProtocol KEEP_ALIVE = new KeepAliveProtocol();
	public static final HandshakeProtocol HANDSHAKE = new HandshakeProtocol();
	public static final ChunkRequestProtocol CHUNK_REQUEST = new ChunkRequestProtocol();
	public static final ChunkTransmissionProtocol CHUNK_TRANSMISSION = new ChunkTransmissionProtocol();
}
