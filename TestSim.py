#ANDES Lab - University of California, Merced
#Author: UCM ANDES Lab
#$Author: abeltran2 $
#$LastChangedDate: 2014-08-31 16:06:26 -0700 (Sun, 31 Aug 2014) $
#! /usr/bin/python
import sys
from TOSSIM import *
from CommandMsg import *

class TestSim:
    # COMMAND TYPES
    CMD_PING = 0
    CMD_NEIGHBOR_DUMP = 1
    CMD_LINKSTATE_DUMP = 2
    CMD_ROUTE_DUMP = 3
    CMD_TEST_CLIENT = 4
    CMD_TEST_SERVER = 5
    CMD_CLIENT_CLOSE = 6
    CMD_APP_LOGIN = 7
    CMD_APP_GLOBAL = 8
    CMD_APP_PRIVATE = 9
    CMD_APP_PRINTUSERS = 10
    CMD_APP_SET_SERVER = 11

    # CHANNELS - see includes/channels.h
    COMMAND_CHANNEL="command";
    GENERAL_CHANNEL="general";

    # Project 1
    NEIGHBOR_CHANNEL="neighbor";
    FLOODING_CHANNEL="flooding";

    # Project 2
    ROUTING_CHANNEL="routing";

    # Project 3
    TRANSPORT_CHANNEL="transport";

    # Personal Debuggin Channels for some of the additional models implemented.
    HASHMAP_CHANNEL="hashmap";

    # Initialize Vars
    numMote=0

    def __init__(self):
        self.t = Tossim([])
        self.r = self.t.radio()

        #Create a Command Packet
        self.msg = CommandMsg()
        self.pkt = self.t.newPacket()
        self.pkt.setType(self.msg.get_amType())

    # Load a topo file and use it.
    def loadTopo(self, topoFile):
        print 'Creating Topo!'
        # Read topology file.
        topoFile = 'topo/'+topoFile
        f = open(topoFile, "r")
        self.numMote = int(f.readline());
        print 'Number of Motes', self.numMote
        for line in f:
            s = line.split()
            if s:
                print " ", s[0], " ", s[1], " ", s[2];
                self.r.add(int(s[0]), int(s[1]), float(s[2]))

    # Load a noise file and apply it.
    def loadNoise(self, noiseFile):
        if self.numMote == 0:
            print "Create a topo first"
            return;

        # Get and Create a Noise Model
        noiseFile = 'noise/'+noiseFile;
        noise = open(noiseFile, "r")
        for line in noise:
            str1 = line.strip()
            if str1:
                val = int(str1)
            for i in range(1, self.numMote+1):
                self.t.getNode(i).addNoiseTraceReading(val)

        for i in range(1, self.numMote+1):
            print "Creating noise model for ",i;
            self.t.getNode(i).createNoiseModel()

    def bootNode(self, nodeID):
        if self.numMote == 0:
            print "Create a topo first"
            return;
        self.t.getNode(nodeID).bootAtTime(1333*nodeID);

    def bootAll(self):
        i=0;
        for i in range(1, self.numMote+1):
            self.bootNode(i);

    def moteOff(self, nodeID):
        self.t.getNode(nodeID).turnOff();

    def moteOn(self, nodeID):
        self.t.getNode(nodeID).turnOn();

    def run(self, ticks):
        for i in range(ticks):
            self.t.runNextEvent()

    # Rough run time. tickPerSecond does not work.
    def runTime(self, amount):
        self.run(amount*1000)

    # Generic Command
    def sendCMD(self, ID, dest, payloadStr):
        self.msg.set_dest(dest);
        self.msg.set_id(ID);
        self.msg.setString_payload(payloadStr)

        self.pkt.setData(self.msg.data)
        self.pkt.setDestination(dest)
        self.pkt.deliver(dest, self.t.time()+5)

    def ping(self, source, dest, msg):
        self.sendCMD(self.CMD_PING, source,"{0}{1}".format(chr(dest),msg));

    def neighborDMP(self, destination):
        self.sendCMD(self.CMD_NEIGHBOR_DUMP, destination, "neighbor command");

    def routeDMP(self, destination):
        self.sendCMD(self.CMD_ROUTE_DUMP, destination, "routing command");

    def linkstateDMP(self, destination):
	self.sendCMD(self.CMD_LINKSTATE_DUMP, destination, "print link_table command"); 
   
    def testClient(self, source, destination, srcPort, destPort, transfer):
        self.sendCMD(self.CMD_TEST_CLIENT, source, "{0}{1}{2}{3}".format(chr(destination),chr(srcPort),chr(destPort),chr(transfer)));

    def testServer(self, destination, port):
        self.sendCMD(self.CMD_TEST_SERVER, destination, chr(port));
    
    def ClientClose(self, ClientAddress, destination, srcPort, destPort):
        self.sendCMD(self.CMD_CLIENT_CLOSE, source, "{0}{1}{2}".format(chr(destination),chr(srcPort),destPort));

    def appLogin(self, Source, ClientPort, Username):
        self.sendCMD(self.CMD_APP_LOGIN, Source, "{0}{1}".format(chr(ClientPort), Username));

    def appSendGlobal(self, Source, Message):
        self.sendCMD(self.CMD_APP_GLOBAL, Source, Message);

    def appSendPrivate(self, Source, Username, Message):
        self.sendCMD(self.CMD_APP_PRIVATE, Source, "{0}{1}".format(Username, Message));

    def setAppServer(self, destination):
        self.sendCMD(self.CMD_APP_SET_SERVER, destination, "setserver command");

    def appPrintUsers(self, Source):
        self.sendCMD(self.CMD_APP_PRINTUSERS, Source);

    def addChannel(self, channelName, out=sys.stdout):
        print 'Adding Channel', channelName;
        self.t.addChannel(channelName, out);
    
def main():
    s = TestSim();
    s.runTime(10);
    s.loadTopo("example.topo");
    s.loadNoise("no_noise.txt");
    s.bootAll();
    s.addChannel(s.COMMAND_CHANNEL);
    s.addChannel(s.GENERAL_CHANNEL);
    s.addChannel(s.NEIGHBOR_CHANNEL);
    s.addChannel(s.FLOODING_CHANNEL);
    s.addChannel(s.ROUTING_CHANNEL);
    s.addChannel(s.TRANSPORT_CHANNEL);
    
    s.runTime(70);
#    s.neighborDMP(4);
#    s.runTime(40);
#    s.linkstateDMP(8);
#    s.runTime(40);
#    s.ping(1,5, "hello 8 to 2");
#    s.runTime(40);
#    s.routeDMP(8);
#    s.runTime(40);

# Test out Project 3
#    s.testServer(9, 80);
#    s.runTime(40);
#    s.testServer(5, 80);
#    s.runTime(40);
#    s.testServer(4, 60);
#    s.runTime(40);
#    s.testServer(9, 81);
#    s.runTime(40);
    s.testServer(9, 82);
    s.runTime(40);
    s.setAppServer(1);
    s.runTime(40);

    s.testClient(3, 9, 70, 82, 100);
    s.runTime(50);

#    s.testClient(3, 9, 71, 83, 128);
#    s.runTime(50);
#    s.testClient(3, 9, 72, 81, 50);
#    s.runTime(50);
#    s.testServer(9, 86);
#    s.runTime(40);
#    s.testServer(3, 50);
#    s.runTime(40);
    s.appLogin(4, 30, "testUser\r\n");
    s.runTime(40);
    s.appSendGlobal(4, "Fuckme\r\n");
    s.runTime(40);
#Combined total of chars between both arrays have a max of 20 chars. Anything higher than 20 will cause it to crash...
    s.appSendPrivate(5, "FuckingUseruewqosy\r\n", "Fk\r\n");
    s.runTime(40);
if __name__ == '__main__':
    main()
