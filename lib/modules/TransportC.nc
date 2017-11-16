#include "../includes/am_types.h"

configuration TransportC{
   provides interface Transport;
   uses interface List<RoutedTable> as ConfirmedTableC;
   uses interface List<socket_store_t> as SocketsC;
}

implementation{
   components TransportP;
   Transport = TransportP;

    components new SimpleSendC(AM_PACK);
    TransportP.Sender -> SimpleSendC;

    components new ListC(socket_store_t, 10) as Modify_The_StatesC;
    TransportP.Modify_The_States-> Modify_The_StatesC;
   
    TransportP.ConfirmedList = ConfirmedTableC;
    TransportP.Sockets = SocketsC;
}
