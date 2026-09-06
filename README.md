# Project Zomboid — Vehicle Finder

Find your Favorite Car.

Mod Build 42 buat nyari kendaraan di sekitar kamu: satu tombol mobil melayang
(bisa digeser ke mana aja) yang buka daftar semua kendaraan yang ke-load di
sekitar pemain — nama, warna, jarak, dan arah kompas, urut dari yang paling
dekat. Klik salah satu barisnya buat "track": tombolnya bakal nunjukin titik
arah + jarak walaupun jendelanya ditutup.

## Kenapa tombolnya berdiri sendiri, bukan nempel ke sidebar vanilla

Sidebar kiri (Inventory / Health / Crafting / dll) dikontrol `MainScreen.lua`
punya vanilla. Kalau mod nyisipin tombol ke file itu, mod-nya bakal rusak tiap
Build 42 update — dan itu juga sumber error `require(...)` yang muncul di log
crash sebelumnya. Jadi tombolnya dibikin berdiri sendiri dan didaftarin
langsung ke UI manager.

Bedanya sama versi sebelumnya: sekarang bukan cuma "gak nempel ke vanilla",
tapi memang dirancang biar gak tabrakan sama mod lain:

| Risiko | Cara mod ini menghindarinya |
| --- | --- |
| Patch file vanilla | Nol patch. Gak ada `require` file vanilla sama sekali; class UI baru dibikin di dalam event (`OnGameStart`), pas Lua vanilla udah kelar di-load. Ini yang bikin error `require(...)` kemarin gak akan kejadian lagi. |
| Nabrak global mod lain | Cuma ada **satu** global: `VehicleFinder`. Semua fungsi/class ada di dalamnya. |
| Nimpa fungsi vanilla / mod lain | Gak ada satu pun fungsi atau tabel vanilla yang di-override. Mod ini cuma `Events.*.Add` dan bikin UI sendiri. |
| Tombol nimpa HUD mod lain | Pas pertama kali jalan, posisi tombol dicari otomatis: kandidat posisi dicek satu-satu ke `UIManager.getUI()`, yang udah kepakai dilewatin. Habis itu bisa digeser sendiri dan posisinya disimpan. |
| Rebutan tombol F8 | F8 cuma **default**, didaftarin ke Options → Key bindings (dedup, gak nimpa binding punya mod lain), jadi tinggal diganti kalau bentrok. Hotkey juga diabaikan waktu kamu lagi ngetik di chat atau di kolom search. |
| Mod mobil (Filibuster, Autotsar, dll) | Daftar kendaraan dibaca read-only dari `getCell():getVehicles()`. Kendaraan mod yang gak punya translation `IGUI_VehicleName...` tetap tampil dengan nama yang kebaca (`SuperTruck` → `Super Truck`) dan ditandai `*`. Warna/ID yang gak tersedia di script mod tertentu di-skip, bukan bikin error. |
| API berubah di build berikutnya | Semua panggilan ke API game dibungkus (`VF.safe`). Kalau ada API yang hilang, fiturnya yang mati — UI-nya gak ikut crash. |

## Cara pakai

- Klik tombol mobil = sama persis kayak tekan **F8** (buka/tutup jendela).
- **Drag** tombolnya buat mindahin; posisinya disimpan.
- **Klik kanan** tombolnya: buka/tutup, ukuran tombol (32–56 px), reset posisi,
  atau sembunyiin tombol (tetap bisa dibuka pakai hotkey).
- Ketik di kolom search buat nyaring nama kendaraan.
- Klik satu baris buat nge-track kendaraannya, "Clear target" buat berhenti.

## Sandbox option: mobil hangus (burnt)

Mobil hangus nggak bisa dikendarai — cuma bisa dipreteli buat part. Kalau kamu
lagi nyari mobil buat dipakai, wreck begitu cuma bikin daftarnya rame.

Ada satu sandbox option buat itu:

| Option | Default | Efek |
| --- | --- | --- |
| **Vehicle Finder → List burnt vehicles** | `on` | `off` = semua wreck hangus dibuang dari hasil pencarian |

Cara nyetelnya: waktu bikin dunia baru, pilih **Sandbox** (bukan preset
Apocalypse/Survivor langsung) → cari halaman **Vehicle Finder** di daftar
kategori sebelah kiri.

Catatan penting: sandbox option itu **per-dunia**, disimpan di save-nya, dan
dipilih waktu dunia dibuat. Jadi buat save yang udah jalan, setelannya nggak
bisa diubah dari dalam game. Kalau kamu mau bisa ganti kapan aja tanpa bikin
dunia baru, bilang aja — aku tambahin checkbox di jendelanya.

Deteksi hangusnya dari nama script kendaraan (`...Burnt`), jadi wreck dari mod
mobil lain yang ikut penamaan vanilla juga kefilter. Kalau build-nya nyediain
`isBurnt()`, itu dipakai sebagai cadangan. Waktu filternya aktif, footer
jendelanya nulis `burnt hidden` biar jelas kenapa ada mobil yang nggak muncul.

Cakupan pencarian = area yang lagi di-load game (chunk sekitar pemain). Mod ini
gak baca file save atau peta, jadi gak ada info kendaraan yang belum pernah
ke-load.

## Ikon

Ikonnya dibikin sendiri buat mod ini — pixel art mobil 32×32 dengan palet ala
Project Zomboid (outline gelap, bodi merah bata kusam, kaca abu kebiruan, ban
hitam rata). Sumbernya ada di `tools/generate_icons.py` (grid pixel-nya
ditulis manual di situ), regenerate-nya:

```bash
pip install pillow
python3 tools/generate_icons.py
```

Output: `Contents/mods/VehicleFinder/42/media/textures/VehicleFinder_Car.png`,
`poster.png`, dan `preview.png`. Kalau texture-nya gagal ke-load karena satu
dan lain hal, tombolnya nggambar mobil versi sederhana pakai `drawRect`, jadi
gak pernah jadi kotak kosong.

## Install

Yang dicopy ke game itu **folder `VehicleFinder`-nya saja**, bukan folder repo,
bukan folder `Contents`. Tujuannya:

```
Windows : %USERPROFILE%\Zomboid\mods\VehicleFinder\
Linux   : ~/Zomboid/mods/VehicleFinder/
```

Susunannya harus persis begini — ini struktur mod Build 42, beda dari Build 41:

```
Zomboid/mods/VehicleFinder/
    common/                  <- harus ada, isinya memang kosong
    42/
        mod.info             <- di dalam folder 42, bukan di root
        poster.png
        media/
            lua/client/VehicleFinder/*.lua
            lua/shared/Translate/EN/IG_UI_EN.txt
            textures/VehicleFinder_Car.png
```

Dua hal yang bikin mod nggak kelihatan di menu Mods walau foldernya sudah benar:

1. `mod.info` ditaruh di root folder mod (gaya Build 41) — di B42 dia harus di
   dalam folder versi `42/`.
2. Folder `common/` nggak ada — B42 nge-skip mod-nya diam-diam, tanpa error di
   `console.txt`.

Terus aktifin lewat menu **Mods** di dalam game.

### Kalau mod-nya masih nggak muncul di menu Mods

Penyebab paling sering sisanya: folder kelewat satu tingkat.

| Salah | Kenapa |
| --- | --- |
| `Zomboid\mods\Project-Zomboid-Vehicle-Finder-...\Contents\mods\VehicleFinder\` | folder repo/ZIP ikut kecopy |
| `Zomboid\mods\Contents\mods\VehicleFinder\` | folder `Contents` ikut kecopy |
| `Zomboid\mods\VehicleFinder\VehicleFinder\` | Windows bikin folder dobel waktu extract |
| `Zomboid\Workshop\...` | itu folder buat upload Workshop, bukan mod lokal |

Patokannya: **`...\Zomboid\mods\VehicleFinder\42\mod.info` harus ada.**
Kalau path itu benar tapi tetap nggak kebaca, coba hapus
`Zomboid\mods\reset-mods-42_00.txt` (file itu nyimpen daftar mod aktif dan
kadang nyangkut), terus cek `%USERPROFILE%\Zomboid\console.txt`.

Setting UI (posisi/ukuran tombol, geometry jendela) disimpan di
`Zomboid/VehicleFinder_settings.ini`, bukan di save game - jadi nggak ngefek ke
multiplayer dan nggak nyampur sama ModData mod lain.

## Struktur

```
Contents/mods/VehicleFinder/
  common/                            wajib ada buat B42, sengaja kosong
  42/
    mod.info
    poster.png
    media/
      lua/client/VehicleFinder/
        VehicleFinder_01_Core.lua      namespace, settings, helper, cari posisi kosong
        VehicleFinder_02_Vehicles.lua  scan kendaraan (aman buat kendaraan mod)
        VehicleFinder_03_Icon.lua      loader texture + gambar fallback
        VehicleFinder_04_Button.lua    tombol melayang (drag, klik, klik kanan)
        VehicleFinder_05_Window.lua    jendela utama (search, list, tracking)
        VehicleFinder_06_Main.lua      keybinding + event, satu-satunya entry point
      lua/shared/Translate/EN/IG_UI_EN.txt
      lua/shared/Translate/EN/Sandbox_EN.txt
      sandbox-options.txt                sandbox option "List burnt vehicles"
      textures/VehicleFinder_Car.png
tests/                               stub API PZ + test
tools/                               generator ikon + runner test
```

File di-prefix angka biar urutan load-nya pasti (Core duluan).

## Test

Mod-nya bisa dijalanin di luar game: ada stub kecil dari API Project Zomboid,
terus mod-nya digiring lewat skenario nyata (start game, hotkey, klik/drag
tombol, search, tracking, resize, ganti resolusi, keluar ke main menu).

```bash
pip install lupa
python3 tools/run_tests.py
```

Test-nya juga nge-fail kalau ada warning yang keluar diam-diam dari `VF.safe`,
jadi API yang salah nama ketahuan tanpa harus buka game.
