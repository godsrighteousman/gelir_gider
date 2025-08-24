import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'dart:async' show Stream;

// Kullanıcı modeli
class User {
  final String id;
  final String username;
  final DateTime createdAt;

  User({required this.id, required this.username, required this.createdAt});

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'createdAt': createdAt.toIso8601String(),
      };

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'],
        username: json['username'],
        createdAt: DateTime.parse(json['createdAt']),
      );
}

// Tema provider'ı
class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = false;

  bool get isDarkMode => _isDarkMode;

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    _saveThemeToFirebase();
    notifyListeners();
  }

  void setTheme(bool isDark) {
    _isDarkMode = isDark;
    _saveThemeToFirebase();
    notifyListeners();
  }

  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  // Firebase'e tema ayarını kaydet
  Future<void> _saveThemeToFirebase() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('currentUser');

      if (userId != null) {
        final userData = jsonDecode(userId);
        final userIdString = userData['id'] as String;

        await firestore.collection('userSettings').doc(userIdString).update({
          'isDarkMode': _isDarkMode,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        print('✅ Tema ayarı Firebase\'e kaydedildi: $_isDarkMode');
      }
    } catch (e) {
      print('❌ Firebase tema kaydetme hatası: $e');
    }
  }

  // Firebase'den tema ayarını yükle
  Future<void> loadThemeFromFirebase() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('currentUser');

      if (userId != null) {
        final userData = jsonDecode(userId);
        final userIdString = userData['id'] as String;

        final settingsDoc =
            await firestore.collection('userSettings').doc(userIdString).get();

        if (settingsDoc.exists) {
          final data = settingsDoc.data()!;
          if (data['isDarkMode'] != null) {
            _isDarkMode = data['isDarkMode'] as bool;
            print('✅ Tema ayarı Firebase\'den yüklendi: $_isDarkMode');
            notifyListeners();
          }
        }
      }
    } catch (e) {
      print('❌ Firebase tema yükleme hatası: $e');
    }
  }
}

// Kullanıcı yönetimi için provider
class UserProvider extends ChangeNotifier {
  User? _currentUser;

  User? get currentUser => _currentUser;

  Future<void> login(String username) async {
    final prefs = await SharedPreferences.getInstance();

    // Kullanıcı ID'sini kullanıcı adından oluştur (sabit)
    final userId = username.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    _currentUser = User(
      id: userId,
      username: username,
      createdAt: DateTime.now(),
    );

    // Kullanıcı bilgilerini kaydet
    await prefs.setString('currentUser', jsonEncode(_currentUser!.toJson()));
    await prefs.setBool('isLoggedIn', true);

    // Firebase'e kullanıcı kaydet
    try {
      if (!globalFirebaseInitialized) {
        print('⚠️ Firebase başlatılmadı, kullanıcı kaydedilemiyor');
        return;
      }

      final firestore = FirebaseFirestore.instance;
      await firestore.collection('users').doc(userId).set({
        'id': userId,
        'username': username,
        'createdAt': FieldValue.serverTimestamp(),
      });
      print('✅ Kullanıcı Firebase\'e kaydedildi: $userId');
    } catch (e) {
      print('❌ Firebase kullanıcı kaydetme hatası: $e');
    }

    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUser = null;
    await prefs.remove('currentUser');
    await prefs.setBool('isLoggedIn', false);
    notifyListeners();
  }

  Future<void> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('currentUser');
    if (userJson != null) {
      _currentUser = User.fromJson(jsonDecode(userJson));
      notifyListeners();
    }
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isLoggedIn') ?? false;
  }
}

// Gider modeli
class Expense {
  final double amount;
  final String category;
  final DateTime date;
  final String? note;

  Expense({
    required this.amount,
    required this.category,
    required this.date,
    this.note,
  });
}

// Arkadaş modeli
class Friend {
  final String id;
  final String userId;
  final String displayName;
  final DateTime addedDate;

  Friend({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.addedDate,
  });

  String get fullName => displayName;
}

// Ortak alışveriş modeli
class SharedExpense {
  final String id;
  final double amount;
  final String description;
  final String category;
  final DateTime date;
  final String debtType;
  final String createdBy; // Harcamayı oluşturan kullanıcı ID'si
  final String createdByName; // Harcamayı oluşturan kullanıcı adı
  final String
      expenseOwnerId; // Harcamayı yapan kişinin ID'si (renk belirleme için)

  SharedExpense({
    required this.id,
    required this.amount,
    required this.description,
    required this.category,
    required this.date,
    required this.debtType,
    required this.createdBy,
    required this.createdByName,
    String? expenseOwnerId,
  }) : expenseOwnerId =
            expenseOwnerId ?? createdBy; // Varsayılan olarak createdBy kullan

  double get debtAmount {
    // Bu getter artık kullanılmıyor, doğrudan amount kullanılıyor
    // Borç hesaplaması _calculateNetDebtFor fonksiyonunda yapılıyor
    return amount;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'description': description,
        'category': category,
        'date': date.toIso8601String(),
        'debtType': debtType,
        'createdBy': createdBy,
        'createdByName': createdByName,
        'expenseOwnerId': expenseOwnerId,
      };

  factory SharedExpense.fromJson(Map<String, dynamic> json) => SharedExpense(
        id: json['id'],
        amount: json['amount'].toDouble(),
        description: json['description'],
        category: json['category'],
        date: DateTime.parse(json['date']),
        debtType: json['debtType'],
        createdBy: json['createdBy'],
        createdByName: json['createdByName'],
        expenseOwnerId:
            json['expenseOwnerId'] ?? json['createdBy'], // Geriye uyumluluk
      );
}

// Kategori listesi ve renkleri
const kategoriRenkleri = {
  'Yemek': Colors.red,
  'Ulaşım': Colors.blue,
  'Giyim': Colors.green,
  'Eğlence': Colors.purple,
  'Fatura': Colors.orange,
  'Diğer': Colors.grey,
};

const kategoriler = ['Yemek', 'Ulaşım', 'Giyim', 'Eğlence', 'Fatura', 'Diğer'];

// Login sayfası
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final userProvider = UserProvider();
        await userProvider.login(_usernameController.text.trim());

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const KashiApp()),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Giriş yapılırken hata oluştu: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo ve başlık
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue[400]!, Colors.blue[600]!],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet,
                    size: 64,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Kashi',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Harcama Takip Uygulaması',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                const SizedBox(height: 48),

                // Login formu
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        Text(
                          'Hoş Geldiniz!',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Kullanıcı adınızı belirleyin',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Username alanı
                        TextFormField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            labelText: 'Kullanıcı Adı',
                            hintText: 'Örn: ahmet',
                            prefixIcon: const Icon(Icons.person),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Kullanıcı adı gerekli';
                            }
                            if (value.trim().length < 3) {
                              return 'Kullanıcı adı en az 3 karakter olmalı';
                            }
                            if (value.trim().length > 20) {
                              return 'Kullanıcı adı en fazla 20 karakter olmalı';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),

                        // Login butonu
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[600],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text(
                                    'Giriş Yap',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Bilgi kartı
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[600]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Kullanıcı adınız belirlendikten sonra otomatik olarak size özel bir ID atanacaktır.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class KashiApp extends StatefulWidget {
  const KashiApp({super.key});

  @override
  State<KashiApp> createState() => _KashiAppState();
}

class _KashiAppState extends State<KashiApp> {
  final UserProvider _userProvider = UserProvider();
  final ThemeProvider _themeProvider = ThemeProvider();
  bool _isLoading = true;
  bool _isLoggedIn = false;

  // Hafif dark mod teması
  ThemeData _buildLightDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      primarySwatch: Colors.blue,
      scaffoldBackgroundColor: const Color(0xFF1A1A1A), // Hafif koyu gri
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF2D2D2D), // Koyu gri
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardTheme: CardTheme(
        color: const Color(0xFF2D2D2D), // Koyu gri
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF2D2D2D),
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
      ),
      iconTheme: const IconThemeData(
        color: Colors.white,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white),
        titleLarge: TextStyle(color: Colors.white),
        titleMedium: TextStyle(color: Colors.white),
      ),
      colorScheme: const ColorScheme.dark(
        primary: Colors.blue,
        secondary: Colors.blueAccent,
        surface: Color(0xFF2D2D2D),
        background: Color(0xFF1A1A1A),
        onSurface: Colors.white,
        onBackground: Colors.white,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final isLoggedIn = await _userProvider.isLoggedIn();
    if (isLoggedIn) {
      await _userProvider.loadUser();
    }

    setState(() {
      _isLoggedIn = isLoggedIn;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.grey[50],
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue[400]!, Colors.blue[600]!],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Kashi',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const CircularProgressIndicator(),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isLoggedIn) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: _userProvider),
          ChangeNotifierProvider.value(value: _themeProvider),
        ],
        child: Consumer<ThemeProvider>(
          builder: (context, themeProvider, child) {
            return MaterialApp(
              title: 'Kashi',
              debugShowCheckedModeBanner: false,
              theme: ThemeData.light(),
              darkTheme: _buildLightDarkTheme(),
              themeMode: themeProvider.themeMode,
              home: const LoginPage(),
            );
          },
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _userProvider),
        ChangeNotifierProvider.value(value: _themeProvider),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Kashi',
            debugShowCheckedModeBanner: false,
            theme: ThemeData.light(),
            darkTheme: _buildLightDarkTheme(),
            themeMode: themeProvider.themeMode,
            home: const MainTabScreen(),
          );
        },
      ),
    );
  }
}

// Ana tab ekranı
class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const ExpenseHomePage(),
    const FriendsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Ana Sayfa',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Friends',
          ),
        ],
      ),
    );
  }
}

// Ana gider sayfası
class ExpenseHomePage extends StatefulWidget {
  const ExpenseHomePage({super.key});

  @override
  State<ExpenseHomePage> createState() => _ExpenseHomePageState();
}

class _ExpenseHomePageState extends State<ExpenseHomePage> {
  final List<Expense> _expenses = [];
  final UserProvider _userProvider = UserProvider();
  double? _totalBudget;
  int? _salaryDay;
  String _selectedFilter = 'Tümü';
  String _selectedSort = 'Tarih';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      await _userProvider.loadUser();
      await _loadUserSettingsFromFirebase(); // Firebase'den kullanıcı ayarlarını yükle

      // Tema ayarını Firebase'den yükle
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      await themeProvider.loadThemeFromFirebase();

      await _loadExpenses();
      await _loadBudget();
      await _loadSalaryDay();

      if (mounted) {
        setState(() {
          // UI'yi yenile
        });
      }
    } catch (e) {
      print('❌ Veri yükleme hatası: $e');
      if (mounted && ScaffoldMessenger.of(context).mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Veri yüklenirken hata oluştu: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Firebase'den kullanıcı ayarlarını yükle
  Future<void> _loadUserSettingsFromFirebase() async {
    if (_userProvider.currentUser == null) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final userId = _userProvider.currentUser!.id;

      print('🔍 Kullanıcı ayarları Firebase\'den yükleniyor: $userId');

      final settingsDoc =
          await firestore.collection('userSettings').doc(userId).get();

      if (settingsDoc.exists) {
        final data = settingsDoc.data()!;

        // Bütçe bilgisini yükle
        if (data['totalBudget'] != null) {
          _totalBudget = (data['totalBudget'] as num).toDouble();
          print('✅ Bütçe Firebase\'den yüklendi: $_totalBudget₺');
        }

        // Maaş günü bilgisini yükle
        if (data['salaryDay'] != null) {
          _salaryDay = data['salaryDay'] as int;
          print('✅ Maaş günü Firebase\'den yüklendi: $_salaryDay');
        }

        print('✅ Kullanıcı ayarları Firebase\'den yüklendi');
      } else {
        print(
            'ℹ️ Kullanıcı ayarları Firebase\'de bulunamadı, local storage\'dan yüklenecek');
      }
    } catch (e) {
      print('❌ Firebase kullanıcı ayarları yükleme hatası: $e');
    }
  }

  // Firebase'e kullanıcı ayarlarını kaydet
  Future<void> _saveUserSettingsToFirebase() async {
    if (_userProvider.currentUser == null) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final userId = _userProvider.currentUser!.id;

      final settingsData = {
        'userId': userId,
        'totalBudget': _totalBudget,
        'salaryDay': _salaryDay,
        'isDarkMode': false, // Varsayılan tema
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      await firestore
          .collection('userSettings')
          .doc(userId)
          .set(settingsData, SetOptions(merge: true));

      print('✅ Kullanıcı ayarları Firebase\'e kaydedildi');
    } catch (e) {
      print('❌ Firebase kullanıcı ayarları kaydetme hatası: $e');
    }
  }

  // Firebase'e harcama kaydet
  Future<void> _saveExpenseToFirebase(Expense expense) async {
    if (_userProvider.currentUser == null) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final userId = _userProvider.currentUser!.id;

      await firestore.collection('userExpenses').add({
        'userId': userId,
        'amount': expense.amount,
        'category': expense.category,
        'date': FieldValue.serverTimestamp(),
        'note': expense.note,
        'type': 'personal', // Kişisel harcama
        'createdBy': userId,
        'createdByName': _userProvider.currentUser!.username,
      });

      print(
          '✅ Harcama Firebase\'e kaydedildi: ${expense.note ?? expense.category} - ${expense.amount}₺');
    } catch (e) {
      print('❌ Firebase harcama kaydetme hatası: $e');
    }
  }

  // Firebase'den harcamaları yükle
  Future<void> _loadExpensesFromFirebase() async {
    if (_userProvider.currentUser == null) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final userId = _userProvider.currentUser!.id;

      print('🔍 Kişisel harcamalar Firebase\'den yükleniyor: $userId');

      final expensesQuery = await firestore
          .collection('userExpenses')
          .where('userId', isEqualTo: userId)
          .where('type', isEqualTo: 'personal')
          .orderBy('date', descending: true)
          .get();

      if (mounted) {
        setState(() {
          _expenses.clear();
          _expenses.addAll(expensesQuery.docs.map((doc) {
            final data = doc.data();
            return Expense(
              amount: (data['amount'] as num).toDouble(),
              category: data['category'] as String? ?? 'Diğer',
              date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
              note: data['note'] as String?,
            );
          }));
        });
      }

      print('✅ ${_expenses.length} kişisel harcama Firebase\'den yüklendi');
    } catch (e) {
      print('❌ Firebase harcama yükleme hatası: $e');
    }
  }

  // Harcamaları kaydet
  Future<void> _saveExpenses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _userProvider.currentUser?.id ?? 'default';
      final expensesJson = _expenses
          .map((e) => {
                'amount': e.amount,
                'category': e.category,
                'date': e.date.toIso8601String(),
                'note': e.note,
              })
          .toList();
      await prefs.setString('expenses_$userId', jsonEncode(expensesJson));
      print('💾 ${_expenses.length} harcama kaydedildi');
    } catch (e) {
      print('❌ Harcama kaydetme hatası: $e');
    }
  }

  // Harcamaları yükle
  Future<void> _loadExpenses() async {
    try {
      // Önce Firebase'den yükle
      await _loadExpensesFromFirebase();

      // Eğer Firebase'de veri yoksa local storage'dan yükle
      if (_expenses.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final userId = _userProvider.currentUser?.id ?? 'default';
        final expensesString = prefs.getString('expenses_$userId');
        if (expensesString != null) {
          final expensesJson = jsonDecode(expensesString) as List;
          if (mounted) {
            setState(() {
              _expenses.clear();
              _expenses.addAll(expensesJson.map((e) => Expense(
                    amount: e['amount'].toDouble(),
                    category: e['category'],
                    date: DateTime.parse(e['date']),
                    note: e['note'],
                  )));
            });
          }
          print('✅ ${_expenses.length} harcama local storage\'dan yüklendi');
        } else {
          print('ℹ️ Henüz harcama verisi yok');
        }
      }
    } catch (e) {
      print('❌ Harcama yükleme hatası: $e');
    }
  }

  // Bütçeyi kaydet
  Future<void> _saveBudget() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = _userProvider.currentUser?.id ?? 'default';
    if (_totalBudget != null) {
      await prefs.setDouble('totalBudget_$userId', _totalBudget!);
      // Firebase'e de kaydet
      await _saveUserSettingsToFirebase();
    }
  }

  // Bütçeyi yükle
  Future<void> _loadBudget() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = _userProvider.currentUser?.id ?? 'default';
    final budget = prefs.getDouble('totalBudget_$userId');
    if (budget != null) {
      setState(() {
        _totalBudget = budget;
      });
    }
  }

  // Maaş gününü kaydet
  Future<void> _saveSalaryDay() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = _userProvider.currentUser?.id ?? 'default';
    if (_salaryDay != null) {
      await prefs.setInt('salaryDay_$userId', _salaryDay!);
      // Firebase'e de kaydet
      await _saveUserSettingsToFirebase();
    }
  }

  // Maaş gününü yükle
  Future<void> _loadSalaryDay() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = _userProvider.currentUser?.id ?? 'default';
    final salaryDay = prefs.getInt('salaryDay_$userId');
    if (salaryDay != null) {
      setState(() {
        _salaryDay = salaryDay;
      });
    }
  }

  Future<void> _addExpense(Expense expense) async {
    setState(() {
      _expenses.add(expense);
    });

    // Harcamaları kaydet ve UI'yi güncelle
    await _saveExpenses();
    await _saveExpenseToFirebase(expense); // Firebase'e de kaydet

    // UI'yi yeniden yükle
    if (mounted) {
      setState(() {
        // State zaten güncellenmiş durumda, sadece UI'yi yenile
      });
    }

    if (mounted) {
      try {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${expense.amount.toStringAsFixed(2)} ₺ ${expense.category} harcaması eklendi!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      } catch (e) {
        print('❌ SnackBar gösterme hatası: $e');
      }
    }
  }

  Future<void> _removeExpense(int index) async {
    final expense = _expenses[index];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Harcamayı Sil'),
        content: Text(
            '${expense.amount.toStringAsFixed(2)} ₺ ${expense.category} harcaması silinecek. Emin misin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              setState(() {
                _expenses.removeAt(index);
              });
              await _saveExpenses();
              if (mounted) {
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  double get _remainingBudget {
    if (_totalBudget == null) return 0;
    double spent = _expenses.fold(0, (sum, e) => sum + e.amount);
    return _totalBudget! - spent;
  }

  int get _daysUntilSalary {
    if (_salaryDay == null) return 0;

    final now = DateTime.now();
    final currentMonth = now.month;
    final currentYear = now.year;

    DateTime salaryDate;
    try {
      salaryDate = DateTime(currentYear, currentMonth, _salaryDay!);
    } catch (e) {
      salaryDate = DateTime(currentYear, currentMonth + 1, 0);
    }

    if (salaryDate.isBefore(now)) {
      try {
        salaryDate = DateTime(currentYear, currentMonth + 1, _salaryDay!);
      } catch (e) {
        salaryDate = DateTime(currentYear, currentMonth + 2, 0);
      }
    }

    return salaryDate.difference(now).inDays;
  }

  List<Expense> get _filteredExpenses {
    List<Expense> filtered = _expenses;
    final now = DateTime.now();

    switch (_selectedFilter) {
      case 'Bugün':
        filtered = _expenses
            .where((e) =>
                e.date.year == now.year &&
                e.date.month == now.month &&
                e.date.day == now.day)
            .toList();
        break;
      case 'Bu Hafta':
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        filtered = _expenses
            .where((e) =>
                e.date.isAfter(weekStart.subtract(const Duration(days: 1))))
            .toList();
        break;
      case 'Bu Ay':
        final monthStart = DateTime(now.year, now.month, 1);
        filtered = _expenses
            .where((e) =>
                e.date.isAfter(monthStart.subtract(const Duration(days: 1))))
            .toList();
        break;
    }

    switch (_selectedSort) {
      case 'Tarih':
        filtered.sort((a, b) => b.date.compareTo(a.date));
        break;
      case 'Tutar':
        filtered.sort((a, b) => b.amount.compareTo(a.amount));
        break;
      case 'Kategori':
        filtered.sort((a, b) => a.category.compareTo(b.category));
        break;
    }

    return filtered;
  }

  Map<String, double> get _categoryTotals {
    final Map<String, double> totals = {};
    for (final expense in _filteredExpenses) {
      totals[expense.category] =
          (totals[expense.category] ?? 0) + expense.amount;
    }
    return totals;
  }

  void _showSalaryDayDialog() async {
    final controller =
        TextEditingController(text: _salaryDay?.toString() ?? '');
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.calendar_today, color: Colors.blue[600]),
            ),
            const SizedBox(width: 12),
            const Text('Maaş Günü Ayarla'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ayın hangi günü maaş alıyorsunuz?'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Gün (1-31)',
                hintText: 'Örn: 15',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              final day = int.tryParse(controller.text);
              if (day != null && day >= 1 && day <= 31) {
                Navigator.pop(context, day);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[600],
              foregroundColor: Colors.white,
            ),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() {
        _salaryDay = result;
      });
      _saveSalaryDay();
    }
  }

  void _showBudgetDialog() async {
    final controller =
        TextEditingController(text: _totalBudget?.toStringAsFixed(2) ?? '');
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  Icon(Icons.account_balance_wallet, color: Colors.green[600]),
            ),
            const SizedBox(width: 12),
            const Text('Bütçe Ayarla'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Aylık toplam bütçenizi girin'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Bütçe (₺)',
                hintText: 'Örn: 5000.00',
                prefixIcon: const Icon(Icons.attach_money),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text.replaceAll(',', '.'));
              if (val != null && val >= 0) {
                Navigator.pop(context, val);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[600],
              foregroundColor: Colors.white,
            ),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() {
        _totalBudget = result;
      });
      _saveBudget();
    }
  }

  @override
  Widget build(BuildContext context) {
    double toplamGunluk = 0;
    double toplamHaftalik = 0;
    double toplamAylik = 0;
    final bugun = DateTime.now();
    final haftaIlkGun = bugun.subtract(Duration(days: bugun.weekday - 1));
    final ayIlkGun = DateTime(bugun.year, bugun.month, 1);

    for (final e in _expenses) {
      if (e.date.year == bugun.year &&
          e.date.month == bugun.month &&
          e.date.day == bugun.day) {
        toplamGunluk += e.amount;
      }
      if (e.date.isAfter(haftaIlkGun.subtract(const Duration(days: 1)))) {
        toplamHaftalik += e.amount;
      }
      if (e.date.isAfter(ayIlkGun.subtract(const Duration(days: 1)))) {
        toplamAylik += e.amount;
      }
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kashi',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
            if (_userProvider.currentUser != null)
              Text(
                '${_userProvider.currentUser!.username} (${_userProvider.currentUser!.id})',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.blue[600],
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: 'Yenile',
              onPressed: () async {
                // Tüm verileri yenile
                await _loadData();

                // UI'ı güncelle
                if (mounted) {
                  setState(() {
                    // State'i yenile
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Ana sayfa yenilendi'),
                      backgroundColor: Colors.blue,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  );
                }
              },
            ),
          ),
          IconButton(
            icon: Icon(Theme.of(context).brightness == Brightness.dark
                ? Icons.light_mode
                : Icons.dark_mode),
            onPressed: () {
              // Tema değiştir
              final themeProvider =
                  Provider.of<ThemeProvider>(context, listen: false);
              themeProvider.toggleTheme();

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(themeProvider.isDarkMode
                      ? 'Gece modu açıldı'
                      : 'Gündüz modu açıldı'),
                  backgroundColor: Colors.blue,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              );
            },
            tooltip: 'Tema Değiştir',
          ),
          if (_userProvider.currentUser != null)
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: _userProvider.currentUser!.id));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text('ID kopyalandı: ${_userProvider.currentUser!.id}'),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              tooltip: 'ID Kopyala',
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Çıkış Yap',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Maaş günü kartı
            GestureDetector(
              onTap: _showSalaryDayDialog,
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue[400]!, Colors.blue[600]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.calendar_today,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _salaryDay == null
                                ? 'Maaş gününü ayarla'
                                : 'Maaş gününe kalan',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _salaryDay == null
                                ? 'Tıkla ve ayarla'
                                : '$_daysUntilSalary gün',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white.withOpacity(0.7),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),

            // Bütçe kartı
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.account_balance_wallet,
                                color: Colors.green[600]),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Aylık Bütçe',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: _showBudgetDialog,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_totalBudget != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Toplam: ${_totalBudget!.toStringAsFixed(2)} ₺',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Kalan: ${_remainingBudget.toStringAsFixed(2)} ₺',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _remainingBudget < 0
                                ? Colors.red
                                : Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _totalBudget! > 0
                          ? (1 - _remainingBudget / _totalBudget!)
                              .clamp(0.0, 1.0)
                          : 0,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _remainingBudget < 0 ? Colors.red : Colors.green,
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'Henüz bütçe girilmedi',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // İstatistik kartları
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Bugün',
                      '₺${toplamGunluk.toStringAsFixed(2)}',
                      Icons.today,
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      'Bu Hafta',
                      '₺${toplamHaftalik.toStringAsFixed(2)}',
                      Icons.view_week,
                      Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      'Bu Ay',
                      '₺${toplamAylik.toStringAsFixed(2)}',
                      Icons.calendar_month,
                      Colors.green,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Filtre ve sıralama
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedFilter,
                          items: ['Tümü', 'Bugün', 'Bu Hafta', 'Bu Ay']
                              .map((filter) => DropdownMenuItem(
                                    value: filter,
                                    child: Text(filter),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedFilter = value!;
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedSort,
                          items: ['Tarih', 'Tutar', 'Kategori']
                              .map((sort) => DropdownMenuItem(
                                    value: sort,
                                    child: Text(sort),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedSort = value!;
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Kategori dağılımı
            if (_categoryTotals.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.pie_chart, color: Colors.grey[700]),
                        const SizedBox(width: 8),
                        const Text(
                          'Kategori Dağılımı',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...(_categoryTotals.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value)))
                        .map((entry) {
                      final total = _categoryTotals.values
                          .fold(0.0, (sum, val) => sum + val);
                      final percentage =
                          total > 0 ? (entry.value / total * 100) : 0;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color:
                                    kategoriRenkleri[entry.key] ?? Colors.grey,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                entry.key,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            Text(
                              '₺${entry.value.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '(%${percentage.toStringAsFixed(1)})',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Harcama listesi
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.receipt_long, color: Colors.grey[700]),
                        const SizedBox(width: 8),
                        const Text(
                          'Harcama Geçmişi',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_filteredExpenses.length} harcama',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_filteredExpenses.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.add_shopping_cart,
                                size: 40,
                                color: Colors.grey[400],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Henüz harcama yok',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'İlk harcamanızı eklemek için\n+ butonuna tıklayın',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _filteredExpenses.length,
                      itemBuilder: (context, index) {
                        final expense = _filteredExpenses[index];
                        return _buildExpenseCard(expense, index);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 100), // FloatingActionButton için boşluk
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await showDialog<Expense>(
            context: context,
            builder: (context) => const ExpenseAddDialog(),
          );
          if (result != null) {
            await _addExpense(result);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Harcama Ekle'),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseCard(Expense expense, int index) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (kategoriRenkleri[expense.category] ?? Colors.grey)
                .withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getCategoryIcon(expense.category),
            color: kategoriRenkleri[expense.category] ?? Colors.grey,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                expense.category,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
            Text(
              '₺${expense.amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: kategoriRenkleri[expense.category] ?? Colors.grey,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 12,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  '${expense.date.day}.${expense.date.month}.${expense.date.year}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                if (expense.note != null && expense.note!.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Icon(
                    Icons.note,
                    size: 12,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      expense.note!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(
            Icons.delete_outline,
            color: Colors.red[400],
            size: 20,
          ),
          onPressed: () async =>
              await _removeExpense(_expenses.indexOf(expense)),
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Yemek':
        return Icons.restaurant;
      case 'Ulaşım':
        return Icons.directions_car;
      case 'Giyim':
        return Icons.checkroom;
      case 'Eğlence':
        return Icons.movie;
      case 'Fatura':
        return Icons.receipt;
      case 'Diğer':
        return Icons.more_horiz;
      default:
        return Icons.shopping_cart;
    }
  }

  // Logout işlemi
  Future<void> _logout() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Çıkış Yap'),
        content: const Text(
            'Hesabınızdan çıkış yapmak istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _userProvider.logout();
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const KashiApp()),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );
  }
}

// Arkadaş listesi sayfası
class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final List<Friend> _friends = [];
  final List<SharedExpense> _sharedExpenses = [];
  final UserProvider _userProvider = UserProvider();
  StreamSubscription<QuerySnapshot>? _friendsSubscription;

  @override
  void initState() {
    super.initState();
    _initializeFriends();
  }

  Future<void> _initializeFriends() async {
    await _loadUser();
    await _loadFriends(); // Önce local storage'dan yükle
    await _loadFriendsFromFirebase(); // Sonra Firebase'den güncelle
    await _loadAllSharedExpenses(); // Tüm ortak harcamaları yükle
    _listenToFriends(); // Gerçek zamanlı dinlemeyi başlat
  }

  @override
  void dispose() {
    _friendsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUser() async {
    await _userProvider.loadUser();
  }

  // Tüm ortak harcamaları Firebase'den yükle (Duplicate önleme ile)
  Future<void> _loadAllSharedExpenses() async {
    if (_userProvider.currentUser == null) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final userId = _userProvider.currentUser!.id;

      print('🔍 Tüm ortak harcamalar yükleniyor: $userId');

      // Mevcut harcamaların ID'lerini al
      Set<String> existingIds = _sharedExpenses.map((e) => e.id).toSet();

      // Kullanıcının tüm harcamalarını çek
      final expensesQuery = await firestore
          .collection('userExpenses')
          .where('userId', isEqualTo: userId)
          .get();

      // Yeni harcamaları ekle (sadece mevcut olmayanları)
      List<SharedExpense> newExpenses = [];

      // İlk sorgudan gelen veriler (ben -> arkadaş)
      for (final doc in expensesQuery.docs) {
        if (!existingIds.contains(doc.id)) {
          final data = doc.data();
          try {
            newExpenses.add(SharedExpense(
              id: doc.id,
              amount: (data['amount'] as num).toDouble(),
              description: data['description'] as String,
              category: data['category'] as String? ?? 'Diğer',
              date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
              debtType: data['debtType'] as String,
              createdBy: data['createdBy'] as String? ?? '',
              createdByName: data['createdByName'] as String? ?? '',
            ));
            print(
                '✅ Yeni harcama eklendi: ${data['description']} - ${data['amount']}₺');
          } catch (e) {
            print('❌ Harcama yükleme hatası (1): $e');
          }
        }
      }

      // Sadece yeni harcamaları ekle
      if (newExpenses.isNotEmpty) {
        setState(() {
          _sharedExpenses.addAll(newExpenses);
        });
        print(
            '📊 ${newExpenses.length} yeni harcama eklendi, toplam: ${_sharedExpenses.length}');
      } else {
        print('📊 Yeni harcama yok, mevcut: ${_sharedExpenses.length}');
      }
    } catch (e) {
      print('❌ Ortak harcamalar yükleme hatası: $e');
    }
  }

  // Arkadaşları kaydet
  Future<void> _saveFriends() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = _userProvider.currentUser?.id ?? 'default';
    final friendsJson = _friends
        .map((f) => {
              'id': f.id,
              'userId': f.userId,
              'displayName': f.displayName,
              'addedDate': f.addedDate.toIso8601String(),
            })
        .toList();
    await prefs.setString('friends_$userId', jsonEncode(friendsJson));
  }

  // Arkadaşları yükle
  Future<void> _loadFriends() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = _userProvider.currentUser?.id ?? 'default';
    final friendsString = prefs.getString('friends_$userId');
    if (friendsString != null) {
      final friendsJson = jsonDecode(friendsString) as List;
      setState(() {
        _friends.clear();
        _friends.addAll(friendsJson.map((f) => Friend(
              id: f['id'],
              userId: f['userId'],
              displayName: f['displayName'],
              addedDate: DateTime.parse(f['addedDate']),
            )));
      });
    }
  }

  void _removeFriend(int index) {
    final friendToRemove = _friends[index];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Arkadaşı Sil'),
        content: Text(
            '${friendToRemove.fullName} arkadaş listenden silinecek. Bu işlem geri alınamaz. Emin misin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Önce popup'ı kapat
              Navigator.pop(context);

              // UI'den kaldır
              setState(() {
                _friends.removeAt(index);
              });

              // Local storage'dan kaldır
              await _saveFriends();

              // Firebase'den karşılıklı arkadaşlığı sil
              await _removeFriendshipFromFirebase(friendToRemove);

              // Başarı mesajı göster
              if (mounted && ScaffoldMessenger.of(context).mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        '${friendToRemove.fullName} arkadaş listesinden silindi'),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  // Firebase'den karşılıklı arkadaşlığı sil
  Future<void> _removeFriendshipFromFirebase(Friend friend) async {
    if (_userProvider.currentUser == null) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final currentUserId = _userProvider.currentUser!.id;
      final friendUserId = friend.userId;

      print('🗑️ Arkadaşlık siliniyor: $currentUserId <-> $friendUserId');

      // İlk yön: Ben -> Arkadaş
      final friendshipQuery1 = await firestore
          .collection('friendships')
          .where('user1Id', isEqualTo: currentUserId)
          .where('user2Id', isEqualTo: friendUserId)
          .get();

      for (final doc in friendshipQuery1.docs) {
        await doc.reference.delete();
        print('✅ Arkadaşlık silindi: $currentUserId -> $friendUserId');
      }

      // İkinci yön: Arkadaş -> Ben
      final friendshipQuery2 = await firestore
          .collection('friendships')
          .where('user1Id', isEqualTo: friendUserId)
          .where('user2Id', isEqualTo: currentUserId)
          .get();

      for (final doc in friendshipQuery2.docs) {
        await doc.reference.delete();
        print(
            '✅ Karşılıklı arkadaşlık silindi: $friendUserId -> $currentUserId');
      }

      print('✅ Arkadaşlık Firebase\'den tamamen silindi');
    } catch (e) {
      print('❌ Firebase arkadaşlık silme hatası: $e');
    }
  }

  double _getTotalDebtFor(Friend friend) {
    // Bu fonksiyon artık kullanılmıyor, _calculateDebtFor kullanılıyor
    return _calculateDebtFor(friend);
  }

  int _getSharedExpenseCount(Friend friend) {
    // Bu fonksiyon artık kullanılmıyor, _getExpenseCountFor kullanılıyor
    return _getExpenseCountFor(friend);
  }

  // Yeni borç hesaplama sistemi
  double _calculateDebtFor(Friend friend) {
    if (_userProvider.currentUser == null) return 0.0;

    final userId = _userProvider.currentUser!.id;
    final friendId = friend.userId;

    // Shared expenses'i hesapla
    double totalDebt = 0.0;

    // Benim eklediğim harcamalar (arkadaşım bana borçlu)
    for (final expense in _getSharedExpensesForFriend(friend)) {
      if (expense.debtType == 'full') {
        totalDebt += expense.amount; // Arkadaşım bana tam tutarı borçlu
      } else {
        totalDebt += expense.amount / 2; // Arkadaşım bana yarısını borçlu
      }
    }

    return totalDebt;
  }

  // Net borç/alacak hesaplama (DB'den)
  double _calculateNetDebtFor(Friend friend) {
    // Firebase'den net durumu al
    return _getNetBalanceFromCache(friend.userId);
  }

  // Cache'den net durum alma
  double _getNetBalanceFromCache(String friendId) {
    // Bu fonksiyon arkadaşlar listesinde kullanılıyor
    // Şimdilik 0 döndür, daha sonra cache sistemi eklenebilir
    return 0.0;
  }

  // Borç durumu açıklaması (Düzeltilmiş mantık)
  String _getDebtStatusText(Friend friend) {
    final netDebt = _calculateNetDebtFor(friend);

    if (netDebt > 0) {
      return '${friend.fullName} size ${netDebt.toStringAsFixed(0)}₺ borçlu';
    } else if (netDebt < 0) {
      return 'Siz ${friend.fullName}\'e ${netDebt.abs().toStringAsFixed(0)}₺ borçlusunuz';
    } else {
      return 'Hesap eşit';
    }
  }

  // Arkadaş için harcama sayısı
  int _getExpenseCountFor(Friend friend) {
    return _getSharedExpensesForFriend(friend).length;
  }

  // Arkadaş için shared expenses listesi (Düzeltilmiş)
  List<SharedExpense> _getSharedExpensesForFriend(Friend friend) {
    if (_userProvider.currentUser == null) return [];

    final userId = _userProvider.currentUser!.id;
    final friendId = friend.userId;

    // Bu arkadaşla olan tüm ortak harcamaları filtrele
    List<SharedExpense> expenses = [];

    try {
      // Global shared expenses listesinden bu arkadaşla olanları filtrele
      expenses = _sharedExpenses.where((expense) {
        // Harcama benim tarafımdan mı arkadaşım tarafından mı yapılmış
        final isCreatedByMe = expense.createdBy == userId;
        final isCreatedByFriend = expense.createdBy == friendId;

        // Bu harcama bu arkadaşla ilgili mi kontrol et
        // Sadece bu iki kişi arasındaki harcamaları al
        return (isCreatedByMe && expense.createdBy == userId) ||
            (isCreatedByFriend && expense.createdBy == friendId);
      }).toList();

      // Duplicate kontrolü yap
      Set<String> uniqueIds = {};
      List<SharedExpense> uniqueExpenses = [];

      for (final expense in expenses) {
        if (!uniqueIds.contains(expense.id)) {
          uniqueExpenses.add(expense);
          uniqueIds.add(expense.id);
        }
      }

      print(
          '🔍 ${friend.fullName} için ${uniqueExpenses.length} benzersiz harcama bulundu');
      return uniqueExpenses;
    } catch (e) {
      print('❌ Arkadaş harcamaları çekme hatası: $e');
    }

    return expenses;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Arkadaşlarım',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
            if (_userProvider.currentUser != null)
              Text(
                '${_userProvider.currentUser!.username} (${_userProvider.currentUser!.id})',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        actions: [
          if (_userProvider.currentUser != null)
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: _userProvider.currentUser!.id));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text('ID kopyalandı: ${_userProvider.currentUser!.id}'),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              tooltip: 'ID Kopyala',
            ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.green[600],
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: 'Yenile',
              onPressed: () async {
                // Tüm verileri yenile
                await _loadFriendsFromFirebase();
                await _loadAllSharedExpenses();

                // UI'ı güncelle
                if (mounted) {
                  setState(() {
                    // State'i yenile
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Arkadaşlar listesi yenilendi'),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  );
                }
              },
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.blue[600],
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.person_add, color: Colors.white),
              tooltip: 'Arkadaş Ekle',
              onPressed: () => _showAddFriendDialog(),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // İstatistik kartları
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Toplam Arkadaş',
                    '${_friends.length}',
                    Icons.people,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Toplam Alacak',
                    '₺${_friends.fold(0.0, (sum, f) => sum + _calculateNetDebtFor(f).clamp(0.0, double.infinity)).toStringAsFixed(0)}',
                    Icons.account_balance_wallet,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Toplam Borç',
                    '₺${_friends.fold(0.0, (sum, f) => sum + _calculateNetDebtFor(f).clamp(double.negativeInfinity, 0.0).abs()).toStringAsFixed(0)}',
                    Icons.account_balance_wallet,
                    Colors.red,
                  ),
                ),
              ],
            ),
          ),

          // Arkadaş listesi
          Expanded(
            child: _friends.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _friends.length,
                    itemBuilder: (context, index) {
                      final friend = _friends[index];
                      return _buildFriendCard(friend, index);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendCard(Friend friend, int index) {
    final netDebt = _calculateNetDebtFor(friend);
    final expenseCount = _getExpenseCountFor(friend);
    final isOwed = netDebt > 0; // Pozitif ise arkadaşım bana borçlu
    final isDebtor = netDebt < 0; // Negatif ise ben arkadaşıma borçluyum

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FriendDetailPage(friend: friend),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.blue[400]!,
                        Colors.blue[600]!,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      friend.fullName[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // İsim ve bilgiler
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        friend.fullName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ID: ${friend.userId}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.receipt_long,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$expenseCount ortak alışveriş',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getDebtStatusText(friend),
                        style: TextStyle(
                          fontSize: 11,
                          color: isOwed
                              ? Colors.green[600]
                              : isDebtor
                                  ? Colors.red[600]
                                  : Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Borç durumu ve işlemler
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isOwed
                            ? Colors.green[50]
                            : isDebtor
                                ? Colors.red[50]
                                : Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isOwed
                            ? '+₺${netDebt.abs().toStringAsFixed(0)}'
                            : isDebtor
                                ? '-₺${netDebt.abs().toStringAsFixed(0)}'
                                : '₺0',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isOwed
                              ? Colors.green[700]
                              : isDebtor
                                  ? Colors.red[700]
                                  : Colors.grey[600],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            Icons.chat,
                            size: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _removeFriend(index),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              Icons.delete_outline,
                              size: 16,
                              color: Colors.red[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.people_outline,
              size: 48,
              color: Colors.blue[600],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Henüz arkadaş eklenmemiş',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Arkadaşlarınızı ekleyerek ortak\nharcamalarınızı takip edin',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showAddFriendDialog(),
            icon: const Icon(Icons.person_add),
            label: const Text('İlk Arkadaşını Ekle'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[600],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddFriendDialog() async {
    final userIdController = TextEditingController();
    String? foundUserName;
    bool isSearching = false;

    final result = await showDialog<Friend>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.person_add, color: Colors.blue[600]),
              ),
              const SizedBox(width: 12),
              const Text('Arkadaş Ekle'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Kullanıcının kendi ID'si
              if (_userProvider.currentUser != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.person, color: Colors.green[600], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sizin ID\'niz:',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _userProvider.currentUser!.id,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.green[600],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (_userProvider.currentUser != null) const SizedBox(height: 16),
              TextField(
                controller: userIdController,
                decoration: InputDecoration(
                  labelText: 'Arkadaş ID',
                  hintText: 'Örn: ahmet',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                onChanged: (value) async {
                  if (value.length >= 2) {
                    setDialogState(() {
                      isSearching = true;
                    });

                    try {
                      if (!globalFirebaseInitialized) {
                        print('⚠️ Firebase başlatılmadı, kullanıcı aranamıyor');
                        setDialogState(() {
                          foundUserName = null;
                          isSearching = false;
                        });
                        return;
                      }

                      // Firebase'den kullanıcı ara
                      final firestore = FirebaseFirestore.instance;
                      final userDoc = await firestore
                          .collection('users')
                          .doc(value.toLowerCase())
                          .get();

                      if (userDoc.exists) {
                        final userData = userDoc.data()!;
                        final foundUserId = userData['id'] as String;
                        final foundUsername = userData['username'] as String;

                        // Kendini eklemeye çalışıyorsa engelle
                        if (foundUserId == _userProvider.currentUser?.id) {
                          setDialogState(() {
                            foundUserName = null;
                            isSearching = false;
                          });
                          return;
                        }

                        setDialogState(() {
                          foundUserName = foundUsername;
                          isSearching = false;
                        });
                      } else {
                        setDialogState(() {
                          foundUserName = null;
                          isSearching = false;
                        });
                      }
                    } catch (e) {
                      print('Firebase arama hatası: $e');
                      setDialogState(() {
                        foundUserName = null;
                        isSearching = false;
                      });
                    }
                  } else {
                    setDialogState(() {
                      foundUserName = null;
                      isSearching = false;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              if (isSearching)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Kullanıcı aranıyor...'),
                    ],
                  ),
                ),
              if (foundUserName != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: Colors.green[600], size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Kullanıcı bulundu!',
                              style: TextStyle(
                                color: Colors.green[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              foundUserName!,
                              style: TextStyle(
                                color: Colors.green[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (userIdController.text.isNotEmpty &&
                  foundUserName == null &&
                  !isSearching)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: Colors.red[600], size: 24),
                      const SizedBox(width: 12),
                      Text(
                        'Kullanıcı bulunamadı',
                        style: TextStyle(
                          color: Colors.red[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: foundUserName != null
                  ? () {
                      Navigator.pop(
                        context,
                        Friend(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          userId: userIdController.text.toLowerCase(),
                          displayName: foundUserName!,
                          addedDate: DateTime.now(),
                        ),
                      );
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Ekle'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      // UI'yi hemen güncelle
      setState(() {
        _friends.add(result);
      });

      // Local storage'a kaydet
      await _saveFriends();

      // Firebase'e karşılıklı arkadaşlık kaydet
      try {
        final firestore = FirebaseFirestore.instance;
        final currentUserId = _userProvider.currentUser!.id;
        final currentUsername = _userProvider.currentUser!.username;
        final friendUserId = result.userId;
        final friendUsername = result.displayName;

        // Önce mevcut arkadaşlığı kontrol et
        final existingFriendship = await firestore
            .collection('friendships')
            .where('user1Id', isEqualTo: currentUserId)
            .where('user2Id', isEqualTo: friendUserId)
            .limit(1)
            .get();

        if (existingFriendship.docs.isNotEmpty) {
          print('⚠️ Arkadaşlık zaten mevcut: $currentUserId -> $friendUserId');
          return;
        }

        // İlk yön: Ben -> Arkadaş
        await firestore.collection('friendships').add({
          'user1Id': currentUserId,
          'user2Id': friendUserId,
          'user1Name': currentUsername,
          'user2Name': friendUsername,
          'createdAt': FieldValue.serverTimestamp(),
        });
        print(
            '✅ Arkadaşlık Firebase\'e kaydedildi: $currentUserId -> $friendUserId');

        // İkinci yön: Arkadaş -> Ben (otomatik)
        await firestore.collection('friendships').add({
          'user1Id': friendUserId,
          'user2Id': currentUserId,
          'user1Name': friendUsername,
          'user2Name': currentUsername,
          'createdAt': FieldValue.serverTimestamp(),
        });
        print(
            '✅ Karşılıklı arkadaşlık Firebase\'e kaydedildi: $friendUserId -> $currentUserId');

        // Başarı mesajı göster
        if (mounted && ScaffoldMessenger.of(context).mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('$friendUsername ile karşılıklı arkadaşlık kuruldu!'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          );
        }
      } catch (e) {
        print('❌ Firebase arkadaşlık kaydetme hatası: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Arkadaşlık eklenirken hata oluştu: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          );
        }
      }
    }
  }

  // Arkadaşları Firebase'den yükle
  Future<void> _loadFriendsFromFirebase() async {
    if (_userProvider.currentUser == null) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final userId = _userProvider.currentUser!.id;
      print('🔍 Arkadaşlar yükleniyor: $userId');

      final friendshipsQuery = await firestore
          .collection('friendships')
          .where('user1Id', isEqualTo: userId)
          .get();

      print(
          '📡 Firebase\'den ${friendshipsQuery.docs.length} arkadaşlık bulundu');

      final List<Friend> firebaseFriends = [];

      for (final doc in friendshipsQuery.docs) {
        final data = doc.data();
        firebaseFriends.add(Friend(
          id: doc.id,
          userId: data['user2Id'] as String,
          displayName: data['user2Name'] as String,
          addedDate:
              (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        ));
        print('✅ Arkadaş yüklendi: ${data['user2Name']} (${data['user2Id']})');
      }

      setState(() {
        // Mevcut arkadaşları temizle ve yenilerini ekle (duplicate kontrolü ile)
        _friends.clear();
        final Set<String> addedUserIds = {};

        for (final friend in firebaseFriends) {
          if (!addedUserIds.contains(friend.userId)) {
            _friends.add(friend);
            addedUserIds.add(friend.userId);
            print(
                '✅ Arkadaş eklendi: ${friend.displayName} (${friend.userId})');
          } else {
            print(
                '⚠️ Duplicate arkadaş atlandı: ${friend.displayName} (${friend.userId})');
          }
        }
      });

      // Local storage'a kaydet
      await _saveFriends();
      print('💾 ${firebaseFriends.length} arkadaş local storage\'a kaydedildi');
    } catch (e) {
      print('❌ Firebase arkadaş yükleme hatası: $e');
      // Hata durumunda local storage'dan yükle
      await _loadFriends();
    }
  }

  // Gerçek zamanlı arkadaş dinleme
  void _listenToFriends() async {
    if (_userProvider.currentUser == null) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final userId = _userProvider.currentUser!.id;

      print('🔍 Arkadaşlar gerçek zamanlı dinleniyor: $userId');

      _friendsSubscription = firestore
          .collection('friendships')
          .where('user1Id', isEqualTo: userId)
          .snapshots()
          .listen((snapshot) {
        print(
            '📡 Firebase\'den ${snapshot.docs.length} arkadaşlık güncellendi');

        final List<Friend> firebaseFriends = [];

        for (final doc in snapshot.docs) {
          final data = doc.data();
          try {
            firebaseFriends.add(Friend(
              id: doc.id,
              userId: data['user2Id'] as String,
              displayName: data['user2Name'] as String,
              addedDate:
                  (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
            ));
          } catch (e) {
            print('❌ Arkadaş yükleme hatası: $e');
          }
        }

        setState(() {
          // Mevcut arkadaşları temizle ve yenilerini ekle (duplicate kontrolü ile)
          _friends.clear();
          final Set<String> addedUserIds = {};

          for (final friend in firebaseFriends) {
            if (!addedUserIds.contains(friend.userId)) {
              _friends.add(friend);
              addedUserIds.add(friend.userId);
            }
          }
        });

        // Local storage'a kaydet
        _saveFriends();
        print('💾 ${firebaseFriends.length} arkadaş güncellendi ve kaydedildi');
      });
    } catch (e) {
      print('❌ Firebase gerçek zamanlı arkadaş dinleme hatası: $e');
    }
  }
}

// Arkadaş detayı (ortak alışverişler) sayfası
class FriendDetailPage extends StatefulWidget {
  final Friend friend;
  const FriendDetailPage({super.key, required this.friend});

  @override
  State<FriendDetailPage> createState() => _FriendDetailPageState();
}

class _FriendDetailPageState extends State<FriendDetailPage> {
  final List<SharedExpense> _sharedExpenses = [];
  final UserProvider _userProvider = UserProvider();
  StreamSubscription<QuerySnapshot>? _expensesSubscription;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await _loadUser();
    await _loadNetBalanceFromFirebase(); // Net durumu yükle
    await _loadSharedExpensesFromFirebase(); // Harcamaları yükle
    await _loadSharedExpenses(); // Local'den yükle
    _listenToSharedExpenses(); // Gerçek zamanlı dinlemeyi başlat
  }

  @override
  void dispose() {
    _expensesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUser() async {
    await _userProvider.loadUser();
  }

  // Ortak harcamaları kaydet
  Future<void> _saveSharedExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = _userProvider.currentUser?.id ?? 'default';
    final friendId = widget.friend.userId;
    final expensesJson = _sharedExpenses
        .map((e) => {
              'id': e.id,
              'amount': e.amount,
              'description': e.description,
              'date': e.date.toIso8601String(),
              'debtType': e.debtType,
            })
        .toList();
    await prefs.setString(
        'sharedExpenses_${userId}_$friendId', jsonEncode(expensesJson));
  }

  // Ortak harcamaları yükle
  Future<void> _loadSharedExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = _userProvider.currentUser?.id ?? 'default';
    final friendId = widget.friend.userId;
    final expensesString =
        prefs.getString('sharedExpenses_${userId}_$friendId');
    if (expensesString != null) {
      final expensesJson = jsonDecode(expensesString) as List;
      setState(() {
        _sharedExpenses.clear();
        _sharedExpenses.addAll(expensesJson.map((e) => SharedExpense(
              id: e['id'],
              amount: e['amount'].toDouble(),
              description: e['description'],
              category: e['category'] ?? 'Diğer',
              date: DateTime.parse(e['date']),
              debtType: e['debtType'],
              createdBy: e['createdBy'] ?? '',
              createdByName: e['createdByName'] ?? '',
            )));
      });
    }
  }

  // Ortak harcamaları Firebase'e kaydet (Tek kayıt, her iki kullanıcı da görür)
  Future<void> _saveSharedExpenseToFirebase(SharedExpense expense) async {
    if (_userProvider.currentUser == null) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final userId = _userProvider.currentUser!.id;
      final friendId = widget.friend.userId;

      // createdByName alanının dolu olduğundan emin ol
      String finalCreatedByName = expense.createdByName;
      if (finalCreatedByName.isEmpty) {
        finalCreatedByName =
            _userProvider.currentUser?.username ?? 'Bilinmeyen Kullanıcı';
        print(
            '🔧 createdByName boş olduğu için düzeltildi: $finalCreatedByName');
      }

      // Kategori alanının dolu olduğundan emin ol
      String finalCategory = expense.category;
      print('🔍 Kaydedilecek kategori: "$finalCategory"');
      if (finalCategory.isEmpty) {
        finalCategory = 'Diğer';
        print('🔧 Kategori boş olduğu için "Diğer" olarak ayarlandı');
      } else {
        print('✅ Kategori doğru şekilde kaydedilecek: $finalCategory');
      }

      // Tek harcama kaydı oluştur - her iki kullanıcı da bu kaydı görecek
      await firestore.collection('userExpenses').add({
        'amount': expense.amount,
        'description': expense.description,
        'category': finalCategory, // Düzeltilmiş kategoriyi kullan
        'date': FieldValue.serverTimestamp(),
        'debtType': expense.debtType,
        'createdBy': expense.createdBy,
        'createdByName': finalCreatedByName, // Düzeltilmiş ismi kullan
        'expenseOwnerId':
            expense.expenseOwnerId, // Harcamayı yapan kişinin ID'si
        'expenseId': expense.id,
        'userId': expense.createdBy, // Harcama yapan kişi
        'friendId':
            expense.createdBy == userId ? friendId : userId, // Karşı taraf
        'sharedWith': [
          userId,
          friendId
        ], // Hangi kullanıcılar arasında paylaşıldığı
      });

      // Net durumu güncelle
      await _updateNetBalance(expense);

      print(
          '✅ Harcama Firebase\'e kaydedildi (tek kayıt): ${expense.description} - ${expense.amount}₺ - ${expense.createdByName} - Kategori: $finalCategory - Firebase\'e gönderilen kategori: "$finalCategory"');
    } catch (e) {
      print('❌ Firebase harcama kaydetme hatası: $e');
    }
  }

  // Net durumu güncelle (Düzeltilmiş mantık)
  Future<void> _updateNetBalance(SharedExpense newExpense) async {
    if (_userProvider.currentUser == null) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final userId = _userProvider.currentUser!.id;
      final friendId = widget.friend.userId;

      // Sabit sıralama: Alfabetik sıraya göre user1 ve user2 belirle
      final user1Id = userId.compareTo(friendId) < 0 ? userId : friendId;
      final user2Id = userId.compareTo(friendId) < 0 ? friendId : userId;
      final user1Name = user1Id == userId
          ? _userProvider.currentUser!.username
          : widget.friend.displayName;
      final user2Name = user1Id == userId
          ? widget.friend.displayName
          : _userProvider.currentUser!.username;

      // Mevcut net durumu al
      final netBalanceQuery = await firestore
          .collection('netBalances')
          .where('user1Id', isEqualTo: user1Id)
          .where('user2Id', isEqualTo: user2Id)
          .get();

      double currentNetBalance = 0.0;
      String documentId = '';

      if (netBalanceQuery.docs.isNotEmpty) {
        final data = netBalanceQuery.docs.first.data();
        currentNetBalance = (data['netBalance'] as num).toDouble();
        documentId = netBalanceQuery.docs.first.id;
      }

      // Net durum hesaplama (user1 perspektifinden)
      double netBalanceChange = 0.0;

      if (newExpense.createdBy == user1Id) {
        // user1'in harcaması - user1 alacaklı olur
        if (newExpense.debtType == 'payment') {
          netBalanceChange =
              -newExpense.amount; // user1'in ödemesi user1'in borcunu azaltır
          print(
              '💰 ${user1Name} ödemesi: -${newExpense.amount}₺ (user1 borcu azalır)');
        } else {
          double amount = newExpense.debtType == 'full'
              ? newExpense.amount
              : newExpense.amount / 2;
          netBalanceChange =
              amount; // user1'in harcaması user1'in alacağını artırır
          print('💰 ${user1Name} harcaması: +${amount}₺ (user1 alacağı artar)');
        }
      } else {
        // user2'nin harcaması - user2 alacaklı olur, user1 borçlu olur
        if (newExpense.debtType == 'payment') {
          netBalanceChange =
              newExpense.amount; // user2'nin ödemesi user1'in alacağını azaltır
          print(
              '💰 ${user2Name} ödemesi: +${newExpense.amount}₺ (user1 alacağı azalır)');
        } else {
          double amount = newExpense.debtType == 'full'
              ? newExpense.amount
              : newExpense.amount / 2;
          netBalanceChange =
              -amount; // user2'nin harcaması user1'in borcunu artırır
          print('💰 ${user2Name} harcaması: -${amount}₺ (user1 borcu artar)');
        }
      }

      double newNetBalance = currentNetBalance + netBalanceChange;

      // Net durumu güncelle veya oluştur
      if (documentId.isNotEmpty) {
        await firestore.collection('netBalances').doc(documentId).update({
          'netBalance': newNetBalance,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      } else {
        await firestore.collection('netBalances').add({
          'user1Id': user1Id,
          'user2Id': user2Id,
          'user1Name': user1Name,
          'user2Name': user2Name,
          'netBalance': newNetBalance,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }

      // Cache'i güncelle (kendi perspektifimden)
      if (userId == user1Id) {
        _cachedNetBalance = newNetBalance;
      } else {
        _cachedNetBalance = -newNetBalance;
      }

      print('📊 Net durum güncellendi: $currentNetBalance -> $newNetBalance');
      print(
          '📊 ${_userProvider.currentUser!.username} net durum: ${newNetBalance > 0 ? '+' : ''}${newNetBalance}₺');
    } catch (e) {
      print('❌ Net durum güncelleme hatası: $e');
    }
  }

  // Ortak harcamaları Firebase'den yükle (Duplicate kontrolü ile)
  Future<void> _loadSharedExpensesFromFirebase() async {
    if (_userProvider.currentUser == null) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final userId = _userProvider.currentUser!.id;
      final friendId = widget.friend.userId;

      print(
          '🔍 Ortak harcamalar Firebase\'den yükleniyor: $userId <-> $friendId');

      // Mevcut harcamaların ID'lerini al
      Set<String> existingIds = _sharedExpenses.map((e) => e.id).toSet();
      final List<SharedExpense> newExpenses = [];

      // Tek sorgu ile tüm ortak harcamaları al (sharedWith alanını kullan)
      final sharedExpensesQuery = await firestore
          .collection('userExpenses')
          .where('sharedWith', arrayContains: userId)
          .get();

      // Tüm ortak harcamaları işle (duplicate kontrolü ile)
      for (final doc in sharedExpensesQuery.docs) {
        if (!existingIds.contains(doc.id)) {
          final data = doc.data();
          try {
            // Sadece bu arkadaşla olan harcamaları al
            List<dynamic> sharedWith =
                data['sharedWith'] as List<dynamic>? ?? [];
            if (!sharedWith.contains(friendId)) {
              continue; // Bu harcama bu arkadaşla değil, atla
            }

            // createdByName alanını belirle ve düzelt
            String createdByName = data['createdByName'] as String? ?? '';
            if (createdByName.isEmpty || createdByName == '') {
              // createdBy ID'sine göre belirle
              String createdById = data['createdBy'] as String? ?? '';
              if (createdById == userId) {
                createdByName = _userProvider.currentUser?.username ?? 'Ben';
              } else if (createdById == friendId) {
                createdByName = widget.friend.displayName;
              } else {
                createdByName = 'Bilinmeyen Kullanıcı';
              }
              print(
                  '🔧 createdByName düzeltildi: $createdByName (createdBy: $createdById)');
            }

            // createdBy alanını düzelt
            String createdBy = data['createdBy'] as String? ?? '';
            if (createdBy.isEmpty || createdBy == '') {
              createdBy = data['userId'] as String? ?? '';
              print('🔧 createdBy düzeltildi: $createdBy');
            }

            // expenseOwnerId alanını belirle
            String expenseOwnerId = data['expenseOwnerId'] as String? ?? '';
            if (expenseOwnerId.isEmpty || expenseOwnerId == '') {
              expenseOwnerId = data['userId'] as String? ?? '';
              print('🔧 expenseOwnerId düzeltildi: $expenseOwnerId');
            }

            // Kategori alanını kontrol et
            String category = data['category'] as String? ?? '';
            print('🔍 Firebase\'den gelen kategori: "$category"');
            if (category.isEmpty) {
              category = 'Diğer';
              print('🔧 Kategori boş olduğu için "Diğer" olarak ayarlandı');
            } else {
              print('✅ Kategori doğru şekilde alındı: $category');
            }

            newExpenses.add(SharedExpense(
              id: doc.id,
              amount: (data['amount'] as num).toDouble(),
              description: data['description'] as String,
              category: category,
              date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
              debtType: data['debtType'] as String,
              createdBy: createdBy,
              createdByName: createdByName,
              expenseOwnerId: expenseOwnerId,
            ));
            print(
                '✅ Harcama eklendi: ${data['description']} - ${data['amount']}₺ - $createdByName - createdBy: $createdBy - expenseOwnerId: $expenseOwnerId - Kategori: $category - Firebase ID: ${doc.id}');
          } catch (e) {
            print('❌ Harcama yükleme hatası: $e');
          }
        }
      }

      // Tarihe göre sırala
      newExpenses.sort((a, b) => b.date.compareTo(a.date));

      if (mounted && newExpenses.isNotEmpty) {
        setState(() {
          _sharedExpenses.addAll(newExpenses);
        });
        print(
            '📊 ${newExpenses.length} yeni harcama eklendi, toplam: ${_sharedExpenses.length}');
      } else {
        print('📊 Yeni harcama yok, mevcut: ${_sharedExpenses.length}');
      }
      await _saveSharedExpenses();
    } catch (e) {
      print('❌ Firebase ortak harcama yükleme hatası: $e');
    }
  }

  // Gerçek zamanlı ortak harcama dinleme (Tek sorgu ile)
  void _listenToSharedExpenses() async {
    if (_userProvider.currentUser == null) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final userId = _userProvider.currentUser!.id;
      final friendId = widget.friend.userId;

      print(
          '🔍 Ortak harcamalar gerçek zamanlı dinleniyor: $userId <-> $friendId');

      // Önceki subscription'ı iptal et
      _expensesSubscription?.cancel();

      // Tek stream ile tüm ortak harcamaları dinle
      final sharedExpensesStream = firestore
          .collection('userExpenses')
          .where('sharedWith', arrayContains: userId)
          .snapshots();

      _expensesSubscription = sharedExpensesStream.listen((snapshot) {
        _processExpensesSnapshot(snapshot, 'Ortak harcamalar');
      });

      print('✅ Gerçek zamanlı dinleme başlatıldı');
    } catch (e) {
      print('❌ Firebase gerçek zamanlı dinleme hatası: $e');
    }
  }

  // Ortak harcama snapshot'larını işle (Duplicate kontrolü ile)
  void _processExpensesSnapshot(QuerySnapshot snapshot, String streamName) {
    print('📡 $streamName: ${snapshot.docs.length} ortak harcama alındı');

    final List<SharedExpense> newExpenses = [];
    final userId = _userProvider.currentUser?.id ?? '';
    final friendId = widget.friend.userId;

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      try {
        // Sadece bu arkadaşla olan harcamaları al
        List<dynamic> sharedWith = data['sharedWith'] as List<dynamic>? ?? [];
        if (!sharedWith.contains(friendId)) {
          continue; // Bu harcama bu arkadaşla değil, atla
        }

        // createdByName alanını belirle ve düzelt
        String createdByName = data['createdByName'] as String? ?? '';
        if (createdByName.isEmpty || createdByName == '') {
          // createdBy ID'sine göre belirle
          String createdById = data['createdBy'] as String? ?? '';
          if (createdById == userId) {
            createdByName = _userProvider.currentUser?.username ?? 'Ben';
          } else if (createdById == friendId) {
            createdByName = widget.friend.displayName;
          } else {
            createdByName = 'Bilinmeyen Kullanıcı';
          }
          print(
              '🔧 $streamName - createdByName düzeltildi: $createdByName (createdBy: $createdById)');
        }

        // createdBy alanını düzelt
        String createdBy = data['createdBy'] as String? ?? '';
        if (createdBy.isEmpty || createdBy == '') {
          createdBy = data['userId'] as String? ?? '';
          print('🔧 $streamName - createdBy düzeltildi: $createdBy');
        }

        // expenseOwnerId alanını belirle
        String expenseOwnerId = data['expenseOwnerId'] as String? ?? '';
        if (expenseOwnerId.isEmpty || expenseOwnerId == '') {
          expenseOwnerId = data['userId'] as String? ?? '';
          print('🔧 $streamName - expenseOwnerId düzeltildi: $expenseOwnerId');
        }

        // Kategori alanını kontrol et
        String category = data['category'] as String? ?? '';
        print('🔍 $streamName - Firebase\'den gelen kategori: "$category"');
        if (category.isEmpty) {
          category = 'Diğer';
          print(
              '🔧 $streamName - Kategori boş olduğu için "Diğer" olarak ayarlandı');
        } else {
          print('✅ $streamName - Kategori doğru şekilde alındı: $category');
        }

        newExpenses.add(SharedExpense(
          id: doc.id,
          amount: (data['amount'] as num).toDouble(),
          description: data['description'] as String,
          category: category,
          date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
          debtType: data['debtType'] as String,
          createdBy: createdBy,
          createdByName: createdByName,
          expenseOwnerId: expenseOwnerId,
        ));
        print(
            '✅ $streamName - Ortak harcama: ${data['description']} - ${data['amount']}₺ - $createdByName - createdBy: $createdBy - Kategori: $category - Firebase ID: ${doc.id}');
      } catch (e) {
        print('❌ $streamName - Ortak harcama yükleme hatası: $e');
      }
    }

    // Mevcut listeye ekle veya güncelle (duplicate kontrolü ile)
    if (mounted) {
      setState(() {
        // Yeni harcamaları ekle veya mevcut olanları güncelle
        for (final newExpense in newExpenses) {
          final existingIndex =
              _sharedExpenses.indexWhere((e) => e.id == newExpense.id);
          if (existingIndex == -1) {
            // Yeni harcama ekle
            _sharedExpenses.add(newExpense);
            print(
                '➕ Yeni harcama eklendi: ${newExpense.description} - Kategori: ${newExpense.category}');
          } else {
            // Mevcut harcamayı güncelle (kategori değişiklikleri için)
            final oldExpense = _sharedExpenses[existingIndex];
            if (oldExpense.category != newExpense.category) {
              print(
                  '🔄 Kategori güncellendi: ${oldExpense.category} -> ${newExpense.category}');
            }
            _sharedExpenses[existingIndex] = newExpense;
          }
        }

        // Tarihe göre sırala
        _sharedExpenses.sort((a, b) => b.date.compareTo(a.date));

        print('📊 Toplam ${_sharedExpenses.length} harcama listelendi');
      });
    }

    _saveSharedExpenses();
  }

  void _showAddSharedExpenseDialog() {
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    String selectedDebtType = 'full';
    String selectedCategory = kategoriler.first;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.receipt_long, color: Colors.green[600]),
              ),
              const SizedBox(width: 12),
              const Text('Ortak Alışveriş Ekle'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Tutar (₺)',
                  hintText: 'Örn: 250.00',
                  prefixIcon: const Icon(Icons.attach_money),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: InputDecoration(
                  labelText: 'Açıklama',
                  hintText: 'Örn: Market alışverişi',
                  prefixIcon: const Icon(Icons.description),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
              ),
              const SizedBox(height: 16),
              // Kategori seçimi
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedCategory,
                    isExpanded: true,
                    items: kategoriler.map((category) {
                      return DropdownMenuItem(
                        value: category,
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color:
                                    kategoriRenkleri[category] ?? Colors.grey,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(category),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedCategory = value!;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Borç türünü seçin:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Column(
                      children: [
                        RadioListTile<String>(
                          title: const Text('Hepsini yansıt'),
                          subtitle: const Text(
                              'Tüm tutar karşı tarafa borç olarak yansır'),
                          value: 'full',
                          groupValue: selectedDebtType,
                          onChanged: (value) {
                            setDialogState(() {
                              selectedDebtType = value!;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<String>(
                          title: const Text('Yarısını yansıt'),
                          subtitle: const Text(
                              'Tutarın yarısı karşı tarafa borç olarak yansır'),
                          value: 'half',
                          groupValue: selectedDebtType,
                          onChanged: (value) {
                            setDialogState(() {
                              selectedDebtType = value!;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount =
                    double.tryParse(amountController.text.replaceAll(',', '.'));
                final desc = descriptionController.text.trim();
                if (amount != null && amount > 0 && desc.isNotEmpty) {
                  final newExpense = SharedExpense(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    amount: amount,
                    description: desc,
                    category: selectedCategory,
                    date: DateTime.now(),
                    debtType: selectedDebtType,
                    createdBy: _userProvider.currentUser?.id ?? '',
                    createdByName: _userProvider.currentUser?.username ?? '',
                    expenseOwnerId: _userProvider.currentUser?.id ??
                        '', // Harcamayı yapan kişi
                  );

                  print(
                      '🆕 Yeni harcama oluşturuldu: ${newExpense.description} - ${newExpense.amount}₺ - ${newExpense.debtType}');

                  // Önce Firebase'e kaydet
                  await _saveSharedExpenseToFirebase(newExpense);

                  // Local state'i güncelleme - Firebase stream otomatik güncelleyecek
                  // setState(() {
                  //   _sharedExpenses.add(newExpense);
                  // });

                  // await _saveSharedExpenses();

                  Navigator.pop(context);

                  // SnackBar'ı güvenli şekilde göster
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      try {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                '${widget.friend.fullName} ile ortak alışveriş eklendi!'),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        );
                      } catch (e) {
                        print('❌ SnackBar gösterme hatası: $e');
                      }
                    }
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Ekle'),
            ),
          ],
        ),
      ),
    );
  }

  // Net borç/alacak hesaplama (DB'den)
  double _calculateNetDebtForFriend() {
    // TODO: Firebase'den net durumu yükle
    return _cachedNetBalance;
  }

  // Cache'lenmiş net durum
  double _cachedNetBalance = 0.0;

  // Net durumu Firebase'den yükle
  Future<void> _loadNetBalanceFromFirebase() async {
    if (_userProvider.currentUser == null) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final userId = _userProvider.currentUser!.id;
      final friendId = widget.friend.userId;

      // Sabit sıralama: Alfabetik sıraya göre user1 ve user2 belirle
      final user1Id = userId.compareTo(friendId) < 0 ? userId : friendId;
      final user2Id = userId.compareTo(friendId) < 0 ? friendId : userId;

      final netBalanceQuery = await firestore
          .collection('netBalances')
          .where('user1Id', isEqualTo: user1Id)
          .where('user2Id', isEqualTo: user2Id)
          .get();

      if (netBalanceQuery.docs.isNotEmpty) {
        final data = netBalanceQuery.docs.first.data();
        double rawNetBalance = (data['netBalance'] as num).toDouble();

        // Perspektif düzeltmesi: Net durum her zaman user1 perspektifinden kaydediliyor
        // user1: pozitif değer = alacaklı, negatif değer = borçlu
        // user2: pozitif değer = borçlu, negatif değer = alacaklı
        if (data['user1Id'] == userId) {
          // Ben user1'im, değer zaten benim perspektifimden
          _cachedNetBalance = rawNetBalance;
        } else {
          // Ben user2'yim, değeri benim perspektifime çevir
          // user1'in alacağı = user2'nin borcu
          // user1'in borcu = user2'nin alacağı
          _cachedNetBalance = -rawNetBalance;
        }

        print(
            '📊 Net durum Firebase\'den yüklendi: ${_cachedNetBalance > 0 ? '+' : ''}${_cachedNetBalance}₺');

        // Net durum açıklaması
        if (_cachedNetBalance > 0) {
          print(
              '📊 ${_userProvider.currentUser!.username} ${widget.friend.displayName}\'e ${_cachedNetBalance}₺ alacaklı');
        } else if (_cachedNetBalance < 0) {
          print(
              '📊 ${_userProvider.currentUser!.username} ${widget.friend.displayName}\'e ${_cachedNetBalance.abs()}₺ borçlu');
        } else {
          print(
              '📊 ${_userProvider.currentUser!.username} ve ${widget.friend.displayName} arasında borç yok');
        }
      } else {
        _cachedNetBalance = 0.0;
        print('📊 Net durum bulunamadı, varsayılan: 0₺');
      }
    } catch (e) {
      print('❌ Net durum yükleme hatası: $e');
      _cachedNetBalance = 0.0;
    }
  }

  // Ödeme ekleme fonksiyonu
  void _showPaymentDialog() {
    final amountController = TextEditingController();
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.payment, color: Colors.green[600]),
            ),
            const SizedBox(width: 12),
            const Text('Ödeme Ekle'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Ödeme Tutarı (₺)',
                hintText: 'Örn: 100.00',
                prefixIcon: const Icon(Icons.attach_money),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: noteController,
              decoration: InputDecoration(
                labelText: 'Not (opsiyonel)',
                hintText: 'Örn: Nakit ödeme',
                prefixIcon: const Icon(Icons.note),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount =
                  double.tryParse(amountController.text.replaceAll(',', '.'));
              if (amount != null && amount > 0) {
                await _addPayment(amount, noteController.text.trim());
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[600],
              foregroundColor: Colors.white,
            ),
            child: const Text('Ödeme Ekle'),
          ),
        ],
      ),
    );
  }

  // Ödeme ekleme (Tek kayıt, her iki kullanıcı da görür)
  Future<void> _addPayment(double amount, String note) async {
    if (_userProvider.currentUser == null) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final userId = _userProvider.currentUser!.id;
      final friendId = widget.friend.userId;

      // createdByName alanının dolu olduğundan emin ol
      String finalCreatedByName = _userProvider.currentUser?.username ?? '';
      if (finalCreatedByName.isEmpty) {
        finalCreatedByName = 'Bilinmeyen Kullanıcı';
        print(
            '🔧 Ödeme createdByName boş olduğu için düzeltildi: $finalCreatedByName');
      }

      // Kategori alanının dolu olduğundan emin ol
      String finalCategory = 'Ödeme';
      print('🔧 Ödeme kategorisi: $finalCategory');

      // Tek ödeme kaydı oluştur - her iki kullanıcı da bu kaydı görecek
      await firestore.collection('userExpenses').add({
        'amount': amount,
        'description': note.isNotEmpty ? note : 'Ödeme',
        'category': finalCategory, // Düzeltilmiş kategoriyi kullan
        'date': FieldValue.serverTimestamp(),
        'debtType': 'payment',
        'createdBy': userId,
        'createdByName': finalCreatedByName, // Düzeltilmiş ismi kullan
        'expenseOwnerId': userId, // Ödemeyi yapan kişi
        'expenseId': DateTime.now().millisecondsSinceEpoch.toString(),
        'userId': userId,
        'friendId': friendId,
        'sharedWith': [userId, friendId],
      });

      print('✅ Ödeme Firebase\'e kaydedildi (tek kayıt): $amount₺');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$amount₺ ödeme eklendi'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } catch (e) {
      print('❌ Ödeme ekleme hatası: $e');
    }
  }

  double get _totalShared =>
      _sharedExpenses.fold(0, (sum, e) => sum + e.amount);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.friend.fullName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            Text(
              'ID: ${widget.friend.userId}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.blue[600],
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: 'Yenile',
              onPressed: () async {
                // Tüm verileri yenile
                await _loadSharedExpensesFromFirebase();
                await _loadNetBalanceFromFirebase();

                // UI'ı güncelle
                if (mounted) {
                  setState(() {
                    // State'i yenile
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Sayfa yenilendi'),
                      backgroundColor: Colors.blue,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  );
                }
              },
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.orange[600],
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.payment, color: Colors.white),
              tooltip: 'Ödeme Ekle',
              onPressed: _showPaymentDialog,
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.green[600],
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.add, color: Colors.white),
              tooltip: 'Alışveriş Ekle',
              onPressed: _showAddSharedExpenseDialog,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Özet kartları
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    'Net Durum',
                    '₺${_cachedNetBalance.toStringAsFixed(2)}',
                    Icons.account_balance_wallet,
                    _cachedNetBalance > 0
                        ? Colors.green
                        : _cachedNetBalance < 0
                            ? Colors.red
                            : Colors.orange,
                    _cachedNetBalance > 0
                        ? '${widget.friend.fullName} size borçlu'
                        : _cachedNetBalance < 0
                            ? 'Siz ${widget.friend.fullName}\'e borçlusunuz'
                            : 'Hesap eşit',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'Toplam Alışveriş',
                    '${_sharedExpenses.length}',
                    Icons.receipt_long,
                    Colors.blue,
                    'Ortak harcama',
                  ),
                ),
              ],
            ),
          ),

          // Alışveriş geçmişi
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.history, color: Colors.grey[700]),
                        const SizedBox(width: 8),
                        const Text(
                          'Alışveriş Geçmişi',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _sharedExpenses.isEmpty
                        ? _buildEmptyExpenseState()
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _sharedExpenses.length,
                            itemBuilder: (context, index) {
                              final expense = _sharedExpenses[index];
                              return _buildExpenseCard(expense, index);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
      String title, String value, IconData icon, Color color, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseCard(SharedExpense expense, int index) {
    final isPayment = expense.debtType == 'payment';
    final isFullDebt = expense.debtType == 'full';
    final currentUserId = _userProvider.currentUser?.id ?? '';
    final isCreatedByMe =
        expense.expenseOwnerId == currentUserId; // expenseOwnerId kullan

    // Renk belirleme: Kendi harcamam yeşil, karşı tarafın harcaması kırmızı
    final cardColor = isPayment
        ? Colors.orange[50]
        : (isCreatedByMe ? Colors.green[50] : Colors.red[50]);
    final borderColor = isPayment
        ? Colors.orange[200]!
        : (isCreatedByMe ? Colors.green[200]! : Colors.red[200]!);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isPayment
                  ? Colors.orange[50]
                  : (isCreatedByMe ? Colors.green[50] : Colors.red[50]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isPayment
                  ? Icons.payment
                  : (isCreatedByMe ? Icons.add_circle : Icons.remove_circle),
              color: isPayment
                  ? Colors.orange[600]
                  : (isCreatedByMe ? Colors.green[600] : Colors.red[600]),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        expense.description,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: kategoriRenkleri[expense.category]
                                ?.withOpacity(0.1) ??
                            Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        expense.category,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: kategoriRenkleri[expense.category] ??
                              Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${expense.date.day}.${expense.date.month}.${expense.date.year} - ${expense.createdByName}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                if (!isPayment)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isFullDebt ? Colors.red[100] : Colors.orange[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isFullDebt ? 'Hepsini yansıt' : 'Yarısını yansıt',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color:
                            isFullDebt ? Colors.red[700] : Colors.orange[700],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₺${expense.amount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isPayment
                      ? Colors.orange[600]
                      : (isCreatedByMe ? Colors.green[600] : Colors.blue[600]),
                ),
              ),
              Text(
                isPayment
                    ? 'Ödeme'
                    : (isCreatedByMe
                        ? (expense.debtType == 'full'
                            ? 'Alacak (Tam)'
                            : 'Alacak (Yarı)')
                        : (expense.debtType == 'full'
                            ? 'Borç (Tam)'
                            : 'Borç (Yarı)')),
                style: TextStyle(
                  fontSize: 10,
                  color: isPayment
                      ? Colors.orange[600]
                      : (isCreatedByMe ? Colors.green[600] : Colors.blue[600]),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyExpenseState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.receipt_long,
                size: 40,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Henüz ortak alışveriş yok',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.friend.fullName} ile ilk ortak\nalışverişinizi ekleyin',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _showAddSharedExpenseDialog,
              icon: const Icon(Icons.add),
              label: const Text('İlk Alışverişi Ekle'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Gider ekleme dialogu
class ExpenseAddDialog extends StatefulWidget {
  const ExpenseAddDialog({super.key});

  @override
  State<ExpenseAddDialog> createState() => _ExpenseAddDialogState();
}

class _ExpenseAddDialogState extends State<ExpenseAddDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String _category = kategoriler.first;
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue[400]!, Colors.blue[600]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.add_shopping_cart,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Yeni Harcama Ekle',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Form
            Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Tutar alanı
                    TextFormField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Tutar',
                        hintText: '0.00',
                        prefixIcon: const Icon(Icons.attach_money),
                        suffixText: '₺',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Tutar girin';
                        }
                        final amount =
                            double.tryParse(value.replaceAll(',', '.'));
                        if (amount == null || amount <= 0) {
                          return 'Geçerli tutar girin';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Kategori seçimi
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _category,
                          isExpanded: true,
                          items: kategoriler.map((category) {
                            return DropdownMenuItem(
                              value: category,
                              child: Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: kategoriRenkleri[category] ??
                                          Colors.grey,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(category),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _category = value!;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Tarih seçimi
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, color: Colors.blue[600]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Tarih',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${_date.day}.${_date.month}.${_date.year}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.blue[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _date,
                                firstDate: DateTime(2020),
                                lastDate:
                                    DateTime.now().add(const Duration(days: 1)),
                              );
                              if (picked != null) {
                                setState(() {
                                  _date = picked;
                                });
                              }
                            },
                            child: const Text('Değiştir'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Not alanı
                    TextFormField(
                      controller: _noteController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Not (opsiyonel)',
                        hintText: 'Harcama hakkında not ekleyin...',
                        prefixIcon: const Icon(Icons.note),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Butonlar
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('İptal'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (_formKey.currentState!.validate()) {
                                final amount = double.parse(_amountController
                                    .text
                                    .replaceAll(',', '.'));
                                Navigator.pop(
                                  context,
                                  Expense(
                                    amount: amount,
                                    category: _category,
                                    date: _date,
                                    note: _noteController.text.trim().isEmpty
                                        ? null
                                        : _noteController.text.trim(),
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[600],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Ekle'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase başlatma
  bool firebaseInitialized = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Firebase başarıyla başlatıldı!');
    firebaseInitialized = true;

    // Firebase bağlantısını test et
    try {
      final firestore = FirebaseFirestore.instance;
      await firestore.collection('test').doc('test').get();
      print('✅ Firebase Firestore bağlantısı başarılı!');
    } catch (e) {
      print(
          '⚠️ Firebase Firestore bağlantısı başarısız, test modunda devam ediliyor: $e');
    }
  } catch (e) {
    print('❌ Firebase başlatma hatası: $e');
    print('⚠️ Uygulama Firebase olmadan devam ediyor...');
    firebaseInitialized = false;
  }

  // Global Firebase durumunu sakla
  globalFirebaseInitialized = firebaseInitialized;

  runApp(const KashiApp());
}

// Global Firebase durumu
bool globalFirebaseInitialized = false;
