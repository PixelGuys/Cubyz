package io.cubyz.multiplayer.server;

import io.netty.bootstrap.ServerBootstrap;
import io.netty.channel.ChannelFuture;
import io.netty.channel.ChannelInitializer;
import io.netty.channel.ChannelOption;
import io.netty.channel.EventLoopGroup;
import io.netty.channel.nio.NioEventLoopGroup;
import io.netty.channel.socket.SocketChannel;
import io.netty.channel.socket.nio.NioServerSocketChannel;

public class CubyzServer {

	private int port;
	static boolean internal; // integrated

	public CubyzServer(int port) {
		this.port = port;
	}

	public void start(boolean internal) throws Exception {
		CubyzServer.internal = internal;
		ServerSettings ss = new ServerSettings();
		ss.maxPlayers = 20;
		ss.playerTimeout = 5000;
		ss.playerPingTime = 5000;
		ss.internal = true;
		
		EventLoopGroup bossGroup = new NioEventLoopGroup();
		EventLoopGroup workerGroup = new NioEventLoopGroup();
		try {
			ServerBootstrap b = new ServerBootstrap();
			b.group(bossGroup, workerGroup).channel(NioServerSocketChannel.class)
					.childHandler(new ChannelInitializer<SocketChannel>() {
						@Override
						public void initChannel(SocketChannel ch) throws Exception {
							ch.pipeline().addLast(new ServerHandler(CubyzServer.this, ss));
						}
					}).option(ChannelOption.SO_BACKLOG, 128).
					childOption(ChannelOption.SO_KEEPALIVE, true);

			// Bind and start to accept incoming connections.
			ChannelFuture f = b.bind(port);

			// Wait until the server socket is closed.
			// In this example, this does not happen, but you can do that to gracefully
			// shut down your server.
			//f.channel().closeFuture().sync();
		} finally {
			//workerGroup.shutdownGracefully();
			//bossGroup.shutdownGracefully();
		}
	}

}
