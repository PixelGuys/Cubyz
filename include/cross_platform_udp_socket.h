#include <stdint.h>

void startup();

int init(unsigned short localPort);
int deinit(int socketID);
int sendTo(int socketID, const char* data, uintptr_t size, uint32_t ip, uint16_t port);
intptr_t receiveFrom(int socketID, char* buffer, uintptr_t size, int timeout, uint32_t* resultIP, uint16_t* resultPort);
uint32_t parseIP(const char* ip);

int getError();