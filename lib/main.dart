import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final AudioPlayer globalAlarmPlayer = AudioPlayer();

String? pendingAlarmPayload;
bool isAlarmScreenOpen = false;

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  if (response.payload != null && response.payload!.isNotEmpty) {
    pendingAlarmPayload = response.payload;
  }
}

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

  final launchDetails =
      await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
  if (launchDetails != null &&
      launchDetails.didNotificationLaunchApp &&
      launchDetails.notificationResponse?.payload != null) {
    pendingAlarmPayload = launchDetails.notificationResponse!.payload;
  }

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) async {
      if (response.id != null) {
        await flutterLocalNotificationsPlugin.cancel(response.id!);
      }
      if (response.actionId == 'confirm_dose') {
        await globalAlarmPlayer.stop();
        return;
      }
      if (response.payload != null && response.payload!.isNotEmpty) {
        _openIncomingCallAlarmScreen(response.payload!);
      }
    },
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );
}

void _openIncomingCallAlarmScreen(String payload) {
  if (isAlarmScreenOpen) return;
  try {
    final Map<String, dynamic> data = jsonDecode(payload);
    isAlarmScreenOpen = true;
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: IncomingCallAlarmScreen(
            medId: data['id'] ?? 1000,
            medName: data['name'] ?? 'الدواء',
            medType: data['type'] ?? 'أقراص',
            dosageAmount: data['dosageAmount'] ?? 'جرعة واحدة',
            doseInfo: data['doseInfo'] ?? '',
            imagePath: data['imagePath'],
            ringtonePath: data['ringtonePath'],
          ),
        ),
      ),
    ).then((_) {
      isAlarmScreenOpen = false;
    });
  } catch (_) {
    isAlarmScreenOpen = false;
  }
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
  final String? ringtonePath;
  final String? ringtoneName;

  Medicine({
    required this.id,
    required this.name,
    required this.type,
    required this.dosageAmount,
    required this.doseTimes,
    this.imagePath,
    this.ringtonePath,
    this.ringtoneName,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'dosageAmount': dosageAmount,
        'doseTimes': doseTimes.map((e) => e.toJson()).toList(),
        'imagePath': imagePath,
        'ringtonePath': ringtonePath,
        'ringtoneName': ringtoneName,
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
      id: json['id'] is int
          ? json['id'] % 90000
          : Random().nextInt(80000) + 1000,
      name: json['name'] ?? '',
      type: json['type'] ?? 'أقراص',
      dosageAmount: json['dosageAmount'] ?? 'جرعة واحدة',
      doseTimes: parsedTimes,
      imagePath: json['imagePath'],
      ringtonePath: json['ringtonePath'],
      ringtoneName: json['ringtoneName'],
    );
  }
}

class EsmatMedicineApp extends StatelessWidget {
  const EsmatMedicineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
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
    Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const Directionality(
            textDirection: TextDirection.rtl,
            child: HomeScreen(),
          ),
        ),
      );
      if (pendingAlarmPayload != null) {
        final payload = pendingAlarmPayload!;
        pendingAlarmPayload = null;
        Future.delayed(const Duration(milliseconds: 150), () {
          _openIncomingCallAlarmScreen(payload);
        });
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

/// واجهة تشبه شاشة الاتصال الوارد (قبول / كنسلة أو تأجيل) مع صورة الدواء والنغمة المحددة
class IncomingCallAlarmScreen extends StatefulWidget {
  final int medId;
  final String medName;
  final String medType;
  final String dosageAmount;
  final String doseInfo;
  final String? imagePath;
  final String? ringtonePath;

  const IncomingCallAlarmScreen({
    super.key,
    required this.medId,
    required this.medName,
    required this.medType,
    required this.dosageAmount,
    required this.doseInfo,
    this.imagePath,
    this.ringtonePath,
  });

  @override
  State<IncomingCallAlarmScreen> createState() =>
      _IncomingCallAlarmScreenState();
}

class _IncomingCallAlarmScreenState extends State<IncomingCallAlarmScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  Timer? _vibrationTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _startRingtoneAndVibration();
  }

  Future<void> _startRingtoneAndVibration() async {
    // اهتزاز متكرر مثل المكالمة الواردة
    HapticFeedback.heavyImpact();
    _vibrationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      HapticFeedback.heavyImpact();
    });

    try {
      await globalAlarmPlayer.stop();
      await globalAlarmPlayer.setReleaseMode(ReleaseMode.loop);
      await globalAlarmPlayer.setVolume(1.0);
      await globalAlarmPlayer.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.alarm,
            audioFocus: AndroidAudioFocus.gain,
          ),
        ),
      );

      if (widget.ringtonePath != null &&
          File(widget.ringtonePath!).existsSync()) {
        await globalAlarmPlayer.play(DeviceFileSource(widget.ringtonePath!));
      }
    } catch (_) {}
  }

  Future<void> _acceptDose() async {
    _vibrationTimer?.cancel();
    await globalAlarmPlayer.stop();
    await flutterLocalNotificationsPlugin.cancelAll();
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text('✅ بالشفاء العاجل! تم تسجيل أخذ ${widget.medName}'),
        ),
      );
    }
  }

  Future<void> _snoozeOrCancelDose() async {
    _vibrationTimer?.cancel();
    await globalAlarmPlayer.stop();
    await flutterLocalNotificationsPlugin.cancelAll();

    // إعادة التذكير بعد 10 دقائق تلقائياً
    final snoozeTime =
        tz.TZDateTime.now(tz.local).add(const Duration(minutes: 10));
    final payload = jsonEncode({
      'id': widget.medId,
      'name': widget.medName,
      'type': widget.medType,
      'dosageAmount': widget.dosageAmount,
      'doseInfo': 'تذكير مؤجل (بعد 10 دقائق)',
      'imagePath': widget.imagePath,
      'ringtonePath': widget.ringtonePath,
    });

    final androidDetails = AndroidNotificationDetails(
      'esmat_call_alarm_v10',
      'Esmat - مكالمة منبه الدواء',
      channelDescription: 'تنبيهات مواعيد الأدوية بواجهة اتصال',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      additionalFlags: Int32List.fromList([4]),
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      99999,
      '📞 تذكير مؤجل: ${widget.medName}',
      'حان موعد أخذ الجرعة (${widget.dosageAmount})',
      snoozeTime,
      NotificationDetails(android: androidDetails),
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔕 تم تأجيل المنبه وسيعاود الرنين بعد 10 دقائق'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _vibrationTimer?.cancel();
    _pulseController.dispose();
    globalAlarmPlayer.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasImage =
        widget.imagePath != null && File(widget.imagePath!).existsSync();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0A2E2A),
              Color(0xFF061A18),
              Color(0xFF000000),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // الجزء العلوي: شارة مكالمة دواء واردة + اسم الدواء
                Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.tealAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                            color: Colors.tealAccent.withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.phone_in_talk,
                              color: Colors.tealAccent, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'منبه موعد الدواء...',
                            style: TextStyle(
                              color: Colors.tealAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      widget.medName,
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${widget.medType}  •  ${widget.dosageAmount}',
                      style: const TextStyle(
                        fontSize: 22,
                        color: Colors.amberAccent,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (widget.doseInfo.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.doseInfo,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ],
                ),

                // المنتصف: صورة علبة الدواء بإطار نبّاض مثل صورة المتصل
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final scale = 1.0 + (_pulseController.value * 0.06);
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 240,
                        height: 240,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.tealAccent.withValues(
                                  alpha: 0.25 + (_pulseController.value * 0.25)),
                              blurRadius: 30,
                              spreadRadius: 8,
                            ),
                          ],
                          border: Border.all(
                            color: Colors.tealAccent,
                            width: 4,
                          ),
                        ),
                        child: ClipOval(
                          child: hasImage
                              ? Image.file(
                                  File(widget.imagePath!),
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  color: Colors.teal.shade900,
                                  child: const Icon(
                                    Icons.medication,
                                    size: 110,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    );
                  },
                ),

                // الأسفل: أزرار الرد (تم أخذ الجرعة) والكنسلة (تأجيل 10 دقائق) مثل شاشة الاتصال
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      // زر الكنسلة / التأجيل (أحمر)
                      Column(
                        children: [
                          GestureDetector(
                            onTap: _snoozeOrCancelDose,
                            child: Container(
                              width: 78,
                              height: 78,
                              decoration: BoxDecoration(
                                color: Colors.red.shade600,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withValues(alpha: 0.4),
                                    blurRadius: 16,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.call_end,
                                color: Colors.white,
                                size: 38,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'تأجيل 10 د',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      // زر القبول / تم أخذ الجرعة (أخضر)
                      Column(
                        children: [
                          GestureDetector(
                            onTap: _acceptDose,
                            child: Container(
                              width: 78,
                              height: 78,
                              decoration: BoxDecoration(
                                color: Colors.green.shade500,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.green.withValues(alpha: 0.5),
                                    blurRadius: 20,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 42,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'تم أخذ الجرعة',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<Medicine> medicines = [];
  Timer? _foregroundAlarmTimer;
  String? _lastTriggeredKey;

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
    WidgetsBinding.instance.addObserver(this);
    _requestAllPermissions();
    _loadMedicines();
    _startForegroundWatcher();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkIfDoseJustArrived();
    }
  }

  /// فحص فوري عند فتح التطبيق من شاشة القفل لفتح واجهة الاتصال مباشرة
  void _checkIfDoseJustArrived() {
    final now = DateTime.now();
    for (final med in medicines) {
      for (int i = 0; i < med.doseTimes.length; i++) {
        final dose = med.doseTimes[i];
        if (now.hour == dose.hour &&
            (now.minute == dose.minute || now.minute == (dose.minute + 1) % 60)) {
          final key = '${med.id}_${now.day}_${dose.hour}_${dose.minute}';
          if (_lastTriggeredKey != key) {
            _lastTriggeredKey = key;
            _openIncomingCallAlarmScreen(jsonEncode({
              'id': med.id,
              'name': med.name,
              'type': med.type,
              'dosageAmount': med.dosageAmount,
              'doseInfo': 'الجرعة ${i + 1} من ${med.doseTimes.length}',
              'imagePath': med.imagePath,
              'ringtonePath': med.ringtonePath,
            }));
          }
        }
      }
    }
  }

  void _startForegroundWatcher() {
    _foregroundAlarmTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      for (final med in medicines) {
        for (int i = 0; i < med.doseTimes.length; i++) {
          final dose = med.doseTimes[i];
          if (now.hour == dose.hour &&
              now.minute == dose.minute &&
              now.second < 3) {
            final key = '${med.id}_${now.day}_${now.hour}_${now.minute}';
            if (_lastTriggeredKey != key) {
              _lastTriggeredKey = key;
              _openIncomingCallAlarmScreen(jsonEncode({
                'id': med.id,
                'name': med.name,
                'type': med.type,
                'dosageAmount': med.dosageAmount,
                'doseInfo': 'الجرعة ${i + 1} من ${med.doseTimes.length}',
                'imagePath': med.imagePath,
                'ringtonePath': med.ringtonePath,
              }));
            }
          }
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _foregroundAlarmTimer?.cancel();
    super.dispose();
  }

  Future<void> _requestAllPermissions() async {
    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
    await androidPlugin?.requestFullScreenIntentPermission();

    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  Future<void> _loadMedicines() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('medicines_list');
    if (data != null) {
      final List decoded = jsonDecode(data);
      if (mounted) {
        setState(() {
          medicines = decoded.map((e) => Medicine.fromJson(e)).toList();
        });
      }
    }
  }

  Future<void> _saveMedicines() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded =
        jsonEncode(medicines.map((e) => e.toJson()).toList());
    await prefs.setString('medicines_list', encoded);
  }

  Future<String> _saveFilePermanently(String sourcePath, String prefix) async {
    final dir = await getApplicationDocumentsDirectory();
    final ext = sourcePath.split('.').last;
    final destPath =
        '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final copied = await File(sourcePath).copy(destPath);
    return copied.path;
  }

  AndroidNotificationDetails _buildAlarmDetails({
    required String medName,
    required String medType,
    required String dosageAmount,
    required int doseNumber,
    required int totalDoses,
    String? imagePath,
  }) {
    BigPictureStyleInformation? bigPictureStyle;
    FilePathAndroidBitmap? largeIconBitmap;

    if (imagePath != null && File(imagePath).existsSync()) {
      final bitmap = FilePathAndroidBitmap(imagePath);
      largeIconBitmap = bitmap;
      bigPictureStyle = BigPictureStyleInformation(
        bitmap,
        largeIcon: bitmap,
        contentTitle: '📞 موعد الدواء: $medName ($medType)',
        summaryText: 'الجرعة $doseNumber من $totalDoses | المقدار: $dosageAmount',
      );
    }

    return AndroidNotificationDetails(
      'esmat_call_alarm_v10',
      'Esmat - مكالمة منبه الدواء',
      channelDescription: 'تنبيهات مواعيد الأدوية بواجهة اتصال وصورة الدواء',
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
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      largeIcon: largeIconBitmap,
      styleInformation: bigPictureStyle,
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(
          'open_alarm',
          '📞 فتح شاشة الدواء',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'confirm_dose',
          '✅ تم أخذ الجرعة',
          cancelNotification: true,
          showsUserInterface: true,
        ),
      ],
    );
  }

  Future<void> _scheduleMedicineDoses(Medicine med) async {
    final now = tz.TZDateTime.now(tz.local);

    for (int i = 0; i < med.doseTimes.length; i++) {
      final dose = med.doseTimes[i];
      final int notificationId = (med.id * 10) + i;

      var scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        dose.hour,
        dose.minute,
      );
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      final payload = jsonEncode({
        'id': med.id,
        'name': med.name,
        'type': med.type,
        'dosageAmount': med.dosageAmount,
        'doseInfo': 'الجرعة ${i + 1} من ${med.doseTimes.length}',
        'imagePath': med.imagePath,
        'ringtonePath': med.ringtonePath,
      });

      final androidDetails = _buildAlarmDetails(
        medName: med.name,
        medType: med.type,
        dosageAmount: med.dosageAmount,
        doseNumber: i + 1,
        totalDoses: med.doseTimes.length,
        imagePath: med.imagePath,
      );

      await flutterLocalNotificationsPlugin.zonedSchedule(
        notificationId,
        '📞 موعد الدواء: ${med.name}',
        'النوع: ${med.type} | الجرعة ${i + 1} من ${med.doseTimes.length} (${med.dosageAmount})',
        scheduledDate,
        NotificationDetails(android: androidDetails),
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  Future<void> _testAlarmNow() async {
    final lastMed = medicines.isNotEmpty ? medicines.last : null;
    _openIncomingCallAlarmScreen(jsonEncode({
      'id': lastMed?.id ?? 1000,
      'name': lastMed?.name ?? 'تجربة مكالمة الدواء',
      'type': lastMed?.type ?? 'أقراص',
      'dosageAmount': lastMed?.dosageAmount ?? 'قرص واحد',
      'doseInfo': 'معاينة شاشة الاتصال والصورة والنغمة',
      'imagePath': lastMed?.imagePath,
      'ringtonePath': lastMed?.ringtonePath,
    }));
  }

  Future<void> _deleteMedicine(int index) async {
    final med = medicines[index];
    setState(() {
      medicines.removeAt(index);
    });
    await _saveMedicines();

    try {
      for (int i = 0; i < 10; i++) {
        await flutterLocalNotificationsPlugin.cancel((med.id * 10) + i);
      }
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حذف ${med.name}')),
      );
    }
  }

  String _formatTime(int hour, int minute) {
    final period = hour >= 12 ? 'مساءً' : 'صباحاً';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    final displayMin = minute.toString().padLeft(2, '0');
    return '$displayHour:$displayMin $period';
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'شراب':
        return Icons.liquor;
      case 'حقن':
        return Icons.vaccines;
      case 'نقط':
        return Icons.water_drop;
      case 'مرهم / كريم':
        return Icons.healing;
      case 'فوار':
        return Icons.local_drink;
      case 'بخاخ':
        return Icons.air;
      default:
        return Icons.medication;
    }
  }

  void _showAddMedicineSheet() {
    final nameController = TextEditingController();
    final amountController = TextEditingController(text: 'قرص واحد');
    String selectedType = medicineTypes.first;
    int dosesCount = 1;
    List<TimeOfDay> selectedTimes = [TimeOfDay.now()];
    String? pickedImagePath;
    String? pickedRingtonePath;
    String? pickedRingtoneName;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'إضافة دواء وجرعاته',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم الدواء',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.medication),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedType,
                          decoration: const InputDecoration(
                            labelText: 'نوع الدواء',
                            border: OutlineInputBorder(),
                          ),
                          items: medicineTypes
                              .map((type) => DropdownMenuItem(
                                    value: type,
                                    child: Text(type),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() {
                                selectedType = val;
                                if (val == 'شراب') {
                                  amountController.text = '5 مل (ملعقة)';
                                } else if (val == 'نقط') {
                                  amountController.text = '5 نقط';
                                } else if (val == 'حقن') {
                                  amountController.text = 'حقنة واحدة';
                                } else {
                                  amountController.text = 'قرص واحد';
                                }
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: amountController,
                          decoration: const InputDecoration(
                            labelText: 'مقدار الجرعة',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: dosesCount,
                    decoration: const InputDecoration(
                      labelText: 'عدد الجرعات في اليوم',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.repeat),
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('جرعة واحدة يومياً')),
                      DropdownMenuItem(value: 2, child: Text('جرعتين يومياً (كل 12 ساعة)')),
                      DropdownMenuItem(value: 3, child: Text('3 جرعات يومياً (كل 8 ساعات)')),
                      DropdownMenuItem(value: 4, child: Text('4 جرعات يومياً (كل 6 ساعات)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() {
                          dosesCount = val;
                          final baseHour = selectedTimes.first.hour;
                          final baseMin = selectedTimes.first.minute;
                          final stepHours = 24 ~/ val;
                          selectedTimes = List.generate(
                            val,
                            (index) => TimeOfDay(
                              hour: (baseHour + (index * stepHours)) % 24,
                              minute: baseMin,
                            ),
                          );
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'مواعيد الجرعات (اضغط لتعديل أي ميعاد):',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(dosesCount, (i) {
                    final t = selectedTimes[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.alarm, color: Colors.teal),
                        label: Text(
                          'الجرعة ${i + 1}: ${_formatTime(t.hour, t.minute)}',
                          style: const TextStyle(fontSize: 16),
                        ),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: t,
                          );
                          if (picked != null) {
                            setModalState(() {
                              selectedTimes[i] = picked;
                            });
                          }
                        },
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.music_note, color: Colors.deepOrange),
                    label: Text(
                      pickedRingtoneName != null
                          ? 'النغمة: $pickedRingtoneName'
                          : 'إضافة نغمة من الجهاز (اختياري)',
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.audio,
                      );
                      if (result != null && result.files.single.path != null) {
                        final savedAudio = await _saveFilePermanently(
                            result.files.single.path!, 'ringtone');
                        setModalState(() {
                          pickedRingtonePath = savedAudio;
                          pickedRingtoneName = result.files.single.name;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('تصوير الدواء'),
                          onPressed: () async {
                            final picker = ImagePicker();
                            final img = await picker.pickImage(
                                source: ImageSource.camera, imageQuality: 70);
                            if (img != null) {
                              final savedImg = await _saveFilePermanently(
                                  img.path, 'med_img');
                              setModalState(() => pickedImagePath = savedImg);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.photo_library),
                          label: const Text('من الاستوديو'),
                          onPressed: () async {
                            final picker = ImagePicker();
                            final img = await picker.pickImage(
                                source: ImageSource.gallery, imageQuality: 70);
                            if (img != null) {
                              final savedImg = await _saveFilePermanently(
                                  img.path, 'med_img');
                              setModalState(() => pickedImagePath = savedImg);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  if (pickedImagePath != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        File(pickedImagePath!),
                        height: 100,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: isSaving
                        ? null
                        : () async {
                            if (nameController.text.trim().isEmpty) return;
                            setModalState(() => isSaving = true);

                            final safeId = Random().nextInt(80000) + 1000;
                            final newMed = Medicine(
                              id: safeId,
                              name: nameController.text.trim(),
                              type: selectedType,
                              dosageAmount: amountController.text.trim().isEmpty
                                  ? 'جرعة واحدة'
                                  : amountController.text.trim(),
                              doseTimes: selectedTimes
                                  .map((t) =>
                                      DoseTime(hour: t.hour, minute: t.minute))
                                  .toList(),
                              imagePath: pickedImagePath,
                              ringtonePath: pickedRingtonePath,
                              ringtoneName: pickedRingtoneName,
                            );

                            setState(() {
                              medicines.add(newMed);
                            });
                            await _saveMedicines();

                            try {
                              await _scheduleMedicineDoses(newMed);
                            } catch (_) {}

                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'تم حفظ منبه ${newMed.name} (${newMed.doseTimes.length} جرعات)'),
                                ),
                              );
                            }
                          },
                    child: Text(
                      isSaving ? 'جاري الحفظ...' : 'حفظ وتشغيل منبه الجرعات',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Esmat | مواعيد الأدوية'),
        centerTitle: true,
        backgroundColor: Colors.teal.shade700,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'إعدادات الأذونات',
          icon: const Icon(Icons.settings),
          onPressed: () async {
            await _requestAllPermissions();
            await openAppSettings();
          },
        ),
        actions: [
          IconButton(
            tooltip: 'تجربة واجهة الاتصال الآن',
            icon: const Icon(Icons.phone_in_talk),
            onPressed: _testAlarmNow,
          ),
        ],
      ),
      body: medicines.isEmpty
          ? const Center(
              child: Text(
                'أهلاً بك في تطبيق Esmat\nمفيش أدوية متسجلة حالياً\nاضغط على (+) لإضافة دواء وجرعاته',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: medicines.length,
              itemBuilder: (context, index) {
                final med = medicines[index];
                final timesSummary = med.doseTimes
                    .asMap()
                    .entries
                    .map((e) =>
                        'ج${e.key + 1}: ${_formatTime(e.value.hour, e.value.minute)}')
                    .join('  •  ');

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    onTap: () {
                      _openIncomingCallAlarmScreen(jsonEncode({
                        'id': med.id,
                        'name': med.name,
                        'type': med.type,
                        'dosageAmount': med.dosageAmount,
                        'doseInfo': 'معاينة شاشة الاتصال والنغمة',
                        'imagePath': med.imagePath,
                        'ringtonePath': med.ringtonePath,
                      }));
                    },
                    leading: med.imagePath != null &&
                            File(med.imagePath!).existsSync()
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(med.imagePath!),
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.teal.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(_getTypeIcon(med.type),
                                color: Colors.teal, size: 32),
                          ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            med.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${med.type} • ${med.doseTimes.length} جرعات',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.teal.shade800,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'المقدار: ${med.dosageAmount}',
                            style: const TextStyle(
                                fontSize: 14, color: Colors.black87),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            timesSummary,
                            style: TextStyle(
                              color: Colors.teal.shade700,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (med.ringtoneName != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '🎵 النغمة: ${med.ringtoneName}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.deepOrange),
                            ),
                          ],
                        ],
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteMedicine(index),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddMedicineSheet,
        backgroundColor: Colors.teal.shade700,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('إضافة دواء'),
      ),
    );
  }
}
