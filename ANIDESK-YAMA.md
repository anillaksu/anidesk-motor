# AniDesk yaması (RustDesk 1.5.3, dal anidesk-tema)

## Renk tablosu (flutter/lib/common.dart; Tema.cs paleti)
| Yer | Eski | Yeni | Tema.cs adı |
|---|---|---|---|
| MyTheme.accent | 0071FF | D4A853 | Altın |
| accent50 / accent80 | 0071FF (a 77/AA) | D4A853 (a 77/AA) | Altın |
| canvasColor | 212121 | 0B0A10 | Zemin |
| idColor | 00B6F0 | 4FD0DC | Sinyal |
| cmIdColor | 21790B | 6FCF97 | Ok |
| button | 2C8CFF | C4783C | Kehribar (beyaz yazı okunsun diye altın değil) |
| dark scaffold/dialog | 18191E | 0B0A10 | Zemin |
| dark kart/dialog çizgisi/girdi/outlined | 24252B | 12101A | Yüzey |
| dark menü çubuğu | 121212 | 0B0A10 | Zemin |
| dark hoverColor | 2D2E35 | 1C1926 | türetilmiş (palette yok) |
| dark colorScheme.primary | Colors.blue | D4A853 | Altın |
Dokunulmadı: açık tema, ColorThemeExtension, common.dart ~1316-1324 (renk yardımcısı), font (Segoe UI için ayrı iş).

## Yükselt
- consts.dart: `kAniDeskHideElevate = true`.
- server_page.dart: buildAuthorized ve buildUnAuthorized `showElevation` başına `!kAniDeskHideElevate &&` (Yükselt ve "Kabul Et ve Yükselt" düğmeleri gizli; yalnız Kabul düğmesi kalır).

## src/lang/tr.rs
Parola Gerekli -> Parola gerekli; Accept -> Bağlantıya izin ver; Do you accept? -> Teknisyenin bilgisayarınıza bağlanmasına izin veriyor musunuz?; Accept and Elevate -> Bağlantıya izin ver (+ tooltip); Incoming connection -> Destek bağlantısı isteği; Disconnect yazım hatası (Bağlanıyı -> Bağlantıyı).
Not: Accept ve Do you accept? başka yerlerde de kullanılır (genel etki).

## Ad / simge (YAPILMADI, yalnız liste)
Cargo.toml: [package] name/description (7), [package.metadata.winres] ProductName (263), 282 bundle name; flutter/pubspec.yaml description; flutter/windows/runner/Runner.rc 93, 98 (FileDescription, ProductName); main.cpp 87 (app_name); simgeler res/icon.ico, res/icon.png, flutter/windows/runner/resources/app_icon.ico; APP_NAME src/ içinde hbb_common config (APP_NAME) [okunmadı].

## Derleme gereksinimi
Flutter 3.24.5 (~1.5-2 GB, 15-25 dk), Visual Studio Build Tools C++ (~6 GB), vcpkg + x64-windows-static libvpx libyuv opus aom (~2-3 GB, 30-60 dk), LLVM/clang, rust-bridge codegen (CI'da sabit sürüm), Rust (CI 1.75). Toplam ~10 GB, ilk derleme 1-2 saat.
