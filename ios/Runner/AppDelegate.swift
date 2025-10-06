import Flutter
import UIKit
import Firebase
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    
    // Push notification izinleri
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
      UNUserNotificationCenter.current().requestAuthorization(
        options: authOptions,
        completionHandler: {_, _ in })
    } else {
      let settings: UIUserNotificationSettings =
      UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
      application.registerUserNotificationSettings(settings)
    }
    
    application.registerForRemoteNotifications()
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // FCM token alındığında
  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Messaging.messaging().apnsToken = deviceToken
    print("✅ APNs token alındı ve FCM'e atandı")
    
    // FCM token'ı al
    Messaging.messaging().token { token, error in
      if let error = error {
        print("❌ FCM token alınamadı: \(error)")
      } else if let token = token {
        print("✅ FCM token alındı: \(token)")
      }
    }
  }
  
  // APNs token alınamadığında
  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("❌ APNs token alınamadı: \(error)")
  }
  
  // Foreground notification handler
  override func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    print("🔔 Foreground notification alındı: \(notification.request.content.title)")
    print("📱 İçerik: \(notification.request.content.body)")
    print("📱 Data: \(notification.request.content.userInfo)")
    
    // Notification'ı göster
    completionHandler([.alert, .badge, .sound])
  }
  
  // Notification tap handler
  override func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    print("🔔 Notification'a tıklandı: \(response.notification.request.content.title)")
    print("📱 İçerik: \(response.notification.request.content.body)")
    print("📱 Data: \(response.notification.request.content.userInfo)")
    
    completionHandler()
  }
  
  // Remote notification handler
  override func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    print("🔔 Remote notification alındı: \(userInfo)")
    completionHandler(.newData)
  }
}
