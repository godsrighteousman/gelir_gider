import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AutoPushService {
  static const String _oneSignalApiUrl =
      'https://onesignal.com/api/v1/notifications';

  // OneSignal App ID ve REST API Key (OneSignal Dashboard'dan alınacak)
  static const String _appId = '04de4d00-21ea-429c-9f53-3138e15732c7';
  static const String _restApiKey =
      'niwpdkdriuibmkbtzkowfk6hd'; // OneSignal Dashboard > Settings > Keys & IDs

  // Ortak harcama eklendiğinde otomatik push gönder
  static Future<void> sendSharedExpenseNotification({
    required String expenseDescription,
    required double amount,
    required String createdByName,
    required String targetUserId,
    required String targetUserName,
  }) async {
    try {
      print('🔔 Ortak harcama push notification gönderiliyor...');
      print('📱 Hedef kullanıcı: $targetUserName');
      print('📱 Harcama: $expenseDescription - $amount₺');
      print('📱 Harcama yapan: $createdByName');

      // Hedef kullanıcının OneSignal Player ID'sini al
      final playerId = await _getUserPlayerId(targetUserId);
      if (playerId == null) {
        print('❌ Hedef kullanıcının Player ID\'si bulunamadı');
        return;
      }

      // Push notification gönder
      await _sendOneSignalNotification(
        playerId: playerId,
        title: '💰 Yeni Ortak Harcama',
        message: '$createdByName $amount₺ harcama ekledi: $expenseDescription',
        data: {
          'type': 'shared_expense',
          'expense_description': expenseDescription,
          'amount': amount.toString(),
          'created_by': createdByName,
          'target_user': targetUserName,
        },
      );

      print('✅ Ortak harcama push notification gönderildi');
    } catch (e) {
      print('❌ Ortak harcama push notification hatası: $e');
    }
  }

  // Kullanıcının OneSignal Player ID'sini al
  static Future<String?> _getUserPlayerId(String userId) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final doc = await firestore.collection('userTokens').doc(userId).get();

      if (doc.exists) {
        final data = doc.data()!;
        return data['playerId'] as String?;
      }

      return null;
    } catch (e) {
      print('❌ Player ID alma hatası: $e');
      return null;
    }
  }

  // OneSignal REST API ile push notification gönder
  static Future<void> _sendOneSignalNotification({
    required String playerId,
    required String title,
    required String message,
    Map<String, String>? data,
  }) async {
    try {
      final body = {
        'app_id': _appId,
        'include_player_ids': [playerId],
        'headings': {'en': title},
        'contents': {'en': message},
        'data': data ?? {},
        'small_icon': 'ic_notification',
        'large_icon': 'ic_notification',
      };

      final response = await http.post(
        Uri.parse(_oneSignalApiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic $_restApiKey',
        },
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        print('✅ OneSignal push gönderildi');
      } else {
        print('❌ OneSignal push hatası: ${response.statusCode}');
        print('❌ Response: ${response.body}');
      }
    } catch (e) {
      print('❌ OneSignal API hatası: $e');
    }
  }

  // Kullanıcının Player ID'sini Firebase'e kaydet
  static Future<void> saveUserPlayerId(String userId, String playerId) async {
    try {
      final firestore = FirebaseFirestore.instance;
      await firestore.collection('userTokens').doc(userId).set({
        'playerId': playerId,
        'platform': 'iOS',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Player ID Firebase\'e kaydedildi: $userId');
    } catch (e) {
      print('❌ Player ID kaydetme hatası: $e');
    }
  }

  // Test push notification gönder
  static Future<void> sendTestPush(String playerId) async {
    await _sendOneSignalNotification(
      playerId: playerId,
      title: '🧪 Test Push',
      message: 'Bu bir test push notification\'dır!',
      data: {'type': 'test'},
    );
  }
}
