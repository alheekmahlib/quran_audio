import 'dart:developer' show log;
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../constants/quran_constants.dart';
import 'media_item_builder.dart';

/// إدارة أيقونة الإشعارات (artUri) المعروضة في شاشة القفل/البلوتوث.
///
/// Manages the notification icon (artUri) shown on the lock screen / Bluetooth.
///
/// `audio_service` يتطلب `artUri` يُشير إلى ملف حقيقي أو رابط شبكي. لذلك
/// عند تمرير صورة من assets، تُنسخ إلى مجلد مؤقت ثم يُبنى `Uri.file()` منها.
///
/// `audio_service` requires `artUri` pointing to a real file or a network URL.
/// So when an asset image is supplied, it is copied to a temp directory and a
/// `Uri.file()` is built from it.
class AudioArt {
  AudioArt._();

  /// الأيقونة الافتراضية المضمّنة في حزمة المكتبة.
  /// The default icon bundled within the library package.
  static const String defaultAssetPath = QuranConstants.defaultArtAssetPath;

  /// عيّن الأيقونة من مسار asset.
  ///
  /// Set the icon from an asset path.
  ///
  /// [assetPath] - مسار الـ asset (مثل `assets/images/logo.png` أو
  ///   `packages/quran_audio/assets/images/quran_audio_logo.png`).
  static Future<void> setFromAsset(String assetPath,
      {bool fallbackToDefault = true}) async {
    try {
      if (kIsWeb) {
        // على الويب لا يمكن نسخ ملف؛ استخدم resolve نسبي.
        MediaItemBuilder.appIconUri = Uri.base.resolve(assetPath);
        await MediaItemBuilder.refreshCurrentMediaItem();
        return;
      }

      // انسخ ملف الـ asset إلى مجلد مؤقت.
      // Copy the asset file to a temp directory.
      final byteData = await rootBundle.load(assetPath);
      final tempDir = await getTemporaryDirectory();
      final fileName = assetPath.split('/').last;
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);

      MediaItemBuilder.appIconUri = Uri.file(file.path);
      await MediaItemBuilder.refreshCurrentMediaItem();
      log('AudioArt set from asset: $assetPath', name: 'AudioArt');
    } catch (e, s) {
      log('AudioArt: failed to set asset "$assetPath": $e',
          name: 'AudioArt', stackTrace: s);
      if (fallbackToDefault) {
        await setDefault();
      }
    }
  }

  /// عيّن الأيقونة من رابط شبكي (http/https).
  ///
  /// Set the icon from a network URL (http/https).
  static Future<void> setFromUrl(String url) async {
    final parsed = Uri.tryParse(url);
    if (parsed == null ||
        (parsed.scheme != 'http' && parsed.scheme != 'https')) {
      log('AudioArt: invalid URL "$url"', name: 'AudioArt');
      return;
    }
    MediaItemBuilder.appIconUri = parsed;
    await MediaItemBuilder.refreshCurrentMediaItem();
    log('AudioArt set from URL: $url', name: 'AudioArt');
  }

  /// عيّن الأيقونة من مسار ملف محلي على الجهاز.
  ///
  /// Set the icon from a local file path on the device.
  static Future<void> setFromFile(String filePath) async {
    if (kIsWeb) return;
    final file = File(filePath);
    if (await file.exists()) {
      MediaItemBuilder.appIconUri = Uri.file(file.path);
      await MediaItemBuilder.refreshCurrentMediaItem();
      log('AudioArt set from file: $filePath', name: 'AudioArt');
    } else {
      log('AudioArt: file not found "$filePath"', name: 'AudioArt');
    }
  }

  /// عيّن الأيقونة تلقائياً حسب نوع المصدر (asset / url / file).
  ///
  /// Set the icon automatically based on the source type.
  ///
  /// يكتشف النوع من النص المُمرّر:
  /// - يبدأ بـ `http://` أو `https://` → رابط شبكي.
  /// - يبدأ بـ `assets/` أو `packages/` → asset.
  /// - غير ذلك على المنصات الأصلية → مسار ملف محلي.
  /// - على الويب → يُحلّ نسبياً.
  static Future<void> setFrom(dynamic source) async {
    if (source is! String) {
      log('AudioArt: source must be a String', name: 'AudioArt');
      return;
    }
    final ref = source.trim();
    if (ref.isEmpty) {
      await setDefault();
      return;
    }

    // رابط شبكي / network URL
    if (ref.startsWith('http://') || ref.startsWith('https://')) {
      await setFromUrl(ref);
      return;
    }

    // asset
    if (ref.startsWith('assets/') || ref.startsWith('packages/')) {
      await setFromAsset(ref);
      return;
    }

    // على الويب، اعتبره رابطاً نسبياً.
    if (kIsWeb) {
      MediaItemBuilder.appIconUri = Uri.base.resolve(ref);
      await MediaItemBuilder.refreshCurrentMediaItem();
      return;
    }

    // مسار ملف محلي / local file path
    await setFromFile(ref);
  }

  /// استخدم الأيقونة الافتراضية المضمّنة في المكتبة.
  ///
  /// Use the default icon bundled with the library.
  static Future<void> setDefault() async {
    await setFromAsset(QuranConstants.defaultArtAssetPath,
        fallbackToDefault: false);
  }

  /// امسح الأيقونة (تُعرض إشعار بدون صورة).
  ///
  /// Clear the icon (notification shows without an image).
  static Future<void> clear() async {
    MediaItemBuilder.appIconUri = null;
    await MediaItemBuilder.refreshCurrentMediaItem();
  }

  /// الأيقونة الحالية (قد تكون null) / Current icon URI (may be null).
  static Uri? get current => MediaItemBuilder.appIconUri;
}
