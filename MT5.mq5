//+------------------------------------------------------------------+
//|                                                          MT5.mq5 |
//|                                              jaffer wilson, 2020 |
//+------------------------------------------------------------------+
#property copyright "© 2020Jaffer Wilson"
#property link      "jafferwilson@gmail.com"
#property version   "1.00"

#include "SocketLib.mqh"
#include "Symbol.mqh"
#resource "sym_port.txt" as string port_list
string Host="0.0.0.0";
ushort Port=0;
input string append_to_symbol_name = "MT4";

SOCKET64 server=INVALID_SOCKET64;
SOCKET64 conns[];
string sep_symbol[];
int lent = StringSplit(_Symbol,'_',sep_symbol);
string symbol_custom=sep_symbol[0]+"_"+append_to_symbol_name;
long id_chart1=0;
bool is_History_Loaded = false,Once_Time_replace=true;
//------------------------------------------------------------------ OnInit
int OnInit()
  {
   string split_ports[];
   int length_split = StringSplit(port_list,'\n',split_ports);
   Port=0;
   for(int i=0; i<length_split; i++)
     {
      if(StringFind(split_ports[i],_Symbol)>=0)
        {
         int replace_string_len = StringReplace(split_ports[i],_Symbol+"=","");
         Port = ushort(split_ports[i]);
         break;
        }
     }
   if(Port <=0)
     {
      PrintFormat("The Symbols %s is not in the file",_Symbol);
      return INIT_FAILED;
     }
   Print(_Symbol," is assigned to Port: ",Port);
   for(long charts = ChartFirst(); charts!=-1 && !_StopFlag; charts=ChartNext(charts))
     {
      if(ChartSymbol(charts) == symbol_custom)
         ChartClose(charts);
     }
   SymbolSelect(symbol_custom,false);
   CustomSymbolDelete(symbol_custom);

   const SYMBOL SYMB(symbol_custom);
   if(SYMB.IsExist() == false) // If Created
     {
      SYMB.CloneProperties(sep_symbol[0]);
      CustomSymbolSetInteger(symbol_custom,SYMBOL_DIGITS,_Digits);
      SymbolSelect(SYMB.Name,1);
      CustomSymbolSetString(SYMB.Name,SYMBOL_PATH,SymbolInfoString(sep_symbol[0],SYMBOL_PATH));
     }
   else
     {
      CustomSymbolSetInteger(symbol_custom,SYMBOL_DIGITS,_Digits);
      SymbolSelect(SYMB.Name,1);
      CustomSymbolSetString(SYMB.Name,SYMBOL_PATH,SymbolInfoString(sep_symbol[0],SYMBOL_PATH));
     }
   is_History_Loaded = false;
   Once_Time_replace=true;
   Load_History();

   return 0;
  }
//------------------------------------------------------------------ OnDeinit
void OnDeinit(const int reason) { EventKillTimer(); CloseClean(); if(id_chart1!=0)ChartClose(id_chart1);}
//------------------------------------------------------------------ OnTrade
//------------------------------------------------------------------ OnTimer
void OnTimer()
  {
   if(server==INVALID_SOCKET64)
      StartServer(Host,Port);
   else
     {
      AcceptClients(); // add pending clients
     }
  }
//------------------------------------------------------------------ StartServer
void StartServer(string addr,ushort port)
  {
// initialize the library
   char wsaData[];
   ArrayResize(wsaData,sizeof(WSAData));
   int res=WSAStartup(MAKEWORD(2,2), wsaData);
   if(res!=0)
     {
      Print("-WSAStartup failed error: "+string(res));
      return;
     }

// create a socket
   server=socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);
   if(server==INVALID_SOCKET64)
     {
      Print("-Create failed error: "+WSAErrorDescript(WSAGetLastError()));
      CloseClean();
      return;
     }

// bind to address and port
   Print("try bind..."+addr+":"+string(port));

   char ch[];
   StringToCharArray(addr,ch);
   sockaddr_in addrin;
   addrin.sin_family=AF_INET;
   addrin.sin_addr.u.S_addr=inet_addr(ch);
   addrin.sin_port=htons(port);
   ref_sockaddr ref;
   ref.in=addrin;
   if(bind(server,ref.ref,sizeof(addrin))==SOCKET_ERROR)
     {
      int err=WSAGetLastError();
      if(err!=WSAEISCONN)
        {
         Print("-Connect failed error: "+WSAErrorDescript(err)+". Cleanup socket");
         CloseClean();
         return;
        }
     }

// set to nonblocking mode
   int non_block=1;
   res=ioctlsocket(server,(int)FIONBIO,non_block);
   if(res!=NO_ERROR)
     {
      Print("ioctlsocket failed error: "+string(res));
      CloseClean();
      return;
     }

// listen port and accept client connections
   if(listen(server,SOMAXCONN)==SOCKET_ERROR)
     {
      Print("Listen failed with error: ",WSAErrorDescript(WSAGetLastError()));
      CloseClean();
      return;
     }

   Print("start server ok");
  }
//------------------------------------------------------------------ Accept
void AcceptClients() // Accept a client socket
  {
   if(server==INVALID_SOCKET64)
      return;

// add all pending clients
   SOCKET64 client=INVALID_SOCKET64;
   do
     {
      ref_sockaddr ch;
      int len=sizeof(ref_sockaddr);
      client=accept(server,ch.ref,len);
      if(client==INVALID_SOCKET64)
        {
         int err=WSAGetLastError();
         if(err!=WSAEWOULDBLOCK)
           {
            Print("Accept failed with error: ",WSAErrorDescript(err));
            CloseClean();
           }
         return;
        }

      // set to nonblocking mode
      int non_block=1;
      int res=ioctlsocket(client, (int)FIONBIO, non_block);
      if(res!=NO_ERROR)
        {
         Print("ioctlsocket failed error: "+string(res));
         continue;
        }

      // add client socket to the array
      int n=ArraySize(conns);
      ArrayResize(conns,n+1);
      conns[n]=client;
      char rbuf[150];
      int rlen=150;
      Comment("");
      int r=0;
      do
        {
         res=recv(client,rbuf,rlen,0);
         if(res<0)
           {
            int err=WSAGetLastError();
            if(err!=WSAEWOULDBLOCK)
              {
               Print("-Receive failed error: "+string(err)+" "+WSAErrorDescript(err));
               CloseClean();
               return;
              }
            break;
           }
         if(res==0 && r==0)
           {
            Print("-Receive. connection closed");
            CloseClean();
            return;
           }
         r+=res;
         uchar rdata[];
         string data[];
         ArrayCopy(rdata,rbuf,ArraySize(rdata),0,res);
         int length = StringSplit(CharArrayToString(rdata),',',data);
         if(length>5)
           {
            if(data[1]==_Symbol)
              {
               MqlTick ticks_array[1];
               ticks_array[0].time=datetime(long(data[2]));
               ticks_array[0].ask =double(data[3]);
               ticks_array[0].bid =double(data[4]);
               ticks_array[0].time_msc=(long(data[5])*1000)+long(data[12]);
               CustomTicksAdd(symbol_custom,ticks_array);
               //if(Once_Time_replace==true)
                 {
                  MqlRates rates_add[1];
                  rates_add[0].time=datetime(long(data[6]));
                  rates_add[0].open=double(data[7]);
                  rates_add[0].high=double(data[8]);
                  rates_add[0].low =double(data[9]);
                  rates_add[0].close=double(data[10]);
                  rates_add[0].spread=int(data[11]);
                  rates_add[0].tick_volume=long(data[12]);
                  rates_add[0].real_volume=0;
                  if(CustomRatesUpdate(symbol_custom,rates_add)<=0)
                    {
                     PrintFormat("Cannot Update the Rates for Symbol: %s  Error:%d ",_Symbol,GetLastError());
                     if(CustomRatesReplace(symbol_custom,rates_add[0].time,rates_add[0].time,rates_add)<=0)
                        PrintFormat("Cannot Replace the rate for Symbol : %s Error: %d",_Symbol,GetLastError());
                    }
                  Once_Time_replace=false;
                 }
              }
           }
        }
      while(res>0 && res>=rlen);

      // show client information
      //char ipstr[23]= {0};
      //ref_sockaddr_in aclient;
      //aclient.in=ch.in; // convert into structure to get additional information about the connection
      //inet_ntop(aclient.in.sin_family, aclient.ref, ipstr, sizeof(ipstr)); // get the address
      //printf("Accept new client %s : %d",CharArrayToString(ipstr),ntohs(aclient.in.sin_port));

     }
   while(client!=INVALID_SOCKET64);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CloseClean() // close and clear operation
  {
   printf("Shutdown server and %d connections",ArraySize(conns));
   if(server!=INVALID_SOCKET64)
     {
      closesocket(server);   // close the server
      server=INVALID_SOCKET64;
     }
   for(int i=ArraySize(conns)-1; i>=0; --i)
      Close(conns[i]); // close the clients
   ArrayResize(conns,0);
   WSACleanup();
  }
//------------------------------------------------------------------ Close
void Close(SOCKET64 &asock) // close one socket
  {
   if(asock==INVALID_SOCKET64)
      return;
   if(shutdown(asock,SD_BOTH)==SOCKET_ERROR)
      Print("-Shutdown failed error: "+WSAErrorDescript(WSAGetLastError()));
   closesocket(asock);
   asock=INVALID_SOCKET64;
  }
//------------------------------------------------------------------ GetSymbolLot
void Load_History()
  {
   ResetLastError();
   if(FileIsExist(StringFormat("MT4Hist//%s.csv",_Symbol),FILE_COMMON))
     {
      int file  = FileOpen(StringFormat("MT4Hist//%s.csv",_Symbol),FILE_COMMON|FILE_CSV|FILE_WRITE|FILE_READ|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_ANSI,',');
      if(file!=INVALID_HANDLE)
        {
         MqlRates rates[];
         int size_counter = 1;
         while(!FileIsEnding(file) && !_StopFlag)
           {
            ArrayResize(rates,size_counter);
            rates[size_counter-1].time = datetime(FileReadString(file));
            rates[size_counter-1].open = double(FileReadString(file));
            rates[size_counter-1].high = double(FileReadString(file));
            rates[size_counter-1].low = double(FileReadString(file));
            rates[size_counter-1].close = double(FileReadString(file));
            rates[size_counter-1].spread = int(FileReadString(file));
            rates[size_counter-1].tick_volume = long(FileReadString(file));
            size_counter++;
           }
         FileClose(file);
         if(CustomRatesUpdate(symbol_custom,rates)<=0)
           {
            PrintFormat("Rates Cannot be Updated for Symbol: %s Error: %d",symbol_custom,GetLastError());
            if(CustomRatesReplace(symbol_custom,rates[0].time,rates[size_counter-1].time,rates)<=0)
               PrintFormat("Rates Cannot be Replace for Symbol: %s Error: %d",symbol_custom,GetLastError());
           }
        }

      is_History_Loaded = true;
      id_chart1=ChartOpen(symbol_custom,PERIOD_M1);
      EventSetMillisecondTimer(20);
     }

  }
//+------------------------------------------------------------------+
