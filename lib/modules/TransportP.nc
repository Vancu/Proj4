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
   //uses interface Random as Random;
}

implementation{
   //Global Socket Index used in function readval and accept.
   socket_t SocketIndex; 
   //Here, we want to manipulate a variable in our list, here's the function to do that
   error_t ChangeVal(socket_t fd, socket_addr_t *addr, uint8_t flag);

   //Here, we want to check for a flag or other data in our list. Here's our function to do that
   error_t ReadVal(socket_t fd, uint8_t flag);

   //This searchPack is specific to a single node. This is for when we want to alter any kind of information inside the Socket, whether it be states, addr, port, etc.
   //Returns Success if able to alter data or FAIL if no data was altered.
   error_t ChangeVal(socket_t fd, socket_addr_t *addr, uint8_t flag)
   {
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
                        BindSocket.src = Address_Bind.port;
                        Modified = TRUE;
                        dbg(TRANSPORT_CHANNEL, "fd found with flag BIND, binding node %d to port %d\n", addr->addr, addr->port);
                        call Modify_The_States.pushfront(BindSocket);
                }
		
		//Flag 2 = Listen
		else if (BindSocket.fd == fd && !Modified && flag == 2)
		{
			enum socket_state ChangeState;
                        ChangeState = LISTEN;
                        BindSocket.state = ChangeState;
                        Modified = TRUE;
                        dbg(TRANSPORT_CHANNEL, "fd found with flag LISTEN, Also changing the state to LISTEN in port: %d (same as TOS_NODE_ID) Assume that the port reported above is true\n", BindSocket.src);
                        call Modify_The_States.pushfront(BindSocket);

		}
		
		//Flag 3 = Connect
		else if (BindSocket.fd == fd && !Modified && flag == 3)
		{
			dbg(TRANSPORT_CHANNEL, "Connect call was fired, lets see if I can change the state...\n");

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

        if (Modified)
                return SUCCESS;

        else
                return FAIL;
   }

   error_t ReadVal(socket_t fd, uint8_t flag)
   {
   	uint8_t i;
   	socket_store_t BindSocket;
	i = 0;
        while (i < call Sockets.size())
        {
		BindSocket = call Sockets.get(i);
   		
		//Flag 1 = Accept;
   		if  (BindSocket.fd == fd && flag == 1 && BindSocket.state == LISTEN)
   		{       
   			SocketIndex = fd;
        		return SUCCESS;                
   		}

		//Flag 2 = Used in Read part of TransportP
		else if (BindSocket.fd == fd && flag == 2)
		{
			SocketIndex = fd;
                        return SUCCESS;
		}
	}

	//Wasn't able to find the fd or the fd's state wasn't LISTEN
	return FAIL;
   }

    //Checks to see if there's space in List to initialize a socket with default values.
    //By returning a socket_t, we're returning an index within List. By returning 255, We have an no more room in List.
    command socket_t Transport.socket()
    {
	//socket_t fd;
    	socket_store_t CheckSocket;
	uint8_t i;
	
	//If we have more than MAX_NUM_OF_SOCKETS, then we send a FAIL, alerting that we cannot set-up to bind and more ports	
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
		CheckSocket.effectiveWindow = SOCKET_BUFFER_SIZE;
		CheckSocket.RTT = 0;
		//Initialize the Send and Recieve Buffers
		for(i = 0; i < SOCKET_BUFFER_SIZE; i++)
		{
			CheckSocket.rcvdBuff[i] = 250;
                        CheckSocket.sendBuff[i] = 250;			
		}
		call Sockets.pushback(CheckSocket);
		return CheckSocket.fd;
	}

	else
 	{
		dbg(TRANSPORT_CHANNEL, "Returned NULL set as 255. No more room in Socket List\n");
		return 255;
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
	error_t BindFunc;
	uint8_t i;
	socket_store_t BindSocket;
	//Check to see if I'm able to bind. Generally if socket() function call was successfully able to return a valid index fd, BindFunc will return Success
	//As it's able to bind addr's port in index fd.
	BindFunc = ChangeVal(fd, addr, 1);
	
	i = 0;
	//A simple print to see what ports have been Binded with TOS_NODE_ID
        while (i < call Sockets.size())
        {
                BindSocket = call Sockets.get(i);
                if (!BindSocket.used)
                        break;
                dbg(TRANSPORT_CHANNEL, "We're going to attempt to print out all ports. Index: %d.  Node: %d with port: %d\n", i, TOS_NODE_ID, BindSocket.src);
                i++;
        }
	
	return BindFunc;	
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

   //Unsure if this works since I'm using Receive.receive in Node.nc to handle accepts of payload that are structs of socket_store_t
   command socket_t Transport.accept(socket_t fd)
    {
        error_t CheckFD;
	CheckFD = ReadVal(fd, 1);	
    
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

    //This is generally from the client side. We want to write Client's buffer content that was passed in to it's sendBuff[SOCKET_BUFFER_SIZE], 
    //Which should then be put in a packet and sent to the server to be read (haven't implimented that aspect).
    //In the end, we return how much data we were able to write from buff to Client's sendBuff.
    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen)
    {
	socket_store_t WriteSocket;
        uint8_t BufferIndex, i;
        uint16_t Able_to_Write;
        bool Modified = FALSE;

	Able_to_Write = 0;
        
	//Reason why I'm not sending to the function defined above is because we are required to write from buffer sent from this function.
        //It would be redundant to overload the function
        //WE ARE ALSO IN AN INDEX SOMEWHERE, WE'RE NOT STARTING AT FRONT
        while (!call Sockets.isEmpty())
        {
                WriteSocket = call Sockets.front();
                call Sockets.popfront();       
		//In Write, we want to move data from buff to Socket's sendBuff.
		if (WriteSocket.fd == fd && !Modified)
                {
                        BufferIndex = WriteSocket.lastWritten;

                       	//Begin to write data from buff onto Server's Received buff
                        for(i = 0; i < bufflen; i++)
                       	{
                                WriteSocket.sendBuff[BufferIndex] = buff[i];
        	                BufferIndex++;
				
				//We've run out of space inside sendBuff... 
				if (BufferIndex >= SOCKET_BUFFER_SIZE)
					break;
                        }
			
			//Amount of data we were able to write which will be returned after moving all data to temp and back to main list
                        Able_to_Write = bufflen;

			WriteSocket.lastWritten = BufferIndex;
                        //Now that we've writen content to the rcvdBuff, change the effective Window
                        dbg(TRANSPORT_CHANNEL, "Here, we successfully altered the SENDBUFFER. Maybe try printing out the values\n");

                        //As a test, begin to write data from sendBuff, THIS MAY PRINT GARBAGE VALUES IF NOT COMPLETELY FILLED.
                        dbg(TRANSPORT_CHANNEL, "------------------------\n");
			for(i = 0; i < SOCKET_BUFFER_SIZE; i++)
                        {       
				dbg(TRANSPORT_CHANNEL, "%d\n", WriteSocket.sendBuff[i]);
                                
                        }
			dbg(TRANSPORT_CHANNEL, "------------------------\n");
                        
			//At this point we have writen all or as much data into the rcvdBuff, so go ahead and push into temp list where it will be pused back into main
                        Modified = TRUE;
                        call Modify_The_States.pushfront(WriteSocket);
                }

                else
                        call Modify_The_States.pushfront(WriteSocket);

        }

        while (!call Modify_The_States.isEmpty())
        {
                call Sockets.pushfront(call Modify_The_States.front());
                call Modify_The_States.popfront();
        }

	return Able_to_Write;

    }

   /**
    * This will pass the packet so you can handle it internally. 
    * @param
    *    pack *package: the TCP packet that you are handling.
    * @Side Client/Server 
    * @return uint16_t - return SUCCESS if you are able to handle this
    *    packet or FAIL if there are errors.
    */

   //Receive is mainly handled in node.nc's Receive.receive.
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

    //This is generally from the Server side. We want to write Client's buffer content that was passed in to the server's rcvdBuff[SOCKET_BUFFER_SIZE],
    //Which should then make a packet and send ACKs for eact time it recieves some data. Asks the client to send more data (haven't implimented that aspect).
   //In the end, we return how much data the server was able to read from buff sent from Client's sendBuff which is written to Server's rcvdBuff. 
    command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen)
    {
   	socket_store_t WriteSocket, EditedSocket;
	uint8_t BufferIndex, i;
        uint16_t Able_to_Read;
	bool Modified = FALSE;
	
        //Reason why I'm not sending to the function defined above is because we are required to write from buffer sent from this function.
        //It would be redundant to overload the function
        //WE ARE ALSO IN AN INDEX SOMEWHERE, WE'RE NOT STARTING AT FRONT
        while (!call Sockets.isEmpty())
       	{
        	WriteSocket = call Sockets.front();
                call Sockets.popfront();
                
		//Find that specific Socket and write to server's buffer
		if (WriteSocket.fd == fd && !Modified)
                {
			BufferIndex = WriteSocket.nextExpected;
                	//WriteSocket = call Sockets.get(fd);
                	//Check to see if the size of buffer (data we plan on writing) is more than the "effective window" of that socket
                	//Drop the packet if this is the case;
                	
			if (WriteSocket.effectiveWindow < bufflen)
                	{
				Able_to_Read = WriteSocket.effectiveWindow;
                               	//Begin to write data from buff onto Server's Received buff
                                for(i = 0; i < Able_to_Read; i++)
                                {       
                                        WriteSocket.rcvdBuff[BufferIndex] = buff[i];
                                        BufferIndex++;
                                }
				WriteSocket.effectiveWindow = WriteSocket.effectiveWindow - Able_to_Read;
                	}

                	//This means we have enough space to write into the buffer
                	//You start with that Socket's (Server's) next expected and move(write) content from buff to recieved buffer
              
			else
                	{
				//Begin to write data from buff onto Server's Received buff
                 	      	for(i = 0; i < bufflen; i++)
                  	      	{
                              		WriteSocket.rcvdBuff[BufferIndex] = buff[i];
                              		BufferIndex++;
                        	}
                       		Able_to_Read = bufflen; 
	                        //Now that we've writen content to the rcvdBuff, change the effective Window
        	                WriteSocket.effectiveWindow = WriteSocket.effectiveWindow - bufflen;
				dbg(TRANSPORT_CHANNEL, "Here, we successfully altered the RCVDBUFFER and the EffectiveWindow should theoretically be changed. Lets Print it: %d, \n", EditedSocket.effectiveWindow);
                
			}

			WriteSocket.nextExpected = BufferIndex;
			
			//As a test, begin to print writen data from sendBuff, THIS MAY PRINT GARBAGE VALUES.
                        dbg(TRANSPORT_CHANNEL, "----------READ VALUES--------------\n");
                        for(i = 0; i < SOCKET_BUFFER_SIZE; i++)
                        {
                                dbg(TRANSPORT_CHANNEL, "%d\n", WriteSocket.rcvdBuff[i]);
                                
                        }
                        dbg(TRANSPORT_CHANNEL, "----------END OF READ--------------\n");
			//At this point we have writen all or as much data into the rcvdBuff, so go ahead and push into temp list where it will be pused back into main
                        Modified = TRUE;
                        call Modify_The_States.pushfront(WriteSocket);
               	}

                else
               		call Modify_The_States.pushfront(WriteSocket);

       	}

        while (!call Modify_The_States.isEmpty())
        {
        	call Sockets.pushfront(call Modify_The_States.front());
                call Modify_The_States.popfront();
        }	

	return Able_to_Read;
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

   //What we do with connect is we make a struct of socket_store_t and fill in that struct with appropriate data such as the flag for SYN, what the destination port and addr is. 
   //This struct will represent the payload of the packet which is also created in this function. The packet has the src of TOS_NODE_ID, dest of addr->addr which is where we want the packet to go
   //along with TTL, seq, and protocol set. After the making of the packet and struct, traverse thru the Routed Table to find out which node to send it to and send it. Node.nc's Receive handles this paclet.
   command error_t Transport.connect(socket_t fd, socket_addr_t * addr)
   {
	//dbg(GENERAL_CHANNEL, "Successfully called a thing. Here's the Node ID that called it: %d\n", TOS_NODE_ID);
        error_t ChangeState;
	uint8_t i;
	//uint8_t port;
        RoutedTable calculatedTable;
	socket_store_t SocketFlag;
        pack SynchroPacket;
	//enum socket_state ChangeState;
        bool MadePacket = FALSE;

	ChangeState = ChangeVal(fd, addr, 3);
	SocketFlag = call Sockets.get(fd);
	//FLAG IS FOR SYN
	SocketFlag.flag = 1;
	SocketFlag.dest.port = addr->port;
	SocketFlag.dest.addr = addr->addr;
	//port = addr->port;
	SynchroPacket.src = TOS_NODE_ID;
	SynchroPacket.dest = addr->addr;
	SynchroPacket.seq = 1;
	SynchroPacket.TTL = MAX_TTL;
	SynchroPacket.protocol = PROTOCOL_TCP;
	//SynchroPacket.payload = port;
	memcpy(SynchroPacket.payload, &SocketFlag, (uint8_t) sizeof(SocketFlag));   
	for(i = 0; i < call ConfirmedList.size(); i++)
        {

                calculatedTable = call ConfirmedList.get(i);
                if (calculatedTable.Node_ID == addr->addr)
                {
			call Sender.send(SynchroPacket, calculatedTable.Next);
			MadePacket = TRUE;
                        break;
                }
        }
	 dbg(TRANSPORT_CHANNEL, "We're out of the for loop\n");
	if (MadePacket)
		return SUCCESS;

	else
		return FALSE;
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
   //Simple close function which changes initial socket's state to CLOSED. The optimal way to go about this is to close connection with both the client and address
   //At the moment, it only closes what it gives in. 
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
   //Simple function to simply change the state of the index of Socket to be in a LISTEN state. Generally happens after a successful bind.
   command error_t Transport.listen(socket_t fd)
   {
	socket_addr_t * addr;
	return ChangeVal(fd, addr, 2);
   }

}
