enum AppLanguage { english, indonesian }

extension AppLanguageInfo on AppLanguage {
  String get code => this == AppLanguage.indonesian ? 'id' : 'en';
  String get label => this == AppLanguage.indonesian ? 'Bahasa Indonesia' : 'English';
}

AppLanguage languageFromCode(String? code) =>
    code == 'id' ? AppLanguage.indonesian : AppLanguage.english;

/// Hand-rolled two-language strings.
///
/// A full ARB/gen-l10n setup would drag a code generation step into the build
/// for a fixed pair of languages; this stays greppable and has no codegen.
class S {
  const S(this.lang);

  final AppLanguage lang;

  String _p(String en, String id) => lang == AppLanguage.indonesian ? id : en;

  // ------------------------------------------------------------------- brand
  String get tagline => _p('Turn any place on Earth into art',
      'Ubah tempat mana pun di bumi jadi karya seni');

  // -------------------------------------------------------------------- home
  String get searchHint =>
      _p('Search a city, address or landmark', 'Cari kota, alamat, atau landmark');
  String get recent => _p('Recent', 'Terakhir dibuka');
  String get popular => _p('Popular', 'Populer');
  String get startWithPlace => _p('Start with a place', 'Mulai dari sebuah tempat');
  String get yourLibrary => _p('Your library', 'Koleksi Anda');
  String get nothingSaved => _p('Nothing saved yet', 'Belum ada yang disimpan');
  String get nothingSavedBody => _p(
      'Save a design in the studio and it will appear here, ready to re-export any time.',
      'Simpan desain dari studio dan akan muncul di sini, siap diekspor ulang kapan saja.');
  String get noFavourites => _p('No favourites yet', 'Belum ada favorit');
  String get noFavouritesBody => _p('Long-press a design to mark it as a favourite.',
      'Tekan lama sebuah desain untuk menandainya sebagai favorit.');
  String get nothingFound => _p('Nothing found', 'Tidak ditemukan');
  String get tryAnotherSpelling => _p('Try another spelling, or add the country name.',
      'Coba ejaan lain, atau tambahkan nama negaranya.');
  String get importRoute => _p('Import a GPX route', 'Impor rute GPX');
  String get openSettings => _p('Settings', 'Pengaturan');
  String get useMyLocation => _p('Use my location', 'Pakai lokasi saya');
  String get locationDenied => _p('Location permission was denied.',
      'Izin lokasi ditolak.');
  String get locationUnavailable =>
      _p('Could not get a location fix.', 'Tidak bisa mendapatkan lokasi.');
  String get attributionLine => _p(
      'Map data (c) OpenStreetMap contributors, ODbL. Search by Nominatim.',
      'Data peta (c) kontributor OpenStreetMap, ODbL. Pencarian oleh Nominatim.');

  // ----------------------------------------------------------------- library
  String get favouritesOnly => _p('Favourites', 'Favorit');
  String get all => _p('All', 'Semua');
  String get sortRecent => _p('Newest', 'Terbaru');
  String get sortOldest => _p('Oldest', 'Terlama');
  String get sortName => _p('Name', 'Nama');
  String get rename => _p('Rename', 'Ganti nama');
  String get duplicate => _p('Duplicate', 'Duplikat');
  String get delete => _p('Delete', 'Hapus');
  String get addFavourite => _p('Add to favourites', 'Tambahkan ke favorit');
  String get removeFavourite => _p('Remove from favourites', 'Hapus dari favorit');
  String get cancel => _p('Cancel', 'Batal');
  String get save => _p('Save', 'Simpan');
  String deleteDesignTitle(String name) =>
      _p('Delete "$name"?', 'Hapus "$name"?');
  String get deleteDesignBody => _p('This removes it from your library.',
      'Desain ini akan dihapus dari koleksi Anda.');
  String get renameTitle => _p('Rename design', 'Ganti nama desain');

  // ------------------------------------------------------------------ studio
  String get studio => _p('Studio', 'Studio');
  String get across => _p('across', 'lebar');
  String get offline => _p('offline', 'offline');
  String get undo => _p('Undo', 'Urungkan');
  String get redo => _p('Redo', 'Ulangi');
  String get saveToLibrary => _p('Save to library', 'Simpan ke koleksi');
  String get savedToLibrary => _p('Saved to your library', 'Tersimpan di koleksi Anda');
  String couldNotSave(Object e) => _p('Could not save: $e', 'Gagal menyimpan: $e');
  String get moveTheMap => _p('Move the map', 'Pindahkan peta');
  String get preparing => _p('Preparing...', 'Menyiapkan...');
  String get tryAgain => _p('Try again', 'Coba lagi');
  String get somethingWrong => _p('Something went wrong', 'Terjadi kesalahan');
  String get tracingContours =>
      _p('Tracing terrain contours', 'Menelusuri kontur terrain');

  // ------------------------------------------------------------------ panels
  String get tabLooks => _p('Looks', 'Gaya');
  String get tabColour => _p('Colour', 'Warna');
  String get tabLayers => _p('Layers', 'Layer');
  String get tabText => _p('Text', 'Teks');
  String get tabFrame => _p('Frame', 'Bingkai');
  String get tabSize => _p('Size', 'Ukuran');

  String get looks => _p('Looks', 'Gaya');
  String get area => _p('Area', 'Area');
  String get howMuchMap =>
      _p('How much of the map to show', 'Seberapa luas peta ditampilkan');
  String get terrain => _p('Terrain', 'Terrain');
  String get contourLines => _p('Contour lines', 'Garis kontur');
  String get contourHint => _p('Adds real terrain relief, downloaded once per place',
      'Menambah relief terrain asli, diunduh sekali per lokasi');
  String get contourReading => _p('Reading elevation data...', 'Membaca data elevasi...');
  String get contourReady => _p('Traced from public-domain elevation tiles',
      'Ditelusuri dari tile elevasi domain publik');
  String get contourNone =>
      _p('No usable elevation data here', 'Tidak ada data elevasi yang berguna di sini');
  String get hillshade => _p('Hillshade relief', 'Relief hillshade');
  String get hillshadeHint => _p('Shades slopes using the elevation already downloaded',
      'Membayangi lereng memakai elevasi yang sudah diunduh');
  String get thickness => _p('Thickness', 'Ketebalan');
  String get roadWeight => _p('Road weight', 'Ketebalan jalan');
  String get refreshData => _p('Refresh data', 'Muat ulang data');
  String get removeRoute => _p('Remove route', 'Hapus rute');

  String get baseColours => _p('Base colours', 'Warna dasar');
  String get background => _p('Background', 'Latar');
  String get gradientTint => _p('Gradient tint', 'Gradasi latar');
  String get textColour => _p('Text', 'Teks');
  String get accentColour => _p('Accent & captions', 'Aksen & keterangan');
  String get finish => _p('Finish', 'Sentuhan akhir');
  String get paperGrain => _p('Paper grain', 'Grain kertas');
  String get vignette => _p('Vignette', 'Vignette');
  String get buildings => _p('Buildings', 'Bangunan');
  String get heightShading => _p('Height shading', 'Gradasi tinggi');
  String get tallBuildingTint => _p('Tall building tint', 'Warna bangunan tinggi');
  String get heightHint => _p(
      'Buildings are tinted by their real height from OpenStreetMap. Areas where nobody has mapped heights stay flat.',
      'Bangunan diwarnai menurut tinggi aslinya dari OpenStreetMap. Area yang tingginya belum dipetakan tetap rata.');
  String get grading => _p('Colour grading', 'Colour grading');
  String get contrast => _p('Contrast', 'Kontras');
  String get saturation => _p('Saturation', 'Saturasi');
  String get warmth => _p('Warmth', 'Kehangatan');
  String get duotone => _p('Duotone', 'Duotone');
  String get duotoneShadow => _p('Shadow tone', 'Warna bayangan');
  String get duotoneHighlight => _p('Highlight tone', 'Warna sorotan');
  String get resetGrade => _p('Reset grading', 'Reset grading');
  String get route => _p('Route', 'Rute');
  String get routeColour => _p('Route colour', 'Warna rute');
  String get routeWeight => _p('Route weight', 'Ketebalan rute');
  String get routeGlow => _p('Route glow', 'Cahaya rute');
  String get routeHint => _p(
      'Import a GPX from the home screen to draw a run, ride or trip on top of the map.',
      'Impor GPX dari layar utama untuk menggambar lari, sepeda, atau perjalanan di atas peta.');
  String get routeMarkers => _p('Start & finish markers', 'Penanda start & finish');
  String get elevationProfile => _p('Elevation profile', 'Profil elevasi');

  String get mapLabels => _p('Map labels', 'Label peta');
  String get showLabels => _p('Show street & area names', 'Tampilkan nama jalan & area');
  String get labelSize => _p('Label size', 'Ukuran label');
  String get labelColour => _p('Label colour', 'Warna label');
  String get labelHint => _p(
      'Only names that fit along their road or inside their area are drawn, and overlapping ones are dropped.',
      'Hanya nama yang muat di sepanjang jalannya atau di dalam areanya yang digambar; yang bertumpuk dilewati.');

  String get words => _p('Words', 'Teks');
  String get titleField => _p('Title', 'Judul');
  String get subtitleField => _p('Subtitle', 'Subjudul');
  String get customLine => _p('Custom line', 'Baris bebas');
  String get customHint =>
      _p('Anniversary, dedication, anything', 'Tanggal jadian, dedikasi, apa saja');
  String get typeface => _p('Typeface', 'Tipografi');
  String get fineTuning => _p('Fine tuning', 'Penyetelan');
  String get textSize => _p('Text size', 'Ukuran teks');
  String get letterSpacing => _p('Letter spacing', 'Jarak huruf');
  String get placement => _p('Placement', 'Penempatan');
  String get belowMap => _p('Below map', 'Di bawah peta');
  String get overBottom => _p('Over bottom', 'Di atas bawah');
  String get overTop => _p('Over top', 'Di atas atas');
  String get hidden => _p('Hidden', 'Sembunyi');
  String get alignLeft => _p('Align left', 'Rata kiri');
  String get alignCentre => _p('Centred', 'Rata tengah');
  String get alignRight => _p('Align right', 'Rata kanan');
  String get showPosterText => _p('Show poster text', 'Tampilkan teks poster');
  String get uppercaseTitle => _p('Uppercase title', 'Judul huruf besar');
  String get dividerRule => _p('Divider rule', 'Garis pemisah');
  String get coordinates => _p('Coordinates', 'Koordinat');
  String get useDms => _p('Use DMS format', 'Pakai format DMS');
  String get dmsHint => _p('Degrees, minutes, seconds', 'Derajat, menit, detik');
  String get decimalHint => _p('Decimal degrees', 'Derajat desimal');
  String get dateField => _p('Date', 'Tanggal');

  String get mapShape => _p('Map shape', 'Bentuk peta');
  String get fullBleed => _p('Full bleed', 'Penuh');
  String get rectangle => _p('Rectangle', 'Persegi');
  String get circle => _p('Circle', 'Lingkaran');
  String get rounded => _p('Rounded', 'Rounded');
  String get arch => _p('Arch', 'Arch');
  String get border => _p('Border', 'Bingkai');
  String get borderNone => _p('None', 'Tanpa');
  String get borderHairline => _p('Hairline', 'Tipis');
  String get borderDouble => _p('Double', 'Ganda');
  String get borderInset => _p('Inset', 'Inset');
  String get borderPlate => _p('Plate', 'Plat');
  String get margins => _p('Margins', 'Margin');
  String get outerMargin => _p('Outer margin', 'Margin luar');
  String get customPaper => _p('Custom paper colour', 'Warna kertas kustom');
  String get paperFollows =>
      _p('Paper follows the map background', 'Kertas mengikuti latar peta');
  String get fullBleedHint => _p(
      'Full bleed ignores margins and prints the map edge to edge - the best choice for phone wallpapers.',
      'Full bleed mengabaikan margin dan mencetak peta dari tepi ke tepi - paling pas untuk wallpaper HP.');

  String get canvas => _p('Canvas', 'Kanvas');
  String get wallpaperHint => _p(
      'Wallpaper switches the poster to edge-to-edge with the text over the map. Change it back any time in the Frame tab.',
      'Wallpaper mengubah poster jadi penuh dengan teks di atas peta. Bisa dikembalikan kapan saja di tab Bingkai.');
  String get exportArtwork => _p('Export artwork', 'Ekspor karya');

  // ------------------------------------------------------------------ export
  String get export => _p('Export', 'Ekspor');
  String get renderAndSave => _p('Render & save', 'Render & simpan');
  String get renderAgain => _p('Render again', 'Render lagi');
  String get share => _p('Share', 'Bagikan');
  String renderingPercent(int p) => _p('Rendering $p%  -  keep the app open',
      'Merender $p%  -  biarkan aplikasi terbuka');
  String savedToGallery(String size) => _p('Saved to your gallery (CARTA album) - $size',
      'Tersimpan di galeri (album CARTA) - $size');
  String writtenToStorage(String format, String size) => _p(
      '$format written to app storage - $size. Use Share to keep it.',
      '$format ditulis ke penyimpanan aplikasi - $size. Pakai Bagikan untuk menyimpannya.');
  String get exportAttribution => _p(
      'Every export carries the OpenStreetMap credit required by the ODbL licence.',
      'Setiap ekspor menyertakan kredit OpenStreetMap yang diwajibkan lisensi ODbL.');
  String pageSize(String w, String h, int dpi) =>
      _p('Page $w x $h inch at $dpi DPI', 'Halaman $w x $h inci pada $dpi DPI');

  // ---------------------------------------------------------------- settings
  String get settings => _p('Settings', 'Pengaturan');
  String get offlineMapData => _p('Offline map data', 'Data peta offline');
  String get storedCaptures => _p('Stored captures', 'Lokasi tersimpan');
  String get diskUsed => _p('Disk used', 'Ruang terpakai');
  String get clearOfflineData => _p('Clear offline data', 'Hapus data offline');
  String get clearing => _p('Clearing...', 'Menghapus...');
  String get offlineCleared =>
      _p('Offline map data cleared', 'Data peta offline dihapus');
  String get cacheHint => _p(
      'Downloaded map and terrain data lets you restyle and re-export a place with no connection. It is capped at about 280 MB and the oldest captures are dropped first.',
      'Data peta dan terrain yang sudah diunduh membuat Anda bisa mengubah gaya dan mengekspor ulang tanpa koneksi. Dibatasi sekitar 280 MB dan tangkapan terlama dibuang lebih dulu.');
  String get libraryLabel => _p('Library', 'Koleksi');
  String get savedDesigns => _p('Saved designs', 'Desain tersimpan');
  String get dataAndLicences => _p('Data & licences', 'Data & lisensi');
  String get about => _p('About', 'Tentang');
  String get language => _p('Language', 'Bahasa');
  String get licenceBody => _p(
      'Map data (c) OpenStreetMap contributors, licensed under the ODbL. That credit is rendered on every poster you export and cannot be switched off - it is the licence condition, and it is what makes the results safe to sell.\n\nPlace search by Nominatim. Terrain from the public-domain Terrarium elevation tiles.\n\nBundled typefaces: Inter, Playfair Display, Cormorant Garamond, Cinzel, Oswald, Montserrat, Josefin Sans, Bebas Neue and Space Mono, all under the SIL Open Font License 1.1.',
      'Data peta (c) kontributor OpenStreetMap, berlisensi ODbL. Kredit itu dirender pada setiap poster yang Anda ekspor dan tidak bisa dimatikan - itu syarat lisensinya, sekaligus yang membuat hasilnya aman dijual.\n\nPencarian lokasi oleh Nominatim. Terrain dari tile elevasi Terrarium domain publik.\n\nFont bawaan: Inter, Playfair Display, Cormorant Garamond, Cinzel, Oswald, Montserrat, Josefin Sans, Bebas Neue, dan Space Mono, semuanya di bawah SIL Open Font License 1.1.');

  // -------------------------------------------------------------- onboarding
  String get skip => _p('Skip', 'Lewati');
  String get next => _p('Next', 'Lanjut');
  String get startCreating => _p('Start creating', 'Mulai berkarya');
  String get onboard1Title => _p('Any place on Earth', 'Tempat mana pun di bumi');
  String get onboard1Body => _p(
      'Search a city, a street, or the spot where something happened. CARTA pulls its streets, water and buildings straight from OpenStreetMap.',
      'Cari kota, jalan, atau titik tempat sesuatu terjadi. CARTA mengambil jalan, air, dan bangunannya langsung dari OpenStreetMap.');
  String get onboard2Title => _p('Eighteen looks, one tap', 'Delapan belas gaya, satu ketuk');
  String get onboard2Body => _p(
      'Minimal, Blueprint, Neon, Vintage and more. Then take it further: every layer, colour, weight and typeface is yours to change.',
      'Minimal, Blueprint, Neon, Vintage, dan lainnya. Lalu lanjutkan: tiap layer, warna, ketebalan, dan tipografi bisa Anda ubah.');
  String get onboard3Title => _p('Real terrain, real routes', 'Terrain asli, rute asli');
  String get onboard3Body => _p(
      'Switch on contour lines and hillshading traced from public elevation data, or import a GPX and put your own run on the wall.',
      'Nyalakan garis kontur dan hillshade dari data elevasi publik, atau impor GPX dan pajang rute lari Anda sendiri.');
  String get onboard4Title => _p('Built to be printed', 'Dibuat untuk dicetak');
  String get onboard4Body => _p(
      'Export up to 35 megapixels, or a print-ready PDF at 300 DPI. Everything renders on your device - no account, no subscription.',
      'Ekspor hingga 35 megapiksel, atau PDF siap cetak 300 DPI. Semuanya dirender di perangkat Anda - tanpa akun, tanpa langganan.');
}
