## Quran Audio
<p align="center">
<img src="https://raw.githubusercontent.com/alheekmahlib/data/main/packages/quran_audio/quran_audio_logo.png" width="90"/>
</p>
<p align="center">
<img src="https://raw.githubusercontent.com/alheekmahlib/data/main/packages/quran_audio/img.png" width="500"/>
</p>


<!-- الصف الأول: شارات pub.dev -->
<p align="center">
  <a href="https://pub.dev/packages/quran_audio">
    <img alt="pub package" src="https://img.shields.io/pub/v/quran_audio.svg?color=2cacbf&labelColor=145261" />
  </a>
  <a href="https://pub.dev/packages/quran_audio/score">
    <img alt="pub points" src="https://img.shields.io/pub/points/quran_audio?color=2cacbf&labelColor=145261" />
  </a>
  <a href="https://pub.dev/packages/quran_audio/score">
    <img alt="likes" src="https://img.shields.io/pub/likes/quran_audio?color=2cacbf&labelColor=145261" />
  </a>
  <a href="https://pub.dev/packages/quran_audio/score">
    <img alt="Pub Downloads" src="https://img.shields.io/pub/dm/quran_audio?color=2cacbf&labelColor=145261" />
  </a>
  <a href="LICENSE">
    <img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-2cacbf.svg?labelColor=145261" />
  </a>
</p>

<!-- الصف الثاني: المنصات المدعومة -->
<p align="center">
  <a href="https://flutter.dev/">
    <img alt="Web" src="https://img.shields.io/badge/Web-145261?logo=google-chrome&logoColor=white" />
  </a>
  <a href="https://flutter.dev/">
    <img alt="Windows" src="https://img.shields.io/badge/Windows-145261?logo=Windows&logoColor=white" />
  </a>
  <a href="https://flutter.dev/">
    <img alt="macOS" src="https://img.shields.io/badge/macOS-145261?logo=apple&logoColor=white" />
  </a>
  <a href="https://flutter.dev/">
    <img alt="Android" src="https://img.shields.io/badge/Android-145261?logo=android&logoColor=white" />
  </a>
  <a href="https://flutter.dev/">
    <img alt="iOS" src="https://img.shields.io/badge/iOS-145261?logo=ios&logoStyle=bold&logoColor=white" />
  </a>
</p>

A Flutter package for Quran audio playback — **logic only, no UI**. It supports two independent playback systems (full-surah and per-ayah), system media notifications, offline downloads, and repeat modes — all through a single unified `QuranAudio` facade.

#

## Table of Contents

- [Getting started](#getting-started)
- [Usage Example](#usage-example)
  - [Play a Surah](#play-a-surah)
  - [Play a Specific Ayah](#play-a-specific-ayah)
  - [Playback Controls](#playback-controls)
- [Reciters](#reciters)
- [Notification Icon](#notification-icon)
- [Offline Downloads](#offline-downloads)
- [Repeat](#repeat)
- [Reading State (GetX)](#reading-state-getx)
- [Metadata Helpers](#metadata-helpers)
- [How it Works](#how-it-works)
- [Sources](#sources)
- [License](#license)

#

## Getting started

#### Android
The required permissions for audio playback (`WAKE_LOCK`, and `FOREGROUND_SERVICE_MEDIA_PLAYOUT`) are automatically added by the package. You don't need to manually edit your AndroidManifest.xml.

Additionally, to enable system-integrated audio controls (notification/lockscreen) using `audio_service`, your app's MainActivity must extend `AudioServiceActivity`:

Kotlin:
```kotlin
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity: AudioServiceActivity()
```

Java:
```java
import com.ryanheise.audioservice.AudioServiceActivity;

public class MainActivity extends AudioServiceActivity {}
```

If you don't apply this change, the audio will still work locally, but system controls won't be available.

#### iOS
For background audio playback, you must add the following to your app's `Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

#### macOS
macOS requires a network entitlement. Open `macos/Runner/DebugProfile.entitlements` and add:

```xml
<key>com.apple.security.network.client</key>
<true/>
```

> ⚠️ Also add the same key to `macos/Runner/Release.entitlements`, otherwise release builds cannot reach the network for audio streaming.

The library works out of the box on macOS (just_audio uses the native AVAudioPlayer backend). The minimum deployment target should be macOS 11.0.

#### Windows & Linux
No manual setup is required. The library automatically initializes the `media_kit` audio backend on Windows and Linux via `just_audio_media_kit` during `QuranAudio.init()`. Just run:

```bash
flutter run -d windows   # or -d linux
```

> **Note:** System media notifications (lock-screen controls) are not available on Windows, Linux, or macOS — this is an `audio_service` limitation. Audio playback itself works fully on all desktop platforms.

#### Web
The library works on web in **streaming-only mode** (no offline downloads, since browsers have no file system). `QuranAudio.init()` handles everything automatically:

```bash
flutter run -d chrome
```

- ✅ Play surahs & ayahs (streamed from network URLs)
- ✅ Reciter selection, repeat modes, playback controls
- ❌ Offline downloads (not possible on web — use streaming instead)
- ❌ System media notifications (not supported on web by `audio_service`)

### Installation

In the `pubspec.yaml` of your flutter project, add the following dependency:

```yaml
dependencies:
  ...
  quran_audio: ^1.0.0
```

Import it:

```dart
import 'package:quran_audio/quran_audio.dart';
```

Initialize it:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize the entire library in one step
  await QuranAudio.init();
  runApp(const MyApp());
}
```

> 💡 `QuranAudio.init()` accepts optional parameters:
> ```dart
> await QuranAudio.init(
>   enableSystemNotifications: true,   // false = no notifications (lighter, for web/tests)
>   androidNotificationChannelId: 'com.myapp.quran',
>   androidNotificationChannelName: 'Quran Playback',
>   notificationIconSource: 'assets/images/logo.png', // custom icon (asset/url/file)
> );
> ```

> By default, `QuranAudio.init()` uses the library's bundled icon for the system media notification. To change it at runtime, see [Notification Icon](#notification-icon).

## Notification Icon

The system media notification (lock screen / Bluetooth / car audio) shows an icon. By default the library's bundled logo is used. You can set a custom icon from an asset, a network URL, or a local file:

```dart
// From an asset (most common)
await QuranAudio.setNotificationIconFromAsset('assets/images/my_logo.png');

// From a network URL
await QuranAudio.setNotificationIconFromUrl('https://example.com/logo.png');

// From a local file path
await QuranAudio.setNotificationIconFromFile('/path/to/logo.png');

// Auto-detect type (asset / url / file)
await QuranAudio.setNotificationIcon('assets/images/my_logo.png');

// Revert to the library's default icon
await QuranAudio.useDefaultNotificationIcon();

// Read the current icon URI
final Uri? icon = QuranAudio.notificationIcon;
```

> The icon is refreshed live — if playback is active when you call these methods, the notification updates immediately.

## Usage Example

### Play a Surah

Play a full surah (single MP3 file per surah):

```dart
// Play Surah Al-Baqarah
QuranAudio.playSurah(2);

// Play Surah Al-Fatihah
QuranAudio.playSurah(1);
```

### Play a Specific Ayah

Play a specific ayah by surah number and ayah number:

```dart
// Play Ayat al-Kursi (2:255), continue to following ayahs
QuranAudio.playAyah(
  surah: 2,
  ayah: 255,
  singleAyah: false, // false = continue to next ayahs
);

// Play a single ayah then stop
QuranAudio.playAyah(
  surah: 36,
  ayah: 1,
  singleAyah: true,
);
```

### Playback Controls

Controls automatically execute on the **currently active** system — no need to know which is running.

```dart
QuranAudio.pause();               // Pause (active system)
QuranAudio.resume();              // Resume (active system)
QuranAudio.stop();                // Stop completely
QuranAudio.next();                // Next (surah or ayah)
QuranAudio.previous();            // Previous (surah or ayah)
QuranAudio.seek(Duration(minutes: 5));  // Seek to position
QuranAudio.togglePlayPause();     // Toggle play/pause
```

<details>
<summary>Complete Audio Example</summary>

```dart
class AudioPlayerScreen extends StatelessWidget {
  const AudioPlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = QuranAudio.surahController;
    return Scaffold(
      appBar: AppBar(title: const Text('Quran Audio Player')),
      body: Column(
        children: [
          // Reactive now-playing display
          Obx(() {
            final surahNo = c.currentSurahNumber.value;
            final meta = QuranAudio.surah(surahNo);
            return Text('${meta.name} — ${meta.englishName}');
          }),

          // Control buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: QuranAudio.previous,
                icon: const Icon(Icons.skip_previous),
              ),
              IconButton(
                onPressed: QuranAudio.togglePlayPause,
                icon: const Icon(Icons.play_arrow),
              ),
              IconButton(
                onPressed: QuranAudio.next,
                icon: const Icon(Icons.skip_next),
              ),
              IconButton(
                onPressed: QuranAudio.stop,
                icon: const Icon(Icons.stop),
              ),
            ],
          ),

          // Progress bar
          StreamBuilder<PositionData>(
            stream: QuranAudio.positionDataStream,
            builder: (context, snap) {
              final d = snap.data;
              return Slider(
                value: d?.position.inSeconds.toDouble() ?? 0,
                max: d?.duration.inSeconds.toDouble() ?? 1,
                onChanged: (v) => QuranAudio.seek(
                  Duration(seconds: v.toInt()),
                ),
              );
            },
          ),

          // Play buttons
          ElevatedButton(
            onPressed: () => QuranAudio.playSurah(1),
            child: const Text('Play Al-Fatihah'),
          ),
          ElevatedButton(
            onPressed: () => QuranAudio.playAyah(surah: 2, ayah: 255),
            child: const Text('Play Ayat al-Kursi'),
          ),
        ],
      ),
    );
  }
}
```

</details>

## Reciters

The library ships with two independent reciter lists (matching the original `quran_library`):

- **Surah reciters**: 21 reciters (quranicaudio.com, mp3quran.net, tarteel.ai)
- **Ayah reciters**: 12 reciters (cdn.islamic.network, everyayah.com)

```dart
// Change reciter by index
QuranAudio.setSurahReader(2);
QuranAudio.setAyahReader(1);

// Access the lists
final surahReaders = QuranAudio.surahReaders;
final ayahReaders = QuranAudio.ayahReaders;
final currentIndex = QuranAudio.surahReaderIndex;
```

<details>
<summary>Custom Reciters</summary>

```dart
// Override the default surah reciters list
SurahReaders.customReaders = [
  const ReaderInfo(
    index: 0,
    name: 'My Custom Reciter',
    readerNamePath: 'my_reader/',
    url: 'https://my-server.com/quran/',
  ),
];

// Override the default ayah reciters list
AyahReaders.customReaders = [
  const ReaderInfo(
    index: 0,
    name: 'My Custom Reciter',
    readerNamePath: 'my_reader',
    url: 'https://everyayah.com/data/',
  ),
];
```

</details>

## Offline Downloads

```dart
// Surah system (single MP3 file)
await QuranAudio.downloadSurah(2);                  // Download Al-Baqarah
final ready = await QuranAudio.isSurahDownloaded(2);
await QuranAudio.deleteSurahDownload(2);

// Ayah system (one MP3 per ayah)
await QuranAudio.downloadSurahAyahs(2);             // All ayahs of Al-Baqarah
await QuranAudio.downloadAyahRange(2, from: 1, to: 10);  // Range
final ready = await QuranAudio.isSurahAyahsDownloaded(2);
await QuranAudio.deleteSurahAyahDownloads(2);

// Cancel any ongoing download
QuranAudio.cancelDownload();
```

## Repeat

```dart
QuranAudio.repeatAyah();      // Repeat the current ayah
QuranAudio.repeatSurah();     // Repeat the current surah
QuranAudio.repeatAyahRange(   // Repeat a range of ayahs
  fromAyah: 1,
  toAyah: 10,
  times: 3,
);
QuranAudio.disableRepeat();   // Disable repeat
```

## Reading State (GetX)

> ⚠️ **Important**: Each `Obx` must read `.value` **directly** from a controller inside its builder. Do not wrap a whole widget in `Obx` if Rx values are read in a deeper `build` — GetX will throw an error.

```dart
final c = QuranAudio.surahController;

// ✅ Correct — .value is read directly inside Obx
Obx(() => Text(
  c.isPlaying.value ? 'Playing' : 'Paused',
));

Obx(() => Text('Surah: ${c.currentSurahNumber.value}'));
```

<details>
<summary>Progress bar & reactive card</summary>

```dart
// Progress bar via StreamBuilder (no Obx needed)
StreamBuilder<PositionData>(
  stream: QuranAudio.positionDataStream,
  builder: (context, snap) {
    final d = snap.data;
    return Slider(
      value: d?.position.inSeconds.toDouble() ?? 0,
      max: d?.duration.inSeconds.toDouble() ?? 1,
      onChanged: (v) => QuranAudio.seek(Duration(seconds: v.toInt())),
    );
  },
);

// A reactive now-playing card
class NowPlayingCard extends StatelessWidget {
  Widget build(BuildContext context) {
    final surahC = QuranAudio.surahController;
    final ayahC = QuranAudio.ayahController;
    return Obx(() {
      final surahNo = surahC.currentSurahNumber.value;
      final ayahNo = ayahC.currentAyahInSurah.value;
      final playing = surahC.isPlaying.value || ayahC.isPlaying.value;
      final meta = QuranAudio.surah(surahNo);
      return Card(
        child: ListTile(
          title: Text(meta.name),
          subtitle: Text(playing ? 'Playing' : 'Paused'),
          trailing: Text('$ayahNo / ${meta.ayahCount}'),
        ),
      );
    });
  }
}
```

</details>

## Metadata Helpers

Instead of bundling the full Quran file (745KB), the library uses a tiny (~3KB) JSON holding only surah numbers, names, and ayah counts. Unique ayah numbers (UQ 1..6236) are computed cumulatively — no need to store them.

```dart
QuranAudio.ayahCountOf(2);          // → 286
QuranAudio.uqNumberOf(2, 255);      // → 262
QuranAudio.surah(2).name;           // → "Surat Al-Baqarah"
QuranAudio.allSurahs;               // → List<SurahMeta> (114 entries)

// Validation
QuranAudio.metadata.isValidSurah(2);           // → true
QuranAudio.metadata.isValidAyah(2, 255);       // → true
```

## How it Works

The library maintains two independent playback systems, each with its own reciters, URLs, and mechanisms:

| System | Description | Reciters | Sources |
|--------|-------------|----------|---------|
| **Surah** (`SurahAudioController`) | One MP3 per full surah | 21 | quranicaudio.com, mp3quran.net, tarteel.ai |
| **Ayah** (`AyahAudioController`) | One MP3 per ayah | 12 | cdn.islamic.network, everyayah.com |

They share a single `AudioPlayer` via a coordination layer (`AudioEngine`). When one system takes control, the other is automatically stopped and its state is reset.

- **Auto-advance**: Ayahs play sequentially (playlist + windowing); surahs auto-advance to the next (1→114) on completion.
- **Smart controls**: `pause()`/`resume()`/`next()`/`previous()` execute on whichever system is currently active.
- **Direct access**: For advanced use, the controllers are exposed via `QuranAudio.surahController` and `QuranAudio.ayahController`.

## Sources

- Quran metadata (surah names & ayah counts): derived from King Fahd Glorious Quran Printing Complex data
- Audio sources: quranicaudio.com, mp3quran.net, tarteel.ai, cdn.islamic.network, everyayah.com

## License
MIT for code. Read more about the license [here](LICENSE).
