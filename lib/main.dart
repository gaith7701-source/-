import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as pathHelper;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MuthakkaratiApp());
}

const kPrimary = Color(0xFF6C63FF);
const kAccent = Color(0xFFFF6584);

const List<Color> kSubjectColors = [
  Color(0xFF6C63FF), Color(0xFFFF6584), Color(0xFF43BCCD),
  Color(0xFFFFB347), Color(0xFF77DD77), Color(0xFFFF6961),
  Color(0xFF836FFF), Color(0xFF00B4D8),
];

const List<String> kDays = ['الأحد','الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت'];

// ===== APP =====
class MuthakkaratiApp extends StatelessWidget {
  const MuthakkaratiApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مذكرتي المدرسية',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: kPrimary), useMaterial3: true),
      darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: kPrimary, brightness: Brightness.dark), useMaterial3: true),
      themeMode: ThemeMode.system,
      home: const SplashScreen(),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
    );
  }
}

// ===== DATABASE =====
class DBHelper {
  static Database? _db;
  static Future<Database> get db async { _db ??= await _initDB(); return _db!; }

  static Future<Database> _initDB() async {
    final p = pathHelper.join(await getDatabasesPath(), 'muthakkarati.db');
    return openDatabase(p, version: 1, onCreate: (db, v) async {
      await db.execute('CREATE TABLE subjects (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, teacher TEXT, color INTEGER NOT NULL DEFAULT 4280391411)');
      await db.execute('CREATE TABLE schedule (id INTEGER PRIMARY KEY AUTOINCREMENT, subject_id INTEGER, day_index INTEGER NOT NULL, start_time TEXT NOT NULL, end_time TEXT NOT NULL, teacher TEXT)');
      await db.execute('CREATE TABLE lessons (id INTEGER PRIMARY KEY AUTOINCREMENT, subject_id INTEGER NOT NULL, title TEXT NOT NULL, content TEXT, date TEXT NOT NULL)');
      await db.execute('CREATE TABLE homework (id INTEGER PRIMARY KEY AUTOINCREMENT, subject_id INTEGER NOT NULL, description TEXT NOT NULL, due_date TEXT NOT NULL, is_done INTEGER DEFAULT 0)');
      await db.execute('CREATE TABLE exams (id INTEGER PRIMARY KEY AUTOINCREMENT, subject_id INTEGER NOT NULL, title TEXT NOT NULL, exam_date TEXT NOT NULL, topics TEXT, grade REAL)');
      await db.execute('CREATE TABLE ai_chat (id INTEGER PRIMARY KEY AUTOINCREMENT, role TEXT NOT NULL, content TEXT NOT NULL, timestamp TEXT NOT NULL)');
    });
  }

  static Future<int> insertSubject(Map<String, dynamic> d) async => (await db).insert('subjects', d);
  static Future<List<Map<String, dynamic>>> getSubjects() async => (await db).query('subjects');
  static Future<int> deleteSubject(int id) async => (await db).delete('subjects', where: 'id=?', whereArgs: [id]);

  static Future<int> insertSchedule(Map<String, dynamic> d) async => (await db).insert('schedule', d);
  static Future<List<Map<String, dynamic>>> getScheduleForDay(int day) async => (await db).rawQuery('SELECT s.*, sub.name as subject_name, sub.color as subject_color, sub.teacher as sub_teacher FROM schedule s LEFT JOIN subjects sub ON s.subject_id=sub.id WHERE s.day_index=? ORDER BY s.start_time', [day]);
  static Future<List<Map<String, dynamic>>> getAllSchedule() async => (await db).rawQuery('SELECT s.*, sub.name as subject_name, sub.color as subject_color FROM schedule s LEFT JOIN subjects sub ON s.subject_id=sub.id ORDER BY s.day_index, s.start_time');
  static Future<int> deleteSchedule(int id) async => (await db).delete('schedule', where: 'id=?', whereArgs: [id]);

  static Future<int> insertLesson(Map<String, dynamic> d) async => (await db).insert('lessons', d);
  static Future<List<Map<String, dynamic>>> getLessonsForSubject(int sid) async => (await db).query('lessons', where: 'subject_id=?', whereArgs: [sid], orderBy: 'date DESC');
  static Future<List<Map<String, dynamic>>> getAllLessons() async => (await db).rawQuery('SELECT l.*, sub.name as subject_name FROM lessons l LEFT JOIN subjects sub ON l.subject_id=sub.id ORDER BY l.date DESC');

  static Future<int> insertHomework(Map<String, dynamic> d) async => (await db).insert('homework', d);
  static Future<List<Map<String, dynamic>>> getHomework({bool pending = false}) async => (await db).rawQuery('SELECT h.*, sub.name as subject_name, sub.color as subject_color FROM homework h LEFT JOIN subjects sub ON h.subject_id=sub.id ${pending ? "WHERE h.is_done=0" : ""} ORDER BY h.due_date ASC');
  static Future<int> updateHomeworkStatus(int id, bool v) async => (await db).update('homework', {'is_done': v ? 1 : 0}, where: 'id=?', whereArgs: [id]);
  static Future<int> deleteHomework(int id) async => (await db).delete('homework', where: 'id=?', whereArgs: [id]);

  static Future<int> insertExam(Map<String, dynamic> d) async => (await db).insert('exams', d);
  static Future<List<Map<String, dynamic>>> getExams() async => (await db).rawQuery('SELECT e.*, sub.name as subject_name, sub.color as subject_color FROM exams e LEFT JOIN subjects sub ON e.subject_id=sub.id ORDER BY e.exam_date ASC');
  static Future<int> deleteExam(int id) async => (await db).delete('exams', where: 'id=?', whereArgs: [id]);

  static Future<int> insertAIMsg(Map<String, dynamic> d) async => (await db).insert('ai_chat', d);
  static Future<List<Map<String, dynamic>>> getAIChat() async => (await db).query('ai_chat', orderBy: 'timestamp ASC');
  static Future<void> clearAIChat() async => (await db).delete('ai_chat');
}

class Subject {
  final int? id; final String name; final String? teacher; final int color;
  Subject({this.id, required this.name, this.teacher, this.color = 0xFF6C63FF});
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'teacher': teacher, 'color': color};
  factory Subject.fromMap(Map<String, dynamic> m) => Subject(id: m['id'], name: m['name'], teacher: m['teacher'], color: m['color'] ?? 0xFF6C63FF);
}

// ===== SPLASH =====
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}
class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _a = CurvedAnimation(parent: _c, curve: Curves.easeIn);
    _c.forward();
    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => prefs.getBool('is_setup') == true ? const MainApp() : const SetupScreen()));
    });
  }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kPrimary,
    body: FadeTransition(opacity: _a, child: const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.menu_book_rounded, size: 80, color: Colors.white),
      SizedBox(height: 20),
      Text('مذكّرتي المدرسية', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
      SizedBox(height: 8),
      Text('مساعدك الدراسي الشخصي', style: TextStyle(fontSize: 16, color: Colors.white70)),
    ]))),
  );
}

// ===== SETUP =====
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override State<SetupScreen> createState() => _SetupScreenState();
}
class _SetupScreenState extends State<SetupScreen> {
  final _n = TextEditingController(), _g = TextEditingController(), _s = TextEditingController();
  @override void dispose() { _n.dispose(); _g.dispose(); _s.dispose(); super.dispose(); }
  Future<void> _finish() async {
    if (_n.text.trim().isEmpty || _g.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء إدخال الاسم والصف'))); return; }
    final p = await SharedPreferences.getInstance();
    await p.setString('student_name', _n.text.trim());
    await p.setString('student_grade', _g.text.trim());
    await p.setString('student_school', _s.text.trim());
    await p.setBool('is_setup', true);
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainApp()));
  }
  Widget _field(String label, TextEditingController c, IconData icon) => TextField(
    controller: c, style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: Colors.white70), prefixIcon: Icon(icon, color: Colors.white70),
      enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white30), borderRadius: BorderRadius.all(Radius.circular(12))),
      focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white), borderRadius: BorderRadius.all(Radius.circular(12)))),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [kPrimary, Color(0xFF4A47A3)])),
      child: SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 40),
        const Icon(Icons.menu_book_rounded, size: 60, color: Colors.white),
        const SizedBox(height: 20),
        const Text('مرحباً بك!', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
        const Text('أدخل بياناتك للبدء', style: TextStyle(fontSize: 18, color: Colors.white70)),
        const SizedBox(height: 40),
        _field('الاسم الكامل *', _n, Icons.person),
        const SizedBox(height: 16),
        _field('الصف الدراسي *', _g, Icons.school),
        const SizedBox(height: 16),
        _field('المدرسة (اختياري)', _s, Icons.account_balance),
        const Spacer(),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _finish,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kPrimary, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('ابدأ الآن', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        )),
      ]))),
    ),
  );
}

// ===== MAIN APP =====
class MainApp extends StatefulWidget {
  const MainApp({super.key});
  @override State<MainApp> createState() => _MainAppState();
}
class _MainAppState extends State<MainApp> {
  int _idx = 0;
  final _screens = const [HomeScreen(), ScheduleScreen(), SubjectsScreen(), HomeworkScreen(), AIChatScreen()];
  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _idx, children: _screens),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _idx,
      onDestinationSelected: (i) => setState(() => _idx = i),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
        NavigationDestination(icon: Icon(Icons.calendar_today_outlined), selectedIcon: Icon(Icons.calendar_today), label: 'الجدول'),
        NavigationDestination(icon: Icon(Icons.book_outlined), selectedIcon: Icon(Icons.book), label: 'المواد'),
        NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: 'الواجبات'),
        NavigationDestination(icon: Icon(Icons.psychology_outlined), selectedIcon: Icon(Icons.psychology), label: 'المساعد'),
      ],
    ),
  );
}

// ===== HOME SCREEN =====
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  String _name = '', _grade = '';
  List<Map<String, dynamic>> _today = [], _hw = [], _exams = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final today = DateTime.now().weekday % 7;
    final ts = await DBHelper.getScheduleForDay(today);
    final hw = await DBHelper.getHomework(pending: true);
    final ex = await DBHelper.getExams();
    final now = DateTime.now();
    final upEx = ex.where((e) { try { final d = DateTime.parse(e['exam_date']); return d.isAfter(now) && d.isBefore(now.add(const Duration(days: 14))); } catch(_){return false;} }).toList();
    if (mounted) setState(() { _name = p.getString('student_name') ?? ''; _grade = p.getString('student_grade') ?? ''; _today = ts; _hw = hw.take(3).toList(); _exams = upEx.take(3).toList(); _loading = false; });
  }

  String get _greeting { final h = DateTime.now().hour; if (h < 12) return 'صباح الخير'; if (h < 17) return 'مساء الخير'; return 'مساء النور'; }
  String get _dayName => kDays[DateTime.now().weekday % 7];

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          SliverAppBar(
            expandedHeight: 180, pinned: true,
            flexibleSpace: FlexibleSpaceBar(background: Container(
              decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [kPrimary, Color(0xFF4A47A3)])),
              child: SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('$_greeting، $_name', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 4),
                Text('$_dayName | الصف: $_grade', style: const TextStyle(fontSize: 14, color: Colors.white70)),
                const SizedBox(height: 8),
                Row(children: [
                  _chip(Icons.class_outlined, '${_today.length} حصص'),
                  const SizedBox(width: 8),
                  _chip(Icons.assignment_outlined, '${_hw.length} واجبات'),
                ]),
              ]))),
            )),
          ),
          SliverPadding(padding: const EdgeInsets.all(16), sliver: SliverList(delegate: SliverChildListDelegate([
            _sec('📚 حصص اليوم'),
            const SizedBox(height: 8),
            if (_today.isEmpty) _empty('لا توجد حصص اليوم 🎉')
            else ..._today.map((s) => _schedCard(s)),
            const SizedBox(height: 16),
            _sec('📝 واجبات قريبة'),
            const SizedBox(height: 8),
            if (_hw.isEmpty) _empty('لا توجد واجبات معلقة ✓')
            else ..._hw.map((h) => _hwCard(h)),
            const SizedBox(height: 16),
            _sec('📅 امتحانات قادمة'),
            const SizedBox(height: 8),
            if (_exams.isEmpty) _empty('لا توجد امتحانات قريبة')
            else ..._exams.map((e) => _exCard(e)),
            const SizedBox(height: 80),
          ]))),
        ]),
      ),
    );
  }

  Widget _chip(IconData icon, String t) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: Colors.white), const SizedBox(width: 4), Text(t, style: const TextStyle(color: Colors.white, fontSize: 12))]));
  Widget _sec(String t) => Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold));
  Widget _empty(String t) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(t, style: TextStyle(color: Colors.grey[600]))));
  Widget _schedCard(Map<String, dynamic> s) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(leading: Container(width: 4, height: 40, decoration: BoxDecoration(color: Color(s['subject_color'] ?? 0xFF6C63FF), borderRadius: BorderRadius.circular(2))), title: Text(s['subject_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text('${s['start_time']} - ${s['end_time']}')));
  Widget _hwCard(Map<String, dynamic> h) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(leading: CircleAvatar(backgroundColor: Color(h['subject_color'] ?? 0xFF6C63FF), radius: 6), title: Text(h['description'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(h['subject_name'] ?? ''), trailing: Text(h['due_date'] ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 12))));
  Widget _exCard(Map<String, dynamic> e) { int d = 0; try { d = DateTime.parse(e['exam_date']).difference(DateTime.now()).inDays; } catch(_){} return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(leading: const Icon(Icons.quiz_outlined, color: kAccent), title: Text(e['subject_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(e['title'] ?? ''), trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: (d <= 3 ? kAccent : kPrimary).withOpacity(0.15), borderRadius: BorderRadius.circular(12)), child: Text('بعد $d أيام', style: TextStyle(color: d <= 3 ? kAccent : kPrimary, fontSize: 12, fontWeight: FontWeight.bold))))); }
}

// ===== SCHEDULE SCREEN =====
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});
  @override State<ScheduleScreen> createState() => _ScheduleScreenState();
}
class _ScheduleScreenState extends State<ScheduleScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<List<Map<String, dynamic>>> _sched = List.generate(7, (_) => []);
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 7, vsync: this, initialIndex: DateTime.now().weekday % 7);
    _load();
  }
  @override void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    final all = await DBHelper.getAllSchedule();
    final s = List.generate(7, (_) => <Map<String, dynamic>>[]);
    for (final x in all) { final d = x['day_index'] as int; if (d >= 0 && d < 7) s[d].add(x); }
    if (mounted) setState(() { _sched = s; _loading = false; });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الجدول الأسبوعي'), bottom: TabBar(controller: _tab, isScrollable: true, tabs: kDays.map((d) => Tab(text: d.substring(0, 2))).toList())),
    body: _loading ? const Center(child: CircularProgressIndicator()) : TabBarView(controller: _tab, children: List.generate(7, (di) {
      final ds = _sched[di];
      if (ds.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.event_available, size: 64, color: Colors.grey), const SizedBox(height: 16), Text('لا توجد حصص ${kDays[di]}', style: TextStyle(color: Colors.grey[600]))]));
      return ListView.builder(padding: const EdgeInsets.all(16), itemCount: ds.length, itemBuilder: (ctx, i) {
        final s = ds[i]; final c = Color(s['subject_color'] ?? 0xFF6C63FF);
        return Card(margin: const EdgeInsets.only(bottom: 10), child: IntrinsicHeight(child: Row(children: [
          Container(width: 6, decoration: BoxDecoration(color: c, borderRadius: const BorderRadius.only(topRight: Radius.circular(12), bottomRight: Radius.circular(12)))),
          Expanded(chil
