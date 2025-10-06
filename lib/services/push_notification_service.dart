import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PushNotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // FCM token'ı al
  static Future<String?> getToken() async {
    try {
      print('🔔 FCM Token alınıyor...');

      // iOS için özel bekleme
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        print('🔔 iOS cihaz - APNS token bekleniyor...');
        await Future.delayed(const Duration(seconds: 1));
      }

      final token = await _messaging.getToken();

      if (token != null) {
        print('✅ FCM Token başarıyla alındı!');
        print('📱 Token: $token');
        print('📱 Token uzunluğu: ${token.length}');
        return token;
      } else {
        print('❌ FCM Token alınamadı - null döndü');
        return null;
      }
    } catch (e) {
      print('❌ FCM Token hatası: $e');
      return null;
    }
  }

  // Push notification izinlerini iste
  static Future<bool> requestPermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      print('🔔 Push notification izni: ${settings.authorizationStatus}');
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      print('❌ Push notification izni alınamadı: $e');
      return false;
    }
  }

  // Token'ı Firebase'e kaydet
  static Future<void> saveTokenToFirebase(String userId, String token) async {
    try {
      await _firestore.collection('userTokens').doc(userId).set({
        'token': token,
        'platform': defaultTargetPlatform.name,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ FCM Token Firebase\'e kaydedildi');
    } catch (e) {
      print('❌ FCM Token kaydedilemedi: $e');
    }
  }

  // Token'ı güncelle
  static Future<void> updateToken(String userId, String token) async {
    try {
      await _firestore.collection('userTokens').doc(userId).update({
        'token': token,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ FCM Token güncellendi');
    } catch (e) {
      print('❌ FCM Token güncellenemedi: $e');
    }
  }

  // Token'ı sil
  static Future<void> deleteToken(String userId) async {
    try {
      await _firestore.collection('userTokens').doc(userId).delete();
      print('✅ FCM Token silindi');
    } catch (e) {
      print('❌ FCM Token silinemedi: $e');
    }
  }

  // Background message handler
  static Future<void> backgroundMessageHandler(RemoteMessage message) async {
    print('🔔 Background message alındı: ${message.messageId}');
    print('📱 Başlık: ${message.notification?.title}');
    print('📱 İçerik: ${message.notification?.body}');
    print('📱 Data: ${message.data}');
  }

  // Foreground message handler
  static void setupForegroundMessageHandler() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('🔔 Foreground message alındı: ${message.messageId}');
      print('📱 Başlık: ${message.notification?.title}');
      print('📱 İçerik: ${message.notification?.body}');
      print('📱 Data: ${message.data}');

      // Burada custom notification gösterebilirsiniz
      _showLocalNotification(message);
    });
  }

  // Local notification göster
  static void _showLocalNotification(RemoteMessage message) {
    // Bu kısımda flutter_local_notifications paketi kullanılabilir
    // Şimdilik sadece console'a yazdırıyoruz
    print('📱 Local notification gösterilecek: ${message.notification?.title}');
  }

  // Notification tap handler
  static void setupNotificationTapHandler() {
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('🔔 Notification\'a tıklandı: ${message.messageId}');
      print('📱 Data: ${message.data}');

      // Burada notification'a tıklandığında yapılacak işlemler
      _handleNotificationTap(message);
    });
  }

  // Notification tap işlemi
  static void _handleNotificationTap(RemoteMessage message) {
    // Burada notification'a tıklandığında yapılacak işlemler
    // Örneğin: belirli bir sayfaya yönlendirme
    print('📱 Notification tap işlendi: ${message.data}');
  }

  // Tüm kullanıcılara push gönder (admin fonksiyonu)
  static Future<void> sendToAllUsers({
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    try {
      // Bu fonksiyon Firebase Cloud Functions ile implement edilmelidir
      // Şimdilik sadece console'a yazdırıyoruz
      print('📤 Tüm kullanıcılara push gönderilecek:');
      print('📱 Başlık: $title');
      print('📱 İçerik: $body');
      print('📱 Data: $data');
    } catch (e) {
      print('❌ Push gönderilemedi: $e');
    }
  }

  // Belirli kullanıcıya push gönder
  static Future<void> sendToUser({
    required String userId,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    try {
      // Bu fonksiyon Firebase Cloud Functions ile implement edilmelidir
      // Şimdilik sadece console'a yazdırıyoruz
      print('📤 Kullanıcıya push gönderilecek: $userId');
      print('📱 Başlık: $title');
      print('📱 İçerik: $body');
      print('📱 Data: $data');
    } catch (e) {
      print('❌ Push gönderilemedi: $e');
    }
  }

  // Test push notification gönder
  static Future<void> sendTestPush({
    required String title,
    required String body,
  }) async {
    try {
      // Firebase Cloud Messaging REST API kullanarak test push gönder
      final token = await getToken();
      if (token == null) {
        print('❌ FCM Token bulunamadı');
        return;
      }

      print('🧪 Test push gönderiliyor...');
      print('📱 Token: $token');
      print('📱 Başlık: $title');
      print('📱 İçerik: $body');
      print('📱 Firebase Console\'dan bu token ile test edin!');

      // Burada gerçek push gönderme işlemi yapılabilir
      // Firebase Admin SDK veya REST API kullanılabilir
    } catch (e) {
      print('❌ Test push gönderilemedi: $e');
    }
  }

  // iOS cihazdan token al ve kaydet
  static Future<String?> getAndSaveToken(String userId) async {
    try {
      print('🔔 iOS cihazdan FCM token alınıyor...');

      // İzin iste
      final hasPermission = await requestPermission();
      if (!hasPermission) {
        print('❌ Push notification izni verilmedi');
        return null;
      }

      // Token al
      final token = await getToken();
      if (token != null) {
        print('✅ FCM Token alındı: $token');

        // Firebase'e kaydet
        await saveTokenToFirebase(userId, token);
        print('✅ Token Firebase\'e kaydedildi');

        return token;
      } else {
        print('❌ FCM Token alınamadı');
        return null;
      }
    } catch (e) {
      print('❌ Token alma hatası: $e');
      return null;
    }
  }

  // Debug bilgilerini yazdır
  static Future<void> printDebugInfo() async {
    print('🔍 === PUSH NOTIFICATION DEBUG ===');
    print('🔍 Platform: ${defaultTargetPlatform.name}');

    // İzin kontrolü
    final permission = await requestPermission();
    print('🔍 İzin durumu: $permission');

    // Token kontrolü
    final token = await getToken();
    if (token != null) {
      print('✅ FCM Token alındı: $token');
      print('🔍 Token uzunluğu: ${token.length}');
    } else {
      print('❌ FCM Token alınamadı!');
    }

    print('🔍 === DEBUG BİTTİ ===');
  }
}
