interface CommandHandler{
   // Events
   event void ping(uint16_t destination, uint8_t *payload);
   event void printNeighbors();
   event void printRouteTable();
   event void printLinkState();
   event void printDistanceVector();
   event void setTestServer(uint8_t port);
   event void setTestClient(uint8_t dest, uint8_t srcPort, uint8_t destPort, uint16_t transfer);
   event void ClientClose(uint16_t ClientAddress, uint8_t srcPort, uint8_t destPort, uint16_t dest);
   event void setAppServer();
   event void setAppClient();
   event void AppLogin(uint8_t clientport, char* username);
   event void AppBroadCast(char* message);
   event void AppUnicast(char* username, char* message);
   event void AppPrintUsers();
 
}
