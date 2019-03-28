package io.cubyz.multiplayer.client;

import io.netty.bootstrap.Bootstrap;
import io.netty.channel.ChannelFuture;
import io.netty.channel.ChannelInitializer;
import io.netty.channel.ChannelPipeline;
import io.netty.channel.EventLoopGroup;
import io.netty.channel.nio.NioEventLoopGroup;
import io.netty.channel.socket.SocketChannel;
import io.netty.channel.socket.nio.NioSocketChannel;
import io.netty.handler.logging.LogLevel;
import io.netty.handler.logging.LoggingHandler;

public class CubzClient {

	private ChannelFuture future;
	private EventLoopGroup group;
	private boolean connected;
	private LocalServer ls;
	private CubzClientHandler cch;

	/**
	 * Local server representation
	 * 
	 * @author zenith391
	 */
	public static class LocalServer {
		public String brand;
		public String version;
		public PingResponse lastPingResponse;
	}

	/**
	 * Mostly equals to true.
	 * 
	 * @return is client connected to a server.
	 */
	public boolean isConnected() {
		return connected;
	}

	void checkConnection() {
		if (!isConnected())
			throw new IllegalStateException("Client is not connected");
	}

	public LocalServer getLocalServer() {
		return ls;
	}

	public PingResponse ping() {
		ls.lastPingResponse = null;
		checkConnection();
		cch.ping();
		while (ls.lastPingResponse == null) {
			System.out.print(""); // TODO really find an alternative to it (for Java 8, not using Thread.onSpinWait() from Java 9)
		}
		return ls.lastPingResponse;
	}

	public void disconnect() {
		checkConnection();
		try {
			future.channel().close().await();
			group.shutdownGracefully().await();
			connected = false;
		} catch (InterruptedException e) {
			e.printStackTrace();
		}
	}
	
	/**
	 * Disconnect from old server if the client was connected.
	 * 
	 * @param host
	 * @param port
	 */
	public void connect(String host, int port) {
		if (isConnected()) {
			disconnect();
		}
		cch = new CubzClientHandler(CubzClient.this, false);
		group = new NioEventLoopGroup();

		try {
			Bootstrap b = new Bootstrap();
			ls = new LocalServer();
			cch = new CubzClientHandler(CubzClient.this, false);
			b.group(group).channel(NioSocketChannel.class)//.option(ChannelOption.TCP_NODELAY, true)
					.handler(new ChannelInitializer<SocketChannel>() {
						@Override
						public void initChannel(SocketChannel ch) throws Exception {
							ChannelPipeline p = ch.pipeline();
							p.addLast(cch);
							//p.addLast(new LoggingHandler(LogLevel.INFO)); // debugging info
						}
					});
			// Start the client.
			future = b.connect(host, port);
			
			while (!cch.channelActive) {
				System.out.print("");
			}
			
			connected = true;
			//ping();
		} catch (Exception e) {
			System.err.println("Multiplayer Error:");
			e.printStackTrace();
		}
	}

}
