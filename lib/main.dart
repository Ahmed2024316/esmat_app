import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initNotifications();
  runApp(const EsmatMedicineApp());
}

Future<void> _initNotifications() async {
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Africa/Cairo'));

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) async {
      if (response.id != null) {
        await flutterLocalNotificationsPlugin.cancel(response.id!);
      }
    },
  );
}

class DoseTime {
  final int hour;
  final int minute;

  DoseTime({required this.hour, required this.minute});

  Map<String, dynamic> toJson() => {'hour': hour, 'minute': minute};

  factory DoseTime.fromJson(Map<String, dynamic> json) =>
      DoseTime(hour: json['hour'], minute: json['minute']);
}

class Medicine {
  final int id;
  final String name;
  final String type;
  final String dosageAmount;
  final List<DoseTime> doseTimes;
  final String? imagePath;

  Medicine({
    required this.id,
    required this.name,
    required this.type,
    required this.dosageAmount,
    required this.doseTimes,
    this.imagePath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'dosageAmount': dosageAmount,
        'doseTimes': doseTimes.map((e) => e.toJson()).toList(),
        'imagePath': imagePath,
      };

  factory Medicine.fromJson(Map<String, dynamic> json) {
    List<DoseTime> parsedTimes = [];
    if (json['doseTimes'] != null) {
      parsedTimes = (json['doseTimes'] as List)
          .map((e) => DoseTime.fromJson(e))
          .toList();
    } else if (json['hour'] != null && json['minute'] != null) {
      parsedTimes = [DoseTime(hour: json['hour'], minute: json['minute'])];
    }

    return Medicine(
      id: json['id'],
      name: json['name'],
      type: json['type'] ?? 'أقراص',
      dosageAmount: json['dosageAmount'] ?? 'جرعة واحدة',
      doseTimes: parsedTimes,
      imagePath: json['imagePath'],
    );
  }
}

class EsmatMedicineApp extends StatelessWidget {
  const EsmatMedicineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Esmat - منبه الدواء',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const Directionality(
              textDirection: TextDirection.rtl,
              child: HomeScreen(),
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.teal.shade800,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.medication_liquid,
                size: 80,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'ESMAT',
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'منبه وتنظيم مواعيد الأدوية',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Medicine> medicines = [];

  final List<String> medicineTypes = [
    'أقراص',
    'كبسولات',
    'شراب',
    'حقن',
    'نقط',
    'مرهم / كريم',
    'فوار',
    'بخاخ',
  ];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadMedicines();
  }

  Future<void> _requestPermissions() async {
    await Permission.notification.request();
    if (await Permission.scheduleExactAlarm.isDenied) {
      await Permission.scheduleExactAlarm.request();
    }
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  Future<void> _loadMedicines() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('medicines_list');
    if (data != null) {
      final List decoded = jsonDecode(data);
      setState(() {
        medicines = decoded.map((e) => Medicine.fromJson(e)).toList();
      });
    }
  }

  Future<void> _saveMedicines() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded =
        jsonEncode(medicines.map((e) => e.toJson()).toList());
    await prefs.setString('medicines_list', encoded);
  }

  AndroidNotificationDetails _buildAlarmNotificationDetails({
    required String medName,
    required String medType,
    required String dosageAmount,
    required int doseNumber,
    required int totalDoses,
    String? imagePath,
  }) {
    BigPictureStyleInformation? bigPictureStyle;
    if (imagePath != null && File(imagePath).existsSync()) {
      bigPictureStyle = BigPictureStyleInformation(
        FilePathAndroidBitmap(imagePath),
        contentTitle: '⏰ منبه الدواء: $medName ($medType)',
        summaryText: 'الجرعة $doseNumber من $totalDoses \vert{} المقدار: $dosageAmount',
      );
    }

    return AndroidNotificationDetails(
      'esmat_ringtone_alarm_channel_v2',
      'Esmat - رنة منبه الأدوية',
      channelDescription: 'تنبيهات برنة منبه مستمرة لمواعيد الأدوية',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      additionalFlags: Int32List.fromList([4]),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      styleInformation: bigPictureStyle,
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(
          'confirm_dose',
          '✅ تم أخذ الجرعة (إيقاف الرنة)',
          cancelNotification: true,
          showsUserInterface: true,
        ),
      ],
    );
