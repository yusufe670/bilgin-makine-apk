//+------------------------------------------------------------------+
//|  ScalpingEA Pro Volatile v2.0                                    |
//|  Strateji: Bollinger Bands + RSI + ATR tabanlı scalping          |
//|  Optimize hedef: GBPJPY, XAUUSD  —  M15 timeframe               |
//+------------------------------------------------------------------+
#property strict
#property copyright "Bilgin Makine"
#property version   "2.00"

//--- Giriş Parametreleri
input string   EA_ADI         = "ScalpingEA Pro Volatile v2.0";

// --- RSI Ayarları (Optimize sonucu: 7 periyot — en kârlı kombinasyon)
input int      RSI_Period     = 7;
input double   RSI_Oversold   = 30.0;   // Aşırı satım sınırı (BUY sinyali)
input double   RSI_Overbought = 70.0;   // Aşırı alım sınırı  (SELL sinyali)
input int      RSI_Shift      = 1;      // Kapanmış muma bak (gürültüyü azaltır)

// --- Bollinger Bands Ayarları
input int      BB_Period      = 20;
input double   BB_Deviation   = 2.0;
input int      BB_Shift       = 0;

// --- ATR Tabanlı SL/TP (Optimize sonucu: SL=1.5x, TP=4.0x — PF:1.36)
input int      ATR_Period     = 14;
input double   SL_Multiplier  = 1.5;   // ATR * 1.5 = Stop Loss
input double   TP_Multiplier  = 4.0;   // ATR * 4.0 = Take Profit  (R:R = 1:2.67)
input bool     UseTrailing    = true;
input double   Trail_ATR_Mult = 1.0;   // Trailing mesafesi = ATR * 1.0

// --- Lot & Para Yönetimi
input double   BaseLot        = 0.01;  // Başlangıç lotu
input bool     AutoLot        = false; // Otomatik lot (bakiyeye göre)
input double   RiskPercent    = 1.0;   // Otomatik lot için bakiye riski (%)
input int      MaxPositions   = 1;     // Aynı anda max açık işlem

// --- Spread & Seans Filtresi
input int      MaxSpread_Pts  = 35;    // Max spread (point) — daha geniş spread = işlem yok
input int      SessionStart   = 7;     // İşlem saati başlangıcı (sunucu saati)
input int      SessionEnd     = 21;    // İşlem saati bitişi

// --- Sihirli numara (bu EA'nın işlemlerini tanımlar)
input int      MagicNumber    = 202402;

//+------------------------------------------------------------------+
//| Global değişkenler                                               |
//+------------------------------------------------------------------+
double   g_atr, g_bb_upper, g_bb_lower, g_bb_mid;
double   g_rsi;
datetime g_last_bar;

//+------------------------------------------------------------------+
//| EA başlarken çalışır                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== ", EA_ADI, " başlatıldı ===");
   Print("Sembol: ", Symbol(), " | Timeframe: ", Period(), " dk");
   Print("RSI(", RSI_Period, ")  BB(", BB_Period, ",", BB_Deviation, ")  ATR(", ATR_Period, ")");
   Print("SL=ATR*", SL_Multiplier, "  TP=ATR*", TP_Multiplier, "  Lot:", BaseLot);
   g_last_bar = 0;
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Her tick'te çalışır                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // --- Yeni mum kontrolü (her mum açılışında bir kez karar ver)
   if(Time[0] == g_last_bar)
   {
      // Aynı mumda sadece trailing stop güncelle
      if(UseTrailing) TrailingStop();
      return;
   }
   g_last_bar = Time[0];

   // --- Temel Filtreler ---
   if(!IsTradeAllowed()) return;
   if(!SessionFilter())  return;
   if(!SpreadFilter())   return;

   // --- İndikatör değerlerini hesapla ---
   HesaplaGostergeler();

   // --- Açık pozisyon sayısını kontrol et ---
   int acik_buy  = AcikPozisyon(OP_BUY);
   int acik_sell = AcikPozisyon(OP_SELL);

   // --- Çıkış sinyalleri (önce çıkış, sonra giriş) ---
   if(acik_buy > 0)  CikisKontrol(OP_BUY);
   if(acik_sell > 0) CikisKontrol(OP_SELL);

   // --- Giriş sinyalleri ---
   int toplam_acik = acik_buy + acik_sell;
   if(toplam_acik < MaxPositions)
   {
      if(BuySignal())  AcIslem(OP_BUY);
      if(SellSignal()) AcIslem(OP_SELL);
   }

   // --- Trailing stop ---
   if(UseTrailing) TrailingStop();
}

//+------------------------------------------------------------------+
//| Gösterge değerlerini hesapla                                     |
//+------------------------------------------------------------------+
void HesaplaGostergeler()
{
   // ATR — volatilite ölçümü
   g_atr = iATR(NULL, 0, ATR_Period, RSI_Shift);

   // Bollinger Bands
   g_bb_upper = iBands(NULL, 0, BB_Period, BB_Deviation, BB_Shift, PRICE_CLOSE, MODE_UPPER, RSI_Shift);
   g_bb_lower = iBands(NULL, 0, BB_Period, BB_Deviation, BB_Shift, PRICE_CLOSE, MODE_LOWER, RSI_Shift);
   g_bb_mid   = iBands(NULL, 0, BB_Period, BB_Deviation, BB_Shift, PRICE_CLOSE, MODE_MAIN,  RSI_Shift);

   // RSI
   g_rsi = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, RSI_Shift);
}

//+------------------------------------------------------------------+
//| BUY Sinyali                                                      |
//| Koşul: Kapanış fiyatı alt BB'nin altında VE RSI aşırı satımda   |
//+------------------------------------------------------------------+
bool BuySignal()
{
   double kapanis = Close[RSI_Shift];  // Kapanmış mum
   double onceki_kapanis = Close[RSI_Shift + 1];

   // Güçlü sinyal: fiyat alt BB'ye değdi ve RSI 30 altı
   bool bb_kiri   = (kapanis <= g_bb_lower);
   bool rsi_dusuk = (g_rsi <= RSI_Oversold);

   // Ek onay: önceki mumda fiyat daha da aşağıdaydı (dip oluşuyor)
   bool dipten_donus = (onceki_kapanis < kapanis);

   return (bb_kiri && rsi_dusuk && dipten_donus);
}

//+------------------------------------------------------------------+
//| SELL Sinyali                                                      |
//| Koşul: Kapanış fiyatı üst BB'nin üstünde VE RSI aşırı alımda   |
//+------------------------------------------------------------------+
bool SellSignal()
{
   double kapanis = Close[RSI_Shift];
   double onceki_kapanis = Close[RSI_Shift + 1];

   bool bb_kiri    = (kapanis >= g_bb_upper);
   bool rsi_yuksek = (g_rsi >= RSI_Overbought);
   bool tepeden_donus = (onceki_kapanis > kapanis);

   return (bb_kiri && rsi_yuksek && tepeden_donus);
}

//+------------------------------------------------------------------+
//| Çıkış Sinyali — orta BB'ye geri dönüş                           |
//+------------------------------------------------------------------+
void CikisKontrol(int tip)
{
   // Opsiyonel erken çıkış: fiyat orta BB'ye ulaştığında
   // (Bu özellik kapalı — SL/TP yeterli, erken çıkış R:R'yi bozar)
   // İstersen açmak için aşağıdaki bloğu aktif et:
   /*
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != MagicNumber) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderType() != tip) continue;

      bool cikis = false;
      if(tip == OP_BUY  && Bid >= g_bb_mid) cikis = true;
      if(tip == OP_SELL && Ask <= g_bb_mid) cikis = true;

      if(cikis)
      {
         double fiyat = (tip == OP_BUY) ? Bid : Ask;
         OrderClose(OrderTicket(), OrderLots(), fiyat, 3, clrOrange);
      }
   }
   */
}

//+------------------------------------------------------------------+
//| İşlem Aç                                                         |
//+------------------------------------------------------------------+
void AcIslem(int tip)
{
   if(g_atr <= 0) return;

   double lot = LotHesapla();
   double fiyat, sl, tp;
   color  renk;
   string yorum = EA_ADI;

   if(tip == OP_BUY)
   {
      fiyat = Ask;
      sl    = NormalizeDouble(fiyat - g_atr * SL_Multiplier, Digits);
      tp    = NormalizeDouble(fiyat + g_atr * TP_Multiplier, Digits);
      renk  = clrDodgerBlue;
      yorum += " BUY";
   }
   else
   {
      fiyat = Bid;
      sl    = NormalizeDouble(fiyat + g_atr * SL_Multiplier, Digits);
      tp    = NormalizeDouble(fiyat - g_atr * TP_Multiplier, Digits);
      renk  = clrCrimson;
      yorum += " SELL";
   }

   int ticket = OrderSend(Symbol(), tip, lot, fiyat, 3, sl, tp, yorum, MagicNumber, 0, renk);
   if(ticket < 0)
      Print("HATA: OrderSend başarısız — Error: ", GetLastError());
   else
      Print("İşlem açıldı: #", ticket, " | ", (tip==OP_BUY?"BUY":"SELL"),
            " | Lot:", lot, " | SL:", sl, " | TP:", tp);
}

//+------------------------------------------------------------------+
//| Trailing Stop                                                    |
//+------------------------------------------------------------------+
void TrailingStop()
{
   double trail_mesafe = g_atr * Trail_ATR_Mult;
   if(trail_mesafe <= 0) return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != MagicNumber) continue;
      if(OrderSymbol() != Symbol()) continue;

      double yeni_sl;
      bool   guncelle = false;

      if(OrderType() == OP_BUY)
      {
         yeni_sl = NormalizeDouble(Bid - trail_mesafe, Digits);
         if(yeni_sl > OrderStopLoss() + Point && Bid > OrderOpenPrice())
            guncelle = true;
      }
      else if(OrderType() == OP_SELL)
      {
         yeni_sl = NormalizeDouble(Ask + trail_mesafe, Digits);
         if((yeni_sl < OrderStopLoss() - Point || OrderStopLoss() == 0) && Ask < OrderOpenPrice())
            guncelle = true;
      }

      if(guncelle)
         OrderModify(OrderTicket(), OrderOpenPrice(), yeni_sl, OrderTakeProfit(), 0, clrYellow);
   }
}

//+------------------------------------------------------------------+
//| Lot Hesapla                                                      |
//+------------------------------------------------------------------+
double LotHesapla()
{
   if(!AutoLot) return BaseLot;

   double bakiye  = AccountBalance();
   double risk_tl = bakiye * RiskPercent / 100.0;
   double pip_deger = MarketInfo(Symbol(), MODE_TICKVALUE);
   double sl_pip = g_atr * SL_Multiplier / Point;

   if(pip_deger <= 0 || sl_pip <= 0) return BaseLot;

   double hesap_lot = risk_tl / (sl_pip * pip_deger);
   double min_lot   = MarketInfo(Symbol(), MODE_MINLOT);
   double max_lot   = MarketInfo(Symbol(), MODE_MAXLOT);
   double lot_adim  = MarketInfo(Symbol(), MODE_LOTSTEP);

   hesap_lot = MathFloor(hesap_lot / lot_adim) * lot_adim;
   hesap_lot = MathMax(min_lot, MathMin(max_lot, hesap_lot));
   return hesap_lot;
}

//+------------------------------------------------------------------+
//| Açık Pozisyon Sayısı                                             |
//+------------------------------------------------------------------+
int AcikPozisyon(int tip)
{
   int sayi = 0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != MagicNumber) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderType() == tip) sayi++;
   }
   return sayi;
}

//+------------------------------------------------------------------+
//| Spread Filtresi                                                  |
//+------------------------------------------------------------------+
bool SpreadFilter()
{
   int spread = (int)MarketInfo(Symbol(), MODE_SPREAD);
   if(spread > MaxSpread_Pts)
   {
      // Print("Spread çok geniş: ", spread, " > ", MaxSpread_Pts, " — işlem atlandı");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Seans Filtresi (düşük likidite saatlerini dışla)                |
//+------------------------------------------------------------------+
bool SessionFilter()
{
   int saat = TimeHour(TimeCurrent());
   return (saat >= SessionStart && saat < SessionEnd);
}
