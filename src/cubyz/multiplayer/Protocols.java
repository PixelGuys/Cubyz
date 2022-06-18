package cubyz.multiplayer;

import cubyz.multiplayer.protocols.*;

public final class Protocols {
	public static final Protocol[] list = new Protocol[256];
	public static final int[] bytesReceived = new int[256];

	public static final KeepAliveProtocol KEEP_ALIVE = new KeepAliveProtocol();
	public static final HandshakeProtocol HANDSHAKE = new HandshakeProtocol();
	public static final ChunkRequestProtocol CHUNK_REQUEST = new ChunkRequestProtocol();
	public static final ChunkTransmissionProtocol CHUNK_TRANSMISSION = new ChunkTransmissionProtocol();
	public static final PlayerPositionProtocol PLAYER_POSITION = new PlayerPositionProtocol();
	public static final DisconnectProtocol DISCONNECT = new DisconnectProtocol();
	public static final EntityProtocol ENTITY = new EntityProtocol();
	public static final BlockUpdateProtocol BLOCK_UPDATE = new BlockUpdateProtocol();
	public static final UnimportantProtocol UNIMPORTANT = new UnimportantProtocol();
	public static final RenderDistanceProtocol RENDER_DISTANCE = new RenderDistanceProtocol();
	public static final ChatProtocol CHAT = new ChatProtocol();
}
