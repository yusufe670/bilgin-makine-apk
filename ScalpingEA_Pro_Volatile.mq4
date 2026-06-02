//+------------------------------------------------------------------+
//|  ScalpingEA Pro Volatile v5.0  —  Çift Yönlü Agresif Scalper   |
//|  Aynı anda BUY + SELL | Hızlı TP | Sürekli sinyal | M5         |
//+------------------------------------------------------------------+
#property strict
#property version "5.1"

input int    RSI_Period  = 14;
input double RSI_OS      = 45.0;   // BUY eşiği
input double RSI_OB      = 55.0;   // SELL eşiği
input int    BB_Period   = 20;
input double BB_Dev      = 2.0;
input int    ATR_Period  = 14;
input double SL_Mult     = 1.0;
input double TP_Mult     = 1.5;    // Hızlı TP
input bool   UseTrailing = true;
input double Trail_Mult  = 0.5;
input double Lot         = 0.01;
input bool   AutoLot     = false;
input double RiskPct     = 1.0;
input int    MaxBuy      = 5;      // Aynı anda max BUY sayısı
input int    MaxSell     = 5;      // Aynı anda max SELL sayısı
input int    MaxSpread   = 50;
input int    SessStart   = 7;
input int    SessEnd     = 22;
input int    Magic       = 202405;

datetime g_bar;
double   g_atr;

int OnInit() {
   Print("ScalpingEA v5.0 | ", Symbol(), " M", Period(),
         " | BUY+SELL | MaxBuy:", MaxBuy, " MaxSell:", MaxSell);
   return INIT_SUCCEEDED;
}

void OnTick() {
   if(Time[0] == g_bar) { if(UseTrailing) Trail(); return; }
   g_bar = Time[0];

   if(!IsTradeAllowed()) return;
   if((int)MarketInfo(Symbol(),MODE_SPREAD) > MaxSpread) return;
   if(!Seans()) return;

   g_atr = iATR(NULL,0,ATR_Period,1);
   if(g_atr <= 0) return;

   double rsi = iRSI(NULL,0,RSI_Period,PRICE_CLOSE,1);
   double c1  = Close[1];
   double bu  = iBands(NULL,0,BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_UPPER,1);
   double bm  = iBands(NULL,0,BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_MAIN, 1);
   double bl  = iBands(NULL,0,BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_LOWER,1);

   // TERS STRATEJİ: BB ortası üstünde = BUY, altında = SELL
   bool buy_sig  = (rsi >= RSI_OB) || (c1 > bm);
   bool sell_sig = (rsi <= RSI_OS) || (c1 < bm);

   if(buy_sig  && PozSay(OP_BUY)  < MaxBuy)  Ac(OP_BUY);
   if(sell_sig && PozSay(OP_SELL) < MaxSell) Ac(OP_SELL);

   if(UseTrailing) Trail();
}

void Ac(int tip) {
   double lot   = AutoLot ? LotHesapla() : Lot;
   double fiyat = (tip==OP_BUY) ? Ask : Bid;
   double sl    = NormalizeDouble(tip==OP_BUY ? fiyat-g_atr*SL_Mult
                                              : fiyat+g_atr*SL_Mult, Digits);
   double tp    = NormalizeDouble(tip==OP_BUY ? fiyat+g_atr*TP_Mult
                                              : fiyat-g_atr*TP_Mult, Digits);
   int t = OrderSend(Symbol(), tip, lot, fiyat, 3, sl, tp,
                     "ScalpEA v5", Magic, 0,
                     tip==OP_BUY ? clrDodgerBlue : clrCrimson);
   if(t < 0) Print("Hata:", GetLastError());
}

void Trail() {
   double d = g_atr * Trail_Mult;
   if(d <= 0) return;
   for(int i = OrdersTotal()-1; i >= 0; i--) {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=Magic || OrderSymbol()!=Symbol()) continue;
      double nsl;
      if(OrderType()==OP_BUY) {
         nsl = NormalizeDouble(Bid-d,Digits);
         if(Bid>OrderOpenPrice() && nsl>OrderStopLoss()+Point)
            OrderModify(OrderTicket(),OrderOpenPrice(),nsl,OrderTakeProfit(),0,clrGold);
      } else if(OrderType()==OP_SELL) {
         nsl = NormalizeDouble(Ask+d,Digits);
         if(Ask<OrderOpenPrice() && (OrderStopLoss()==0||nsl<OrderStopLoss()-Point))
            OrderModify(OrderTicket(),OrderOpenPrice(),nsl,OrderTakeProfit(),0,clrGold);
      }
   }
}

double LotHesapla() {
   double r  = AccountBalance()*RiskPct/100.0;
   double pv = MarketInfo(Symbol(),MODE_TICKVALUE);
   double sp = g_atr*SL_Mult/Point;
   if(pv<=0||sp<=0) return Lot;
   double l = MathFloor((r/(sp*pv))/MarketInfo(Symbol(),MODE_LOTSTEP))
              *MarketInfo(Symbol(),MODE_LOTSTEP);
   return NormalizeDouble(MathMax(MarketInfo(Symbol(),MODE_MINLOT),
          MathMin(MarketInfo(Symbol(),MODE_MAXLOT),l)),2);
}

int PozSay(int tip) {
   int n=0;
   for(int i=0;i<OrdersTotal();i++) {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()==Magic && OrderSymbol()==Symbol()
         && OrderType()==tip) n++;
   }
   return n;
}

bool Seans() {
   int s=TimeHour(TimeCurrent());
   return (s>=SessStart && s<SessEnd);
}
