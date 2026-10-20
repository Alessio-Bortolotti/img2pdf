# FotoPDF

App Flutter per creare PDF dalle immagini.

App che crea un PDF da una o più immagini, **interamente offline**: nessun dato lascia il dispositivo.

## Funzioni
- **Importa** più immagini (JPG, PNG, WebP, BMP, GIF, TIFF), correzione automatica dell'orientamento EXIF.
- **Ordina** le pagine trascinandole, duplica o elimina.
- **Editor non distruttivo** (puoi sempre tornare all'originale):
  - Ritaglio con maniglie e proporzioni (libero, 1:1, 4:3, 16:9, A4…)
  - Rotazione 90°, specchio orizzontale/verticale, raddrizzamento fine ±45°
  - Ridimensionamento (10–100%) con dimensione risultante in pixel
  - Filtri: grigi, documento, B/N netto, seppia, vintage, caldo, freddo, negativo, nitidezza, sfocatura
  - Regolazioni: luminosità, contrasto, saturazione
- **Anteprima del PDF** prima di salvare, con impostazioni: formato (A4, A3, A5, Letter, Legal, come l'immagine), orientamento (auto/verticale/orizzontale), immagine intera o a pagina piena, margini, qualità JPEG.
- **Salva**, **condividi** o **stampa** il PDF.

## Condivisione dalla galleria (Android)
Da Galleria/Google Foto seleziona una o più immagini → **Condividi** → **FotoPDF**. Le immagini vengono aggiunte all'elenco, anche se l'app è già aperta.

## Ottenere l'APK senza installare nulla (GitHub Actions)
1. Crea un repository su GitHub (anche privato) e carica il contenuto di questa cartella, inclusa `.github/`.
2. Ad ogni push parte il workflow **Build APK** (scheda *Actions*).
3. A fine build (~5–8 min) apri l'esecuzione e scarica l'artefatto **img2pdf-apk**: dentro c'è `app-release.apk`.
4. Sul telefono abilita "Installa app sconosciute" e apri l'APK.

## Avvio in locale
Richiede Flutter 3.22+ (Dart 3.3+).

```bash
cd img2pdf
flutter create --project-name img2pdf .   # genera le cartelle android/ios/windows/macos/linux
flutter pub get
flutter run
```
`flutter create .` non sovrascrive i file già presenti (`lib/`, `pubspec.yaml`).

### Note per piattaforma
- **macOS**: in `macos/Runner/DebugProfile.entitlements` e `Release.entitlements` aggiungi
  ```xml
  <key>com.apple.security.files.user-selected.read-write</key><true/>
  <key>com.apple.security.print</key><true/>
  ```
- **iOS**: le foto HEIC non sono decodificabili dalla libreria `image`; se un file viene rifiutato, esportalo come JPG.
- **Android / Windows / Linux**: nessuna configurazione aggiuntiva.

## Struttura
```
lib/
  main.dart
  models/edit_params.dart        parametri di modifica + modello pagina
  services/image_processor.dart  pipeline immagini (in isolate, puro Dart)
  services/pdf_builder.dart      generazione PDF e impostazioni pagina
  widgets/crop_editor.dart       riquadro di ritaglio interattivo
  screens/home_screen.dart       elenco pagine
  screens/editor_screen.dart     editor immagine
  screens/pdf_screen.dart        anteprima, salvataggio, stampa
```

## Come funziona
Ogni immagine conserva i byte originali e una lista di parametri. Le anteprime dell'editor sono calcolate su una copia ridotta (1400 px) per essere rapide; solo alla creazione del PDF la pipeline viene applicata all'originale a piena risoluzione, in un isolate separato. I render sono messi in cache, quindi cambiare margini o formato non rielabora le immagini.
