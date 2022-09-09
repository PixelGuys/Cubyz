#ifdef _WIN32
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0600
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <sys/socket.h>
#include <netinet/in.h>
#include <sys/types.h>
#include <poll.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <arpa/inet.h>
#endif

#include <stdio.h>

#include <cross_platform_udp_socket.h>

int checkError(int in) {
	// TODO: Print the error here.
	return in;
}

void startup() {
#ifdef _WIN32
	WSADATA d;
	if (WSAStartup(MAKEWORD(2, 2), &d)) {
		fprintf(stderr, "Failed to initialize.\n");
	}
#endif
}

int init(unsigned short localPort) {
	int socketID = checkError(socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP));
	if(socketID == -1) return -1;
	struct sockaddr_in bindingAddr;
	bindingAddr.sin_family = AF_INET;
	bindingAddr.sin_port = htons(localPort);
	bindingAddr.sin_addr.s_addr = inet_addr("127.0.0.1");
	memset(&bindingAddr.sin_zero, 0, 8);
	if(checkError(bind(socketID, (const struct sockaddr*)&bindingAddr, sizeof(bindingAddr))) == -1) {
		close(socketID);
		return -1;
	};
	return socketID;
}

int deinit(int socketID) {
#ifdef _WIN32
	return checkError(closesocket(socketID));
#else
	return checkError(close(socketID));
#endif
}

int sendTo(int socketID, const char* data, uintptr_t size, uint32_t ip, uint16_t port) {
	struct sockaddr_in addr;
	addr.sin_family = AF_INET;
	addr.sin_port = htons(port);
	addr.sin_addr.s_addr = ip;
	memset(&addr.sin_zero, 0, 8);
	return checkError(sendto(socketID, data, size, 0, (const struct sockaddr*)&addr, sizeof(addr)));
}

intptr_t receiveFrom(int socketID, char* buffer, uintptr_t size, int timeout, uint32_t* resultIP, uint16_t* resultPort) {
	struct pollfd pfd = {.fd = socketID, .events = POLLIN};
#ifdef _WIN32
	intptr_t result = checkError(WSAPoll(&pfd, 1, timeout));
#else
	intptr_t result = checkError(poll(&pfd, 1, timeout));
#endif
	if(result <= 0) return result;
	struct sockaddr_in address;
	uint32_t addrLen = sizeof(address);
	result = checkError(recvfrom(socketID, buffer, size, 0, &address, &addrLen));
	
	*resultIP = address.sin_addr.s_addr;
	*resultPort = ntohs(address.sin_port);

	return result;
}
uint32_t parseIP(const char* ip) {
	return inet_addr(ip);
}

int getError() {
	return errno;
}