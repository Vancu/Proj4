/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"

configuration NodeC{
}
implementation {
    components MainC;
    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;

    Node -> MainC.Boot;

    Node.Receive -> GeneralReceive;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

    //Located in dataStructures under interfaces and modules folder
    components new ListC(pack, 32) as PacketStorageC;
    Node.PacketStorage-> PacketStorageC;

    components new ListC(LinkedNeighbor, 32) as NeighborStorageC;
    Node.NeighborStorage-> NeighborStorageC;

    components new ListC(LinkedNeighbor, 32) as NeighborDroppedC;
    Node.NeighborsDropped->NeighborDroppedC;

    components new TimerMilliC() as MyTimerC; //create a new timer with alias "myTimerC"
    Node.periodicTimer-> MyTimerC;

    components RandomC as Random;
    Node.Random -> Random;
}
