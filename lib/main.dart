import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

void main() {
  runApp(const MyPrayerTimesApp());
}

String dataBase = "/data";

// ======================= MODELS ===========================

class StartTimes {
  final String sunrise, fajr, zuhr, asrM1, asrM2, maghrib, isha;
  StartTimes({
    required this.sunrise,
    required this.fajr,
    required this.zuhr,
    required this.asrM1,
    required this.asrM2,
    required this.maghrib,
    required this.isha,
  });
}

class IqamahTimes {
  final String fajr, zuhr, asr, maghrib, isha;
  IqamahTimes({
    required this.fajr,
    required this.zuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
  });
}

class CombinedTimes {
  final StartTimes start;
  final IqamahTimes iqamah;
  final String dateISO;
  CombinedTimes({
    required this.start,
    required this.iqamah,
    required this.dateISO,
  });
}

// ======================= HELPERS ===========================

String _pad(int n) => n < 10 ? "0$n" : "$n";

Future<Map<String, dynamic>> _loadJson(String prefix, int y, int m) async {
  final path = "$dataBase/$prefix-$y-${_pad(m)}.json";
  final res = await http.get(Uri.parse(path));

  if (res.statusCode != 200) {
    return {"days": {}}; // prevents crashes
  }

  return jsonDecode(res.body);
}

StartTimes _parseElm(Map<String, dynamic> month, int d) {
  final day = month["days"]?[_pad(d)];

  if (day == null) {
    return StartTimes(
      sunrise: "--",
      fajr: "--",
      zuhr: "--",
      asrM1: "--",
      asrM2: "--",
      maghrib: "--",
      isha: "--",
    );
  }

  return StartTimes(
    sunrise: day["sunrise"],
    fajr: day["fajr"],
    zuhr: day["zuhr"],
    asrM1: day["asr_mithl1"],
    asrM2: day["asr_mithl2"],
    maghrib: day["maghrib"],
    isha: day["isha"],
  );
}

IqamahTimes _parseMi(Map<String, dynamic> month, int d) {
  final day = month["days"]?[_pad(d)];

  if (day == null) {
    return IqamahTimes(
      fajr: "--",
      zuhr: "--",
      asr: "--",
      maghrib: "--",
      isha: "--",
    );
  }

  return IqamahTimes(
    fajr: day["fajr"],
    zuhr: day["zuhr"],
    asr: day["asr"],
    maghrib: day["maghrib"],
    isha: day["isha"],
  );
}

Future<CombinedTimes> loadCombined(DateTime date) async {
  final elm = await _loadJson("elm", date.year, date.month);
  final mi = await _loadJson("mi", date.year, date.month);

  return CombinedTimes(
    start: _parseElm(elm, date.day),
    iqamah: _parseMi(mi, date.day),
    dateISO: "${date.year}-${_pad(date.month)}-${_pad(date.day)}",
  );
}

// ======================= UI STARTS HERE ===========================

class MyPrayerTimesApp extends StatelessWidget {
  const MyPrayerTimesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "MyPrayerTimes",
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF10B981),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CombinedTimes? data;
  bool loading = true;
  String? error;
  DateTime selected = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final result = await loadCombined(selected);
      setState(() {
        data = result;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDate: selected,
    );

    if (picked != null) {
      setState(() => selected = picked);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("MyPrayerTimes"),
        actions: [
          IconButton(icon: const Icon(Icons.calendar_month), onPressed: _pickDate),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!))
              : _ContentView(data: data!),
    );
  }
}

// ======================= UI COMPONENTS ===========================

class _ContentView extends StatelessWidget {
  final CombinedTimes data;
  const _ContentView({required this.data});

  @override
  Widget build(BuildContext context) {
    final dateText =
        DateFormat("EEEE d MMMM y").format(DateTime.parse(data.dateISO));

    final t = data.start;
    final iq = data.iqamah;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(dateText, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        PrayerCard(title: "Fajr", start: t.fajr, iqamah: iq.fajr, icon: Icons.nightlight_round),
        PrayerCard(title: "Zuhr", start: t.zuhr, iqamah: iq.zuhr, icon: Icons.wb_sunny),
        PrayerCard(title: "Asr", start: t.asrM1, start2: t.asrM2, iqamah: iq.asr, icon: Icons.timelapse),
        PrayerCard(title: "Maghrib", start: t.maghrib, iqamah: iq.maghrib, icon: Icons.sunny),
        PrayerCard(title: "Isha", start: t.isha, iqamah: iq.isha, icon: Icons.dark_mode),
      ],
    );
  }
}

class PrayerCard extends StatelessWidget {
  final String title;
  final String start;
  final String? start2;
  final String iqamah;
  final IconData icon;

  const PrayerCard({
    super.key,
    required this.title,
    required this.start,
    this.start2,
    required this.iqamah,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF93E9BE), Color(0xFF10B981)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          CircleAvatar(radius: 26, backgroundColor: Colors.white, child: Icon(icon, color: Color(0xFF047857))),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _chip("Start", start),
                    if (start2 != null) _chip("Start (2M)", start2!),
                    _chip("Iqāmah", iqamah == "--" ? "No data" : iqamah),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Text("$label: $value"),
    );
  }
}
