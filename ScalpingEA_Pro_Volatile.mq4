//+------------------------------------------------------------------+
//|  ScalpingEA Pro Volatile v7.0  —  Burst Grid Scalper            |
//|  Sinyal gelince anında N işlem açar | MACD+RSI+BB               |
//+------------------------------------------------------------------+
#property strict
#property version "7.1"

// --- İndikatörler
input int    RSI_Period   = 14;
input double RSI_OS       = 45.0;
input double RSI_OB       = 55.0;
input int    BB_Period    = 20;
input double BB_Dev       = 2.0;
input int    MACD_Fast    = 12;
input int    MACD_Slow    = 26;
input int    MACD_Signal  = 9;

// --- Grid / Burst Ayarları
input int    BurstCount   = 10;    // Sinyal gelince kaç işlem AYNI ANDA açılır
input double GridStep     = 5.0;   // İşlemler arası pip farkı
input double GridTP       = 15.0;  // Ortalamadan kaç pip TP
input double GridSL       = 120.0; // Güvenlik SL (pip)

// --- Lot
input double Lot          = 0.50;
input bool   AutoLot      = false;
input double RiskPct      = 0.5;

// --- Filtreler
input int    MaxSpread    = 50;
input int    SessStart    = 7;
input int    SessEnd      = 22;
input int    Magic        = 202407;

datetime g_bar;
double   g_pip;

int OnInit() {
   g_pip = (Digits==3||Digits==5) ? Point*10 : Point;
   Print("ScalpingEA v7.0 Burst Grid | ", Symbol(), " | Burst:", BurstCount,
         " GridStep:", GridStep, "pip | Lot:", Lot);
   return INIT_SUCCEEDED;
}

void OnTick() {
   // TP/SL kontrolü her tik'te çalışır
   GridKontrol(OP_BUY);
   GridKontrol(OP_SELL);

   // Yeni bar kontrolü
   if(Time[0] == g_bar) return;
   g_bar = Time[0];

   if(!IsTradeAllowed()) return;
   if((int)MarketInfo(Symbol(),MODE_SPREAD) > MaxSpread) return;
   if(!Seans()) return;

   // --- İndikatör Değerleri ---
   double rsi    = iRSI(NULL,0,RSI_Period,PRICE_CLOSE,1);
   double c1     = Close[1];
   double bu     = iBands(NULL,0,BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_UPPER,1);
   double bm     = iBands(NULL,0,BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_MAIN, 1);
   double bl     = iBands(NULL,0,BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_LOWER,1);
   double macd   = iMACD(NULL,0,MACD_Fast,MACD_Slow,MACD_Signal,PRICE_CLOSE,MODE_MAIN,  1);
   double signal = iMACD(NULL,0,MACD_Fast,MACD_Slow,MACD_Signal,PRICE_CLOSE,MODE_SIGNAL,1);
   double macd0  = iMACD(NULL,0,MACD_Fast,MACD_Slow,MACD_Signal,PRICE_CLOSE,MODE_MAIN,  2);

   // --- BUY Sinyali ---
   // BB alt bandı kırıldı VEYA RSI aşırı satım + MACD yükseliyor
   bool buy_bb   = (c1 <= bl);
   bool buy_rsi  = (rsi <= RSI_OS);
   bool buy_macd = (macd > macd0);      // MACD yükseliyor (momentum artıyor)
   bool buy_sig  = (buy_bb || buy_rsi) && buy_macd;

   // --- SELL Sinyali ---
   bool sell_bb   = (c1 >= bu);
   bool sell_rsi  = (rsi >= RSI_OB);
   bool sell_macd = (macd < macd0);     // MACD düşüyor
   bool sell_sig  = (sell_bb || sell_rsi) && sell_macd;

   // --- Burst Açış: Sinyal gelince BurstCount kadar işlem AÇ ---
   if(buy_sig && PozSay(OP_SELL) == 0) {
      Print("[SELL BURST — ters] RSI:", DoubleToStr(rsi,1), " MACD:", DoubleToStr(macd,5));
      BurstAc(OP_SELL);
   }
   if(sell_sig && PozSay(OP_BUY) == 0) {
      Print("[BUY BURST — ters] RSI:", DoubleToStr(rsi,1), " MACD:", DoubleToStr(macd,5));
      BurstAc(OP_BUY);
   }
}

// Sinyal gelince BurstCount kadar işlem AYNI ANDA aç
void BurstAc(int tip) {
   double lot = AutoLot ? LotHesapla() : Lot;
   for(int k = 0; k < BurstCount; k++) {
      double fiyat, sl, tp_fiyat;
      if(tip == OP_BUY) {
         fiyat    = Ask - k * GridStep * g_pip;
         sl       = NormalizeDouble(fiyat - GridSL * g_pip, Digits);
         tp_fiyat = NormalizeDouble(fiyat + GridTP * g_pip, Digits);
      } else {
         fiyat    = Bid + k * GridStep * g_pip;
         sl       = NormalizeDouble(fiyat + GridSL * g_pip, Digits);
         tp_fiyat = NormalizeDouble(fiyat - GridTP * g_pip, Digits);
      }

      // İlk işlem market, diğerleri limit
      int tip_emir = (k == 0) ? tip : (tip==OP_BUY ? OP_BUYLIMIT : OP_SELLLIMIT);

      int t = OrderSend(Symbol(), tip_emir, lot, NormalizeDouble(fiyat,Digits),
                        3, sl, tp_fiyat,
                        StringFormat("Burst#%d", k+1), Magic, 0,
                        tip==OP_BUY ? clrDodgerBlue : clrCrimson);
      if(t < 0) Print("Hata k=", k, " err=", GetLastError());
   }
   Print("[BURST] ", BurstCount, " işlem açıldı | ", tip==OP_BUY?"BUY":"SELL");
}

// Ortalama fiyata göre TP/SL kontrolü
void GridKontrol(int tip) {
   // Açık market emirleri
   double toplam_lot = 0, agirlikli = 0, toplam_kar = 0;
   int    cnt = 0;

   for(int i = 0; i < OrdersTotal(); i++) {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=Magic || OrderSymbol()!=Symbol()) continue;
      if(OrderType()!=tip) continue;
      agirlikli  += OrderOpenPrice() * OrderLots();
      toplam_lot += OrderLots();
      toplam_kar += OrderProfit();
      cnt++;
   }
   if(cnt == 0 || toplam_lot <= 0) return;

   double ort   = agirlikli / toplam_lot;
   bool   tp_ok = false, sl_ok = false;

   if(tip == OP_BUY) {
      tp_ok = (Bid >= ort + GridTP * g_pip);
      sl_ok = (Bid <= ort - GridSL * g_pip);
   } else {
      tp_ok = (Ask <= ort - GridTP * g_pip);
      sl_ok = (Ask >= ort + GridSL * g_pip);
   }

   if(tp_ok || sl_ok) {
      Print("[", tp_ok?"TP":"SL", "] ", cnt, " işlem | Kâr: $", DoubleToStr(toplam_kar,2));
      HepsiniKapat(tip);
      // Bekleyen limitleri de iptal et
      LimitleriIptal(tip);
   }
}

void HepsiniKapat(int tip) {
   for(int i = OrdersTotal()-1; i >= 0; i--) {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=Magic || OrderSymbol()!=Symbol()) continue;
      if(OrderType()!=tip) continue;
      double f = (tip==OP_BUY) ? Bid : Ask;
      OrderClose(OrderTicket(), OrderLots(), f, 3, clrGold);
   }
}

void LimitleriIptal(int tip) {
   int limit_tip = (tip==OP_BUY) ? OP_BUYLIMIT : OP_SELLLIMIT;
   for(int i = OrdersTotal()-1; i >= 0; i--) {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=Magic || OrderSymbol()!=Symbol()) continue;
      if(OrderType()==limit_tip) OrderDelete(OrderTicket());
   }
}

double LotHesapla() {
   double r  = AccountBalance()*RiskPct/100.0;
   double pv = MarketInfo(Symbol(),MODE_TICKVALUE);
   double sp = GridSL * g_pip / Point;
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
