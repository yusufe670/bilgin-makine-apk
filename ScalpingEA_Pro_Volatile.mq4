//+------------------------------------------------------------------+
//|  ScalpingEA Pro Volatile v6.0  —  Grid Scalper                  |
//|  Fiyat aleyhine gidince üst üste açar, geri dönünce hepsi kapanır|
//+------------------------------------------------------------------+
#property strict
#property version "6.00"

// --- Giriş Sinyali
input int    RSI_Period  = 14;
input double RSI_OS      = 40.0;   // BUY başlangıç eşiği
input double RSI_OB      = 60.0;   // SELL başlangıç eşiği
input int    BB_Period   = 20;
input double BB_Dev      = 2.0;

// --- Grid Ayarları
input double GridStep    = 10.0;   // Her X pip'te yeni işlem aç
input int    MaxGrid     = 10;     // Max kaç işlem üst üste açılır
input double GridTP      = 15.0;   // Ortalamadan kaç pip kârda kapat
input double GridSL      = 100.0;  // Toplam zarar limiti (pip) — güvenlik

// --- Lot
input double Lot         = 0.01;
input bool   AutoLot     = false;
input double RiskPct     = 0.5;

// --- Filtreler
input int    MaxSpread   = 50;
input int    SessStart   = 7;
input int    SessEnd     = 22;
input int    Magic       = 202406;

datetime g_bar;

int OnInit() {
   Print("ScalpingEA v6.0 Grid | ", Symbol(), " | GridStep:", GridStep,
         " MaxGrid:", MaxGrid, " TP:", GridTP, " pip");
   return INIT_SUCCEEDED;
}

void OnTick() {
   // Grid TP kontrolü her tik'te yap
   GridKontrol(OP_BUY);
   GridKontrol(OP_SELL);

   if(Time[0] == g_bar) return;
   g_bar = Time[0];

   if(!IsTradeAllowed()) return;
   if((int)MarketInfo(Symbol(),MODE_SPREAD) > MaxSpread) return;
   if(!Seans()) return;

   double rsi = iRSI(NULL,0,RSI_Period,PRICE_CLOSE,1);
   double c1  = Close[1];
   double bm  = iBands(NULL,0,BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_MAIN,1);
   double bu  = iBands(NULL,0,BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_UPPER,1);
   double bl  = iBands(NULL,0,BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_LOWER,1);

   int buy_cnt  = PozSay(OP_BUY);
   int sell_cnt = PozSay(OP_SELL);

   // İlk giriş sinyali — normal strateji (BB kırılması + RSI)
   if(buy_cnt == 0) {
      if(c1 <= bl || rsi <= RSI_OS)
         Ac(OP_BUY);
   }
   if(sell_cnt == 0) {
      if(c1 >= bu || rsi >= RSI_OB)
         Ac(OP_SELL);
   }

   // Grid: Fiyat aleyhine gidince yeni işlem ekle
   if(buy_cnt > 0 && buy_cnt < MaxGrid) {
      double son_buy = SonIslemFiyat(OP_BUY);
      if(Bid < son_buy - GridStep * Point * 10)
         Ac(OP_BUY);
   }
   if(sell_cnt > 0 && sell_cnt < MaxGrid) {
      double son_sell = SonIslemFiyat(OP_SELL);
      if(Ask > son_sell + GridStep * Point * 10)
         Ac(OP_SELL);
   }
}

// Ortalama fiyatı hesapla ve TP'ye gelince hepsini kapat
void GridKontrol(int tip) {
   int cnt = PozSay(tip);
   if(cnt == 0) return;

   double toplam_lot   = 0;
   double agirlikli    = 0;
   double toplam_zarar = 0;

   for(int i = 0; i < OrdersTotal(); i++) {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=Magic || OrderSymbol()!=Symbol()) continue;
      if(OrderType()!=tip) continue;
      agirlikli  += OrderOpenPrice() * OrderLots();
      toplam_lot += OrderLots();
      toplam_zarar += OrderProfit();
   }

   if(toplam_lot <= 0) return;

   double ort_fiyat = agirlikli / toplam_lot;
   double pip       = Point * 10;
   bool   tp_hit    = false;
   bool   sl_hit    = false;

   if(tip == OP_BUY) {
      tp_hit = (Bid >= ort_fiyat + GridTP * pip);
      sl_hit = (Bid <= ort_fiyat - GridSL * pip);
   } else {
      tp_hit = (Ask <= ort_fiyat - GridTP * pip);
      sl_hit = (Ask >= ort_fiyat + GridSL * pip);
   }

   if(tp_hit || sl_hit) {
      string sebep = tp_hit ? "TP" : "SL";
      Print("[Grid ", sebep, "] ", cnt, " işlem kapatılıyor | Ort:", ort_fiyat,
            " | Kâr:", toplam_zarar);
      HepsiniKapat(tip);
   }
}

void HepsiniKapat(int tip) {
   for(int i = OrdersTotal()-1; i >= 0; i--) {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=Magic || OrderSymbol()!=Symbol()) continue;
      if(OrderType()!=tip) continue;
      double fiyat = (tip==OP_BUY) ? Bid : Ask;
      if(!OrderClose(OrderTicket(), OrderLots(), fiyat, 3, clrGold))
         Print("Kapama hatası:", GetLastError());
   }
}

void Ac(int tip) {
   double lot   = AutoLot ? LotHesapla() : Lot;
   double fiyat = (tip==OP_BUY) ? Ask : Bid;
   int cnt      = PozSay(tip);
   int t = OrderSend(Symbol(), tip, lot, fiyat, 3, 0, 0,
                     StringFormat("Grid#%d", cnt+1), Magic, 0,
                     tip==OP_BUY ? clrDodgerBlue : clrCrimson);
   if(t < 0) Print("Hata:", GetLastError());
   else Print("[Grid#", cnt+1, "] ", tip==OP_BUY?"BUY":"SELL",
              " @ ", fiyat, " lot=", lot);
}

double SonIslemFiyat(int tip) {
   double son = 0;
   datetime son_zaman = 0;
   for(int i = 0; i < OrdersTotal(); i++) {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=Magic || OrderSymbol()!=Symbol()) continue;
      if(OrderType()!=tip) continue;
      if(OrderOpenTime() >= son_zaman) {
         son_zaman = OrderOpenTime();
         son = OrderOpenPrice();
      }
   }
   return son;
}

double LotHesapla() {
   double r  = AccountBalance()*RiskPct/100.0;
   double pv = MarketInfo(Symbol(),MODE_TICKVALUE);
   double sp = GridSL * Point * 10 / Point;
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
