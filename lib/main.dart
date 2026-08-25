import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// warna spedometer
class AppColors {
  static const bg = Color(0xFF14171C);
  static const surface = Color(0xFF1E232B);
  static const surfaceRaised = Color(0xFF262C35);
  static const cool = Color(0xFF4FB8E8);
  static const warm = Color(0xFFFF7A45);
  static const danger = Color(0xFFFF4D4D);
  static const textPrimary = Color(0xFFE8ECF1);
  static const textMuted = Color(0xFF8A93A3);
  static const divider = Color(0xFF2E3541);
}

// atur warta sesuai suhu (0.0 = min, 1.0 = max)
Color suhuKeWarna(double t) {
  t = t.clamp(0.0, 1.0);
  if (t < 0.5) {
    return Color.lerp(AppColors.cool, const Color(0xFFB6D94F), t * 2)!;
  }
  return Color.lerp(const Color(0xFFB6D94F), AppColors.warm, (t - 0.5) * 2)!;
}

// notifikasi latar belakang
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  final localNotif = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await localNotif.initialize(initSettings);

  final judul = message.data['title'];
  final isi = message.data['body'];

  if (judul != null && isi != null) {
    await localNotif.show(
      0,
      judul,
      isi,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'suhu_alert',
          'Peringatan Suhu',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(
            isi,
            contentTitle: judul,
            htmlFormatContentTitle: false,
            htmlFormatBigText: false,
          ),
        ),
      ),
    );
  }
}

final FlutterLocalNotificationsPlugin _localNotif =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await _localNotif.initialize(initSettings);

  await FirebaseMessaging.instance.requestPermission();

  runApp(const SensorSuhuApp());
}

class SensorSuhuApp extends StatelessWidget {
  const SensorSuhuApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      title: 'Monitor Suhu',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: base.colorScheme.copyWith(
          surface: AppColors.surface,
          primary: AppColors.warm,
        ),
        textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surfaceRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          labelStyle: const TextStyle(color: AppColors.textMuted),
        ),
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final DatabaseReference _sensorRef = FirebaseDatabase.instance.ref('sensor');
  final DatabaseReference _settingsRef = FirebaseDatabase.instance.ref(
    'settings',
  );

  double? _suhu;
  double? _kelembapan;
  bool _kipasStatus = false;

  double _thresholdMin = 25.0;
  double _thresholdMax = 30.0;
  double _thresholdEmergency = 45.0;
  String _nomorWa = '';

  static const double _gaugeMin = 10.0;
  static const double _gaugeMax = 50.0;

  @override
  void initState() {
    super.initState();
    _listenSensor();
    _listenSettings();
    _listenNotifikasi();
    _saveDeviceToken();
  }

  Future<void> _saveDeviceToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await FirebaseDatabase.instance.ref('device_token').set(token);
    }
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      FirebaseDatabase.instance.ref('device_token').set(newToken);
    });
  }

  void _listenSensor() {
    _sensorRef.onValue.listen((event) {
      final data = event.snapshot.value;
      if (data == null) return;
      final map = Map<String, dynamic>.from(data as Map);
      setState(() {
        _suhu = (map['suhu'] as num?)?.toDouble();
        _kelembapan = (map['kelembapan'] as num?)?.toDouble();
        _kipasStatus = map['kipas_status'] == true;
      });
    });
  }

  void _listenSettings() {
    _settingsRef.onValue.listen((event) {
      final data = event.snapshot.value;
      if (data == null) return;
      final map = Map<String, dynamic>.from(data as Map);
      setState(() {
        _thresholdMin = (map['threshold_min'] as num?)?.toDouble() ?? 25.0;
        _thresholdMax = (map['threshold_max'] as num?)?.toDouble() ?? 30.0;
        _thresholdEmergency =
            (map['threshold_emergency'] as num?)?.toDouble() ?? 45.0;
        _nomorWa = map['nomor_wa']?.toString() ?? '';
      });
    });
  }

  void _listenNotifikasi() {
    FirebaseMessaging.onMessage.listen((message) {
      final judul = message.data['title'];
      final isi = message.data['body'];
      if (judul != null && isi != null) {
        _localNotif.show(
          0,
          judul,
          isi,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'suhu_alert',
              'Peringatan Suhu',
              importance: Importance.high,
              priority: Priority.high,
              styleInformation: BigTextStyleInformation(
                isi,
                contentTitle: judul,
                htmlFormatContentTitle: false,
                htmlFormatBigText: false,
              ),
            ),
          ),
        );
      }
    });
  }

  Future<void> _updateThreshold(
    double min,
    double max,
    double emergency,
  ) async {
    await _settingsRef.update({
      'threshold_min': min,
      'threshold_max': max,
      'threshold_emergency': emergency,
    });
  }

  Future<void> _updateNomorWa(String nomor) async {
    await _settingsRef.update({'nomor_wa': nomor});
  }

  void _openThresholdDialog() {
    final minC = TextEditingController(text: _thresholdMin.toStringAsFixed(1));
    final maxC = TextEditingController(text: _thresholdMax.toStringAsFixed(1));
    final emgC = TextEditingController(
      text: _thresholdEmergency.toStringAsFixed(1),
    );

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              'Ambang Batas Suhu',
              style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: minC,
                  style: const TextStyle(color: AppColors.textPrimary),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Kipas mati di bawah',
                    suffixText: '°C',
                    prefixIcon: Icon(
                      Icons.ac_unit,
                      color: AppColors.cool,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: maxC,
                  style: const TextStyle(color: AppColors.textPrimary),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Kipas nyala di atas',
                    suffixText: '°C',
                    prefixIcon: Icon(
                      Icons.local_fire_department,
                      color: AppColors.warm,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: emgC,
                  style: const TextStyle(color: AppColors.textPrimary),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Batas darurat',
                    suffixText: '°C',
                    prefixIcon: Icon(
                      Icons.warning_amber,
                      color: AppColors.danger,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Batal',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.warm),
                onPressed: () async {
                  final min = double.tryParse(minC.text) ?? _thresholdMin;
                  final max = double.tryParse(maxC.text) ?? _thresholdMax;
                  final emg = double.tryParse(emgC.text) ?? _thresholdEmergency;
                  if (min >= max || max >= emg) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Urutan harus: minimum < maksimum < darurat',
                        ),
                      ),
                    );
                    return;
                  }
                  await _updateThreshold(min, max, emg);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Simpan'),
              ),
            ],
          ),
    );
  }

  void _openNomorWaDialog() {
    final nomorController = TextEditingController(text: _nomorWa);

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              'Nomor WhatsApp',
              style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            content: TextField(
              controller: nomorController,
              style: const TextStyle(color: AppColors.textPrimary),
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Nomor tujuan',
                hintText: '6281234567890',
                helperText: 'Format 62xxx, tanpa + atau 0 di depan',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Batal',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.warm),
                onPressed: () async {
                  final nomor = nomorController.text.trim();
                  if (nomor.isEmpty || !nomor.startsWith('62')) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Nomor harus diawali 62')),
                    );
                    return;
                  }
                  await _updateNomorWa(nomor);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Simpan'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suhu = _suhu ?? _gaugeMin;
    final posisi = (suhu - _gaugeMin) / (_gaugeMax - _gaugeMin);
    final warnaSuhu = suhuKeWarna(posisi);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Text(
              'MONITOR SUHU',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 3,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Kipas Otomatis',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 28),

            // ---------- GAUGE UTAMA ----------
            Center(
              child: SizedBox(
                width: 260,
                height: 260,
                child: CustomPaint(
                  painter: _GaugePainter(
                    value: suhu,
                    min: _gaugeMin,
                    max: _gaugeMax,
                    thresholdMin: _thresholdMin,
                    thresholdMax: _thresholdMax,
                    thresholdEmergency: _thresholdEmergency,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _suhu != null ? suhu.toStringAsFixed(1) : '--',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 56,
                            fontWeight: FontWeight.w700,
                            color: warnaSuhu,
                            height: 1,
                          ),
                        ),
                        Text(
                          '°CELSIUS',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 13,
                            letterSpacing: 2,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _kelembapan != null
                              ? '💧 ${_kelembapan!.toStringAsFixed(0)}%'
                              : '💧 --',
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // ---------- STATUS KIPAS ----------
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color:
                      _kipasStatus
                          ? AppColors.warm.withOpacity(0.5)
                          : AppColors.divider,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          _kipasStatus
                              ? AppColors.warm.withOpacity(0.15)
                              : AppColors.surfaceRaised,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.mode_fan_off,
                      color:
                          _kipasStatus ? AppColors.warm : AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _kipasStatus ? 'Kipas Menyala' : 'Kipas Mati',
                          style: GoogleFonts.spaceGrotesk(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Rentang normal ${_thresholdMin.toStringAsFixed(0)}–${_thresholdMax.toStringAsFixed(0)}°C',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ---------- PENGATURAN ----------
            _SettingTile(
              icon: Icons.tune,
              iconColor: AppColors.cool,
              title: 'Ambang Batas Suhu',
              subtitle:
                  '${_thresholdMin.toStringAsFixed(0)}° · ${_thresholdMax.toStringAsFixed(0)}° · darurat ${_thresholdEmergency.toStringAsFixed(0)}°',
              onTap: _openThresholdDialog,
            ),
            const SizedBox(height: 10),
            _SettingTile(
              icon: Icons.chat_bubble_outline,
              iconColor: const Color(0xFF25D366),
              title: 'Notifikasi WhatsApp',
              subtitle: _nomorWa.isEmpty ? 'Belum diatur' : _nomorWa,
              onTap: _openNomorWaDialog,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- CUSTOM PAINTER: GAUGE MELINGKAR ----------
class _GaugePainter extends CustomPainter {
  final double value;
  final double min;
  final double max;
  final double thresholdMin;
  final double thresholdMax;
  final double thresholdEmergency;

  _GaugePainter({
    required this.value,
    required this.min,
    required this.max,
    required this.thresholdMin,
    required this.thresholdMax,
    required this.thresholdEmergency,
  });

  static const double _startAngle = 2.35619; // 135°
  static const double _sweepAngle = 4.71239; // 270°

  double _posisi(double v) => ((v - min) / (max - min)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 14;

    // Track belakang
    final trackPaint =
        Paint()
          ..color = AppColors.surfaceRaised
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      _sweepAngle,
      false,
      trackPaint,
    );

    // Arc progres dengan gradient dingin -> panas
    final progresSweep = _sweepAngle * _posisi(value);
    final gradient = SweepGradient(
      startAngle: _startAngle,
      endAngle: _startAngle + _sweepAngle,
      colors: const [
        AppColors.cool,
        Color(0xFFB6D94F),
        AppColors.warm,
        AppColors.danger,
      ],
      stops: const [0.0, 0.45, 0.75, 1.0],
    );
    final progresPaint =
        Paint()
          ..shader = gradient.createShader(
            Rect.fromCircle(center: center, radius: radius),
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      progresSweep,
      false,
      progresPaint,
    );

    // Tanda batas (min, max, darurat)
    void gambarTanda(double v, Color warna) {
      final sudut = _startAngle + _sweepAngle * _posisi(v);
      final p1 = Offset(
        center.dx + (radius - 12) * math.cos(sudut),
        center.dy + (radius - 12) * math.sin(sudut),
      );
      final p2 = Offset(
        center.dx + (radius + 12) * math.cos(sudut),
        center.dy + (radius + 12) * math.sin(sudut),
      );
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = warna
          ..strokeWidth = 3,
      );
    }

    gambarTanda(thresholdMin, AppColors.cool);
    gambarTanda(thresholdMax, AppColors.warm);
    gambarTanda(thresholdEmergency, AppColors.danger);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.thresholdMin != thresholdMin ||
        oldDelegate.thresholdMax != thresholdMax ||
        oldDelegate.thresholdEmergency != thresholdEmergency;
  }
}
