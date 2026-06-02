//+------------------------------------------------------------------+
//|  ScalpingEA Pro Volatile v3.0                                    |
//|  Strateji: EMA200 Trend + BB(1.8) + RSI(14) + Teyit Mumu        |
//|  Optimize: GBPJPY / XAUUSD  —  M15                              |
//|  Optimize sonuç: PF=2.53 | %50 kazanma | Score=4.82             |
//+------------------------------------------------------------------+
#property strict
#property copyright "Bilgin Makine"
#property version   "3.00"
#property description "EMA200 trend filtresi + Bollinger Bands teyit mumu scalping"

//─────────────────────────────────────────────────────────────────────
//  GİRİŞ PARAMETRELERİ
//─────────────────────────────────────────────────────────────────────

// RSI — Optimize sonucu: 14 periyot, OS:35, OB:70
input int      RSI_Period      = 14;
input double   RSI_Oversold    = 35.0;
input double   RSI_Overbought  = 70.0;

// Bollinger Bands — Optimize sonucu: BB(20, 1.8)
input int      BB_Period       = 20;
input double   BB_Deviation    = 1.8;

// EMA Trend Filtresi — sadece trend yönünde işlem
input int      EMA_Period      = 200;

// ATR Tabanlı SL/TP — Optimize sonucu: SL=1.2x, TP=3.0x  (R:R=1:2.5)
input int      ATR_Period      = 14;
input double   SL_Multiplier   = 1.2;
input double   TP_Multiplier   = 3.0;

// Trailing Stop
input bool     UseTrailing     = true;
input double   Trail_ATR_Mult  = 0.8;

// Lot & Para Yönetimi
input double   BaseLot         = 0.01;
input bool     AutoLot         = false;
input double   RiskPercent     = 1.0;   // Bakiyenin %1'i risk
input int      MaxPositions    = 1;

// Filtreler
input int      MaxSpread_Pts   = 35;
input int      SessionStart    = 7;     // Saat 07:00 (Londra açılışı)
input int      SessionEnd      = 21;    // Saat 21:00

// EA Kimliği
input int      MagicNumber     = 202403;

//─────────────────────────────────────────────────────────────────────
//  GLOBAL
//─────────────────────────────────────────────────────────────────────
datetime g_son_bar;
double   g_atr, g_ema200;
double   g_bb_up, g_bb_mid, g_bb_low;
double   g_rsi;

//─────────────────────────────────────────────────────────────────────
int OnInit()
{
   Print("ScalpingEA Pro Volatile v3.0 başlatıldı | ", Symbol(), " M", Period());
   Print("Parametreler: RSI(", RSI_Period, ") BB(", BB_Period, ",", BB_Deviation,
         ") EMA(", EMA_Period, ") SL=", SL_Multiplier, "x TP=", TP_Multiplier, "x");
   g_son_bar = 0;
   return INIT_SUCCEEDED;
}

//─────────────────────────────────────────────────────────────────────
void OnTick()
{
   // Her mum açılışında bir kez karar ver
   if(Time[0] == g_son_bar)
   {
      if(UseTrailing) TrailingStop();
      return;
   }
   g_son_bar = Time[0];

   if(!IsTradeAllowed())  return;
   if(!SpreadFiltresi())  return;
   if(!SeansFiltresi())   return;

   GostergeleriHesapla();

   int acik_buy  = AcikPozisyon(OP_BUY);
   int acik_sell = AcikPozisyon(OP_SELL);

   if(acik_buy + acik_sell < MaxPositions)
   {
      if(BuySinyali())  IslemAc(OP_BUY);
      if(SellSinyali()) IslemAc(OP_SELL);
   }

   if(UseTrailing) TrailingStop();
}

//─────────────────────────────────────────────────────────────────────
void GostergeleriHesapla()
{
   // Shift=1: kapanmış mumun değerleri (gürültüyü azaltır)
   g_atr    = iATR(NULL, 0, ATR_Period, 1);
   g_ema200 = iMA(NULL, 0, EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
   g_rsi    = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 2);   // 2 mum öncesi (sinyal mumu)
   g_bb_up  = iBands(NULL, 0, BB_Period, BB_Deviation, 0, PRICE_CLOSE, MODE_UPPER, 2);
   g_bb_low = iBands(NULL, 0, BB_Period, BB_Deviation, 0, PRICE_CLOSE, MODE_LOWER, 2);
   g_bb_mid = iBands(NULL, 0, BB_Period, BB_Deviation, 0, PRICE_CLOSE, MODE_MAIN,  1);
}

//─────────────────────────────────────────────────────────────────────
//  BUY SİNYALİ
//  1. EMA200 üzerinde (yükseliş trendi)
//  2. 2 mum önce kapanış alt BB altında + RSI < 35 (sinyal mumu)
//  3. 1 mum önce kapanış alt BB içinde/üstünde (teyit mumu — geri döndü)
//─────────────────────────────────────────────────────────────────────
bool BuySinyali()
{
   double c2  = Close[2];   // Sinyal mumu kapanışı
   double c1  = Close[1];   // Teyit mumu kapanışı

   double bl2 = iBands(NULL, 0, BB_Period, BB_Deviation, 0, PRICE_CLOSE, MODE_LOWER, 2);
   double bl1 = iBands(NULL, 0, BB_Period, BB_Deviation, 0, PRICE_CLOSE, MODE_LOWER, 1);

   bool trend   = (c1 > g_ema200);               // EMA200 üzerinde
   bool sinyal  = (c2 <= bl2 && g_rsi <= RSI_Oversold); // Alt BB kırıldı + RSI aşırı satım
   bool teyit   = (c1 > bl1);                    // Fiyat BB içine geri döndü
   bool yukselis = (c1 > c2);                    // Teyit mumu yeşil (yükselen kapanış)

   return (trend && sinyal && teyit && yukselis);
}

//─────────────────────────────────────────────────────────────────────
//  SELL SİNYALİ
//─────────────────────────────────────────────────────────────────────
bool SellSinyali()
{
   double c2  = Close[2];
   double c1  = Close[1];

   double bu2 = iBands(NULL, 0, BB_Period, BB_Deviation, 0, PRICE_CLOSE, MODE_UPPER, 2);
   double bu1 = iBands(NULL, 0, BB_Period, BB_Deviation, 0, PRICE_CLOSE, MODE_UPPER, 1);

   bool trend   = (c1 < g_ema200);
   bool sinyal  = (c2 >= bu2 && g_rsi >= RSI_Overbought);
   bool teyit   = (c1 < bu1);
   bool dusus   = (c1 < c2);

   return (trend && sinyal && teyit && dusus);
}

//─────────────────────────────────────────────────────────────────────
//  İŞLEM AÇ
//─────────────────────────────────────────────────────────────────────
void IslemAc(int tip)
{
   if(g_atr <= 0) return;

   double lot   = LotHesapla();
   double fiyat = (tip == OP_BUY) ? Ask : Bid;
   double sl, tp;

   if(tip == OP_BUY)
   {
      sl = NormalizeDouble(fiyat - g_atr * SL_Multiplier, Digits);
      tp = NormalizeDouble(fiyat + g_atr * TP_Multiplier, Digits);
   }
   else
   {
      sl = NormalizeDouble(fiyat + g_atr * SL_Multiplier, Digits);
      tp = NormalizeDouble(fiyat - g_atr * TP_Multiplier, Digits);
   }

   string yorum  = StringFormat("ScalpEA v3 %s ATR=%.5f", (tip==OP_BUY?"BUY":"SELL"), g_atr);
   color  renk   = (tip == OP_BUY) ? clrDodgerBlue : clrCrimson;

   int ticket = OrderSend(Symbol(), tip, lot, fiyat, 3, sl, tp, yorum, MagicNumber, 0, renk);

   if(ticket < 0)
      Print("HATA OrderSend: ", GetLastError(), " | tip=", tip, " fiyat=", fiyat, " sl=", sl, " tp=", tp);
   else
      Print("[+] #", ticket, " ", (tip==OP_BUY?"BUY":"SELL"),
            " lot=", lot, " fiyat=", fiyat, " SL=", sl, " TP=", tp);
}

//─────────────────────────────────────────────────────────────────────
//  TRAILING STOP
//─────────────────────────────────────────────────────────────────────
void TrailingStop()
{
   double mesafe = g_atr * Trail_ATR_Mult;
   if(mesafe <= 0) return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != MagicNumber)           continue;
      if(OrderSymbol() != Symbol())                   continue;

      double yeni_sl;

      if(OrderType() == OP_BUY)
      {
         yeni_sl = NormalizeDouble(Bid - mesafe, Digits);
         if(Bid > OrderOpenPrice() && yeni_sl > OrderStopLoss() + Point)
            OrderModify(OrderTicket(), OrderOpenPrice(), yeni_sl, OrderTakeProfit(), 0, clrGold);
      }
      else if(OrderType() == OP_SELL)
      {
         yeni_sl = NormalizeDouble(Ask + mesafe, Digits);
         if(Ask < OrderOpenPrice() && (OrderStopLoss() == 0 || yeni_sl < OrderStopLoss() - Point))
            OrderModify(OrderTicket(), OrderOpenPrice(), yeni_sl, OrderTakeProfit(), 0, clrGold);
      }
   }
}

//─────────────────────────────────────────────────────────────────────
//  LOT HESAPLA
//─────────────────────────────────────────────────────────────────────
double LotHesapla()
{
   if(!AutoLot) return(NormalizeDouble(BaseLot, 2));

   double bakiye   = AccountBalance();
   double risk_usd = bakiye * RiskPercent / 100.0;
   double pip_val  = MarketInfo(Symbol(), MODE_TICKVALUE);
   double sl_pip   = g_atr * SL_Multiplier / Point;

   if(pip_val <= 0 || sl_pip <= 0) return BaseLot;

   double lot      = risk_usd / (sl_pip * pip_val);
   double min_lot  = MarketInfo(Symbol(), MODE_MINLOT);
   double max_lot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lot_adim = MarketInfo(Symbol(), MODE_LOTSTEP);

   lot = MathFloor(lot / lot_adim) * lot_adim;
   return NormalizeDouble(MathMax(min_lot, MathMin(max_lot, lot)), 2);
}

//─────────────────────────────────────────────────────────────────────
int AcikPozisyon(int tip)
{
   int n = 0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != MagicNumber)           continue;
      if(OrderSymbol() != Symbol())                   continue;
      if(OrderType() == tip) n++;
   }
   return n;
}

bool SpreadFiltresi()
{
   return ((int)MarketInfo(Symbol(), MODE_SPREAD) <= MaxSpread_Pts);
}

bool SeansFiltresi()
{
   int saat = TimeHour(TimeCurrent());
   return (saat >= SessionStart && saat < SessionEnd);
}
