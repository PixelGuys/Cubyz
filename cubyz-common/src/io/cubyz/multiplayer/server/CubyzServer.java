package io.cubyz.multiplayer.server;

import io.netty.bootstrap.ServerBootstrap;
import io.netty.channel.Channel;
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
	static ServerSettings settings = new ServerSettings();
	
	static Channel ch;
	static EventLoopGroup boss;
	static EventLoopGroup worker;
	static ServerHandler handler;
	
	static {
		settings.maxPlayers = 20;
		settings.playerTimeout = 5000;
		settings.playerPingTime = 5000;
	}

	public CubyzServer(int port) {
		this.port = port;
	}
	
	public void stop() throws Exception {
		ServerHandler.th.interrupt();
		ServerHandler.world.cleanup();
		
		ch.close();
		worker.shutdownGracefully();
		boss.shutdownGracefully();
	}

	public void start(boolean internal) throws Exception {
		CubyzServer.internal = internal;
		settings.internal = internal;
		
		boss = new NioEventLoopGroup();
		worker = new NioEventLoopGroup();
		handler = new ServerHandler(this, settings);
		
		try {
			ServerBootstrap b = new ServerBootstrap();
			b.group(boss, worker).channel(NioServerSocketChannel.class)
					.childHandler(new ChannelInitializer<SocketChannel>() {
						@Override
						public void initChannel(SocketChannel ch) throws Exception {
							ch.pipeline().addLast(handler);
						}
					}).option(ChannelOption.SO_BACKLOG, 128).
					childOption(ChannelOption.SO_KEEPALIVE, true);
			
			ChannelFuture f = b.bind(port);
			ch = f.channel();
			
			ch.closeFuture().sync();
		} finally {
			worker.shutdownGracefully().sync();
			boss.shutdownGracefully().sync();
		}
	}

}
