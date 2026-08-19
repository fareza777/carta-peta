# CARTA — Map Art Studio

Ubah lokasi mana pun di dunia menjadi poster peta yang layak dicetak. Data dari
OpenStreetMap, render 100% di perangkat, tanpa backend, tanpa API key, tanpa LLM.

> Terinspirasi konsep *prettymaps* (peta sebagai karya seni berlapis), namun
> seluruh kode di sini ditulis ulang dari nol untuk Android: pipeline data,
> mesin render, sistem style, dan UI-nya semua orisinal.

---

## Apa yang bisa dilakukan

| Fitur | Detail |
|---|---|
| Pencarian lokasi | Kota, alamat, atau landmark lewat Nominatim |
| Layer terpisah | Air, taman, pasir, bangunan, rel, jalan (4 kelas), sungai, kontur terrain |
| Hillshade | Relief berbayang dari DEM yang sama dengan kontur, tanpa unduhan tambahan |
| Label peta | Nama jalan mengikuti arah jalannya, nama area di tengah areanya, tabrakan otomatis dilewati |
| Colour grading | Kontras, saturasi, kehangatan, dan duotone — satu matriks warna, tanpa shader |
| 18 preset premium | Minimal, Dark OLED, Blueprint, Vintage, Neon, Pastel, Monochrome, Luxury, Topographic, Architectural, Midnight, Sakura, Forest, Coral, Nordic, Copper, Sunset, Ink Wash |
| Kustomisasi penuh | Warna isi & garis per layer, casing jalan, ketebalan, opacity, glow, garis putus-putus, gradient background, gradasi tinggi bangunan, grain kertas, vignette |
| Mode poster | Judul, subjudul, koordinat (DMS/desimal), tanggal, teks bebas, 9 tipografi, rata kiri/tengah/kanan |
| Bentuk & bingkai | Full bleed, persegi, lingkaran, rounded, arch + 5 gaya border |
| Mode wallpaper | Rasio 9:19.5 dan 9:16, full bleed |
| Route Art | Impor GPX (lari/sepeda/perjalanan), otomatis fit area, tampil jarak/elevasi/durasi |
| Preview realtime | Semua perubahan langsung terlihat, pinch-zoom & geser |
| Export | PNG hingga 4961×7016 (≈35 MP), PDF siap cetak 300 DPI, JPEG untuk berbagi |
| Offline | Data peta yang sudah diunduh disimpan lokal; restyle & re-export tanpa internet |
| Library lokal | Simpan, ganti nama, duplikat, favoritkan, urutkan, dan filter desain |
| Terrain | Garis kontur asli dari DEM publik, ditelusuri di perangkat |
| Undo/redo | 40 langkah termasuk lokasi & framing, tweak slider digabung jadi satu langkah |
| Onboarding | 4 halaman memakai engine render sungguhan lewat kota prosedural, tanpa jaringan |
| Splash | Mark CARTA menggambar dirinya sendiri lewat `PathMetric` |
| Dua bahasa | Inggris & Indonesia, bisa diganti di Pengaturan |
| Lokasi saya | Buat poster dari posisi Anda sekarang |
| Pindah lokasi | Cari & geser peta dari dalam studio tanpa kehilangan style |
| Pengaturan | Ukuran cache offline, hapus data, atribusi & lisensi |

---

## Arsitektur

```
lib/
  core/        geo (Mercator, bbox, window), format helpers, theme
  model/       layer, map_data (+ codec biner), map_style, poster_config,
               format_spec, place, route_track, design
  data/
    osm/       nominatim_client, overpass_query, overpass_client,
               osm_parser (isolate), coastline
    dem/       terrain_tiles, marching_squares (isolate), contour_repository
    cache/     map_cache (LRU di disk)
    store/     design_store (library), prefs_store
    gpx_import.dart
  render/      path_cache, poster_renderer, poster_text, grain, exporter,
               png_writer, pdf_writer
  presets/     style_presets, format_presets, font_presets, curated_places
  state/       providers, search_controller, studio_controller, library_controller
  ui/          home/, studio/ (+ panels/), widgets/
```

### Alur data

```
Nominatim ──► PlaceRef ──► BBox persegi (+18% margin)
                              │
                    Overpass QL (detail otomatis per radius)
                              │
              parse di isolate  ──►  MapDataSet (koordinat lokal float32)
                              │              │
                     cache biner .carta      │
                                             ▼
                                     MapPathCache (Path 0..1)
                                             │
                    PosterRenderer.paint(canvas, size, scene)
                              │                        │
                       CustomPaint (preview)    PictureRecorder (export 4K/8K)
```

### Keputusan teknis yang penting

**Koordinat lokal, bukan world Mercator.** Geometri disimpan relatif terhadap
jendela tangkapan (0..1) sebagai `Float32List`. Kalau disimpan sebagai koordinat
dunia, presisi float32 hanya ~2,4 m — tidak cukup untuk bangunan. Secara lokal,
error turun ke bawah 1 mm untuk area kota. Lihat `test/geo_test.dart`.

**Path dibangun sekali, transform yang bergerak.** `MapPathCache` membangun satu
`Path` per layer dalam ruang 0..1. Zoom/geser/ganti style hanya mengubah matriks
kanvas — tidak pernah membangun ulang geometri. Itulah kenapa preview tetap
mulus di HP.

**Winding dinormalisasi.** Ring luar dipaksa searah, lubang berlawanan, lalu satu
`Path` non-zero per layer mengisi seluruh layer dengan benar — bangunan yang
tumpang tindih menyatu, danau berpulau tetap berlubang.

**Garis pantai.** `natural=coastline` di OSM cuma garis, bukan poligon. Modul
`coastline.dart` menyambung potongan way, memotongnya ke jendela poster
(Liang-Barsky), lalu menutup tiap rantai dengan menyusuri tepi jendela searah
jarum jam — sisi laut menurut konvensi OSM (daratan di kiri arah jalan). Pulau
tertutup jadi lubang. Kalau datanya kacau, modul menyerah dan menggambar garis
pantai saja alih-alih menebak.

**Casing jalan.** Setiap kelas jalan digambar dua lapis: garis lebih tebal
berwarna casing di bawah, garis utama di atas. Semua casing dalam satu band
diletakkan lebih dulu, baru semua garis utamanya — itulah yang membuat
persimpangan padat terbaca sebagai jaringan, bukan gumpalan.

**Jembatan & terowongan.** Tag `bridge`, `tunnel`, dan `layer` dari OSM
dipetakan ke tiga band vertikal. Semua terowongan digambar dulu, lalu semua
jalan permukaan, lalu semua jembatan — jadi flyover jalan kecil tetap berada di
atas jalan besar yang dilintasinya, bukan sebaliknya.

**Tinggi bangunan.** `building:levels` dan `height` sudah ikut di respons
Overpass; sekarang disimpan per-bangunan dan dipakai untuk mewarnai gradasi
tinggi. Gratis, tanpa request tambahan.

**Kontur terrain.** `contour_repository` mengunduh tile DEM Terrarium (domain
publik, tanpa API key), menyusunnya jadi grid elevasi, lalu menelusuri kontur
dengan marching squares di isolate. Setiap perpotongan berada di sisi sel yang
diketahui, jadi penyambungan segmen memakai kunci integer eksak — bukan
pencocokan floating point. Interval dipilih otomatis menurut relief supaya
dataran rendah dan lembah alpine sama-sama terbaca. Hasil diukur: Bandung radius
5 km → 711 polyline dalam 319 ms.

**Peta direkam sekali, bukan tiap ketukan.** `MapPathCache` menyimpan satu
`ui.Picture` berisi seluruh lapisan peta, dikunci pada identitas objek style plus
zoom/pan/rect. Mengetik judul poster tidak mengubah objek style, jadi geometri
tidak pernah diraster ulang — sebelumnya tiap satu huruf memicu raster ulang
semua jalan dan bangunan. `Picture` adalah display list, bukan bitmap, jadi
menyimpannya nyaris tak berbiaya berapa pun resolusinya.

**Hillshade.** Grid elevasi yang sudah diunduh untuk kontur juga dipakai untuk
menghitung shaded relief (Horn, matahari 315 derajat, ketinggian 45 derajat) di
isolate yang sama. Hasilnya dinormalisasi ke abu-abu netral lalu dikomposit
dengan blend overlay — trik yang sama seperti grain — sehingga bekerja pada
kertas terang maupun gelap tanpa jadi lumpur.

**Label.** Untuk garis, label mengambil segmen terpanjang dan mengikuti sudutnya
(selalu dibalik agar tetap tegak); untuk area, label duduk di centroid ring luar.
Nama yang sama muncul sekali saja — instance terpanjang yang menang. Label yang
tidak muat di sepanjang jalannya, atau bertabrakan dengan yang sudah ditempatkan,
dilewati.

**Colour grading.** Kontras, saturasi, kehangatan, dan duotone semuanya bisa
dinyatakan sebagai satu matriks warna 4x5 affine, jadi seluruh grade cuma butuh
satu `saveLayer` dan nol shader. Duotone memetakan luminansi ke ramp antara dua
warna — itu transformasi affine, jadi muat di matriks yang sama.

**Detail otomatis.** Radius besar otomatis menurunkan level detail (bangunan dan
jalan setapak dilepas) supaya poster kota selebar 13 km tetap tajam dan cepat.

**Resolution independent.** Semua ukuran garis dinyatakan dalam "poster unit"
(1 = 1/1000 sisi pendek). Preview 350 px dan export 4961 px memakai kode render
yang sama persis, jadi yang dilihat = yang didapat.

**Export ditulis per-pita, bukan sekaligus.** Cara biasa — raster seluruh gambar
lalu minta engine meng-encode PNG — butuh bitmap penuh *dan* salinan encoder di
memori bersamaan: ~280 MB pada 35 MP, yang pasti dibunuh Android LMK.
`png_writer.dart` merekam display list sekali, meraster satu pita horizontal
pada satu waktu, dan menulis PNG (deflate + filter Up) langsung ke file. Puncak
memori tetap **4 MB** di resolusi mana pun. Display list diputar ulang dengan
translasi, bukan di-clip, sehingga glow dan gradient yang melintasi batas pita
tetap benar — diuji pixel-per-pixel di `test/png_writer_test.dart`.

---

## Build

Prasyarat: Flutter 3.44+, Android SDK, JDK 17+.

```bash
flutter pub get
flutter test
flutter build apk --release
```

APK ada di `build/app/outputs/flutter-apk/app-release.apk`.

Untuk App Bundle Play Store:

```bash
flutter build appbundle --release
```

### Sebelum rilis ke Play Store

`android/app/build.gradle.kts` masih memakai debug keystore. Ganti dengan
keystore rilis milik Anda:

```kotlin
signingConfigs {
    create("release") {
        storeFile = file(System.getenv("CARTA_KEYSTORE") ?: "carta.jks")
        storePassword = System.getenv("CARTA_STORE_PASSWORD")
        keyAlias = System.getenv("CARTA_KEY_ALIAS")
        keyPassword = System.getenv("CARTA_KEY_PASSWORD")
    }
}
buildTypes { release { signingConfig = signingConfigs.getByName("release") } }
```

Application ID saat ini: `studio.carta.mapart`.

---

## Lisensi & atribusi

- **Data peta** © OpenStreetMap contributors, lisensi **ODbL**. Kredit ini
  dirender pada **setiap** poster yang diekspor dan tidak bisa dimatikan —
  itu syarat lisensinya, sekaligus alasan hasilnya aman dipakai komersial.
- **Geocoding** Nominatim. Klien di app menghormati kebijakan pemakaian:
  User-Agent yang mengidentifikasi app dan maksimal 1 permintaan per detik.
- **Overpass API** dipakai lewat 4 mirror publik dengan fallback otomatis.
  Untuk skala produksi besar, pertimbangkan instance Overpass sendiri —
  daftar endpoint ada di `lib/data/osm/overpass_client.dart`.
- **Font** bundled: Inter, Playfair Display, Cormorant Garamond, Cinzel, Oswald,
  Montserrat, Josefin Sans, Bebas Neue, Space Mono — semuanya SIL Open Font
  License 1.1.

---

## Catatan & batasan yang diketahui

- Sumber data adalah OSM apa adanya. Daerah yang pemetaannya jarang akan
  menghasilkan poster yang sepi — itu bukan bug.
- Overpass adalah layanan gratis bersama; saat sibuk, app otomatis pindah mirror
  dan menampilkan pesan yang jelas kalau semuanya penuh.
- Export terbesar (≈35 MP) tetap makan waktu: ~9 detik di desktop, jauh lebih lama
  di HP. Progress bar berjalan per pita, dan app harus tetap terbuka selama proses.
- JPEG dibatasi 8 MP: tidak ada encoder JPEG streaming di Flutter, jadi format
  itu butuh seluruh bitmap di memori. PNG dan PDF tidak punya batas ini.
- Kontur butuh unduhan tile DEM sekali per lokasi; daerah yang sangat datar akan
  melaporkan bahwa tidak ada kontur yang berarti.
- Belum ada: multi-bahasa UI, tema terang untuk shell app, dan sinkronisasi cloud.
