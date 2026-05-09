import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

Future<void> setupNotifications() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

  const initSettings = InitializationSettings(android: androidInit);

  await notifications.initialize(initSettings);

  final androidPlugin = notifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();

  await androidPlugin?.requestNotificationsPermission();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'earthquake_alert_channel',
    'Earthquake Alerts',
    description: 'Notifications for earthquake alert detection',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  await androidPlugin?.createNotificationChannel(channel);
}

Future<Position?> requestLocationPermission() async {
  try {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
  } catch (e) {
    debugPrint("Location error: $e");
    return null;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyC_VAznxpLqoi9xiCXa1SlTNC1aLT4qrRc",
      authDomain: "vbedas.firebaseapp.com",
      databaseURL:
          "https://vbedas-default-rtdb.asia-southeast1.firebasedatabase.app",
      projectId: "vbedas",
      storageBucket: "vbedas.firebasestorage.app",
      messagingSenderId: "38863431120",
      appId: "1:38863431120:web:7200dc3feda823673645d5",
    ),
  );

  await setupNotifications();

  runApp(const VBEDASApp());
}

class VBEDASApp extends StatelessWidget {
  const VBEDASApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VBEDAS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.red,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xfff4f6f8),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int index = 0;

  final pages = const [
    DashboardPage(),
    HistoryPage(),
    NodeStatusPage(),
    SafetyPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
          NavigationDestination(icon: Icon(Icons.sensors), label: 'Nodes'),
          NavigationDestination(
            icon: Icon(Icons.health_and_safety),
            label: 'Safety',
          ),
        ],
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final db = FirebaseDatabase.instance.ref();

  String lastNotificationStatus = "";
  Position? userPosition;
  bool locationLoading = false;

  @override
void initState() {
  super.initState();
}

  Future<void> loadLocation() async {
    setState(() {
      locationLoading = true;
    });

    final pos = await requestLocationPermission();

    if (!mounted) return;

    setState(() {
      userPosition = pos;
      locationLoading = false;
    });
  }

  Future<void> showAlertNotification(String status) async {
    const androidDetails = AndroidNotificationDetails(
      'earthquake_alert_channel',
      'Earthquake Alerts',
      channelDescription: 'Notifications for earthquake alert detection',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      ticker: 'VBEDAS Alert',
    );

    const details = NotificationDetails(android: androidDetails);

    await notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'VBEDAS Alert',
      status,
      details,
    );
  }

  bool isAlertStatus(String status) {
    final s = status.toLowerCase();
    return s.contains("alert") ||
        s.contains("earthquake") ||
        s.contains("confirmed");
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: db.onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = Map<String, dynamic>.from(
          snapshot.data!.snapshot.value as Map,
        );

        final latest = Map<String, dynamic>.from(data["latest"] ?? {});
        final node1 = Map<String, dynamic>.from(data["node1"] ?? {});
        final node2 = Map<String, dynamic>.from(data["node2"] ?? {});
        final finalStatus =
            Map<String, dynamic>.from(data["finalStatus"] ?? {});
        final tests = Map<String, dynamic>.from(data["tests"] ?? {});
        final events = Map<String, dynamic>.from(data["events"] ?? {});

        final status = finalStatus["status"]?.toString() ??
            latest["status"]?.toString() ??
            "Normal";

        final acceleration =
            double.tryParse("${latest["acceleration"] ?? 0}") ?? 0.0;
        final threshold =
            double.tryParse("${latest["threshold"] ?? 0.75}") ?? 0.75;

        final totalTests = double.tryParse("${tests["totalTests"] ?? 0}") ?? 0;
        final correct =
            double.tryParse("${tests["correctDetections"] ?? 0}") ?? 0;
        final efficiency = totalTests == 0 ? 0 : (correct / totalTests) * 100;

        if (isAlertStatus(status) && lastNotificationStatus != status) {
          lastNotificationStatus = status;
          showAlertNotification(status);
        }

        if (!isAlertStatus(status)) {
          lastNotificationStatus = "";
        }

        final graphEvents = events.values
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((e) => isAlertStatus("${e["status"] ?? ""}"))
            .toList();

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "VBEDAS Dashboard",
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Vibration Based Earthquake Detection and Alert System",
                ),
                const SizedBox(height: 20),
                StatusBanner(status: status),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.25,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  children: [
                    InfoCard(
                      title: "Acceleration",
                      value: "${acceleration.toStringAsFixed(3)} g",
                      icon: Icons.speed,
                    ),
                    InfoCard(
                      title: "Threshold",
                      value: "${threshold.toStringAsFixed(2)} g",
                      icon: Icons.timeline,
                    ),
                    InfoCard(
                      title: "Total Events",
                      value: "${events.length}",
                      icon: Icons.warning,
                    ),
                    InfoCard(
                      title: "Reliability",
                      value: "${efficiency.toStringAsFixed(1)}%",
                      icon: Icons.verified,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const SectionTitle("User Location"),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: boxDecoration(),
                  child: userPosition == null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              locationLoading
                                  ? "Getting location..."
                                  : "Location permission not available.",
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              onPressed: locationLoading ? null : loadLocation,
                              icon: const Icon(Icons.location_on),
                              label: const Text("Allow Location"),
                            ),
                          ],
                        )
                      : Text(
                          "Latitude: ${userPosition!.latitude.toStringAsFixed(6)}\n"
                          "Longitude: ${userPosition!.longitude.toStringAsFixed(6)}\n"
                          "Accuracy: ${userPosition!.accuracy.toStringAsFixed(1)} m",
                        ),
                ),
                const SizedBox(height: 20),
                const SectionTitle("Confirmed Detection Graph"),
                Container(
                  height: 250,
                  padding: const EdgeInsets.all(12),
                  decoration: boxDecoration(),
                  child: graphEvents.isEmpty
                      ? const Center(
                          child: Text("No confirmed/alert event yet"),
                        )
                      : LineChart(
                          LineChartData(
                            gridData: const FlGridData(show: true),
                            titlesData: const FlTitlesData(show: true),
                            borderData: FlBorderData(show: true),
                            lineBarsData: [
                              LineChartBarData(
                                spots: List.generate(
                                  graphEvents.length,
                                  (i) => FlSpot(
                                    i.toDouble(),
                                    double.tryParse(
                                          "${graphEvents[i]["acceleration"] ?? 0}",
                                        ) ??
                                        0,
                                  ),
                                ),
                                isCurved: true,
                                barWidth: 3,
                                dotData: const FlDotData(show: true),
                              ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 20),
                const SectionTitle("Two-Node Verification"),
                Row(
                  children: [
                    Expanded(
                      child: NodeMiniCard(
                        title: "Primary Node",
                        status:
                            "${node1["status"] ?? latest["status"] ?? "Normal"}",
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: NodeMiniCard(
                        title: "Checker Node",
                        status: "${node2["status"] ?? "Normal"}",
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  bool isAlertStatus(String status) {
    final s = status.toLowerCase();
    return s.contains("alert") ||
        s.contains("earthquake") ||
        s.contains("confirmed");
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseDatabase.instance.ref("events");

    return SafeArea(
      child: StreamBuilder(
        stream: db.onValue,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
            return const Center(child: Text("No alert history available"));
          }

          final data = Map<String, dynamic>.from(
            snapshot.data!.snapshot.value as Map,
          );

          final events = data.values
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
              .reversed
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                "Alert History",
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ...events.map((event) {
                final status = "${event["status"] ?? "Alert"}";
                final isAlert = isAlertStatus(status);

                return Card(
                  child: ListTile(
                    leading: Icon(
                      isAlert ? Icons.warning : Icons.check_circle,
                      color: isAlert ? Colors.red : Colors.green,
                    ),
                    title: Text(status),
                    subtitle: Text(
                      "Acceleration: ${event["acceleration"] ?? "N/A"} g\n"
                      "Threshold: ${event["threshold"] ?? "N/A"} g\n"
                      "Time: ${event["timestamp"] ?? "N/A"}",
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class NodeStatusPage extends StatelessWidget {
  const NodeStatusPage({super.key});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseDatabase.instance.ref();

    return SafeArea(
      child: StreamBuilder(
        stream: db.onValue,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = Map<String, dynamic>.from(
            snapshot.data!.snapshot.value as Map,
          );

          final latest = Map<String, dynamic>.from(data["latest"] ?? {});
          final node1 = Map<String, dynamic>.from(data["node1"] ?? {});
          final node2 = Map<String, dynamic>.from(data["node2"] ?? {});

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                "Module Status",
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              NodeDetailCard(
                title: "Primary Alert Node",
                status: "${node1["status"] ?? latest["status"] ?? "Normal"}",
                delta: "${node1["delta"] ?? latest["acceleration"] ?? "N/A"}",
                lastSeen:
                    "${node1["lastSeen"] ?? latest["timestamp"] ?? "N/A"}",
              ),
              NodeDetailCard(
                title: "Secondary Checker Node",
                status: "${node2["status"] ?? "Normal"}",
                delta: "${node2["delta"] ?? "N/A"}",
                lastSeen: "${node2["lastDetectionMillis"] ?? "N/A"}",
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: boxDecoration(),
                child: const Text(
                  "If both nodes detect vibration within the confirmation time window, "
                  "the event is considered a confirmed earthquake-like vibration. "
                  "If only one node detects vibration, the event is dismissed as a possible local disturbance.",
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class SafetyPage extends StatelessWidget {
  const SafetyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tips = [
      "Drop, cover, and hold during shaking.",
      "Stay away from windows and heavy objects.",
      "Do not use elevators during an earthquake.",
      "Move to an open area after shaking stops.",
      "Keep emergency contacts and first-aid ready.",
      "Follow official instructions from authorities.",
    ];

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "Safety Guide",
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...tips.map(
            (tip) => Card(
              child: ListTile(
                leading: const Icon(Icons.health_and_safety),
                title: Text(tip),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: boxDecoration(),
            child: const Text(
              "This application is designed for local awareness only. "
              "It does not predict earthquakes or replace professional seismic monitoring systems.",
            ),
          ),
        ],
      ),
    );
  }
}

class StatusBanner extends StatelessWidget {
  final String status;

  const StatusBanner({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final alert = status.toLowerCase().contains("alert") ||
        status.toLowerCase().contains("earthquake") ||
        status.toLowerCase().contains("confirmed");

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: alert ? Colors.red : Colors.green,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        status,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const InfoCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: boxDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28),
          const Spacer(),
          Text(title),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class NodeMiniCard extends StatelessWidget {
  final String title;
  final String status;

  const NodeMiniCard({
    super.key,
    required this.title,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final alert = status.toLowerCase().contains("alert") ||
        status.toLowerCase().contains("earthquake") ||
        status.toLowerCase().contains("confirmed");

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          const SizedBox(height: 8),
          Text(
            status,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: alert ? Colors.red : Colors.green,
            ),
          ),
        ],
      ),
    );
  }
}

class NodeDetailCard extends StatelessWidget {
  final String title;
  final String status;
  final String delta;
  final String lastSeen;

  const NodeDetailCard({
    super.key,
    required this.title,
    required this.status,
    required this.delta,
    required this.lastSeen,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.sensors),
        title: Text(title),
        subtitle: Text(
          "Status: $status\nDelta: $delta\nLast Seen: $lastSeen",
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;

  const SectionTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    );
  }
}

BoxDecoration boxDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withAlpha(18),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );
}