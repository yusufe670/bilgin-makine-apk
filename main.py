import json, os, datetime
from kivy.utils import platform
from kivymd.app import MDApp
from kivy.lang import Builder
from kivymd.uix.dialog import MDDialog
from kivymd.uix.button import MDRaisedButton, MDFlatButton
from kivymd.uix.boxlayout import MDBoxLayout
from kivymd.uix.list import ThreeLineAvatarIconListItem, IconLeftWidget
from kivymd.uix.textfield import MDTextField
from kivymd.uix.label import MDLabel
from fpdf import FPDF

KV = '''
MDBoxLayout:
    orientation: "vertical"
    MDTopAppBar:
        title: "Bilgin Makine Stok & Teklif"
        right_action_items: [["file-pdf-box", lambda x: app.teklif_penceresini_ac()]]
    
    MDBoxLayout:
        size_hint_y: None
        height: "50dp"
        md_bg_color: 0.1, 0.5, 0.7, 1
        padding: "10dp"
        MDLabel:
            id: depo_bilgi
            text: "TOPLAM DEPO DEĞERİ: 0.00 EUR"
            halign: "center"
            bold: True
            text_color: 1, 1, 1, 1

    ScrollView:
        MDList:
            id: urun_listesi

    MDFloatingActionButton:
        icon: "plus"
        pos_hint: {"center_x": .85, "center_y": .1}
        on_release: app.urun_dialog_ac()
'''

class UrunKart(ThreeLineAvatarIconListItem):
    def __init__(self, ad, fiyat, miktar, alarm, tarih, **kwargs):
        super().__init__(**kwargs)
        self.ad, self.fiyat, self.miktar, self.alarm = ad, fiyat, miktar, alarm
        stok_toplam = fiyat * miktar
        
        self.text = f"Parça: {ad}" 
        self.secondary_text = f"Fiyat: {fiyat}€ | Adet: {miktar} | Toplam: {stok_toplam:.2f}€"
        self.tertiary_text = f"Eklendiği Tarih: {tarih}"
        
        self.secili = False
        ik = "alert-decagram" if int(miktar) <= int(alarm) else "check-circle"
        self.add_widget(IconLeftWidget(icon=ik))

    def on_release(self):
        self.secili = not self.secili
        self.bg_color = [0.8, 0.9, 1, 1] if self.secili else [1, 1, 1, 1]
        app = MDApp.get_running_app()
        if self.secili: app.teklif_listesi[self.ad] = {"fiyat": self.fiyat}
        else: app.teklif_listesi.pop(self.ad, None)

    def on_touch_down(self, touch):
        if self.collide_point(*touch.pos) and touch.is_double_tap:
            MDApp.get_running_app().urun_dialog_ac(self.ad)
            return True
        return super().on_touch_down(touch)

class ServisApp(MDApp):
    teklif_listesi = {}

    def build(self):
        self.theme_cls.primary_palette = "Teal"
        self.db_dosya = os.path.join(self.user_data_dir, "bilgin_makine_v5.json")
        self.veriler = self.yukle()
        return Builder.load_string(KV)

    def on_start(self): 
        if platform == "android":
            from android.permissions import request_permissions, Permission
            request_permissions([Permission.WRITE_EXTERNAL_STORAGE, Permission.READ_EXTERNAL_STORAGE])
        self.yenile()

    def yukle(self):
        if os.path.exists(self.db_dosya):
            with open(self.db_dosya, "r", encoding="utf-8") as f: return json.load(f)
        return {}

    def yenile(self):
        self.root.ids.urun_listesi.clear_widgets()
        toplam_depo = 0
        for ad, d in self.veriler.items():
            toplam_depo += (d['fiyat'] * d['miktar'])
            tarih = d.get('tarih', "-")
            self.root.ids.urun_listesi.add_widget(
                UrunKart(ad=ad, fiyat=d['fiyat'], miktar=d['miktar'], alarm=d.get('alarm', 2), tarih=tarih)
            )
        self.root.ids.depo_bilgi.text = f"TOPLAM DEPO DEĞERİ: {toplam_depo:,.2f} EUR"

    def urun_dialog_ac(self, eski_ad=None):
        title = "Düzenle" if eski_ad else "Ürün Ekle"
        c = MDBoxLayout(orientation="vertical", spacing="5dp", size_hint_y=None, height="260dp")
        self.i_ad = MDTextField(hint_text="Parça Adı", text=eski_ad if eski_ad else "")
        self.i_fi = MDTextField(hint_text="Birim Fiyat (€)", text=str(self.veriler[eski_ad]['fiyat']) if eski_ad else "", input_filter="float")
        self.i_mi = MDTextField(hint_text="Stok Adedi", text=str(self.veriler[eski_ad]['miktar']) if eski_ad else "", input_filter="int")
        self.i_al = MDTextField(hint_text="Kritik Stok Sınırı", text=str(self.veriler[eski_ad].get('alarm', 2)) if eski_ad else "2", input_filter="int")
        for i in [self.i_ad, self.i_fi, self.i_mi, self.i_al]: c.add_widget(i)
        
        btns = [MDRaisedButton(text="KAYDET", on_release=lambda x: self.kaydet(eski_ad))]
        if eski_ad: btns.insert(0, MDFlatButton(text="SİL", text_color=[1,0,0,1], on_release=lambda x: self.sil(eski_ad)))
        self.d = MDDialog(title=title, type="custom", content_cls=c, buttons=btns)
        self.d.open()

    def kaydet(self, eski_ad):
        if self.i_ad.text:
            tarih = datetime.datetime.now().strftime("%d/%m/%Y")
            if eski_ad and eski_ad in self.veriler: 
                tarih = self.veriler[eski_ad].get('tarih', tarih)
                del self.veriler[eski_ad]
            self.veriler[self.i_ad.text] = {"fiyat": float(self.i_fi.text or 0), "miktar": int(self.i_mi.text or 0), "alarm": int(self.i_al.text or 2), "tarih": tarih}
            with open(self.db_dosya, "w", encoding="utf-8") as f: json.dump(self.veriler, f)
            self.yenile(); self.d.dismiss()

    def sil(self, ad):
        if ad in self.veriler: del self.veriler[ad]
        with open(self.db_dosya, "w", encoding="utf-8") as f: json.dump(self.veriler, f)
        self.yenile(); self.d.dismiss()

    def teklif_penceresini_ac(self):
        if not self.teklif_listesi: return
        self.ly = MDBoxLayout(orientation="vertical", spacing="5dp", size_hint_y=None, height="550dp")
        self.m_adi = MDTextField(hint_text="Müşteri İsmi")
        self.t_notu = MDTextField(hint_text="Teklif Notu")
        self.genel_toplam_label = MDLabel(text="GENEL TOPLAM: 0.00 €", bold=True, halign="right")
        
        self.ly.add_widget(MDLabel(text="BİLGİN MAKİNE TEKLİF PANELİ", halign="center", bold=True))
        self.ly.add_widget(self.m_adi)
        
        baslik = MDBoxLayout(size_hint_y=None, height="30dp", md_bg_color=[0.9, 0.9, 0.9, 1])
        for t, s in [(" Parça", 0.3), ("Adet", 0.2), ("Toplam", 0.5)]:
            baslik.add_widget(MDLabel(text=t, size_hint_x=s, bold=True, font_style="Caption"))
        self.ly.add_widget(baslik)

        self.inputs = {}
        def toplam_guncelle(*args):
            g_t = 0
            for ad, (mi, fi, res) in self.inputs.items():
                try:
                    ara_t = float(mi.text or 0) * float(fi.text or 0)
                    res.text = f"{ara_t:.2f} €"
                    g_t += ara_t
                except: pass
            self.genel_toplam_label.text = f"GENEL TOPLAM: {g_t:.2f} €"

        for ad, d in self.teklif_listesi.items():
            s = MDBoxLayout(spacing="5dp", size_hint_y=None, height="45dp")
            mi = MDTextField(text="1", size_hint_x=0.2, input_filter="int")
            fi = MDTextField(text=str(d["fiyat"]), size_hint_x=0.25, input_filter="float")
            res = MDLabel(text=f"{d['fiyat']} €", size_hint_x=0.25, font_style="Caption")
            mi.bind(text=toplam_guncelle); fi.bind(text=toplam_guncelle)
            s.add_widget(MDLabel(text=ad[:10], size_hint_x=0.3, font_style="Body2"))
            s.add_widget(mi); s.add_widget(fi); s.add_widget(res)
            self.ly.add_widget(s); self.inputs[ad] = (mi, fi, res)
        
        self.ly.add_widget(self.genel_toplam_label)
        self.ly.add_widget(self.t_notu)
        toplam_guncelle()
        self.td = MDDialog(title="Teklif Hazırla", type="custom", content_cls=self.ly, buttons=[MDRaisedButton(text="PDF OLUŞTUR", on_release=self.pdf_uret)])
        self.td.open()

    def pdf_uret(self, *args):
        try:
            pdf = FPDF()
            pdf.add_page()
            pdf.set_text_color(0, 102, 204); pdf.set_font("Arial", "B", 20)
            pdf.cell(190, 15, "BILGIN MAKINE", ln=True, align="C")
            pdf.set_text_color(0, 0, 0); pdf.set_font("Arial", "B", 14)
            pdf.cell(190, 10, "TEKLIF FORMU", ln=True, align="C")
            pdf.set_font("Arial", "", 11)
            pdf.cell(100, 7, f"Musteri: {self.m_adi.text}")
            pdf.cell(90, 7, f"Tarih: {datetime.datetime.now().strftime('%d/%m/%Y')}", ln=True, align="R")
            pdf.cell(100, 7, "Teklif Veren: Erol Bilgin")
            pdf.cell(90, 7, "Tel: 0535 891 09 79", ln=True, align="R")
            pdf.ln(8)
            pdf.set_fill_color(0, 102, 204); pdf.set_text_color(255, 255, 255); pdf.set_font("Arial", "B", 10)
            pdf.cell(80, 10, " Parca Adi", 1, 0, "L", True); pdf.cell(30, 10, "Adet", 1, 0, "C", True)
            pdf.cell(40, 10, "Birim Fiyat", 1, 0, "C", True); pdf.cell(40, 10, "Toplam", 1, 1, "C", True)
            pdf.set_text_color(0, 0, 0); pdf.set_font("Arial", "", 10)
            g_t = 0
            for ad, (mi, fi, res) in self.inputs.items():
                m, f = float(mi.text or 0), float(fi.text or 0)
                pdf.cell(80, 10, ad, 1); pdf.cell(30, 10, str(int(m)), 1, 0, "C")
                pdf.cell(40, 10, f"{f:.2f} EUR", 1, 0, "C"); pdf.cell(40, 10, f"{m*f:.2f} EUR", 1, 1, "R")
                g_t += (m*f)
            pdf.ln(5); pdf.set_font("Arial", "B", 14); pdf.set_text_color(0, 102, 204)
            pdf.cell(190, 10, f"GENEL TOPLAM: {g_t:,.2f} EUR", ln=True, align="R")
            pdf.set_text_color(0, 0, 0); pdf.ln(5); pdf.set_font("Arial", "I", 10)
            pdf.multi_cell(190, 8, f"Notlar: {self.t_notu.text}")
            
            if platform == "android":
                klasor = "/storage/emulated/0/Download"
                if not os.path.exists(klasor):
                    klasor = self.user_data_dir
            else:
                klasor = os.getcwd()
                
            yol = os.path.join(klasor, f"Teklif_{self.m_adi.text}.pdf")
            pdf.output(yol)
            self.td.dismiss()
        except Exception as e: print(f"HATA: {e}")

if __name__ == '__main__':
    ServisApp().run()
