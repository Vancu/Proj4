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

   socket_t SocketIndex; 
   //Here, we want to manipulate a variable in our list, here's the function to do that
   error_t ChangeVal(socket_t fd, socket_addr_t *addr, uint8_t flag);

   //Here, we want to check for a flag or other data in our list. Here's our function to do that
   error_t ReadVal(socket_t fd);


   //This searchPack is specific to a single node. This is also enabling for when this node recieves the same packet from a different
   error_t ChangeVal(socket_t fd, socket_addr_t *addr, uint8_t flag)
   {
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
                
		//Flag = 1 BIND
		if (BindSocket.fd == fd && !Modified && flag == 1)
                {
                        Address_Bind.port = addr->port;
                        Address_Bind.addr = addr->addr;
                        BindSocket.dest = Address_Bind;
                        Modified = TRUE;
                        dbg(TRANSPORT_CHANNEL, "fd found with flag BIND, inserting addr of node %d to port %d\n", Address_Bind.addr, Address_Bind.port);
                        call Modify_The_States.pushfront(BindSocket);
                }
		
		//Flag 2 = Listen
		else if (BindSocket.fd == fd && !Modified && flag == 2)
		{
			enum socket_state ChangeState;
                        ChangeState = LISTEN;
                        BindSocket.state = ChangeState;
                        Modified = TRUE;
                        dbg(TRANSPORT_CHANNEL, "fd found with flag LISTEN, Also changing the state to LISTEN in addr: %d (same as TOS_NODE_ID) Assume that the port reported above is true\n", TOS_NODE_ID);
                        call Modify_The_States.pushfront(BindSocket);

		}
		
		//Flag 3 = Connect
		else if (BindSocket.fd == fd && !Modified && flag == 3)
		{
			dbg(TRANSPORT_CHANNEL, "Connect is fake established/will change flags\n");

			if (BindSocket.state == CLOSED)
			{
				enum socket_state ChangeState;
                        	ChangeState = SYN_SENT;
                        	BindSocket.state = ChangeState;
                        	Modified = TRUE;
				dbg(TRANSPORT_CHANNEL, "State is closed, should we change it to SYN_SENT.	We are going to change the state.\n");
				call Modify_The_States.pushfront(BindSocket);
			}
		}

		//Flag 4 = Close
		else if (BindSocket.fd == fd && !Modified && flag == 4)
		{
                        enum socket_state ChangeState;
                        ChangeState = CLOSED;
                        BindSocket.state = ChangeState;
                        Modified = TRUE;
                        dbg(TRANSPORT_CHANNEL, "State is closed, should we change it to CLOSED.       We are going to change the state.\n");
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
        while (i < call Sockets.size())
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

   error_t ReadVal(socket_t fd)
   {
   	uint8_t i;
   	socket_store_t BindSocket;
	i = 0;
        while (i < call Sockets.size())
        {
		BindSocket = call Sockets.get(i);
   		//This is for Accept;
   		if  (BindSocket.fd == fd  && BindSocket.state == LISTEN)
   		{       
   			SocketIndex = fd;
        		return SUCCESS;                
   		}
	}

	//Wasn't able to find the fd or the fd's state wasn't LISTEN
	return FAIL;
   }
    command socket_t Transport.socket()
    {
	//socket_t fd;
    	socket_store_t CheckSocket;
	dbg(GENERAL_CHANNEL, "Successfully called a thing. Here's the Node ID that called it: %d\n", TOS_NODE_ID);
	
	if (call Sockets.size() < MAX_NUM_OF_SOCKETS)
	{
        	CheckSocket.fd = call Sockets.size();
		CheckSocket.used = TRUE;
		CheckSocket.state = CLOSED;
		CheckSocket.lastAck = 0;
		CheckSocket.lastSent = 0;
		CheckSocket.lastRead = 0;
		CheckSocket.lastWritten = 0;
		CheckSocket.lastRcvd = 0;
		CheckSocket.nextExpected = 0;
		CheckSocket.effectiveWindow = 1;
		call Sockets.pushback(CheckSocket);
		return CheckSocket.fd;
	}

	else
 	{
		dbg(TRANSPORT_CHANNEL, "Returned NULL set as 250\n");
		return 250;
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
	return ChangeVal(fd, addr, 1);	
/*	//dbg(GENERAL_CHANNEL, "Successfully called a thing. Here's the Node ID that called it: %d\n", TOS_NODE_ID);
*    	uint8_t i;
*	socket_store_t BindSocket;
*	socket_addr_t Address_Bind;
*	bool Modified = FALSE;
*
*	//What we want to do is because we cannot directly modify the content in the list, we want to check to see if we have a match in FD
*	//if there's a match and it hasn't been found already, we want to modify it's contents so that it's directly bonded. If not, we just 
*	//Move the contents are either continue looking if we haven't found it or just move it while we already modified one of the indexes.
*	while (!call Sockets.isEmpty())
*	{
*		BindSocket = call Sockets.front();
*		call Sockets.popfront();
*		if (BindSocket.fd == fd && !Modified)
*		{
*			Address_Bind.port = addr->port;
*			Address_Bind.addr = addr->addr;
*			BindSocket.dest	= Address_Bind;
*			Modified = TRUE;
*			dbg(TRANSPORT_CHANNEL, "fd found, inserting addr of node %d to port %d\n", Address_Bind.addr, Address_Bind.port);
*			call Modify_The_States.pushfront(BindSocket);
*		} 
*		
*		else
*			call Modify_The_States.pushfront(BindSocket);
*		
*	}
*	
*	while (!call Modify_The_States.isEmpty())
*	{
*		call Sockets.pushfront(call Modify_The_States.front());
*		call Modify_The_States.popfront();
*	}
*		
*	i = 0;
*	while (!call Sockets.isEmpty())
*	{
*		BindSocket = call Sockets.get(i);
*		if (!BindSocket.used)
*			break;
*		dbg(TRANSPORT_CHANNEL, "We're going to attempt to print out addr of Index: %d.  Addr: %d with port: %d\n", i, BindSocket.dest.addr, BindSocket.dest.port);
*		i++;
*	}	
*	if (Modified)
*		return SUCCESS;
*
*	else
*/		return FAIL;
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
        error_t CheckFD;
	CheckFD = ReadVal(fd);	
    
	if (CheckFD == SUCCESS)
		return SocketIndex;

	else
	{
		dbg(TRANSPORT_CHANNEL, "Socket %d was not available or doesn't have state LISTEN, Connection not accepted.\n", fd);
		return 250;		
    	}
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
	//One of the errors you want to check is to see if the packet received even is for the TCP Protocol
	if (package->protocol == PROTOCOL_TCP)
		return SUCCESS;

	else
		return FAIL;
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
        error_t Push_into_List;
	uint8_t i;
	uint8_t port;
        RoutedTable calculatedTable;
	//socket_store_t BindSocket;
        pack SynchroPacket;
	//enum socket_state ChangeState;
        //bool Modified = FALSE;

	port = addr->port;
	SynchroPacket.src = TOS_NODE_ID;
	SynchroPacket.dest = addr->addr;
	SynchroPacket.seq = 1;
	SynchroPacket.TTL = MAX_TTL;
	SynchroPacket.protocol = PROTOCOL_TCP;
	//SynchroPacket.payload = port;
	for(i = 0; i < call ConfirmedList.size(); i++)
        {

                calculatedTable = call ConfirmedList.get(i);
                if (calculatedTable.Node_ID == addr->addr)
                {
			call Sender.send(SynchroPacket, calculatedTable.Next);
                        break;
                }
        }
	
	//call Sender.send(SynchroPacket, addr->addr);

	//We want to bind onto list, then afterwards we want to see if we can connect/
	return Push_into_List = ChangeVal(fd, addr, 3);	
/*        //What we want to do is because we cannot directly modify the content in the list, we want to check to see if we have a match in FD
*        //if there's a match and it hasn't been found already, we want to modify it's contents so that it's directly bonded. If not, we just
 *       //Move the contents are either continue looking if we haven't found it or just move it while we already modified one of the indexes.
  *      while (!call Sockets.isEmpty())
   *     {
    *            BindSocket = call Sockets.front();
     *           call Sockets.popfront();
      *          if (BindSocket.fd == fd && !Modified && BindSocket.state == LISTEN)
       *         {
        *                ChangeState = ESTABLISHED;
         *               BindSocket.state = ChangeState;
          *              Modified = TRUE;
           *             //dbg(TRANSPORT_CHANNEL, "fd found, Also changing the state to LISTEN in addr: %d which is in port: %d\n", BindSocket.addr, BindSocket.port);
            *            call Modify_The_States.pushfront(BindSocket);
             *   }
*
 *               else
  *                      call Modify_The_States.pushfront(BindSocket);
*
 *       }
*
 *       while (!call Modify_The_States.isEmpty())
  *      {
   *             call Sockets.pushfront(call Modify_The_States.front());
    *            call Modify_The_States.popfront();
     *   }
*
*        i = 0;
 *       while (!call Sockets.isEmpty())
  *      {
   *             BindSocket = call Sockets.get(i);
    *            if (!BindSocket.used)
     *                   break;
*
 *               if (BindSocket.state == ESTABLISHED)
  *                      dbg(TRANSPORT_CHANNEL, "~~~~~~~HELLO~~~~~~~~ Index which has a changed from LISTEN to ESTABLISHED. Print out  Index: %d.  Addr: %d with port: %d\n", i, BindSocket.dest.addr, BindSocket.dest.port);
   *             i++;
    *    }
     *   if (Modified)
      *          return SUCCESS;

       * else
    *            return FAIL;
   
*/  }

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
	socket_addr_t * addr;
        return ChangeVal(fd, addr, 4);
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
	socket_addr_t * addr;
	return ChangeVal(fd, addr, 2);
/*	//dbg(GENERAL_CHANNEL, "Successfully called a thing. Here's the Node ID that called it: %d\n", TOS_NODE_ID);
*       uint8_t i;
*       socket_store_t BindSocket;
*       enum socket_state ChangeState;
*       bool Modified = FALSE;
*
*       //What we want to do is because we cannot directly modify the content in the list, we want to check to see if we have a match in FD 
*       //if there's a match and it hasn't been found already, we want to modify it's contents so that it's directly bonded. If not, we just
*       //Move the contents are either continue looking if we haven't found it or just move it while we already modified one of the indexes.
*        while (!call Sockets.isEmpty())
 *       {
  *              BindSocket = call Sockets.front();
   *             call Sockets.popfront();
    *            if (BindSocket.fd == fd && !Modified)
     *           {
*			ChangeState = LISTEN;
 *                       BindSocket.state = ChangeState;
  *                      Modified = TRUE;
   *                     //dbg(TRANSPORT_CHANNEL, "fd found, Also changing the state to LISTEN in addr: %d which is in port: %d\n", BindSocket.addr, BindSocket.port);
    *                    call Modify_The_States.pushfront(BindSocket);
     *           }
*
 *               else
  *                      call Modify_The_States.pushfront(BindSocket);
*
 *       }
*
 *       while (!call Modify_The_States.isEmpty())
  *      {
   *             call Sockets.pushfront(call Modify_The_States.front());
    *            call Modify_The_States.popfront();
     *   }
*
 *       i = 0;
  *      while (!call Sockets.isEmpty())
   *     {
    *            BindSocket = call Sockets.get(i);
     *           if (!BindSocket.used)
      *                  break;
       *         
	*	if (BindSocket.state == LISTEN)
	*		dbg(TRANSPORT_CHANNEL, "There should be no change except the index which has a changed to LISTEN. Print out  Index: %d.  Addr: %d with port: %d\n", i, BindSocket.dest.addr, BindSocket.dest.port);
         *       i++;
        *}
       * if (Modified)
        *        return SUCCESS;

      *  else
       *         return FAIL;
 */  }

}
