//+------------------------------------------------------------------+
//|  ScalpingEA Pro Volatile v4.0  —  Agresif Scalper               |
//|  M5 | Sık işlem | BB + RSI | GBPJPY / XAUUSD                   |
//+------------------------------------------------------------------+
#property strict
#property version "4.00"

input int      RSI_Period     = 14;
input double   RSI_OS         = 40.0;   // BUY eşiği (gevşek = çok sinyal)
input double   RSI_OB         = 60.0;   // SELL eşiği
input int      BB_Period      = 20;
input double   BB_Dev         = 2.0;
input int      ATR_Period     = 14;
input double   SL_Mult        = 1.0;    // Dar SL
input double   TP_Mult        = 2.0;    // R:R = 1:2
input bool     UseTrailing    = true;
input double   Trail_Mult     = 0.7;
input double   Lot            = 0.01;
input bool     AutoLot        = false;
input double   RiskPct        = 1.0;
input int      MaxPos         = 5;      // Aynı anda 5 işlem (max 10 yapılabilir)
input int      MaxSpread      = 40;
input int      SessStart      = 7;
input int      SessEnd        = 22;
input int      Magic          = 202404;

datetime g_bar;
double   g_atr;

int OnInit() {
   Print("ScalpingEA v4.0 | ", Symbol(), " M", Period(), " | Lot:", Lot);
   return INIT_SUCCEEDED;
}

void OnTick() {
   if(Time[0] == g_bar) { if(UseTrailing) Trail(); return; }
   g_bar = Time[0];
   if(!IsTradeAllowed()) return;
   if((int)MarketInfo(Symbol(),MODE_SPREAD) > MaxSpread) return;
   if(!Seans()) return;

   g_atr = iATR(NULL,0,ATR_Period,1);

   double rsi  = iRSI(NULL,0,RSI_Period,PRICE_CLOSE,1);
   double c1   = Close[1];
   double bu   = iBands(NULL,0,BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_UPPER,1);
   double bl   = iBands(NULL,0,BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_LOWER,1);

   int buy_cnt  = PozSay(OP_BUY);
   int sell_cnt = PozSay(OP_SELL);

   // BUY: Fiyat alt BB'ye değdi + RSI aşırı satım
   if(buy_cnt + sell_cnt < MaxPos) {
      if(c1 <= bl && rsi <= RSI_OS)
         Ac(OP_BUY);
      if(c1 >= bu && rsi >= RSI_OB)
         Ac(OP_SELL);
   }

   if(UseTrailing) Trail();
}

void Ac(int tip) {
   if(g_atr <= 0) return;
   double lot   = AutoLot ? LotHesapla() : Lot;
   double fiyat = (tip==OP_BUY) ? Ask : Bid;
   double sl    = NormalizeDouble(tip==OP_BUY ? fiyat-g_atr*SL_Mult : fiyat+g_atr*SL_Mult, Digits);
   double tp    = NormalizeDouble(tip==OP_BUY ? fiyat+g_atr*TP_Mult : fiyat-g_atr*TP_Mult, Digits);
   int t = OrderSend(Symbol(), tip, lot, fiyat, 3, sl, tp,
                     "ScalpEA v4.0", Magic, 0, tip==OP_BUY?clrDodgerBlue:clrCrimson);
   if(t < 0) Print("Hata: ", GetLastError());
   else Print("[+] ", tip==OP_BUY?"BUY":"SELL", " #", t, " lot=", lot, " sl=", sl, " tp=", tp);
}

void Trail() {
   double d = g_atr * Trail_Mult;
   if(d <= 0) return;
   for(int i = OrdersTotal()-1; i >= 0; i--) {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=Magic || OrderSymbol()!=Symbol()) continue;
      double nsl;
      if(OrderType()==OP_BUY) {
         nsl = NormalizeDouble(Bid-d, Digits);
         if(Bid>OrderOpenPrice() && nsl>OrderStopLoss()+Point)
            OrderModify(OrderTicket(),OrderOpenPrice(),nsl,OrderTakeProfit(),0,clrGold);
      } else {
         nsl = NormalizeDouble(Ask+d, Digits);
         if(Ask<OrderOpenPrice() && (OrderStopLoss()==0||nsl<OrderStopLoss()-Point))
            OrderModify(OrderTicket(),OrderOpenPrice(),nsl,OrderTakeProfit(),0,clrGold);
      }
   }
}

double LotHesapla() {
   double r = AccountBalance()*RiskPct/100.0;
   double pv = MarketInfo(Symbol(),MODE_TICKVALUE);
   double sl_p = g_atr*SL_Mult/Point;
   if(pv<=0||sl_p<=0) return Lot;
   double l = MathFloor((r/(sl_p*pv))/MarketInfo(Symbol(),MODE_LOTSTEP))*MarketInfo(Symbol(),MODE_LOTSTEP);
   return NormalizeDouble(MathMax(MarketInfo(Symbol(),MODE_MINLOT),MathMin(MarketInfo(Symbol(),MODE_MAXLOT),l)),2);
}

int PozSay(int tip) {
   int n=0;
   for(int i=0;i<OrdersTotal();i++) {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()==Magic && OrderSymbol()==Symbol() && OrderType()==tip) n++;
   }
   return n;
}

bool Seans() { int s=TimeHour(TimeCurrent()); return s>=SessStart&&s<SessEnd; }
