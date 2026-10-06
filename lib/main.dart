import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

late Box recentBox;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  recentBox = await Hive.openBox('recent');
  runApp(const MyApp());
}

// ---------- Models ----------
class HourForecast {
  final DateTime time;
  final double temp;
  final int code;
  HourForecast(this.time, this.temp, this.code);
}

class DayForecast {
  final DateTime date;
  final double max, min;
  final int code;
  DayForecast(this.date, this.max, this.min, this.code);
}

class Weather {
  final String city;
  final double temp, wind;
  final int humidity, code;
  final bool isDay;
  final DateTime localTime;
  final List<HourForecast> hours;
  final List<DayForecast> days;
  Weather({
    required this.city,
    required this.temp,
    required this.wind,
    required this.humidity,
    required this.code,
    required this.isDay,
    required this.localTime,
    required this.hours,
    required this.days,
  });
}

// ---------- API (Open-Meteo, no key needed) ----------
Future<Weather> fetchWeather(String query) async {
  final geoRes = await http.get(
    Uri.parse(
      'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(query)}&count=1',
    ),
  );
  final results = jsonDecode(geoRes.body)['results'] as List?;
  if (results == null || results.isEmpty) throw Exception('City not found');
  final place = results[0];

  final res = await http.get(
    Uri.parse(
      'https://api.open-meteo.com/v1/forecast?latitude=${place['latitude']}&longitude=${place['longitude']}'
      '&current=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code,is_day'
      '&hourly=temperature_2m,weather_code'
      '&daily=weather_code,temperature_2m_max,temperature_2m_min'
      '&timezone=auto&forecast_days=5',
    ),
  );
  if (res.statusCode != 200) throw Exception('Weather service error');

  final data = jsonDecode(res.body);
  final cur = data['current'];
  final daily = data['daily'];
  final hourly = data['hourly'];

  // Next 24 hours (from the current hour of that city)
  final nowLocal = DateTime.parse(cur['time']);
  final startHour = DateTime(
    nowLocal.year,
    nowLocal.month,
    nowLocal.day,
    nowLocal.hour,
  );
  final hTimes = hourly['time'] as List;
  final hours = <HourForecast>[];
  for (var i = 0; i < hTimes.length && hours.length < 24; i++) {
    final t = DateTime.parse(hTimes[i]);
    if (t.isBefore(startHour)) continue;
    hours.add(
      HourForecast(
        t,
        (hourly['temperature_2m'][i] as num).toDouble(),
        (hourly['weather_code'][i] as num).toInt(),
      ),
    );
  }

  final times = daily['time'] as List;
  final days = <DayForecast>[];
  for (var i = 0; i < times.length; i++) {
    days.add(
      DayForecast(
        DateTime.parse(times[i]),
        (daily['temperature_2m_max'][i] as num).toDouble(),
        (daily['temperature_2m_min'][i] as num).toDouble(),
        (daily['weather_code'][i] as num).toInt(),
      ),
    );
  }

  return Weather(
    city: place['name'].toString(),
    temp: (cur['temperature_2m'] as num).toDouble(),
    wind: (cur['wind_speed_10m'] as num).toDouble(),
    humidity: (cur['relative_humidity_2m'] as num).toInt(),
    code: (cur['weather_code'] as num).toInt(),
    isDay: (cur['is_day'] as num).toInt() == 1,
    localTime: nowLocal,
    hours: hours,
    days: days,
  );
}

// ---------- Helpers ----------
String describe(int c) {
  if (c == 0) return 'Clear sky';
  if (c <= 3) return 'Partly cloudy';
  if (c == 45 || c == 48) return 'Fog';
  if (c >= 51 && c <= 67) return 'Rain';
  if (c >= 71 && c <= 77) return 'Snow';
  if (c >= 80 && c <= 82) return 'Showers';
  if (c >= 95) return 'Thunderstorm';
  return 'Cloudy';
}

IconData iconFor(int c, [bool day = true]) {
  if (c == 0) return day ? Icons.wb_sunny_rounded : Icons.nightlight_round;
  if (c <= 3) return Icons.wb_cloudy_rounded;
  if (c == 45 || c == 48) return Icons.foggy;
  if (c >= 51 && c <= 67) return Icons.grain;
  if (c >= 71 && c <= 77) return Icons.ac_unit;
  if (c >= 80 && c <= 82) return Icons.water_drop_rounded;
  if (c >= 95) return Icons.thunderstorm_rounded;
  return Icons.cloud_rounded;
}

// Always 3 colours so the background animates smoothly between weathers.
List<Color> gradientFor(int c, bool day) {
  if (c >= 95) {
    return const [Color(0xFF3A3A5C), Color(0xFF24243E), Color(0xFF0B0B1A)];
  }
  if ((c >= 51 && c <= 67) || (c >= 80 && c <= 82)) {
    return const [Color(0xFF4CA1AF), Color(0xFF2C3E50), Color(0xFF1B2735)];
  }
  if (c >= 71 && c <= 77) {
    return const [Color(0xFF74EBD5), Color(0xFF7B8FD6), Color(0xFF5C258D)];
  }
  if (!day) {
    return const [Color(0xFF302B63), Color(0xFF1F1B4D), Color(0xFF0F0C29)];
  }
  if (c == 45 || c == 48) {
    return const [Color(0xFF757F9A), Color(0xFF5A6480), Color(0xFF3F4C6B)];
  }
  if (c == 0) {
    return const [Color(0xFFF7971E), Color(0xFFFF5E62), Color(0xFF8E2DE2)];
  }
  return const [Color(0xFF4B6CB7), Color(0xFF3A4E8C), Color(0xFF182848)];
}

List<String> getRecent() =>
    List<String>.from(recentBox.get('cities', defaultValue: []));

void saveRecent(String city) {
  final list = getRecent()
    ..remove(city)
    ..insert(0, city);
  recentBox.put('cities', list.take(5).toList());
}

// ---------- Glass card (blurred, translucent) ----------
class Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: child,
      ),
    ),
  );
}

// ---------- UI ----------
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Weather App',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
    // lets the hourly list scroll with mouse drag on web/desktop
    scrollBehavior: const MaterialScrollBehavior().copyWith(
      dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
    ),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final controller = TextEditingController();
  late Future<Weather> future;
  List<Color> bg = gradientFor(0, true);

  @override
  void initState() {
    super.initState();
    future = fetchWeather('Hyderabad');
    attach(future);
  }

  void attach(Future<Weather> f) {
    f
        .then((w) {
          saveRecent(w.city);
          if (mounted) setState(() => bg = gradientFor(w.code, w.isDay));
        })
        .catchError((_) {});
  }

  void search(String city) {
    city = city.trim();
    if (city.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => future = fetchWeather(city));
    attach(future);
  }

  Widget label(String t) => Text(
    t,
    style: const TextStyle(
      color: Colors.white70,
      fontSize: 12,
      letterSpacing: 1.4,
      fontWeight: FontWeight.w600,
    ),
  );

  Widget circle(double s) => Container(
    width: s,
    height: s,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: 0.07),
    ),
  );

  Widget stat(IconData icon, Color color, String value, String title) =>
      Expanded(
        child: Glass(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      );

  Widget rangeBar(double min, double max, double wMin, double wMax) {
    const w = 90.0;
    final span = (wMax - wMin) == 0 ? 1.0 : (wMax - wMin);
    final width = ((max - min) / span * w).clamp(10.0, w).toDouble();
    final left = ((min - wMin) / span * w).clamp(0.0, w - width).toDouble();
    return SizedBox(
      width: w,
      height: 6,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Positioned(
            left: left,
            width: width,
            top: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF80D8FF), Color(0xFFFFD54F)],
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget hero(Weather w) {
    final glow = (w.isDay && w.code == 0)
        ? const Color(0xFFFFE082)
        : Colors.white;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_on_rounded, size: 22),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                w.city,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          DateFormat('EEEE, d MMM  •  h:mm a').format(w.localTime),
          style: const TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: glow.withValues(alpha: 0.45),
                blurRadius: 70,
                spreadRadius: 8,
              ),
            ],
          ),
          child: Icon(iconFor(w.code, w.isDay), size: 110, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          '${w.temp.round()}°',
          style: const TextStyle(
            fontSize: 100,
            fontWeight: FontWeight.w200,
            height: 1.1,
            shadows: [
              Shadow(
                color: Colors.black26,
                blurRadius: 24,
                offset: Offset(0, 6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Text(
            describe(w.code).toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget hourly(Weather w) => Glass(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label('HOURLY FORECAST'),
        const SizedBox(height: 14),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: w.hours.length,
            separatorBuilder: (_, __) => const SizedBox(width: 22),
            itemBuilder: (_, i) {
              final h = w.hours[i];
              final dayHour = h.time.hour >= 6 && h.time.hour < 19;
              return Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    i == 0 ? 'Now' : DateFormat('h a').format(h.time),
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Icon(iconFor(h.code, dayHour), size: 28),
                  Text(
                    '${h.temp.round()}°',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget forecast(Weather w) {
    final wMin = w.days.map((d) => d.min).reduce((a, b) => a < b ? a : b);
    final wMax = w.days.map((d) => d.max).reduce((a, b) => a > b ? a : b);
    return Glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label('5-DAY FORECAST'),
          const SizedBox(height: 6),
          ...w.days.asMap().entries.map((e) {
            final d = e.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 54,
                    child: Text(
                      e.key == 0 ? 'Today' : DateFormat('EEE').format(d.date),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(iconFor(d.code), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      describe(d.code),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  SizedBox(
                    width: 30,
                    child: Text(
                      '${d.min.round()}°',
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ),
                  const SizedBox(width: 8),
                  rangeBar(d.min, d.max, wMin, wMax),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${d.max.round()}°',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 800),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: bg,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(top: -90, right: -70, child: circle(280)),
          Positioned(bottom: 140, left: -100, child: circle(320)),
          Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: Colors.white),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      children: [
                        // Search bar
                        Glass(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            controller: controller,
                            onSubmitted: search,
                            style: const TextStyle(color: Colors.white),
                            cursorColor: Colors.white,
                            decoration: InputDecoration(
                              hintText: 'Search city...',
                              hintStyle: const TextStyle(color: Colors.white70),
                              border: InputBorder.none,
                              icon: const Icon(
                                Icons.search_rounded,
                                color: Colors.white70,
                              ),
                              suffixIcon: IconButton(
                                icon: const Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Colors.white,
                                ),
                                onPressed: () => search(controller.text),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Recent searches (Hive)
                        ValueListenableBuilder(
                          valueListenable: recentBox.listenable(),
                          builder: (_, __, ___) => Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: getRecent()
                                .map(
                                  (c) => ActionChip(
                                    avatar: const Icon(
                                      Icons.history_rounded,
                                      size: 16,
                                      color: Colors.white70,
                                    ),
                                    label: Text(c),
                                    labelStyle: const TextStyle(
                                      color: Colors.white,
                                    ),
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.16,
                                    ),
                                    side: BorderSide.none,
                                    shape: const StadiumBorder(),
                                    onPressed: () {
                                      controller.text = c;
                                      search(c);
                                    },
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: 24),
                        FutureBuilder<Weather>(
                          future: future,
                          builder: (context, snap) {
                            Widget content;
                            if (snap.connectionState != ConnectionState.done) {
                              content = const Padding(
                                key: ValueKey('loading'),
                                padding: EdgeInsets.symmetric(vertical: 120),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                ),
                              );
                            } else if (snap.hasError) {
                              final nf = snap.error.toString().contains(
                                'City not found',
                              );
                              content = Glass(
                                key: const ValueKey('error'),
                                padding: const EdgeInsets.all(32),
                                child: Center(
                                  child: Column(
                                    children: [
                                      const Icon(
                                        Icons.cloud_off_rounded,
                                        size: 52,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        nf
                                            ? 'City not found. Try another name.'
                                            : 'Could not load weather.\nCheck your internet.',
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            } else {
                              final w = snap.data!;
                              content = Column(
                                key: ValueKey(w.city),
                                children: [
                                  hero(w),
                                  const SizedBox(height: 28),
                                  Row(
                                    children: [
                                      stat(
                                        Icons.water_drop_rounded,
                                        const Color(0xFF80D8FF),
                                        '${w.humidity}%',
                                        'Humidity',
                                      ),
                                      const SizedBox(width: 12),
                                      stat(
                                        Icons.air_rounded,
                                        const Color(0xFFB9F6CA),
                                        '${w.wind.round()} km/h',
                                        'Wind',
                                      ),
                                      const SizedBox(width: 12),
                                      stat(
                                        Icons.thermostat_rounded,
                                        const Color(0xFFFFAB91),
                                        '${w.days[0].max.round()}° / ${w.days[0].min.round()}°',
                                        'Today',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  hourly(w),
                                  const SizedBox(height: 16),
                                  forecast(w),
                                ],
                              );
                            }
                            return AnimatedSwitcher(
                              duration: const Duration(milliseconds: 450),
                              child: content,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
