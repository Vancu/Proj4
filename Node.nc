/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/socket.h"
//Struct for Neighbor which houses NODE ID AND NumofPings
typedef nx_struct LinkedNeighbor {
	//Node ID and Number of Pings is Stored. This is how we determine the age of the neighbor
	nx_uint16_t Node_ID;
	nx_uint8_t NumofPings;
}LinkedNeighbor;

typedef nx_struct RoutedTable {
        //Node ID and Number of Pings is Stored. This is how we determine the age of the neighbor
        nx_uint16_t Node_ID;
        nx_uint8_t Cost;
	nx_uint8_t Next;
	nx_uint8_t sequence;
	nx_uint8_t AllNeighbors[64];
	nx_uint8_t AllNeighborsLength;
}RoutedTable;

module Node{
   uses interface Boot;
   uses interface Timer<TMilli> as periodicTimer; //Interface that was wired above.
   uses interface LocalTime<TMilli>;
   //uses interface Timer<TMilli> as LSP_Timer; //Interface that was wired above.
   //List of packs to store the info of identified packets, along if we've seen it or not  
   uses interface List<pack> as PacketStorage;   

   //List of structs that holds both Node ID and amount of times pinged to keep track of the neighbors, neighbor will be dropped if number of pings gets too large
   uses interface List<LinkedNeighbor > as NeighborStorage;
   
   //List of structs that holds the LinkedNeighbors that ended up being dropped from NeighborStorage
   uses interface List<LinkedNeighbor > as NeighborsDropped;
   
   uses interface SplitControl as AMControl;

   // Flooding Portion
   uses interface Receive;
   uses interface SimpleSend as Sender;


   uses interface CommandHandler;
   uses interface Random as Random;
   uses interface List<RoutedTable  > as RoutedTableStorage;
   uses interface List<RoutedTable  > as Tentative;
   uses interface List<RoutedTable  > as ConfirmedTable;
   uses interface List<socket_store_t> as SocketState;
   uses interface List<socket_store_t> as Modify_The_States; 
   uses interface Transport;
}

//These are stored in each node
implementation{
   pack sendPackage;
   uint16_t sequence = 0;
   uint16_t LSP_Limit = 0;
   bool Route_LSP_STOP = FALSE;

   //Global variable for index for list SocketState.
   socket_t socket;

   //Global variable for Transfer. For when Receive needs to handle the amount that needs to be transfered.
   uint16_t GlobalTransfer;

   //This is for recording the instance of time where we make the packet that's going to be sent to Server. This is used in conjunction of TimeReceived for when server node
   //Receives it to calculate one half of RTT.
   uint16_t TimeSent;
   uint16_t TimeReceied;

   // Prototypes (aka function definitions that are exclusively in this implimentation
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   //Handles new seen and sent packs by storing into the specific Node's List<pack> named PacketStorage for flooding and List<LinkedNeighbor > for NeighborStorage and NeighborDropped 
   void pushPack(pack Package); 
  
   //Checks to see if the pack has already been received. Alterations can occur if the SeqNum is different. 
   bool DupliPack(pack *Package);

   //Look through our NeighborList to see if it's a new neighbor or not
   void findNeighbor();

   //Look through our network and calculate a cost to reach that path
   void findRoute();

   //Our Dijkstra Algorithm
   void Dijkstra(uint8_t Destination, uint8_t Cost, uint8_t NextHop) ;

   event void Boot.booted(){
      uint32_t begin, timeDifference;    
      uint16_t sign;     

      //Begin is determine how much milliseconds after Boot is called to start firing, which is between 0 to 3.5 seconds
      begin = call Random.rand32() % 3500;

      //To make it more random by determining if you add or subtract from a giving timeDifference, where timeDifference determines how often 
      //Node is fired, which is set to be from 15.5 seconds to 24.5 seconds.
      sign = call Random.rand16() % 2;

      timeDifference = 20000;
      if (sign == 1)
      	    timeDifference += call Random.rand16() % 4500; 
      
      else
   	    timeDifference -= call Random.rand16() % 4500;	

      call AMControl.start();

      call periodicTimer.startPeriodicAt(begin, timeDifference);

      //The reason why we want to fire every now and then is because we don't want the network to constantly be dropping packets because another
      //node is firing at the same time. We want them to be discovering their neighbors at a logical timeframe
      //dbg(GENERAL_CHANNEL, "Booted with the beginning time starting at %d, periodic call fired every %d milliseconds. RouteTimeCheck set to %d ms\n", begin, timeDifference, RouteTimeCheck);
      //dbg(GENERAL_CHANNEL, "Booted Successfully!");
  }


   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   event void periodicTimer.fired() 
	{
		//dbg(GENERAL_CHANNEL, "I'm going to fire a findNeighbor() function\n");
		findNeighbor();
		if (!Route_LSP_STOP);
		{	
			//Was originally at 11
			if (LSP_Limit < 17 && LSP_Limit % 3 == 2 && LSP_Limit > 1)
              		{
				findRoute();
			}
			
			if (LSP_Limit == 17)
				Dijkstra(TOS_NODE_ID, 0, TOS_NODE_ID);
			
		}
	}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
  	//dbg(FLOODING_CHANNEL, "Packet Received\n"); 
      	if(len==sizeof(pack))
	{
		//Creates a pack datatype which takes in from void* payload.
        	pack* myMsg=(pack*) payload;

		//Check to see if we've already received/seen this node already or if the TTL is 0
		if (myMsg->TTL == 0 || DupliPack(myMsg))
		{
			//dbg(FLOODING_CHANNEL, "Recieved packet that has no more TTL OR Node has already seen it, lets drop this packet...\n");
			//dbg(FLOODING_CHANNEL, "TTL: %d,   src: %d,    dest: %d,   seq: %d\n", myMsg->TTL, myMsg->src, myMsg->dest, myMsg->seq);
			//return msg;
		}
		
		//Check to see if this is a packet for calculating routing table
		else if(myMsg->dest == AM_BROADCAST_ADDR && myMsg->protocol == PROTOCOL_LINKSTATE)
		{
			RoutedTable PartialTable;
			pack ForwardedNeighborRoute;
			//We will compare the Packet's NeighborList as it represents the source's list of neighbors with the current node's 
			//list of neighbors.
			bool match;
			uint16_t i;
			LinkedNeighbor NeighborfromNode;
			//uint16_t CostCount;
			//uint8_t* Payload_Array;
			uint8_t Payload_Array_Length;

			i = 0;
			Payload_Array_Length = 0;
			//dbg(ROUTING_CHANNEL, "Node: %d Has successfully received an LSP Packet from Node %d! Cost: %d \n", TOS_NODE_ID, myMsg->src, MAX_TTL - myMsg->TTL);
			//dbg(ROUTING_CHANNEL, "Payload's Array length is: %d \n", call RoutedTableStorage.size());
			//Payload_Array = myMsg->payload;
			match = FALSE;
		
			//dbg(ROUTING_CHANNEL, "myMsg->payload[0] - TOS_NODE_ID is: %d ... myMsg->src is: %d\n", myMsg->payload[0] - TOS_NODE_ID, myMsg->src );
	
			//Check to see if the packet's source is the same as the recieved Node's ID
                        //If so, we'll need to drop it because we don't need to flood back the sender.
			
			if (TOS_NODE_ID == myMsg->src)
                        {
                                        //dbg(ROUTING_CHANNEL, "We've found a match, so we're not going to flood the packet...\n");
                                        match = TRUE;
					//break;
                        }
			else 
			{
				PartialTable.Node_ID = myMsg->src;
                        	//PartialTable.Cost = MAX_TTL - myMsg->TTL;
                        	PartialTable.Next = myMsg->src;
                        	PartialTable.sequence = myMsg->seq;	
				
				while (i < call NeighborStorage.size())
				{ 
					NeighborfromNode = call NeighborStorage.get(i);
					if (myMsg->src == NeighborfromNode.Node_ID)
					{	
						PartialTable.Cost = 1;	
						break;
					}
					else
						PartialTable.Cost = 250;
					i++;
				}

				i = 0;
				//Check to see if we're at the end of the array.
				while (myMsg->payload[i] > 0)
				{
					//We fill the LSP Table's directly connected neighbors.
 	                                PartialTable.AllNeighbors[i] = myMsg->payload[i];
                                        Payload_Array_Length++;
					i++;
				}
				
			}

			//We're going to make an LSP table and flood if the node hasn't seen it already.
			//if there isn't a match between the packet's source and the TOS_NODE_ID, then it's a unique Node.ID for the RoutedTableStorage and we should store it while checking for 
			//lower costs and replacing the shorter costs. 
			if (!match)
			{
				//Pass in the Array Length of Payload onto the struct.
				PartialTable.AllNeighborsLength = Payload_Array_Length;
				//dbg(ROUTING_CHANNEL, "We''re going to insert PartialTable into list of RoundTableStorage...\n");
				call RoutedTableStorage.pushfront(PartialTable);
				
				makePack(&ForwardedNeighborRoute, myMsg->src, AM_BROADCAST_ADDR, myMsg->TTL - 1, PROTOCOL_LINKSTATE, myMsg->seq, (uint8_t*) myMsg->payload, (uint8_t) sizeof(myMsg->payload));
                		pushPack(ForwardedNeighborRoute);
                		call Sender.send(ForwardedNeighborRoute, AM_BROADCAST_ADDR);
			}
			
			//At this point, we're going to drop the node if it never made pack, push, and send
			//Where the for loop would be at
		
		}


		//HERE, CHECK TO SEE IF THIS IS A PACKET CHECKING FOR ITS NEIGHBORS, THIS IS SEPARATE FROM FLOODING
	        else if(myMsg->dest == AM_BROADCAST_ADDR && (myMsg->protocol == PROTOCOL_PING || myMsg->protocol == PROTOCOL_PINGREPLY))
        	{
	        	uint16_t length, i = 0;
        		LinkedNeighbor Neighbor, Neighbor2;
            		bool found = FALSE; 
            		if (myMsg->protocol == PROTOCOL_PING)
            		{
                		//Here, we want to check if the node who sent the packet to this node are neighbors, so instead of broadcasting it like we normally do,
                		//we send back to the source to confirm if they're neighbors or not.   
                		//dbg(NEIGHBOR_CHANNEL, "Packet %d wants to check for its neighbors\n", myMsg->src);
               			makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, myMsg->TTL--, PROTOCOL_PINGREPLY, myMsg->seq, (uint8_t *) myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                		pushPack(sendPackage);
                		call Sender.send(sendPackage, myMsg->src);
				//dbg(NEIGHBOR_CHANNEL, "Does it crash after make,push and send?...\n");
            		}	
             
            		//Here, we get a ping reply, check to see if the neighbor already exist in the specific Node's Neighbor Storage
           		//If we do find a match, mark it as true as it will be handled at the bottom
            		else if (myMsg->protocol == PROTOCOL_PINGREPLY)
            		{       
               			//dbg(GENERAL_CHANNEL, "Neighbor Packet Receive from %d, replying\n", myMsg->src);
               			length = call NeighborStorage.size();
               			//Here is where found = FALSE;
               			for(i = 0; i < length; i++)
     	          		{       
        	        		Neighbor2 = call NeighborStorage.get(i);
                	  		if(Neighbor2.Node_ID == myMsg->src)
                  			{       
                     				Neighbor2.NumofPings = 0;
                    				found = TRUE;
                  			}
               			}
            		}
             
           		//If we didn't find it as a neighbor, then we need to add it to the node's NeighborStorage
	   		if (!found)
            		{       
       				//add it to the list, using the memory of a previous dropped node
			
				//found = FALSE;
				Neighbor = call NeighborsDropped.get(0);
				//check to see if already in list
				length = call NeighborStorage.size();
				for (i = 0; i < length; i++)
				{
					Neighbor2 = call NeighborStorage.get(i);
					if (myMsg->src == Neighbor2.Node_ID)
					{
						found = TRUE;
					}
				}
				if (found) 
				{
					//already in the list, no need to repeat
				}
				else 
				{
					//not in list, so we're going to add it
					//dbg(NEIGHBOR_CHANNEL, "%d not found, put in list\n", myMsg->src);
					Neighbor.Node_ID = myMsg->src;
					Neighbor.NumofPings = 0;
					call NeighborStorage.pushback(Neighbor);
					
					
				}
			}
			
			//This means that the Neighbor exists in the Neighbor List
                
        	}	

	
	//Check the packet to see if the packet received is meant for the node
	else if(myMsg->dest == TOS_NODE_ID && myMsg->protocol == PROTOCOL_PING)
	{
		uint8_t i;
                RoutedTable calculatedTable;
        	dbg(FLOODING_CHANNEL, "Received packet from %d has arrived! Package Payload: %s\n",myMsg->src, myMsg->payload);
		dbg(FLOODING_CHANNEL, "Sending the ACK packet to Node: %d...\n", myMsg->src);
			
		//Hooray! We've successfuly delivered the packet. Now we have to send a ping reply to the initial source

		//Before we make an ACK packet, increment sequence by 1 since it's a different packet and push a newly created ACK packet to the list PacketStorage
                //then broadcast to it's neighbors.
                sequence++;
 
		//Lets make the ACK packet by having the TOS_NODE_ID be the source and the destination be the source, and changing the protocol to be PINGREPLY 
		
                for(i = 0; i < call ConfirmedTable.size(); i++)
                {
                        calculatedTable = call ConfirmedTable.get(i);
                        if (calculatedTable.Node_ID == myMsg->src)
                        {
                                makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_PINGREPLY, sequence, ((uint8_t *)myMsg-> payload), PACKET_MAX_PAYLOAD_SIZE);
                                pushPack(sendPackage);
				//THIS PART WAS CHANGED
				//dbg(FLOODING_CHANNEL, "We're going to send this packet to  calculatedTable.Next: %d\n", myMsg->src);
                                call Sender.send(sendPackage, calculatedTable.Next);
                                break;
                        }
                }
		//makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_PINGREPLY, sequence, (uint8_t *) myMsg->payload, PACKET_MAX_PAYLOAD_SIZE); 
		
		//pushPack(sendPackage);
		//dbg(GENERAL_CHANNEL, "pushPack was successful\n");
		//call Sender.send(sendPackage, AM_BROADCAST_ADDR);
		//dbg(GENERAL_CHANNEL, "Call Sender was successful\n");
		//return msg;
	}
        else if(myMsg->dest == TOS_NODE_ID && myMsg->protocol == PROTOCOL_PINGREPLY)
	{
         	dbg(FLOODING_CHANNEL, "Received ACK packet from %d, where that was the original destination.\n", myMsg->src);
		//dbg(FLOODING_CHANNEL, "Recieved packet, STATS... Payload: %s\n", myMsg->payload);
		//return msg;
		//sequence++;
	}
	
	//Handles ALL TCP Receives. First we go through the whole list to find that specific index that has a Socket with the matching Port. Then we check to see what flag it's currently in.
	//Flag 1 = Received a SYN from src, Send a SYN+ACK, change state to SYN_RCVD
	//Flag 2 = Received a SYN+ACK from src, Send an ACK, change state to ESTABLISHED
	//Flag 3 = Received a ACK from src, change state to change state to ESTABLISHED
	//By the third flag, both the Client and Server's states are Established and are ready to send data.
	else if (myMsg->dest == TOS_NODE_ID && myMsg->protocol == PROTOCOL_TCP)
	{
		socket_store_t* ClientSocketPack;
    		socket_addr_t Client_AddrPort;
		uint8_t i;
                RoutedTable calculatedTable;
                socket_store_t PullfromList;
                pack SynchroPacket;
                uint8_t Next;
                uint8_t CTableIndex;
                socket_store_t SocketFlag;
                socket_store_t BindSocket;
                //socket_addr_t Address_Bind;
                bool Modified, MadeCorrectPack, LastEstablished;

		ClientSocketPack = myMsg->payload;
		Client_AddrPort = ClientSocketPack->dest;
		//Now we should check to see if we can establish a connection between the source and destination
		dbg(TRANSPORT_CHANNEL, "Received packet with protocol_TCP. Here's it's stats of payload.  Addr: %d,    Port: %d  Flag is: %d\n", Client_AddrPort.addr, Client_AddrPort.port, ClientSocketPack->flag);
		Modified = FALSE;
     	        //SocketFlag = call SocketState.get(i);
		MadeCorrectPack = FALSE;
		LastEstablished = FALSE;
	
		for(i = 0; i < call SocketState.size(); i++)
		{	
			PullfromList = call SocketState.get(i);
 	                SocketFlag.dest.port = ClientSocketPack->src;
                        SocketFlag.dest.addr = myMsg->src;

       	                SynchroPacket.src = TOS_NODE_ID;
                        SynchroPacket.dest = myMsg->src;
                        SynchroPacket.seq = myMsg->seq + 1;
                        SynchroPacket.TTL = MAX_TTL;
                        SynchroPacket.protocol = PROTOCOL_TCP;
			if(Client_AddrPort.port == PullfromList.src && PullfromList.state == LISTEN && Client_AddrPort.addr == TOS_NODE_ID && ClientSocketPack->flag == 1)
			{
		      		SocketFlag = call SocketState.get(i);
        		        //FLAG IS FOR SYN+ACK
       		                SocketFlag.flag = 2;
               		        SocketFlag.dest.port = ClientSocketPack->src;
               		        SocketFlag.dest.addr = myMsg->src;
				
	                        memcpy(SynchroPacket.payload, &SocketFlag, (uint8_t) sizeof(SocketFlag));
	                        for(CTableIndex = 0; CTableIndex < call ConfirmedTable.size(); CTableIndex++)
        	                {
		
                	                calculatedTable = call ConfirmedTable.get(CTableIndex);
                        	        if (calculatedTable.Node_ID == SynchroPacket.dest)
                                	{
                                        	Next = calculatedTable.Next;
                                        	MadeCorrectPack = TRUE;
                                        	break;
                                	}
                        	}
			}

                        else if (Client_AddrPort.port == PullfromList.src && PullfromList.state == SYN_SENT && ClientSocketPack->flag == 2)
                        {
                                SocketFlag = call SocketState.get(i);
                                //FLAG IS FOR SENDING AN ESTABLISHED
                                SocketFlag.flag = 3;
                                SocketFlag.dest.port = ClientSocketPack->src;
                                SocketFlag.dest.addr = myMsg->src;

                                memcpy(SynchroPacket.payload, &SocketFlag, (uint8_t) sizeof(SocketFlag));
                                for(CTableIndex = 0; CTableIndex < call ConfirmedTable.size(); CTableIndex++)
                                {
                                        
                                        calculatedTable = call ConfirmedTable.get(CTableIndex);
                                        if (calculatedTable.Node_ID == SynchroPacket.dest)
                                        {       
                                                Next = calculatedTable.Next;
                                                MadeCorrectPack = TRUE;
                                                break;
                                        }
                                }
                        }

                       	else if (Client_AddrPort.port == PullfromList.src && PullfromList.state == SYN_RCVD && ClientSocketPack->flag == 3)
                        {
				dbg(TRANSPORT_CHANNEL, "We received a flag for ESTABLISHED, In theory, this node is in SYN_RCVD. Set this node to Established as well...\n");
				LastEstablished = TRUE;
                        }
                        //If we made the packet or if the pack we received is an ACK packet to signal to change state to ESTABLISHED and not send anymore packets
			if(MadeCorrectPack || LastEstablished)
			{			
        			//What we want to do is because we cannot directly modify the content in the list, we want to check to see if we have a match in FD
        			//if there's a match and it hasn't been found already, we want to modify it's contents so that it's directly bonded. If not, we just
        			//Move the contents are either continue looking if we haven't found it or just move it while we already modified one of the indexes.
        			while (!call SocketState.isEmpty())
        			{
			                BindSocket = call SocketState.front();
               				call SocketState.popfront();
			       		//Modify_The_States
		                	if (BindSocket.fd == i && !Modified)
               				{
                       				enum socket_state ChangeState;
	                                        if (PullfromList.state == LISTEN)
	                                        {
							//Now that we've sent the packet, we gotta change the State from LISTEN TO SYN_RCVD
                		                	ChangeState = SYN_RCVD;
							dbg(TRANSPORT_CHANNEL, "fd found with flag LISTEN, Change state to SYN_RCVD in port: %d\n", BindSocket.src);
                                	        }
                                        	else if (PullfromList.state == SYN_SENT)
                                       		{
                                                        BindSocket.dest.addr = myMsg->src;
                                       			ChangeState = ESTABLISHED;
							dbg(TRANSPORT_CHANNEL, "fd found with flag SYN_SENT, Change state to ESTABLISHED in port: %d\n", BindSocket.src);
						}
						
                                               	else if (PullfromList.state == SYN_RCVD && LastEstablished)
                                                {
							//BindSocket.dest = Client_AddrPort;
                                                        BindSocket.dest.addr = myMsg->src;
							ChangeState = ESTABLISHED;
                                                        dbg(TRANSPORT_CHANNEL, "fd found with flag SYN_RCVD, Change state to ESTABLISHED in port: %d\n", BindSocket.src);
                                                }
                       				BindSocket.state = ChangeState;
                       				Modified = TRUE;
                       				call Modify_The_States.pushfront(BindSocket);	
                			}
						
					else
                        			call Modify_The_States.pushfront(BindSocket);						
				}

				while (!call Modify_The_States.isEmpty())
        			{
                			call SocketState.pushfront(call Modify_The_States.front());
                			call Modify_The_States.popfront();
        			}
				if (MadeCorrectPack && !LastEstablished)
				{
					pushPack(SynchroPacket);
					dbg(TRANSPORT_CHANNEL, "We're about to send a packet to Node: %d, which should hopefully be an immediate Neighbor\n", Next);
                                	call Sender.send(SynchroPacket, Next);	
				}
			}

		}
		
	}	
	//Packet not meant for it, decrement TTL, mark it as seen after making a new pack, and broadcast to neighhors
	else
	{
		uint8_t i;
		RoutedTable calculatedTable;
		//dbg(FLOODING_CHANNEL, "Recieved packet, It's not for it... TTL: %d,   src: %d,    dest: %d,   seq: %d\n", myMsg->TTL, myMsg->src, myMsg->dest, myMsg->seq);
		if (myMsg->protocol == PROTOCOL_TCP)
			dbg(FLOODING_CHANNEL, "Received packet, not meant for it. It's protocol is TCP\n");
	        makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL--, myMsg->protocol, myMsg->seq, ((uint8_t *)myMsg-> payload), PACKET_MAX_PAYLOAD_SIZE);
                pushPack(sendPackage);
		for(i = 0; i < call ConfirmedTable.size(); i++)
        	{       
                	calculatedTable = call ConfirmedTable.get(i);
                	//dbg(ROUTING_CHANNEL, "Dest: %d, Cost: %d, Next: %d \n", calculatedTable.Node_ID,  calculatedTable.Cost,  calculatedTable.Next);
			if (calculatedTable.Node_ID == myMsg->dest)
                	{       
                	        //makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL--, myMsg->protocol, myMsg->seq, ((uint8_t *)myMsg-> payload), PACKET_MAX_PAYLOAD_SIZE);
                	        //pushPack(sendPackage);
				//dbg(FLOODING_CHANNEL, "We're going to send this packet to  calculatedTable.Next: %d\n", calculatedTable.Next);
				call Sender.send(sendPackage, calculatedTable.Next);
                	        //break;
                	}
        	}
		
		//call Sender.send(sendPackage, calculatedTable.Next);
		//makePack(&sendPackage, (myMsg->src), (myMsg->dest), (myMsg->TTL--), (myMsg->protocol), (myMsg->seq), ((uint8_t *)myMsg-> payload), PACKET_MAX_PAYLOAD_SIZE);
		//pushPack(sendPackage);
		//call Sender.send(sendPackage, AM_BROADCAST_ADDR);
		//return msg;
	}

	return msg;

      } 
	else
	{	
      		dbg(FLOODING_CHANNEL, "Unknown Packet Type %d\n", len);
      		return msg;
	}
   }
	


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload)
{
	uint8_t i;
	RoutedTable calculatedTable;
	//dbg(GENERAL_CHANNEL, "PING EVENT \n");
      	//Dijkstra(TOS_NODE_ID, 0, TOS_NODE_ID);
      	for(i = 0; i < call ConfirmedTable.size(); i++)
        {
		       
             	calculatedTable = call ConfirmedTable.get(i);
		if (calculatedTable.Node_ID == destination)
		{
			makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, PROTOCOL_PING, ++sequence, payload, PACKET_MAX_PAYLOAD_SIZE);
       			//CHANGED Sender.send
			call Sender.send(sendPackage, calculatedTable.Next);
			break;
		}
	}	
	//makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, PROTOCOL_PING, sequence, payload, PACKET_MAX_PAYLOAD_SIZE);
      	//call Sender.send(sendPackage, AM_BROADCAST_ADDR);
     	//dbg(GENERAL_CHANNEL, "RESETTING foundPack BOOL \n");
}

   event void CommandHandler.printNeighbors(){
	uint16_t i, size = call NeighborStorage.size();
	LinkedNeighbor printedNeighbor;
	//Print out NeighborList after updating
	
	if(size == 0)
 	{
		//dbg(GENERAL_CHANNEL, "No Neighbors found in Node %d\n", TOS_NODE_ID);
	}
	
	 else 
	{
		//dbg(GENERAL_CHANNEL, "Dumping neighbor list for Node %d\n", size, TOS_NODE_ID);
		for(i = 0; i < size; i++) 
		{
			printedNeighbor = call NeighborStorage.get(i);
			dbg(GENERAL_CHANNEL, "Neighbor: %d, NumofPings: %d\n", printedNeighbor.Node_ID, printedNeighbor.NumofPings);
		}
	}

}

   event void CommandHandler.printRouteTable()
{
	uint16_t i, size = call ConfirmedTable.size();
        RoutedTable calculatedTable;
        //Print out NeighborList after updating

        if(size == 0)
        {
                //dbg(GENERAL_CHANNEL, "No route found in Node %d\n", TOS_NODE_ID);
        	//Dijkstra(TOS_NODE_ID, 0, 0);
	}

        
      	size = call ConfirmedTable.size();
        dbg(GENERAL_CHANNEL, "Dumping Route list for Node %d\n", TOS_NODE_ID);
        for(i = 0; i < size; i++)
        {
        	calculatedTable = call ConfirmedTable.get(i);
        	dbg(GENERAL_CHANNEL, "Node: %d, Cost: %d, NextHop: %d\n", calculatedTable.Node_ID, calculatedTable.Cost, calculatedTable.Next);
	}

	

}

   event void CommandHandler.printLinkState()
{
        RoutedTable PartialTable;
        uint16_t i, m;
        //dbg(ROUTING_CHANNEL, "We checked all of LSP's directly connected neighbors. Printing out the table so far \n");
        dbg(ROUTING_CHANNEL, "----------Node %d's LSP Table--------- \n", TOS_NODE_ID);
        for(m = 0; m < call RoutedTableStorage.size(); m++)
        {
                PartialTable = call RoutedTableStorage.get(m);
		dbg(ROUTING_CHANNEL, "Node_ID: %d  Cost: %d    Next:%d  \n", PartialTable.Node_ID, PartialTable.Cost, PartialTable.Next);
		
		dbg(GENERAL_CHANNEL, "Node: %d's AllNeighbors Array is: \n", PartialTable.Node_ID);
	        for(i = 0; i < PartialTable.AllNeighborsLength; i++)
        	{
			if(PartialTable.AllNeighbors[i] > 0)
                		dbg(GENERAL_CHANNEL, "%d\n",  PartialTable.AllNeighbors[i]);
		}
        }

}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(uint8_t port)
   {
	socket_addr_t ServerAddr;
	ServerAddr.addr = TOS_NODE_ID;
	ServerAddr.port = port;
	dbg(TRANSPORT_CHANNEL, "We're gonna try to bind Node: %d with Port: %d \n", TOS_NODE_ID, port);
	socket = call Transport.socket();
	
	//There's at least room in the Socket to bind Serversocket to current node
	//This would be false is there's no more room
	if (socket >= 0)
	{
		dbg(GENERAL_CHANNEL, "Now lets try printing a thing that's in socket... Number for FD is %d\n", socket);
   		call Transport.bind(socket, &ServerAddr);
		call Transport.listen(socket);
   	}

	else
		dbg(TRANSPORT_CHANNEL, "Node %d was not available to bind, returned NULL(250) is there too many ports open?.\n", TOS_NODE_ID);
   }

   event void CommandHandler.setTestClient(uint8_t dest, uint8_t srcPort, uint8_t destPort, uint16_t transfer)
   {
	socket_addr_t ClientAddr, ServerAddr;
        socket_store_t BindSocket;
	uint8_t i;
	uint8_t testBuff[transfer];
	uint8_t testBuff2[100];
	uint16_t testWrite, testRead;
	
	GlobalTransfer = transfer;
	ClientAddr.addr = TOS_NODE_ID;
        ClientAddr.port = srcPort;
        dbg(TRANSPORT_CHANNEL, "This is for TestClient. We're gonna try to bind Node: %d with srcPort: %d \n", TOS_NODE_ID, srcPort);
        socket = call Transport.socket();
        
        //There's at least room in the Socket to bind Clientsocket to SocketAddress
        //This would be false is there's no more room
        if (socket >= 0)
        {
		BindSocket = call SocketState.get(socket);
		dbg(TRANSPORT_CHANNEL, "Now lets try printing a thing that's in socket... Number for FD is %d\n", socket);
        	if (call Transport.bind(socket, &ClientAddr) == SUCCESS)
		{
			ServerAddr.addr = dest;
			ServerAddr.port = destPort;
			TimeSent = call LocalTime.get();
			dbg(TRANSPORT_CHANNEL, "I just called a LocalTime.get() function. Print that out: %d\n", TimeSent);
			if (call Transport.connect(socket,&ServerAddr) == SUCCESS)
				dbg(TRANSPORT_CHANNEL, "We're at the end of trying to connect/Sending SYN,SYN+ACK,and ACK packets. Check to see if you were able to make both ports established.\n");
			else
				dbg(TRANSPORT_CHANNEL, "Unable to connect/makePack.\n");
			//BindSocket = call SocketState.get(socket);
			//if BindSocket.state
			
   		}

		dbg(TRANSPORT_CHANNEL, "Size should be Transfer: %d\n", transfer);
		for(i = 0; i < transfer; i++)
			testBuff[i] = i + 1;
		
		
		testWrite = call Transport.write(socket, testBuff, transfer);
		dbg(TRANSPORT_CHANNEL, "We were able to write %d amount of data for the first case. We should try calling in read next (theoretically server is gonna call it)\n", testWrite);
		//testRead = call Transport.read(socket, BindSocket.sendBuff, transfer);	
		
	
		for (i = 0; i < 100; i++)
			testBuff2[i] = i + 1;

		dbg(TRANSPORT_CHANNEL, "We're going to use testBuff2 and write into socket which already has data \n");
		testWrite = call Transport.write(socket, testBuff2, 100);
		
                dbg(TRANSPORT_CHANNEL, "We were able to write %d amount of data for the second case.\n", testWrite);

		dbg(TRANSPORT_CHANNEL, "We're going to use testBuff2 again and write into socket which already has data \n");
                testWrite = call Transport.write(socket, testBuff2, 100);		
	}
   }

   event void CommandHandler.ClientClose(uint8_t ClientAddress, uint8_t srcPort, uint8_t destPort, uint8_t dest){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);   
      }


   //This searchPack is specific to a single node. This is also enabling for when this node recieves the same packet from a different 
   bool DupliPack (pack *Package)
   {
   	uint16_t sizeofList = call PacketStorage.size();
 	uint16_t i = 0;
	pack CheckPack;
	for(i = 0; i < sizeofList; i++)
 	{
		//dbg(GENERAL_CHANNEL, "The searchPack loop is going... \n");
		//Go through each packet that's in the list to see if we've discovered it already
		CheckPack = call PacketStorage.get(i);
		
		//Checking for sequence number is important for determining if it's a ping reply or not


		if (CheckPack.src == Package->src && CheckPack.dest == Package->dest && CheckPack.seq == Package->seq)
		{
			//We've discovered this packet already, so go ahead and send the signal to be used later to drop the packet
			return TRUE;
		}
	}
	return FALSE;	
    }

   //We're checking to see if it's full, then to make room since we're dealing with static memory
   void pushPack(pack Package)
   {
	if (call PacketStorage.isFull())
      		call PacketStorage.popfront(); 
	
	call PacketStorage.pushback(Package);
   }

   void findNeighbor() 
   {
   	pack NeighborPack;
	char* message = "this is a test\n";
	//Age all NeighborList first if list is not empty
	//dbg(GENERAL_CHANNEL, "Discovery activated: %d checking list for neighbors\n", TOS_NODE_ID);
	LSP_Limit++;
	//dbg(GENERAL_CHANNEL, "The discoverNeighborList for Node %d has been activated... \n", TOS_NODE_ID);
	if(!call NeighborStorage.isEmpty()) {
		uint16_t sizeofLink = call NeighborStorage.size();
		uint16_t i = 0;
		uint16_t pings = 0;
		LinkedNeighbor temp;
		LinkedNeighbor NeighborNode;
		//dbg(GENERAL_CHANNEL, "Or crash here...\n");
		
		//Increment the NumofPings because we are going through all of the neighbors in NeighborStorage
		//We drop off any neighbors that have been there for too long, one of the ways to prevent network congestion. Number 7 is picked to acheive this
		for(i = 0; i < sizeofLink; i++) {
			temp = call NeighborStorage.get(i);
			temp.NumofPings = temp.NumofPings + 1;
			pings = temp.NumofPings;
			if(pings > 7) 
			{
				LSP_Limit = 0;
				NeighborNode = call NeighborStorage.removefromList(i);
				call NeighborStorage.popback();
				//dbg(NEIGHBOR_CHANNEL, "Node %d dropped due to more than 7 pings\n", NeighborNode.Node);
				call NeighborsDropped.pushfront(NeighborNode);
				i--;
				sizeofLink--;
			}
		}
	}

	//dbg(NEIGHBOR_CHANNEL, "Does it crash here... sendPackage: d%\n", &sendPackage);
	//We're read to ping packet to NeighborStorage
   	makePack(&NeighborPack, TOS_NODE_ID, AM_BROADCAST_ADDR, 2, PROTOCOL_PING, 1, (uint8_t*) message, (uint8_t) sizeof(message));

	//dbg(NEIGHBOR_CHANNEL, "What about crahh here...\n");
	pushPack(NeighborPack);
	call Sender.send(NeighborPack, AM_BROADCAST_ADDR);
   }

   void findRoute()
   {
   	//dbg(GENERAL_CHANNEL, "The routeTable Function for Node %d has been activated... \n", TOS_NODE_ID);
        pack RoutedNeighborPack;
 
       	//Check to first see if the routing table is empty. if so, we fill it with neighbors neighrbor list is empty or not
       	
	if(!call NeighborStorage.isEmpty()) 
	{	
        	uint8_t i = 0;
		LinkedNeighbor temp;
	        uint8_t sizeofLink = (call NeighborStorage.size()) + 1;
        	uint8_t neighbors [sizeofLink];

		//dbg(ROUTING_CHANNEL, "Node: %d Has successfully made an array of size: %d \n", TOS_NODE_ID, (sizeof(neighbors) / sizeof (uint8_t) - 1));
		//dbg(GENERAL_CHANNEL, "Or crash here...\n");
                
        	for(i = 0; i < sizeofLink; i++) 
		{
			temp = call NeighborStorage.get(i);
			neighbors[i] = temp.Node_ID;	
			
			//dbg(ROUTING_CHANNEL, "INDEX: %d    Payload_Array[i]: %d\n", i, neighbors[i]);
			//i++;
			//neighbors[i] = TOS_NODE_ID; 
		}
        	
		neighbors[sizeofLink] = 0;
		//sequence++;
		makePack(&RoutedNeighborPack, TOS_NODE_ID, AM_BROADCAST_ADDR, MAX_TTL - 1, PROTOCOL_LINKSTATE, sequence + 1, (uint8_t*) neighbors, (uint8_t) sizeof(neighbors));
       		pushPack(RoutedNeighborPack);
       		call Sender.send(RoutedNeighborPack, AM_BROADCAST_ADDR);	
		
		//dbg(ROUTING_CHANNEL, "Node: %d Has successfully sent out an LSP Packet! \n", TOS_NODE_ID);
	}

	//else
		//dbg(ROUTING_CHANNEL, "Node: %d currently has no neighbors! \n", TOS_NODE_ID);

   }

   void Dijkstra(uint8_t Destination, uint8_t Cost, uint8_t NextHop)
   {
        RoutedTable NewConfirmed, Node_Next, CheckTentative, CheaperTentative, CheckConfirmed;
	LinkedNeighbor Next_Neighbor;
	uint8_t RTS_Index, NeighborIndex, LSP_Index, TentativeSize, TentativeIndex, CT_Index, Cheaper_T_Index;
	bool inTentative, inConfirmed;
	NewConfirmed.Node_ID = Destination;
        NewConfirmed.Cost = Cost;
        NewConfirmed.Next = NextHop;
	NeighborIndex = 0;
        call ConfirmedTable.pushfront(NewConfirmed);
	
	//dbg(ROUTING_CHANNEL, "We've started after defining everything at the top. Destination: %d \n", Destination);
	
	//Check to see if we're in the initial start of contructing routing table. The beginning starts at TOS_NODE_ID
	//If we're not, then we need to aquire the neighbors of the current NewConfirmed.Node_ID so we can look through it's LSP
	//and continue with the routing table
	
	if(NewConfirmed.Node_ID != TOS_NODE_ID)
	{	
		for(RTS_Index = 0; RTS_Index < call RoutedTableStorage.size(); RTS_Index++)
		{

			Node_Next = call RoutedTableStorage.get(RTS_Index);
			//dbg(ROUTING_CHANNEL, "We pulled out a Node_Next which has a Node_Next.Node_ID of %d\n", Node_Next.Node_ID);
			if (Node_Next.Node_ID == Destination)
			{
				//dbg(ROUTING_CHANNEL, "We now have a match between Node_Next.Node_ID and Destination. Lets access Neighbors of Node_Next.Node_ID\n");
				for(NeighborIndex = 0; NeighborIndex < Node_Next.AllNeighborsLength; NeighborIndex++)
				{
					if ( Node_Next.AllNeighbors[NeighborIndex] > 0)
					{
							//If Neighbor is currently on neither the Confirmed nor the Tentative list,
                			                //then add (Neighbor, Cost, NextHop) to the Tentative list, where NextHop is the direction I go to reach Next.
                                			//This means we need to check which ones are empty.

							//dbg(ROUTING_CHANNEL, "Over here, we are able to find a neighbor of %d (hopefully that's correct) and now we're gonna check it with Tentative and Confirm\n", Node_Next.AllNeighbors[NeighborIndex]);
                                			inTentative = FALSE;
                               				inConfirmed = FALSE;
                                			//Check to see if Tentative is empty
                                			if (!call Tentative.isEmpty())
                                			{
                                        			//Check to see if Neighbor is on Tentative list and see if the cost is less than the currently Listed Cost for Neighbor
                                        			//Replace current entry with (Neighbor, Cost, NextHop) where NextHop is the direction to reach next
                                        			for(TentativeIndex = 0; TentativeIndex < call Tentative.size(); TentativeIndex++)
                                        			{
                                                			CheckTentative = call Tentative.get(TentativeIndex);
                                                			if (CheckTentative.Node_ID == Node_Next.AllNeighbors[NeighborIndex])
									{
										inTentative = TRUE;
										//We know it's in Tentative. Check to see if it's a lower cost to determine if we drop it or not.
										if (CheckTentative.Cost > Node_Next.Cost)
                                                				{
                                                        				//We found a cost that on Tentative List that's less than what it would cost for the neighbor.
                                                        				//Replace entry by first removing that index from the list, then push the cheaper cost and NextHop with it.
	
        	                                                			//dbg(ROUTING_CHANNEL, "Here, we do the thing where we found a cheaper Tentative path and replace it. \n", Destination);
                	                                        			//CheaperTentative = call Tentative.removefromList(TentativeIndex);
											//CheaperTentative.Cost = Node_Next.Cost + 1;
                                	                        			//CheaperTentative.Next = Destination;
                                        	                			//call Tentative.pushfront(CheaperTentative);
                                                	        			//inTentative = TRUE;
                                                				}
                                                				if (CheckTentative.Node_ID == Node_Next.AllNeighbors[NeighborIndex] && CheckTentative.Cost == Node_Next.Cost)
                                                				{
                                                        				inTentative = TRUE;
                                                				}
                                        				}
                                				}
							}
							//Check to see if Neighbor is not con confirmed List
                                			if (!call ConfirmedTable.isEmpty())
                                			{
                                        			for(CT_Index = 0; CT_Index < call ConfirmedTable.size(); CT_Index++)
                                        			{
                                                			CheckConfirmed = call ConfirmedTable.get(CT_Index);
                                                			if (CheckConfirmed.Node_ID == Node_Next.AllNeighbors[NeighborIndex])
                                                			{
										//dbg(ROUTING_CHANNEL, "Is this ever called? This is whe we make inConfirmed = TRUE\n");
                                                        			inConfirmed = TRUE;
                                                			}
                                        			}
                                			}
						
                    		            		//This is where Neighbor is on neither Confirmed or Tentative list. So then store on Tentative List.
                                			if (!inConfirmed && !inTentative)
                                			{
								//ImmediateNeighbor = 0;
                                		        	//First, update the information needed to travel to that node 
						               	Node_Next.Node_ID = Node_Next.AllNeighbors[NeighborIndex];
                						Node_Next.Cost =  Cost + 1;
                						//for(ImmidiateNeighbor = 0; ImmidiateNeighbor < call NeighborStorage.size(); ImmidiateNeighbor++)
								//{
								//
								//}
								Node_Next.Next = Destination;
								//dbg(ROUTING_CHANNEL, "Tentative is going to be filled with Node_Next. Here are its Stats. Node_Next.Node_ID: %d, Node_Next.Cost: %d, Node_Next.Next:%d\n", Node_Next.Node_ID, Node_Next.Cost, Node_Next.Next);
								call Tentative.pushfront(Node_Next);
                               				}
		
					}
				}	
			}
		}
	}
	

	else	
	{	
      		for(NeighborIndex = 0; NeighborIndex < call NeighborStorage.size(); NeighborIndex++)
        	{
                	Next_Neighbor = call NeighborStorage.get(NeighborIndex);
			for(LSP_Index = 0; LSP_Index < call RoutedTableStorage.size(); LSP_Index++)
        		{
				Node_Next = call RoutedTableStorage.get(LSP_Index);
                        	if (Node_Next.Node_ID == Next_Neighbor.Node_ID)
                        	{
					//Node_Next.Next = Next_Neighbor.Node_ID;
				
					//If Neighbor is currently on neither the Confirmed nor the Tentative list, 
					//then add (Neighbor, Cost, NextHop) to the Tentative list, where NextHop is the direction I go to reach Next.
					//This means we need to check which ones are empty.
				
					inTentative = FALSE;
					inConfirmed = FALSE;
					//Check to see if Tentative is empty
					if (!call Tentative.isEmpty())
					{
						//Check to see if Neighbor is on Tentative list and see if the cost is less than the currently Listed Cost for Neighbor
						//Replace current entry with (Neighbor, Cost, NextHop) where NextHop is the direction to reach next
						for(TentativeIndex = 0; TentativeIndex < call Tentative.size(); TentativeIndex++)
						{
							CheckTentative = call Tentative.get(TentativeIndex);
							if (CheckTentative.Node_ID == Node_Next.Node_ID &&  CheckTentative.Cost > Node_Next.Cost)
							{
								//We found a cost that on Tentative List that's less than what it would cost for the neighbor. 
								//Replace entry by first removing that index from the list, then push the cheaper cost and NextHop with it. 
								
								//dbg(ROUTING_CHANNEL, "We've started after defining everything at the top. Destination: %d \n", Destination);
								CheaperTentative = call Tentative.removefromList(TentativeIndex);
								CheaperTentative.Cost = Node_Next.Cost;
								CheaperTentative.Next = Node_Next.Next;
								call Tentative.pushfront(CheaperTentative);
								inTentative = TRUE;	
							}
							if (CheckTentative.Node_ID == Node_Next.Node_ID && CheckTentative.Cost == Node_Next.Cost)
							{
								inTentative = TRUE;
							}
						}
					}
					
					//Check to see if Neighbor is not con confirmed List
					if (!call ConfirmedTable.isEmpty())
					{
						for(CT_Index = 0; CT_Index < call ConfirmedTable.size(); CT_Index++)
						{
							CheckConfirmed = call ConfirmedTable.get(CT_Index);
							if (CheckConfirmed.Node_ID == Node_Next.Node_ID)
							{
								inConfirmed = TRUE;
							}
						} 
					}

					//This is where Neighbor is on neither Confirmed or Tentative list. So then store on Tentative List.
					if (!inConfirmed && !inTentative)
					{
						call Tentative.pushfront(Node_Next);
						
					}
				}
			}
		
                //dbg(ROUTING_CHANNEL, "Next_LSP's Node_ID is...: %d ! Now look through it's neighbors and post it's list\n", Next_LSP.Node_ID);
                
		//LSP_Cost_Find.Node_ID = Next_LSP.Node_ID;
		//LSP_Cost_Find.Cost = Cost + 1;
                //LSP_Cost_Find.Next = Next_LSP.Node_ID;
                //call Tentative.pushfront(LSP_Cost_Find);                    
        	}
	}

	//dbg(ROUTING_CHANNEL, "Lets see what's the size of Tentative List... The size is %d \n", call Tentative.size());
	//dbg(ROUTING_CHANNEL, "-----Tentative Contents----\n");
	for(TentativeIndex = 0; TentativeIndex < call Tentative.size(); TentativeIndex++)
        {
		CheckTentative = call Tentative.get(TentativeIndex);
		//dbg(ROUTING_CHANNEL, "Dest: %d, Cost: %d, Next: %d Index: %d \n", CheckTentative.Node_ID,  CheckTentative.Cost,  CheckTentative.Next, TentativeIndex);
	}

	//dbg(ROUTING_CHANNEL, "-----Confirmed Contents----\n");
        for(CT_Index = 0; CT_Index < call ConfirmedTable.size(); CT_Index++)
        {
                CheckConfirmed = call ConfirmedTable.get(CT_Index);
                //dbg(ROUTING_CHANNEL, "Dest: %d, Cost: %d, Next: %d \n", CheckConfirmed.Node_ID,  CheckConfirmed.Cost,  CheckConfirmed.Next);
        }

	inConfirmed = FALSE;	

	//We're done checking all the neighbor Nodes, lets now pick a tentative with the shortest cost (and shortest Node_ID)
	TentativeSize = call Tentative.size();
	         
     	//If it's the only Tentative on the list, so go ahead, remove it from Tentative, Have it go though recursion where it will get pushed onto the confirmed table.
	//Size of 1 means that index is 0;
	if (TentativeSize == 1)
	{
		
		//dbg(ROUTING_CHANNEL, "We're going to attempt to remove an element in Tentative List when size = 1. Here's before size: %d\n", call Tentative.size());
		//CheaperTentative = call Tentative.removefromList(0);
		CheaperTentative = call Tentative.get(0);
		call Tentative.popback();

		
		//dbg(ROUTING_CHANNEL, "Here's the size after we supposedly dropped an element in TentativeList when size was originally 1. After Size: %d\n", call Tentative.size());	
		//dbg(ROUTING_CHANNEL, "Now that we dropped the last thing in Tentative, lets see if it's aleady in confirmed\n");
		
		inConfirmed = FALSE;
		//CheckTentative = call Tentative.get(TentativeIndex);
		for(CT_Index = 0; CT_Index < call ConfirmedTable.size(); CT_Index++)
                {
			CheckConfirmed = call ConfirmedTable.get(CT_Index);
                       	if (CheaperTentative.Node_ID == CheckConfirmed.Node_ID)
                       	{
             		       	inConfirmed = TRUE;
				//dbg(ROUTING_CHANNEL, "We ran into an instance where the last Tentative was in Confirmed and now we're gonna drop it...\n");
                       	}
		
			if(!inConfirmed)	
			{
				//THE FOLLOWING FOR LOOP IS BUGGY, PLEASE CHECK CAREFULLY
				if (CheaperTentative.Next == CheckConfirmed.Node_ID)
				{
					//dbg(ROUTING_CHANNEL, "We fucking found where the last Tentative's Next is in Confirmed's Node_ID. We should perhaps was look into changing Next...\n");
					CheaperTentative.Next = CheckConfirmed.Next;
				
					//SO GO CHECK IF THE NODE_ID CONNECTS TO IMMEDIATE NEIGHBORS	
					for(NeighborIndex = 0; NeighborIndex < call NeighborStorage.size(); NeighborIndex++)
					{
						Next_Neighbor = call NeighborStorage.get(NeighborIndex);
						if (CheaperTentative.Next == Next_Neighbor.Node_ID)
						{
							//dbg(ROUTING_CHANNEL, "We Theoretically found the 3rd? hop for next neighbor. 4 May still be buggy but it's not recursive atm...\n");
							break;
						}	
					}
					
				}
			}
               	}
		
		//call ConfirmedTable.pushfront(CheaperTentative);
		
		if (!inConfirmed)
			Dijkstra(CheaperTentative.Node_ID, CheaperTentative.Cost, CheaperTentative.Next);
	}
	if (TentativeSize > 1)
	{
		//inConfirmed = FALSE;
		//while (!inConfirmed)
		//{
			//Assume the first is the cheaper tentative
			CheaperTentative = call Tentative.get(0);
			Cheaper_T_Index = 0;
			//dbg(ROUTING_CHANNEL, "What is considered the first Cheaper Tentative is     Dest: %d, Cost: %d\n",CheaperTentative.Node_ID, CheaperTentative.Cost);
			//Should be "<" because we're dealing with a potential size of TentativeList of 2, which translates to Index 1.
			for(TentativeIndex = 1; TentativeIndex < call Tentative.size(); TentativeIndex++)
			{
				CheckTentative = call Tentative.get(TentativeIndex);
				
				//This will execute only if our supposed cheapest cost isn't actually the cheapest cost. So we replace the variable with a new Cheapter Tentative.
				if (CheaperTentative.Cost > CheckTentative.Cost)
				{
					Cheaper_T_Index = TentativeIndex;
					CheaperTentative = CheckTentative;
				}
				//This will only execute if we have the same cost AND the CheaperTentative has a higher Node_ID than CheckTentative
				else if (CheaperTentative.Cost == CheckTentative.Cost && CheaperTentative.Node_ID > CheckTentative.Node_ID) 			
				{
					Cheaper_T_Index = TentativeIndex;
					CheaperTentative = CheckTentative;
				}
	                }	
	        	
			CheckTentative = call Tentative.get(Cheaper_T_Index);
	                for(CT_Index = 0; CT_Index < call ConfirmedTable.size(); CT_Index++)
        	        {
                		CheckConfirmed = call ConfirmedTable.get(CT_Index);
                		if (CheckTentative.Node_ID == CheckConfirmed.Node_ID)
	                	{
        	        		inConfirmed = TRUE;
                			//dbg(ROUTING_CHANNEL, "We ran into an instance where there was more than one Tentative in list, The shortest was in Confirmed and now we're gonna drop it...\n");
                        	}

	                        //THE FOLLOWING FOR LOOP IS A COPY OF ABOVE AND MAY ALSO BE BUGGY, PLEASE CHECK CAREFULLY
        	                if(!inConfirmed)
                	        {
                        	        //THE FOLLOWING FOR LOOP IS BUGGY, PLEASE CHECK CAREFULLY
                                	//CHECKTENTATIVE WAS CHANGED AS APOSED TO CHEAPERTENTATIVE
	                                if (CheaperTentative.Next == CheckConfirmed.Node_ID)
        	                        {
                	                        //dbg(ROUTING_CHANNEL, "DIFFERENT MESSAGE where the last Tentative's Next is in Confirmed's Node_ID. We should perhaps was look into changing Next...\n");
	                        	        CheaperTentative.Next = CheckConfirmed.Next;
	
		                               //SO GO CHECK IF THE NODE_ID CONNECTS TO IMMEDIATE NEIGHBORS
        		                       for(NeighborIndex = 0; NeighborIndex < call NeighborStorage.size(); NeighborIndex++)
              		                       {
                       		                        Next_Neighbor = call NeighborStorage.get(NeighborIndex);
                               		                if (CheaperTentative.Next == Next_Neighbor.Node_ID)
                                       		        {
                                               		        //dbg(ROUTING_CHANNEL, "We Theoretically found A THING? Size is more than 2, change Next and should be pushed?...\n");
                                                       		break;
	  	                                        }
        	                                }
	
        	                        }
               		        }			
				
	                }
			
                                         
		
		//}
               
		//I'M NOT ENTIRELY SURE IF THIS CHEAPER ONE IS TAKING THE CORRECT INDEX OUT OF THE TENTATIVE LIST (CAUTION)
		//We've theoretically the cheapter tentative out of the tentative list. remove it from Tentative, Have it go though recursion where it will get pushed onto the confirmed table.
		if (!inConfirmed)
		{
			if (call Tentative.size() - 1 > 1 && Cheaper_T_Index == call Tentative.size() - 1)
			{
				call Tentative.popback();
				//dbg(ROUTING_CHANNEL, "Popback is used...\n");
			}
			else
			{
				//CheaperTentative = call Tentative.removefromList(Cheaper_T_Index);
				call Tentative.removefromList(Cheaper_T_Index);
				call Tentative.popback();
				//dbg(ROUTING_CHANNEL, "removefromList is used...\n");	
			}
			//call ConfirmedTable.pushfront(CheaperTentative);
                	//dbg(ROUTING_CHANNEL, "What is considered the the final Cheaper Tentative?     Dest: %d, Cost: %d, Cheaper_T_Index: %d\n",CheaperTentative.Node_ID, CheaperTentative.Cost, Cheaper_T_Index);
			Dijkstra(CheaperTentative.Node_ID, CheaperTentative.Cost, CheaperTentative.Next);		
		}
	}	
	
	
	//dbg(ROUTING_CHANNEL, "Next_LSP's Node_ID is...: %d ! Now look through it's neighbors and post it's list\n", Next_LSP.Node_ID);

   }	
} //hewwo
