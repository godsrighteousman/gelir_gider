import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter/foundation.dart';

class OneSignalService {
  static String? _appId;
  static String? _playerId;

  // OneSignal'i başlat
  static Future<void> initialize(String appId) async {
    try {
      _appId = appId;

      // OneSignal'i başlat
      OneSignal.initialize(appId);

      // iOS için özel ayarlar
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        OneSignal.Notifications.requestPermission(true);
      }

      // Player ID'yi al
      _playerId = await OneSignal.User.getOnesignalId();

      print('✅ OneSignal başlatıldı');
      print('📱 App ID: $appId');
      print('📱 Player ID: $_playerId');
    } catch (e) {
      print('❌ OneSignal başlatılamadı: $e');
    }
  }

  // Player ID'yi al
  static String? getPlayerId() {
    return _playerId;
  }

  // Push notification izni iste
  static Future<bool> requestPermission() async {
    try {
      final permission = await OneSignal.Notifications.requestPermission(true);
      print('🔔 OneSignal izin durumu: $permission');
      return permission;
    } catch (e) {
      print('❌ OneSignal izin hatası: $e');
      return false;
    }
  }

  // Notification'a tıklandığında
  static void setupNotificationTapHandler() {
    OneSignal.Notifications.addClickListener((event) {
      print('🔔 OneSignal notification\'a tıklandı');
      print('📱 Notification ID: ${event.notification.notificationId}');
      print('📱 Title: ${event.notification.title}');
      print('📱 Body: ${event.notification.body}');
      print('📱 Additional Data: ${event.notification.additionalData}');
    });
  }

  // Foreground notification handler
  static void setupForegroundHandler() {
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      print('🔔 OneSignal foreground notification');
      print('📱 Title: ${event.notification.title}');
      print('📱 Body: ${event.notification.body}');

      // Notification'ı göster
      event.preventDefault();
    });
  }

  // User tag'leri ayarla
  static Future<void> setUserTags(Map<String, String> tags) async {
    try {
      await OneSignal.User.addTags(tags);
      print('✅ OneSignal user tags ayarlandı: $tags');
    } catch (e) {
      print('❌ OneSignal user tags ayarlanamadı: $e');
    }
  }

  // User ID ayarla
  static Future<void> setUserId(String userId) async {
    try {
      await OneSignal.User.addTags({'user_id': userId});
      print('✅ OneSignal user ID ayarlandı: $userId');
    } catch (e) {
      print('❌ OneSignal user ID ayarlanamadı: $e');
    }
  }

  // Debug bilgilerini yazdır
  static Future<void> printDebugInfo() async {
    print('🔍 === ONESIGNAL DEBUG ===');
    print('🔍 App ID: $_appId');
    print('🔍 Player ID: $_playerId');

    final permission = await OneSignal.Notifications.permission;
    print('🔍 İzin durumu: $permission');

    print('🔍 === ONESIGNAL DEBUG BİTTİ ===');
  }
}
