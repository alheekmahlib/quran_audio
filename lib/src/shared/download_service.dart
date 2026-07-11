import 'dart:developer' show log;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';

import 'platform_io.dart';

/// خدمة تحميل ملفات الصوت — منطق مشترك بين نظامي السور والآيات.
///
/// Audio file download service — shared logic for both surah and ayah systems.
///
/// تستخدم Dio للتحميل مع دعم الإلغاء (CancelToken) وتتبع التقدّم عبر Rx.
/// على الويب: جميع عمليات الملفات no-op (لا نظام ملفات).
///
/// Uses Dio for downloads with cancel support (CancelToken) and Rx progress.
/// On web: all file operations are no-ops (no file system).
class DownloadService {
  DownloadService();

  final Dio _dio = Dio();
  CancelToken cancelToken = CancelToken();

  /// هل التحميل جارٍ؟ / Is a download in progress?
  final RxBool isDownloading = false.obs;

  /// نسبة التقدّم (0.0 - 1.0) / Progress ratio.
  final RxDouble progress = 0.0.obs;

  /// نص نسبة التقدّم (مثل "45") / Progress percentage string.
  final RxString progressString = '0'.obs;

  /// الحجم الكلي للملف بالبايت / Total file size in bytes.
  final RxInt fileSize = 0.obs;

  /// بايتات مُحمّلة / Bytes downloaded.
  final RxInt downloadedBytes = 0.obs;

  /// حمّل ملفاً إن لم يكن موجوداً محلياً / Download a file if not present locally.
  ///
  /// يعيد المسار المحلي للملف (موجود أو مُحمّل حديثاً).
  /// Returns the local path. Returns null on web (no local files).
  Future<String?> downloadIfNotExists({
    required String url,
    required String localPath,
    void Function(int received, int total)? onProgress,
  }) async {
    if (kIsWeb) return null; // لا تنزيلات محلية على الويب

    if (await PlatformIo.fileExists(localPath)) {
      return localPath; // موجود مسبقاً
    }

    await PlatformIo.ensureParentDir(localPath);

    try {
      await _download(
        url: url,
        localPath: localPath,
        onProgress: onProgress,
      );
    } catch (e) {
      log('Download failed for $url: $e', name: 'DownloadService');
      rethrow;
    }
    return localPath;
  }

  /// حمّل ملفاً مباشرة (حتى لو موجود) / Download a file directly.
  Future<bool> download({
    required String url,
    required String localPath,
    void Function(int received, int total)? onProgress,
  }) async {
    if (kIsWeb) return false;
    await PlatformIo.ensureParentDir(localPath);
    return _download(
      url: url,
      localPath: localPath,
      onProgress: onProgress,
    );
  }

  Future<bool> _download({
    required String url,
    required String localPath,
    void Function(int received, int total)? onProgress,
  }) async {
    cancelToken = CancelToken();
    isDownloading.value = true;
    progress.value = 0.0;
    progressString.value = '0';
    downloadedBytes.value = 0;

    try {
      // احصل على حجم الملف عبر HEAD / get file size via HEAD
      // (Headers.contentLengthHeader من dio — لا يحتاج dart:io)
      try {
        final head = await _dio.head(url);
        final len = head.headers.value(Headers.contentLengthHeader);
        if (len != null) fileSize.value = int.parse(len);
      } catch (_) {
        // تجاهل فشل الحصول على الحجم
      }

      await _dio.download(
        url,
        localPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            progress.value = received / total;
            progressString.value =
                ((received / total) * 100).toStringAsFixed(0);
            downloadedBytes.value = received;
          }
          onProgress?.call(received, total);
        },
        cancelToken: cancelToken,
      );

      progress.value = 1.0;
      progressString.value = '100';
      log('Download completed: $localPath', name: 'DownloadService');
      return true;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        log('Download cancelled: $url', name: 'DownloadService');
        // احذف الملف الجزئي
        await PlatformIo.deleteFile(localPath);
      } else {
        log('Download error (${e.type}): ${e.message}',
            name: 'DownloadService');
      }
      return false;
    } catch (e) {
      log('Download error: $e', name: 'DownloadService');
      return false;
    } finally {
      isDownloading.value = false;
    }
  }

  /// ألغِ التحميل الجاري / Cancel the ongoing download.
  void cancel() {
    isDownloading.value = false;
    progress.value = 0.0;
    progressString.value = '0';
    try {
      if (!cancelToken.isCancelled) {
        cancelToken.cancel('Download cancelled by user');
      }
    } catch (_) {}
    cancelToken = CancelToken();
  }

  /// تحقق من وجود ملف محلي / Check if a local file exists.
  Future<bool> fileExists(String localPath) async {
    if (kIsWeb) return false;
    try {
      return PlatformIo.fileExists(localPath);
    } catch (_) {
      return false;
    }
  }

  /// احذف ملفاً محلياً / Delete a local file.
  Future<void> deleteFile(String localPath) async {
    if (kIsWeb) return;
    try {
      await PlatformIo.deleteFile(localPath);
    } catch (e) {
      log('Failed to delete $localPath: $e', name: 'DownloadService');
    }
  }

  void dispose() {
    _dio.close();
  }
}
