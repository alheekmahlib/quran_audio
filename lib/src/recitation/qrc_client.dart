import 'dart:async';
import 'dart:convert';
import 'dart:developer' show log;
import 'dart:typed_data' show Uint8List;

import 'package:web_socket_channel/web_socket_channel.dart';

import 'models/qrc_feedback.dart';
import 'qrc_constants.dart';

/// عميل WebSocket منخفض المستوى لِـ qurani.ai QRC.
///
/// Low-level WebSocket client for the qurani.ai QRC.
///
/// مسؤولياته:
/// - بناء رابط wss حسب استراتيجية المصادقة.
/// - إرسال رسائل JSON الصادرة.
/// - بثّ قطع الصوت الثنائية.
/// - استقبال التصحيح كـ `Stream<QrcFeedback>`.
///
/// لا يدير الميكروفون — تمرّر له القطع الصوتية من الخارج.
///
/// Responsibilities:
/// - Build the wss URL per the auth strategy.
/// - Send outbound JSON messages.
/// - Stream binary audio chunks.
/// - Receive feedback as a `Stream<QrcFeedback>`.
///
/// Does NOT manage the microphone — audio chunks are fed from outside.
class QrcClient {
  QrcClient({
    required String apiKey,
    String? wsUrl,
    QrcAuthStrategy? authStrategy,
  })  : _apiKey = apiKey,
        _wsUrl = wsUrl ?? QrcConstants.defaultWsUrl,
        _authStrategy = authStrategy ?? QrcConstants.defaultAuthStrategy;

  final String _apiKey;
  final String _wsUrl;
  final QrcAuthStrategy _authStrategy;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final StreamController<QrcFeedback> _feedbackController =
      StreamController<QrcFeedback>.broadcast();

  /// هل الاتصال مفتوح؟ / Is the connection open?
  bool get isConnected => _channel != null;

  /// تدفّق التصحيح الوارد. يُغلق عند إغلاق الاتصال.
  /// Incoming feedback stream. Closes when the connection closes.
  Stream<QrcFeedback> get feedbackStream => _feedbackController.stream;

  /// افتح الاتصال. يُرسل المفتاح حسب الاستراتيجية المختارة.
  ///
  /// Open the connection. Sends the key per the chosen strategy.
  Future<void> connect() async {
    if (_channel != null) return;
    try {
      final uri = _buildUri();
      _channel = WebSocketChannel.connect(uri);
      // استمع للرسائل الواردة.
      _sub = _channel!.stream.listen(
        _onData,
        onError: (e, s) => log('QrcClient stream error: $e',
            name: 'QrcClient', stackTrace: s),
        onDone: () {
          log('QrcClient socket closed', name: 'QrcClient');
          if (!_feedbackController.isClosed) {
            _feedbackController.close();
          }
        },
      );
      // إن كانت الاستراتيجية firstMessage، أرسل المفتاح أولاً.
      if (_authStrategy == QrcAuthStrategy.firstMessage) {
        sendJson({QrcConstants.apiKeyQueryParam: _apiKey});
      }
      log('QrcClient connected to $uri (strategy: $_authStrategy)',
          name: 'QrcClient');
    } catch (e, s) {
      log('QrcClient connect failed: $e', name: 'QrcClient', stackTrace: s);
      rethrow;
    }
  }

  /// ابنِ Uri حسب استراتيجية المصادقة.
  /// Build the Uri per the auth strategy.
  Uri _buildUri() {
    switch (_authStrategy) {
      case QrcAuthStrategy.queryParam:
        final base = Uri.parse(_wsUrl);
        return base.replace(queryParameters: {
          ...base.queryParameters,
          QrcConstants.apiKeyQueryParam: _apiKey,
        });
      case QrcAuthStrategy.subprotocol:
        // subprotocol يُمرَّر عبر WebSocketChannel.connect protocols
        // (web_socket_channel يدعمه عبر معامل protocols في بعض البناءات؛
        // نكتفي هنا بِتمريره كـ query احتياطاً لأن توقيع واجهة الحزمة يختلف).
        // TODO: استخدم protocols الرسمي عند توافره عبر الواجهة.
        final base = Uri.parse(_wsUrl);
        return base.replace(queryParameters: {
          ...base.queryParameters,
          QrcConstants.apiKeyQueryParam: _apiKey,
        });
      case QrcAuthStrategy.firstMessage:
        return Uri.parse(_wsUrl);
    }
  }

  /// أرسل رسالة JSON.
  /// Send a JSON message.
  void sendJson(Map<String, dynamic> message) {
    if (_channel == null) {
      log('QrcClient: cannot send — not connected', name: 'QrcClient');
      return;
    }
    _channel!.sink.add(jsonEncode(message));
  }

  /// ابثث قطعة صوت ثنائية.
  /// Stream a binary audio chunk.
  void sendAudioChunk(Uint8List bytes) {
    if (_channel == null) return;
    _channel!.sink.add(bytes);
  }

  void _onData(dynamic data) {
    if (data is String) {
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        if (!_feedbackController.isClosed) {
          _feedbackController.add(QrcFeedback.fromJson(json));
        }
      } catch (e) {
        log('QrcClient: failed to decode message: $e', name: 'QrcClient');
      }
    }
    // الرسائل الثنائية (غير النصية) تُتجاهل — QRC يُرجع JSON نصياً.
    // Binary (non-text) messages are ignored — QRC returns JSON text.
  }

  /// أغلق الاتصال وأصدر الموارد.
  /// Close the connection and release resources.
  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
    if (!_feedbackController.isClosed) {
      await _feedbackController.close();
    }
    log('QrcClient closed', name: 'QrcClient');
  }
}
