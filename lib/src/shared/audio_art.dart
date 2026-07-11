import 'dart:convert' show base64Encode;
import 'dart:developer' show log;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;

import '../constants/quran_constants.dart';
import 'media_item_builder.dart';
import 'platform_io.dart';

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
      // على المنصات الأصلية: انسخ الملف لمجلد مؤقت ثم ابنِ Uri.file.
      // Native: copy the file to a temp dir then build a Uri.file.
      if (!kIsWeb) {
        final byteData = await rootBundle.load(assetPath);
        final tempDir = await PlatformIo.tempDir;
        final fileName = assetPath.split('/').last;
        final filePath = '$tempDir/$fileName';
        final bytes = byteData.buffer
            .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
        await PlatformIo.writeFile(filePath, Uint8List.fromList(bytes));

        MediaItemBuilder.appIconUri = Uri.file(filePath);
        await MediaItemBuilder.refreshCurrentMediaItem();
        log('AudioArt set from asset: $assetPath', name: 'AudioArt');
        return;
      }

      // على الويب: لا نظام ملفات ولا مسار asset صالح كرابط مباشر. حوّل الصورة
      // إلى data URI (base64) — مستقل عن الخادم ولا يُسبّب 404.
      // On web: no file system and the asset path isn't a valid direct URL.
      // Convert the image to a base64 data URI — server-independent, no 404.
      final byteData = await rootBundle.load(assetPath);
      final bytes = byteData.buffer
          .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
      MediaItemBuilder.appIconUri = _buildDataUri(bytes, assetPath);
      await MediaItemBuilder.refreshCurrentMediaItem();
      log('AudioArt set from asset (web data URI): $assetPath',
          name: 'AudioArt');
    } catch (e, s) {
      log('AudioArt: failed to set asset "$assetPath": $e',
          name: 'AudioArt', stackTrace: s);
      if (fallbackToDefault) {
        await setDefault();
      }
    }
  }

  /// ابنِ data URI (base64) من البايتات حسب امتداد الملف (للويب).
  ///
  /// Build a base64 data URI from bytes based on the file extension (for web).
  static Uri _buildDataUri(Uint8List bytes, String assetPath) {
    final ext = assetPath.toLowerCase().split('.').last;
    final mime = switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'svg' => 'image/svg+xml',
      _ => 'image/png',
    };
    final b64 = base64Encode(bytes);
    return Uri.parse('data:$mime;base64,$b64');
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
    if (await PlatformIo.fileExists(filePath)) {
      MediaItemBuilder.appIconUri = Uri.file(filePath);
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

    // على الويب، لا يمكن التعامل مع مسار ملف محلي — تجاهل بأمان.
    // On web, a local file path cannot be resolved — skip safely.
    if (kIsWeb) {
      log('AudioArt: local file paths are not supported on web; '
          'use setFromAsset or setFromUrl instead.',
          name: 'AudioArt');
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
