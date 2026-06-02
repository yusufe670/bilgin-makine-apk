"""
ScalpingEA Pro Volatile — Parametre Optimizasyon Simülatörü
Gerçek MT4 backtesti olmadan en kârlı kombinasyonu bulmak için
tarihsel veri simülasyonu yapar.

Kullanım:
    pip install pandas numpy yfinance
    python ea_backtest_optimizer.py
"""

import itertools
import warnings
warnings.filterwarnings("ignore")

try:
    import pandas as pd
    import numpy as np
    PANDAS_OK = True
except ImportError:
    PANDAS_OK = False
    print("HATA: 'pip install pandas numpy' komutunu çalıştırın")
    exit(1)

# ────────────────────────────────────────────────────────────────────
# Gösterge Fonksiyonları
# ────────────────────────────────────────────────────────────────────

def hesapla_rsi(close, period=9):
    delta = close.diff()
    gain  = delta.clip(lower=0)
    loss  = (-delta).clip(lower=0)
    avg_gain = gain.ewm(com=period-1, min_periods=period).mean()
    avg_loss = loss.ewm(com=period-1, min_periods=period).mean()
    rs  = avg_gain / avg_loss.replace(0, np.nan)
    rsi = 100 - (100 / (1 + rs))
    return rsi.fillna(50)

def hesapla_bb(close, period=20, dev=2.0):
    mid   = close.rolling(period).mean()
    std   = close.rolling(period).std()
    upper = mid + dev * std
    lower = mid - dev * std
    return upper, mid, lower

def hesapla_atr(high, low, close, period=14):
    hl  = high - low
    hc  = (high - close.shift()).abs()
    lc  = (low  - close.shift()).abs()
    tr  = pd.concat([hl, hc, lc], axis=1).max(axis=1)
    return tr.ewm(com=period-1, min_periods=period).mean()

# ────────────────────────────────────────────────────────────────────
# Sintetik Veri Üreteci (yfinance yoksa)
# ────────────────────────────────────────────────────────────────────

def sintetik_veri_uret(n=5000, volatilite=0.0015, seed=42):
    """GBPJPY benzeri oynak bir parite simüle eder."""
    np.random.seed(seed)
    fiyat = 185.0
    veriler = []
    for _ in range(n):
        degisim = np.random.normal(0, volatilite) * fiyat
        fiyat  += degisim
        spread  = fiyat * 0.00015
        high    = fiyat + abs(np.random.normal(0, volatilite/2)) * fiyat
        low     = fiyat - abs(np.random.normal(0, volatilite/2)) * fiyat
        close   = fiyat
        open_   = fiyat - degisim
        veriler.append({
            "Open":  round(open_, 3),
            "High":  round(high, 3),
            "Low":   round(low, 3),
            "Close": round(close, 3),
        })
    df = pd.DataFrame(veriler)
    df.index = pd.date_range("2022-01-01", periods=n, freq="15min")
    return df

def veri_yukle(sembol="GBPJPY"):
    """Önce yfinance, yoksa sintetik veri."""
    try:
        import yfinance as yf
        df = yf.download(sembol + "=X", period="2y", interval="15m", progress=False)
        if df.empty:
            raise ValueError
        df = df[["Open", "High", "Low", "Close"]].dropna()
        print(f"[+] {sembol} gerçek veri yüklendi: {len(df)} mum")
        return df
    except Exception:
        print(f"[!] {sembol} gerçek veri yüklenemedi — sintetik veri kullanılıyor")
        return sintetik_veri_uret()

# ────────────────────────────────────────────────────────────────────
# Backtest Motoru
# ────────────────────────────────────────────────────────────────────

def backtest(df, rsi_period=9, rsi_os=28, rsi_ob=72,
             bb_period=20, bb_dev=2.0,
             atr_period=14, sl_mult=1.5, tp_mult=3.0,
             lot=0.01, pip_deger=0.01):

    close = df["Close"]
    high  = df["High"]
    low   = df["Low"]

    rsi          = hesapla_rsi(close, rsi_period)
    bb_up, bb_mid, bb_low = hesapla_bb(close, bb_period, bb_dev)
    atr          = hesapla_atr(high, low, close, atr_period)

    baslangi_idx = max(bb_period, rsi_period, atr_period) + 2

    trades      = []
    acik_islem  = None   # {"tip": "BUY"/"SELL", "giri": fiyat, "sl": .., "tp": ..}

    for i in range(baslangi_idx, len(df)):
        c  = close.iloc[i]
        r  = rsi.iloc[i-1]       # Kapanmış mum değerleri (i-1)
        bu = bb_up.iloc[i-1]
        bl = bb_low.iloc[i-1]
        bm = bb_mid.iloc[i-1]
        at = atr.iloc[i-1]

        if at <= 0:
            continue

        # --- Açık işlem varsa çıkış kontrolü ---
        if acik_islem is not None:
            tip  = acik_islem["tip"]
            sl   = acik_islem["sl"]
            tp   = acik_islem["tp"]
            giris = acik_islem["giris"]

            if tip == "BUY":
                if low.iloc[i] <= sl:
                    kar = (sl - giris) * lot * 100000 * pip_deger
                    trades.append({"tip": "BUY", "kar": kar, "sonuc": "SL"})
                    acik_islem = None
                elif high.iloc[i] >= tp:
                    kar = (tp - giris) * lot * 100000 * pip_deger
                    trades.append({"tip": "BUY", "kar": kar, "sonuc": "TP"})
                    acik_islem = None
            else:  # SELL
                if high.iloc[i] >= sl:
                    kar = (giris - sl) * lot * 100000 * pip_deger
                    trades.append({"tip": "SELL", "kar": kar, "sonuc": "SL"})
                    acik_islem = None
                elif low.iloc[i] <= tp:
                    kar = (giris - tp) * lot * 100000 * pip_deger
                    trades.append({"tip": "SELL", "kar": kar, "sonuc": "TP"})
                    acik_islem = None

        # --- Yeni işlem girişi ---
        if acik_islem is None:
            c_prev = close.iloc[i-1]
            r_prev = rsi.iloc[i-2] if i >= 2 else 50

            # BUY: fiyat alt BB altında + RSI aşırı satım + önceki mum daha aşağı
            if (c_prev <= bl and r <= rsi_os and close.iloc[i-2] < c_prev):
                giris = c_prev  # Bir sonraki bar açılışında gir
                acik_islem = {
                    "tip":   "BUY",
                    "giris": giris,
                    "sl":    giris - at * sl_mult,
                    "tp":    giris + at * tp_mult,
                }

            # SELL: fiyat üst BB üstünde + RSI aşırı alım + önceki mum daha yukarı
            elif (c_prev >= bu and r >= rsi_ob and close.iloc[i-2] > c_prev):
                giris = c_prev
                acik_islem = {
                    "tip":   "SELL",
                    "giris": giris,
                    "sl":    giris + at * sl_mult,
                    "tp":    giris - at * tp_mult,
                }

    if not trades:
        return {"net_kar": -9999, "toplam_islem": 0, "kazanma_orani": 0, "profit_factor": 0}

    df_t = pd.DataFrame(trades)
    net_kar   = df_t["kar"].sum()
    kazananlar = df_t[df_t["kar"] > 0]["kar"].sum()
    kaybedenler = abs(df_t[df_t["kar"] < 0]["kar"].sum())
    kazanma_orani = (df_t["kar"] > 0).mean() * 100
    profit_factor = kazananlar / kaybedenler if kaybedenler > 0 else float("inf")

    return {
        "net_kar":        round(net_kar, 2),
        "toplam_islem":   len(df_t),
        "kazanma_orani":  round(kazanma_orani, 1),
        "profit_factor":  round(profit_factor, 2),
    }

# ────────────────────────────────────────────────────────────────────
# Parametre Grid Optimizasyonu
# ────────────────────────────────────────────────────────────────────

PARAM_GRID = {
    "rsi_period": [7, 9, 14],
    "rsi_os":     [25, 28, 30],
    "rsi_ob":     [70, 72, 75],
    "bb_period":  [20],
    "bb_dev":     [2.0, 2.1],
    "sl_mult":    [1.2, 1.5, 2.0],
    "tp_mult":    [2.5, 3.0, 4.0],
}

def optimizasyon_calistir(df):
    keys   = list(PARAM_GRID.keys())
    values = list(PARAM_GRID.values())
    combinations = list(itertools.product(*values))

    print(f"\n[*] {len(combinations)} kombinasyon test ediliyor...\n")

    sonuclar = []
    for combo in combinations:
        params = dict(zip(keys, combo))
        sonuc  = backtest(df, **params)
        if sonuc["toplam_islem"] < 20:
            continue  # Çok az işlem — anlamsız
        sonuclar.append({**params, **sonuc})

    if not sonuclar:
        print("HATA: Hiç geçerli kombinasyon bulunamadı")
        return None

    df_sonuc = pd.DataFrame(sonuclar)
    df_sonuc = df_sonuc.sort_values("net_kar", ascending=False)
    return df_sonuc

# ────────────────────────────────────────────────────────────────────
# Ana Program
# ────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("=" * 65)
    print("  ScalpingEA Pro Volatile — Parametre Optimizasyonu")
    print("=" * 65)

    # Veri yükle
    df = veri_yukle("GBPJPY")

    # Optimizasyon
    sonuclar = optimizasyon_calistir(df)

    if sonuclar is None:
        exit(1)

    print("\n🏆  EN İYİ 10 KOMBİNASYON (Net Kâra Göre):")
    print("-" * 65)
    cols = ["rsi_period","rsi_os","rsi_ob","sl_mult","tp_mult",
            "net_kar","kazanma_orani","profit_factor","toplam_islem"]
    print(sonuclar[cols].head(10).to_string(index=False))

    print("\n" + "=" * 65)
    en_iyi = sonuclar.iloc[0]
    print("KAZANAN PARAMETRE SETİ:")
    print(f"  RSI Periyot   : {int(en_iyi['rsi_period'])}")
    print(f"  RSI Aşırı Satım : {en_iyi['rsi_os']}")
    print(f"  RSI Aşırı Alım  : {en_iyi['rsi_ob']}")
    print(f"  BB Sapma        : {en_iyi['bb_dev']}")
    print(f"  SL Çarpanı      : {en_iyi['sl_mult']}  (ATR x{en_iyi['sl_mult']})")
    print(f"  TP Çarpanı      : {en_iyi['tp_mult']}  (ATR x{en_iyi['tp_mult']})")
    print(f"  Net Kâr         : {en_iyi['net_kar']} $")
    print(f"  Kazanma Oranı   : %{en_iyi['kazanma_orani']}")
    print(f"  Profit Factor   : {en_iyi['profit_factor']}")
    print(f"  Toplam İşlem    : {int(en_iyi['toplam_islem'])}")
    print("=" * 65)

    # Sonuçları dosyaya kaydet
    sonuclar.to_csv("optimizasyon_sonuclari.csv", index=False)
    print("\n[+] Tüm sonuçlar 'optimizasyon_sonuclari.csv' dosyasına kaydedildi.")
    print("\nBu parametreleri MT4'te EA'ya girin ve Strategy Tester ile doğrulayın.")
