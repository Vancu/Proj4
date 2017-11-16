/**
 * ANDES Lab - University of California, Merced
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include "../includes/packet.h"
#include "../includes/sendInfo.h"
#include "../includes/channels.h"
#include "../includes/socket.h"

module TransportP{
    // provides shows the interface we are implementing. See lib/interface/Transport.nc
    // to see what funcitons we need to implement.
   provides interface Transport;

   //uses interface Hashmap<socket_store_t> as StateofSockets;
   uses interface List<socket_store_t> as Sockets;
   uses interface List<socket_store_t> as Modify_The_States;
   uses interface SimpleSend as Sender;
   uses interface List<RoutedTable> as ConfirmedList;
}

implementation{
    command socket_t Transport.socket()
    {
	socket_t fd;
    	socket_store_t CheckSocket;
	dbg(GENERAL_CHANNEL, "Successfully called a thing. Here's the Node ID that called it: %d\n", TOS_NODE_ID);
	
	if (call Sockets.size() < MAX_NUM_OF_SOCKETS)
	{
        	CheckSocket.fd = call Sockets.size();
		CheckSocket.used = TRUE;
		call Sockets.pushback(CheckSocket);
		return CheckSocket.fd;
	}

	else
 	{
		dbg(TRANSPORT_CHANNEL, "Returned NULL\n");
		return fd = -1;
	}	
    }

   /**
    * Bind a socket with an address.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       you are binding.
    * @param
    *    socket_addr_t *addr: the source port and source address that
    *       you are biding to the socket, fd.
    * @Side Client/Server
    * @return error_t - SUCCESS if you were able to bind this socket, FAIL
    *       if you were unable to bind.
    */

   command error_t Transport.bind(socket_t fd, socket_addr_t *addr)
    {
	//dbg(GENERAL_CHANNEL, "Successfully called a thing. Here's the Node ID that called it: %d\n", TOS_NODE_ID);
    	uint8_t i;
	socket_store_t BindSocket;
	socket_addr_t Address_Bind;
	bool Modified = FALSE;

	//What we want to do is because we cannot directly modify the content in the list, we want to check to see if we have a match in FD
	//if there's a match and it hasn't been found already, we want to modify it's contents so that it's directly bonded. If not, we just 
	//Move the contents are either continue looking if we haven't found it or just move it while we already modified one of the indexes.
	while (!call Sockets.isEmpty())
	{
		BindSocket = call Sockets.front();
		call Sockets.popfront();
		if (BindSocket.fd == fd && !Modified)
		{
			Address_Bind.port = addr->port;
			Address_Bind.addr = addr->addr;
			BindSocket.dest	= Address_Bind;
			Modified = TRUE;
			dbg(TRANSPORT_CHANNEL, "fd found, inserting addr of node %d to port %d\n", Address_Bind.addr, Address_Bind.port);
			call Modify_The_States.pushfront(BindSocket);
		} 
		
		else
			call Modify_The_States.pushfront(BindSocket);
		
	}
	
	while (!call Modify_The_States.isEmpty())
	{
		call Sockets.pushfront(call Modify_The_States.front());
		call Modify_The_States.popfront();
	}
		
	i = 0;
	while (!call Sockets.isEmpty())
	{
		BindSocket = call Sockets.get(i);
		if (!BindSocket.used)
			break;
		dbg(TRANSPORT_CHANNEL, "We're going to attempt to print out addr of Index: %d.  Addr: %d with port: %d\n", i, BindSocket.dest.addr, BindSocket.dest.port);
		i++;
	}	
	if (Modified)
		return SUCCESS;

	else
		return FAIL;
    }

   /**
    * Checks to see if there are socket connections to connect to and
    * if there is one, connect to it.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that is attempting an accept. remember, only do on listen. 
    * @side Server
    * @return socket_t - returns a new socket if the connection is
    *    accepted. this socket is a copy of the server socket but with
    *    a destination associated with the destination address and port.
    *    if not return a null socket.
    */

   command socket_t Transport.accept(socket_t fd)
    {

    }

   /**
    * Write to the socket from a buffer. This data will eventually be
    * transmitted through your TCP implimentation.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that is attempting a write.
    * @param
    *    uint8_t *buff: the buffer data that you are going to wrte from.
    * @param
    *    uint16_t bufflen: The amount of data that you are trying to
    *       submit.
    * @Side For your project, only client side. This could be both though.
    * @return uint16_t - return the amount of data you are able to write
    *    from the pass buffer. This may be shorter then bufflen
    */

   command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen)
    {

    }

   /**
    * This will pass the packet so you can handle it internally. 
    * @param
    *    pack *package: the TCP packet that you are handling.
    * @Side Client/Server 
    * @return uint16_t - return SUCCESS if you are able to handle this
    *    packet or FAIL if there are errors.
    */

   command error_t Transport.receive(pack* package)
   {

   }

   /**
    * Read from the socket and write this data to the buffer. This data
    * is obtained from your TCP implimentation.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that is attempting a read.
    * @param
    *    uint8_t *buff: the buffer that is being written.
    * @param
    *    uint16_t bufflen: the amount of data that can be written to the
    *       buffer.
    * @Side For your project, only server side. This could be both though.
    * @return uint16_t - return the amount of data you are able to read
    *    from the pass buffer. This may be shorter then bufflen
    */

   command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen)
   {
   
   }

   /**
    * Attempts a connection to an address.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are attempting a connection with. 
    * @param
    *    socket_addr_t *addr: the destination address and port where
    *       you will atempt a connection.
    * @side Client
    * @return socket_t - returns SUCCESS if you are able to attempt
    *    a connection with the fd passed, else return FAIL.
    */
   command error_t Transport.connect(socket_t fd, socket_addr_t * addr)
   {
	//dbg(GENERAL_CHANNEL, "Successfully called a thing. Here's the Node ID that called it: %d\n", TOS_NODE_ID);
        uint8_t i;
        RoutedTable calculatedTable;
	socket_store_t BindSocket;
        pack SynchroPacket;
	enum socket_state ChangeState;
        bool Modified = FALSE;

	SynchroPacket.src = TOS_NODE_ID;
	SynchroPacket.dest = addr->addr;
	SynchroPacket.seq = 1;
	SynchroPacket.TTL = MAX_TTL;
	SynchroPacket.protocol = PROTOCOL_TCP;

        for(i = 0; i < call ConfirmedList.size(); i++)
        {

                calculatedTable = call ConfirmedList.get(i);
                if (calculatedTable.Node_ID == addr->addr)
                {
			call Sender.send(SynchroPacket, calculatedTable.Next);
                        break;
                }
        }
	
	call Sender.send(SynchroPacket, addr->addr);	
        //What we want to do is because we cannot directly modify the content in the list, we want to check to see if we have a match in FD
        //if there's a match and it hasn't been found already, we want to modify it's contents so that it's directly bonded. If not, we just
        //Move the contents are either continue looking if we haven't found it or just move it while we already modified one of the indexes.
        while (!call Sockets.isEmpty())
        {
                BindSocket = call Sockets.front();
                call Sockets.popfront();
                if (BindSocket.fd == fd && !Modified && BindSocket.state == LISTEN)
                {
                        ChangeState = ESTABLISHED;
                        BindSocket.state = ChangeState;
                        Modified = TRUE;
                        //dbg(TRANSPORT_CHANNEL, "fd found, Also changing the state to LISTEN in addr: %d which is in port: %d\n", BindSocket.addr, BindSocket.port);
                        call Modify_The_States.pushfront(BindSocket);
                }

                else
                        call Modify_The_States.pushfront(BindSocket);

        }

        while (!call Modify_The_States.isEmpty())
        {
                call Sockets.pushfront(call Modify_The_States.front());
                call Modify_The_States.popfront();
        }

        i = 0;
        while (!call Sockets.isEmpty())
        {
                BindSocket = call Sockets.get(i);
                if (!BindSocket.used)
                        break;

                if (BindSocket.state == ESTABLISHED)
                        dbg(TRANSPORT_CHANNEL, "~~~~~~~HELLO~~~~~~~~ Index which has a changed from LISTEN to ESTABLISHED. Print out  Index: %d.  Addr: %d with port: %d\n", i, BindSocket.dest.addr, BindSocket.dest.port);
                i++;
        }
        if (Modified)
                return SUCCESS;

        else
                return FAIL;
   }

   /**
    * Closes the socket.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are closing. 
    * @side Client/Server
    * @return socket_t - returns SUCCESS if you are able to attempt
    *    a closure with the fd passed, else return FAIL.
    */
   command error_t Transport.close(socket_t fd)
   {

   }

   /**
    * A hard close, which is not graceful. This portion is optional.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are hard closing. 
    * @side Client/Server
    * @return socket_t - returns SUCCESS if you are able to attempt
    *    a closure with the fd passed, else return FAIL.
    */
   command error_t Transport.release(socket_t fd)
   {

   }

   /**
    * Listen to the socket and wait for a connection.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are hard closing. 
    * @side Server
    * @return error_t - returns SUCCESS if you are able change the state 
    *   to listen else FAIL.
    */
   command error_t Transport.listen(socket_t fd)
   {
	//dbg(GENERAL_CHANNEL, "Successfully called a thing. Here's the Node ID that called it: %d\n", TOS_NODE_ID);
        uint8_t i;
        socket_store_t BindSocket;
        enum socket_state ChangeState;
        bool Modified = FALSE;

        //What we want to do is because we cannot directly modify the content in the list, we want to check to see if we have a match in FD
        //if there's a match and it hasn't been found already, we want to modify it's contents so that it's directly bonded. If not, we just
        //Move the contents are either continue looking if we haven't found it or just move it while we already modified one of the indexes.
        while (!call Sockets.isEmpty())
        {
                BindSocket = call Sockets.front();
                call Sockets.popfront();
                if (BindSocket.fd == fd && !Modified)
                {
			ChangeState = LISTEN;
                        BindSocket.state = ChangeState;
                        Modified = TRUE;
                        //dbg(TRANSPORT_CHANNEL, "fd found, Also changing the state to LISTEN in addr: %d which is in port: %d\n", BindSocket.addr, BindSocket.port);
                        call Modify_The_States.pushfront(BindSocket);
                }

                else
                        call Modify_The_States.pushfront(BindSocket);

        }

        while (!call Modify_The_States.isEmpty())
        {
                call Sockets.pushfront(call Modify_The_States.front());
                call Modify_The_States.popfront();
        }

        i = 0;
        while (!call Sockets.isEmpty())
        {
                BindSocket = call Sockets.get(i);
                if (!BindSocket.used)
                        break;
                
		if (BindSocket.state == LISTEN)
			dbg(TRANSPORT_CHANNEL, "There should be no change except the index which has a changed to LISTEN. Print out  Index: %d.  Addr: %d with port: %d\n", i, BindSocket.dest.addr, BindSocket.dest.port);
                i++;
        }
        if (Modified)
                return SUCCESS;

        else
                return FAIL;
   }

}
