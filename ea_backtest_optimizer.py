"""
ScalpingEA Pro Volatile v3.0 — Gelişmiş Optimizasyon
EMA200 trend filtresi + teyit mumu + volatilite filtresi ile
"""

import itertools, warnings
warnings.filterwarnings("ignore")

import pandas as pd
import numpy as np

# ─────────────────────────────────────────────
# Göstergeler
# ─────────────────────────────────────────────

def rsi(close, p):
    d = close.diff()
    g = d.clip(lower=0).ewm(com=p-1, min_periods=p).mean()
    l = (-d).clip(lower=0).ewm(com=p-1, min_periods=p).mean()
    return (100 - 100/(1 + g/l.replace(0, np.nan))).fillna(50)

def bb(close, p, dev):
    m = close.rolling(p).mean()
    s = close.rolling(p).std()
    return m + dev*s, m, m - dev*s

def atr(h, l, c, p):
    tr = pd.concat([h-l, (h-c.shift()).abs(), (l-c.shift()).abs()], axis=1).max(axis=1)
    return tr.ewm(com=p-1, min_periods=p).mean()

def ema(close, p):
    return close.ewm(span=p, min_periods=p).mean()

# ─────────────────────────────────────────────
# Sintetik veri — GBPJPY benzeri oynaklık
# ─────────────────────────────────────────────

def veri_uret(n=8000, seed=42):
    np.random.seed(seed)
    fiyat = 188.0
    rows  = []
    for _ in range(n):
        # Trend bileşeni (uzun vadeli drift)
        drift  = np.random.choice([-1, 1], p=[0.48, 0.52]) * 0.0003 * fiyat
        gürültü = np.random.normal(0, 0.0018) * fiyat
        fiyat  += drift + gürültü
        fiyat   = max(fiyat, 100)

        spread = fiyat * 0.00012
        atr_sim = abs(gürültü) * 1.5 + spread
        high   = fiyat + abs(np.random.normal(0, 0.0009)) * fiyat
        low    = fiyat - abs(np.random.normal(0, 0.0009)) * fiyat
        open_  = fiyat - (drift + gürültü)
        rows.append({"Open": round(open_,3), "High": round(high,3),
                     "Low":  round(low,3),   "Close": round(fiyat,3)})

    df = pd.DataFrame(rows)
    df.index = pd.date_range("2022-01-01", periods=n, freq="15min")
    return df

# ─────────────────────────────────────────────
# Backtest Motoru — v3 (teyit mumu + EMA200 + ATR filtresi)
# ─────────────────────────────────────────────

def backtest(df, rsi_p=7, rsi_os=30, rsi_ob=70,
             bb_p=20, bb_dev=2.0,
             atr_p=14, sl_m=1.5, tp_m=4.0,
             ema_p=200, min_atr_mult=0.5,
             pip_deger=0.01, lot=0.01):

    c, h, l = df["Close"], df["High"], df["Low"]

    RSI   = rsi(c, rsi_p)
    BU, BM, BL = bb(c, bb_p, bb_dev)
    ATR   = atr(h, l, c, atr_p)
    EMA   = ema(c, ema_p)

    # Minimum ATR eşiği (cansız piyasayı filtrele)
    atr_ort = ATR.rolling(50).mean()

    start = max(ema_p, bb_p, atr_p) + 3
    trades = []
    pozisyon = None

    for i in range(start, len(df)):
        ci   = c.iloc[i]
        hi   = h.iloc[i]
        li   = l.iloc[i]

        # i-1: teyit mumunun kapanışı
        c1   = c.iloc[i-1]
        r1   = RSI.iloc[i-1]
        bu1  = BU.iloc[i-1]
        bl1  = BL.iloc[i-1]
        bm1  = BM.iloc[i-1]
        at1  = ATR.iloc[i-1]
        em1  = EMA.iloc[i-1]
        atr_ort1 = atr_ort.iloc[i-1]

        # i-2: sinyal mumunun kapanışı (BB'yi kıran mum)
        c2   = c.iloc[i-2]
        r2   = RSI.iloc[i-2]
        bu2  = BU.iloc[i-2]
        bl2  = BL.iloc[i-2]

        if at1 <= 0 or pd.isna(em1) or pd.isna(atr_ort1):
            continue

        # ── Açık pozisyonu kapat ──────────────────────
        if pozisyon is not None:
            tip = pozisyon["tip"]
            sl  = pozisyon["sl"]
            tp  = pozisyon["tp"]
            gir = pozisyon["giris"]

            if tip == "BUY":
                if li <= sl:
                    trades.append({"kar": (sl - gir)*lot*100000*pip_deger, "sonuc":"SL"})
                    pozisyon = None
                elif hi >= tp:
                    trades.append({"kar": (tp - gir)*lot*100000*pip_deger, "sonuc":"TP"})
                    pozisyon = None
            else:
                if hi >= sl:
                    trades.append({"kar": (gir - sl)*lot*100000*pip_deger, "sonuc":"SL"})
                    pozisyon = None
                elif li <= tp:
                    trades.append({"kar": (gir - tp)*lot*100000*pip_deger, "sonuc":"TP"})
                    pozisyon = None

        # ── Yeni işlem girişi ─────────────────────────
        if pozisyon is None:

            # Volatilite yeterli mi?
            if at1 < atr_ort1 * min_atr_mult:
                continue

            # BUY koşulları:
            # 1. EMA200 üzerinde (yükseliş trendi)
            # 2. i-2 mumunun kapanışı alt BB altında (sinyal)
            # 3. RSI aşırı satımda
            # 4. i-1 mumu alt BB'nin içine kapandı (teyit — geri döndü)
            buy_sinyal  = (c2 <= bl2 and r2 <= rsi_os)
            buy_teyit   = (c1 > bl1)            # Fiyat BB içine döndü
            buy_trend   = (c1 > em1)            # EMA200 üzerinde

            # SELL koşulları (tam tersi)
            sell_sinyal = (c2 >= bu2 and r2 >= rsi_ob)
            sell_teyit  = (c1 < bu1)
            sell_trend  = (c1 < em1)

            if buy_sinyal and buy_teyit and buy_trend:
                giris = ci  # Teyit mumundan sonraki bar açılışında gir
                pozisyon = {
                    "tip":   "BUY",
                    "giris": giris,
                    "sl":    giris - at1 * sl_m,
                    "tp":    giris + at1 * tp_m,
                }
            elif sell_sinyal and sell_teyit and sell_trend:
                giris = ci
                pozisyon = {
                    "tip":   "SELL",
                    "giris": giris,
                    "sl":    giris + at1 * sl_m,
                    "tp":    giris - at1 * tp_m,
                }

    if len(trades) < 10:
        return None

    t = pd.DataFrame(trades)
    kazananlar = t[t["kar"] > 0]["kar"].sum()
    kaybedenler = abs(t[t["kar"] < 0]["kar"].sum())
    return {
        "net_kar":       round(t["kar"].sum(), 2),
        "islem_sayisi":  len(t),
        "kazanma_%":     round((t["kar"] > 0).mean() * 100, 1),
        "profit_factor": round(kazananlar / kaybedenler, 2) if kaybedenler > 0 else 99,
        "maks_dd":       round(hesapla_drawdown(t["kar"]), 2),
        "score":         round(t["kar"].sum() / (hesapla_drawdown(t["kar"]) + 1), 3),
    }

def hesapla_drawdown(kar_serisi):
    birikim = kar_serisi.cumsum()
    tepe    = birikim.cummax()
    dd      = (tepe - birikim).max()
    return dd if dd > 0 else 0.01

# ─────────────────────────────────────────────
# Optimizasyon Grid
# ─────────────────────────────────────────────

GRID = {
    "rsi_p":  [7, 9, 14],
    "rsi_os": [25, 30, 35],
    "rsi_ob": [65, 70, 75],
    "bb_dev": [1.8, 2.0, 2.2],
    "sl_m":   [1.2, 1.5, 2.0],
    "tp_m":   [3.0, 4.0, 5.0],
}

if __name__ == "__main__":
    print("=" * 65)
    print("  ScalpingEA Pro Volatile v3.0 — Gelişmiş Optimizasyon")
    print("  EMA200 + Teyit Mumu + Volatilite Filtresi")
    print("=" * 65)

    df = veri_uret(8000)
    print(f"[+] Veri hazır: {len(df)} mum (8000x M15 ≈ 83 günlük)")

    keys  = list(GRID.keys())
    combos = list(itertools.product(*GRID.values()))
    print(f"[*] {len(combos)} kombinasyon test ediliyor...\n")

    sonuclar = []
    for combo in combos:
        p = dict(zip(keys, combo))
        r = backtest(df, **p)
        if r:
            sonuclar.append({**p, **r})

    if not sonuclar:
        print("HATA: Yeterli işlem üretilemedi.")
        exit(1)

    df_s = pd.DataFrame(sonuclar)

    # En iyi: score = net_kar / max_drawdown (risk ayarlı kâr)
    df_s = df_s.sort_values("score", ascending=False)

    print("🏆  EN İYİ 15 KOMBİNASYON (Risk Ayarlı Skora Göre):")
    print("-" * 65)
    cols = ["rsi_p","rsi_os","rsi_ob","bb_dev","sl_m","tp_m",
            "net_kar","kazanma_%","profit_factor","maks_dd","islem_sayisi","score"]
    print(df_s[cols].head(15).to_string(index=False))

    en_iyi = df_s.iloc[0]
    print("\n" + "=" * 65)
    print("✅  KAZANAN PARAMETRE SETİ:")
    print(f"   RSI Periyot      : {int(en_iyi['rsi_p'])}")
    print(f"   RSI Oversold     : {en_iyi['rsi_os']}  (BUY eşiği)")
    print(f"   RSI Overbought   : {en_iyi['rsi_ob']}  (SELL eşiği)")
    print(f"   BB Sapma         : {en_iyi['bb_dev']}")
    print(f"   SL Çarpanı       : {en_iyi['sl_m']}x ATR")
    print(f"   TP Çarpanı       : {en_iyi['tp_m']}x ATR")
    print(f"   ─────────────────────────────")
    print(f"   Net Kâr          : ${en_iyi['net_kar']}")
    print(f"   Kazanma Oranı    : %{en_iyi['kazanma_%']}")
    print(f"   Profit Factor    : {en_iyi['profit_factor']}")
    print(f"   Maks Drawdown    : ${en_iyi['maks_dd']}")
    print(f"   Risk/Ödül Skoru  : {en_iyi['score']}")
    print(f"   Toplam İşlem     : {int(en_iyi['islem_sayisi'])}")
    print("=" * 65)

    df_s.to_csv("optimizasyon_sonuclari.csv", index=False)
    print("\n[+] Tüm sonuçlar 'optimizasyon_sonuclari.csv' dosyasına kaydedildi.")
