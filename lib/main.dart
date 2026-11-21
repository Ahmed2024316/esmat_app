import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

class Medicine {
  final int id;
  final String name;
  final int hour;
  final int minute;
  final String? imagePath;

  Medicine({
    required this.id,
    required this.name,
    required this.hour,
    required this.minute,
    this.imagePath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'hour': hour,
        'minute': minute,
        'imagePath': imagePath,
      };

  factory Medicine.fromJson(Map<String, dynamic> json) => Medicine(
        id: json['id'],
        name: json['name'],
        hour: json['hour'],
        minute: json['minute'],
        imagePath: json['imagePath'],
      );
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

  Future<void> _scheduleDailyAlarm(Medicine med) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, med.hour, med.minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    BigPictureStyleInformation? bigPictureStyle;
    if (med.imagePath != null && File(med.imagePath!).existsSync()) {
      bigPictureStyle = BigPictureStyleInformation(
        FilePathAndroidBitmap(med.imagePath!),
        contentTitle: 'Esmat | ميعاد الدواء: ${med.name}',
        summaryText: 'اضغط لتأكيد أخذ الجرعة',
      );
    }

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'esmat_medicine_alarm_v1',
      'Esmat - منبه الأدوية',
      channelDescription: 'تنبيهات مواعيد الأدوية اليومية',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      styleInformation: bigPictureStyle,
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      med.id,
      'Esmat | حآن ميعاد الدواء 💊',
      'اسم الدواء: ${med.name}',
      scheduledDate,
      NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> _deleteMedicine(int index) async {
    final med = medicines[index];
    await flutterLocalNotificationsPlugin.cancel(med.id);
    setState(() {
      medicines.removeAt(index);
    });
    await _saveMedicines();
  }

  String _formatTime(int hour, int minute) {
    final period = hour >= 12 ? 'مساءً' : 'صباحاً';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    final displayMin = minute.toString().padLeft(2, '0');
    return '$displayHour:$displayMin $period';
  }

  void _showAddMedicineSheet() {
    final nameController = TextEditingController();
    TimeOfDay selectedTime = TimeOfDay.now();
    String? pickedImagePath;

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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'إضافة دواء جديد',
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
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.access_time),
                  label: Text(
                    'الميعاد: ${_formatTime(selectedTime.hour, selectedTime.minute)}',
                    style: const TextStyle(fontSize: 16),
                  ),
                  onPressed: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: selectedTime,
                    );
                    if (time != null) {
                      setModalState(() => selectedTime = time);
                    }
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('تصوير الدواء'),
                        onPressed: () async {
                          final picker = ImagePicker();
                          final img = await picker.pickImage(
                              source: ImageSource.camera);
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
                              source: ImageSource.gallery);
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
                      height: 120,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty) return;
                    final newMed = Medicine(
                      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                      name: nameController.text.trim(),
                      hour: selectedTime.hour,
                      minute: selectedTime.minute,
                      imagePath: pickedImagePath,
                    );
                    setState(() {
                      medicines.add(newMed);
                    });
                    await _saveMedicines();
                    await _scheduleDailyAlarm(newMed);
                    if (mounted) Navigator.pop(context);
                  },
                  child: const Text('حفظ وتشغيل المنبه',
                      style: TextStyle(fontSize: 16)),
                ),
              ],
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
      ),
      body: medicines.isEmpty
          ? const Center(
              child: Text(
                'أهلاً بك في تطبيق Esmat\nمفيش أدوية متسجلة حالياً\nاضغط على (+) لإضافة دواء جديد',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: medicines.length,
              itemBuilder: (context, index) {
                final med = medicines[index];
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
                            child: const Icon(Icons.medication,
                                color: Colors.teal, size: 32),
                          ),
                    title: Text(
                      med.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    subtitle: Text(
                      'يومياً الساعة: ${_formatTime(med.hour, med.minute)}',
                      style:
                          TextStyle(color: Colors.teal.shade700, fontSize: 15),
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
