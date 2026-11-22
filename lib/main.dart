import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
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
      id: json['id'] is int ? json['id'] % 100000 : Random().nextInt(90000) + 1000,
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
    Timer(const Duration(milliseconds: 1200), () {
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
    _requestAllRequiredPermissions();
    _loadMedicines();
  }

  Future<void> _requestAllRequiredPermissions() async {
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

  AndroidNotificationDetails _buildAlarmNotificationDetails({
    required String channelKey,
    required String medName,
    required String medType,
    required String dosageAmount,
    required int doseNumber,
    required int totalDoses,
    String? imagePath,
    String? ringtonePath,
  }) {
    BigPictureStyleInformation? bigPictureStyle;
    if (imagePath != null && File(imagePath).existsSync()) {
      bigPictureStyle = BigPictureStyleInformation(
        FilePathAndroidBitmap(imagePath),
        contentTitle: '⏰ منبه الدواء: $medName ($medType)',
        summaryText: 'الجرعة $doseNumber من $totalDoses | المقدار: $dosageAmount',
      );
    }

    AndroidNotificationSound? customSound;
    String channelId = 'esmat_alarm_default_v3';
    String channelName = 'Esmat - منبه الأدوية';

    if (ringtonePath != null && File(ringtonePath).existsSync()) {
      customSound = UriAndroidNotificationSound(Uri.file(ringtonePath).toString());
      channelId = 'esmat_alarm_custom_$channelKey';
      channelName = 'Esmat - منبه $medName';
    }

    return AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'تنبيهات مواعيد الأدوية برنة منبه',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: customSound,
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
          '✅ تم أخذ الجرعة (إيقاف)',
          cancelNotification: true,
          showsUserInterface: true,
        ),
      ],
    );
  }

  Future<void> _scheduleAllDosesForMedicine(Medicine med) async {
    await _requestAllRequiredPermissions();
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

      final androidDetails = _buildAlarmNotificationDetails(
        channelKey: '${med.id}_${med.ringtonePath.hashCode}',
        medName: med.name,
        medType: med.type,
        dosageAmount: med.dosageAmount,
        doseNumber: i + 1,
        totalDoses: med.doseTimes.length,
        imagePath: med.imagePath,
        ringtonePath: med.ringtonePath,
      );

      await flutterLocalNotificationsPlugin.zonedSchedule(
        notificationId,
        '⏰ منبه الدواء: ${med.name}',
        'النوع: ${med.type} | الجرعة ${i + 1} من ${med.doseTimes.length} (${med.dosageAmount})',
        scheduledDate,
        NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  Future<void> _testAlarmNow() async {
    await _requestAllRequiredPermissions();
    final lastMed = medicines.isNotEmpty ? medicines.last : null;
    final androidDetails = _buildAlarmNotificationDetails(
      channelKey: lastMed != null ? '${lastMed.id}_${lastMed.ringtonePath.hashCode}' : 'test',
      medName: lastMed?.name ?? 'تجربة المنبه',
      medType: lastMed?.type ?? 'أقراص',
      dosageAmount: lastMed?.dosageAmount ?? 'قرص واحد',
      doseNumber: 1,
      totalDoses: 1,
      ringtonePath: lastMed?.ringtonePath,
    );

    await flutterLocalNotificationsPlugin.show(
      88888,
      '⏰ تجربة منبه Esmat',
      'اضغط "تم أخذ الجرعة" لإيقاف الرنة',
      NotificationDetails(android: androidDetails),
    );
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
        SnackBar(content: Text('تم حذف ${med.name} وإلغاء منبهاته')),
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
                          : 'اختيار نغمة رنين من الجهاز (اختياري)',
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.audio,
                      );
                      if (result != null && result.files.single.path != null) {
                        setModalState(() {
                          pickedRingtonePath = result.files.single.path;
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
                                source: ImageSource.camera,
                                imageQuality: 70);
                            if (img != null) {
                              setModalState(() => pickedImagePath = img.path);
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
                                source: ImageSource.gallery,
                                imageQuality: 70);
                            if (img != null) {
                              setModalState(() => pickedImagePath = img.path);
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

                            final safeId = Random().nextInt(90000) + 1000;
                            final newMed = Medicine(
                              id: safeId,
                              name: nameController.text.trim(),
                              type: selectedType,
                              dosageAmount: amountController.text.trim().isEmpty
                                  ? 'جرعة واحدة'
                                  : amountController.text.trim(),
                              doseTimes: selectedTimes
                                  .map((t) => DoseTime(hour: t.hour, minute: t.minute))
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
                              await _scheduleAllDosesForMedicine(newMed);
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'تم الحفظ، تأكد من تفعيل إذن التنبيهات الدقيقة من إعدادات الهاتف',
                                    ),
                                  ),
                                );
                              }
                            }

                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'تم ضبط منبه ${newMed.name} (${newMed.doseTimes.length} جرعات)'),
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
          tooltip: 'تفعيل أذونات المنبه',
          icon: const Icon(Icons.security),
          onPressed: () async {
            await _requestAllRequiredPermissions();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('تم طلب أذونات المنبه والعمل في الخلفية')),
              );
            }
          },
        ),
        actions: [
          IconButton(
            tooltip: 'تجربة رنة المنبه الآن',
            icon: const Icon(Icons.notifications_active),
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
