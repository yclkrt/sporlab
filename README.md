<div align="center">

<img src="assets/images/sporlab_logo.png" alt="Sporlab Logo" width="200"/>

# Sporlab

### 🏋️ Antrenman Takip Uygulamasi

<p>
  <img src="https://img.shields.io/badge/Flutter-3.10+-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.0+-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart">
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="License">
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS-blue?style=for-the-badge" alt="Platform">
</p>

**Sporcular ve antrenörler için gelistirilmis kapsamli yonetim sistemi**

[📱 Özellikler](#-özellikler) • [🚀 Kurulum](#-kurulum) • [📸 Ekran Görüntüleri](#-ekran-görüntüleri) • [🛠️ Teknolojiler](#-kullanilan-teknolojiler) • [📞 İletişim](#-iletişim)

</div>

---

## 📖 Uygulama Hakkinda

**Sporlab**, sporcularin antrenman planlarini olusturmasina, takip etmesine ve performanslarini analiz etmesine olanak taniman modern bir mobil uygulamadir. Flutter ile gelistirilmis olup, hem Android hem de iOS platformlarinda sorunsuz calisir.

---

## ✨ Ozellikler

### 📊 Ana Panel
- Genel antrenman ozeti ve istatistikler
- Hizli erisim menusu
- Performans gostergeleri

### 📅 Antrenman Takvimi
- Takvim uzerinden gun secimi
- Secilen gune hatirlatici ekleme
- Hatirlaticilari duzenleme ve silme
- Hatirlatici olan gunlerin gorsel gostergesi
- Verilerin yerel depolama ile kalici saklanmasi

### 📋 Antrenman Planlari
- Grup dersi ve ozel ders plani olusturma
- Plan detaylarini goruntuleme
- Ilerleme takibi
- Isar veritabani ile guvenli veri saklama

### ⏱️ Kronometre
- Hassas sure olcumu
- Tur (lap) kaydi
- En iyi/en kotu tur analizi
- Toplam sure gostermi

### 🎨 Tema Destegi
- Koyu ve acik tema secenegi
- Tema tercihinin kalici saklanmasi
- Her sayfa icin ozel gradient renk duzeni
- Material 3 tasarim sistemi

---

## 📸 Ekran Goruntuleri

| Ana Panel | Antrenman Takvimi | Kronometre | Antrenman Planlari |
|:---:|:---:|:---:|:---:|
| Mavi-Mor Gradient | Kirmizi-Turuncu Gradient | Mor-Yesil Gradient | Yesil-Teal Gradient |

> **Not:** Her sayfa icin farkli gradient renk duzeni kullanilmistir.

---

## 🚀 Kurulum

### Gereksinimler
- Flutter SDK 3.10 veya uzeri
- Dart SDK 3.0 veya uzeri
- Android Studio / Xcode

### Adimlar

1. Projeyi kopyalayin:
```bash
git clone https://github.com/yclkrt/sporlab.git
cd sporlab
```

2. Bagimliliklari yukleyin:
```bash
flutter pub get
```

3. Isar veritabani semalarini olusturun:
```bash
dart run build_runner build
```

4. Uygulamayi calistirin:
```bash
flutter run
```

---

## 🛠️ Kullanilan Teknolojiler

| Teknoloji | Versiyon | Aciklama |
|-----------|----------|----------|
| Flutter | 3.10+ | UI framework |
| Dart | 3.0+ | Programlama dili |
| Riverpod | 3.3+ | State yonetimi |
| Isar | 3.1+ | Yerel veritabani |
| GoRouter | 17.5+ | Sayfa yonlendirme |
| SharedPreferences | 2.5+ | Yerel depolama |

---

## 📁 Proje Yapisi

```
sporlab/
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── providers/theme_provider.dart
│   │   ├── theme/
│   │   │   ├── app_colors.dart
│   │   │   ├── app_gradients.dart
│   │   │   └── app_theme.dart
│   │   ├── router/app_router.dart
│   │   └── widgets/
│   │       ├── app_drawer.dart
│   │       └── main_scaffold.dart
│   └── features/
│       ├── dashboard/presentation/dashboard_page.dart
│       ├── stopwatch/
│       │   ├── presentation/stopwatch_page.dart
│       │   ├── providers/stopwatch_provider.dart
│       │   └── widgets/
│       ├── training_plans/
│       │   ├── data/
│       │   ├── model/
│       │   ├── presentation/
│       │   └── providers/
│       └── training_schedule/
│           ├── data/reminder_service.dart
│           ├── model/reminder.dart
│           ├── presentation/training_schedule.dart
│           ├── providers/reminder_provider.dart
│           └── widgets/
│               ├── calendar_widget.dart
│               └── reminder_list_widget.dart
├── pubspec.yaml
└── README.md
```

---

## 🎨 Renk Paleti & Gradientler

### Ana Renkler
| Renk | Hex | Kullanim |
|------|-----|----------|
| Primary | #E84C3D | Ana vurgu rengi |
| Secondary | #F39C12 | Ikincil vurgu |
| Accent | #2ECC71 | Basari/ilerleme |

### Sayfa Bazli Gradientler
| Sayfa | Gradient | Renkler |
|-------|----------|---------|
| Dashboard | Mavi-Mor | #667eea -> #764ba2 |
| Antrenman Takvimi | Kirmizi-Turuncu | #E84C3D -> #F39C12 |
| Antrenman Planlari | Yesil-Teal | #11998e -> #38ef7d |
| Kronometre | Mor-Yesil | #8360c3 -> #2ebf91 |

---

## 🔧 Gelistirme

### Kod Olusturma
```bash
dart run build_runner build
dart run build_runner watch
```

### Test Calistirma
```bash
flutter test
```

### Derleme
```bash
flutter build apk --release
flutter build ios --release
```

---

## 🤝 Katkida Bulunma

1. Bu repository'yi fork edin
2. Feature branch olusturun
3. Degisikliklerinizi commit edin
4. Branch'inizi push edin
5. Pull Request olusturun

---

## 📞 Iletisim

- **Gelistirici:** [@yclkrt](https://github.com/yclkrt)
- **Proje Linki:** [https://github.com/yclkrt/sporlab](https://github.com/yclkrt/sporlab)

---

<div align="center">

⭐ Bu projeyi begendiyseniz yildiz vermeyi unutmayin!

**Sporlab** - Antrenmaninizi yonetmenin akilli yolu

Made with ❤️ using Flutter

</div>
