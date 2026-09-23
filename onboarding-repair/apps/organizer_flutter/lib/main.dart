import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api.dart';
import 'onboarding.dart';
import 'create_collection.dart';

final apiProvider = Provider<SendohApi>((ref) => throw StateError('Development session required'));
void main() => runApp(const ProviderScope(child: SendohApp()));
String money(dynamic n) => n == null ? 'No target' : '${n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')} FCFA';

class SendohApp extends StatelessWidget {
  const SendohApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Sendoh', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, scaffoldBackgroundColor: const Color(0xFFFAF9F6),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B3D3B), primary: const Color(0xFF0B3D3B)),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(48, 52)))),
    home: const Onboarding(),
  );
}
class DevelopmentSession extends StatefulWidget {
  const DevelopmentSession({super.key});
  @override
  State<DevelopmentSession> createState() => _DevelopmentSessionState();
}
class _DevelopmentSessionState extends State<DevelopmentSession> {
  final url = TextEditingController(text: const String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8000'));
  final token = TextEditingController();
  String? error;
  bool busy = false;
  @override
  void dispose() { url.dispose(); token.dispose(); super.dispose(); }
  Future<void> connect() async {
    setState(() { busy = true; error = null; });
    final api = SendohApi(url.text.trim().replaceAll(RegExp(r'/$'), ''), token.text.trim());
    try {
      final profile = await api.request('/me');
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)], child: Shell(name: profile['display_name'] as String))));
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(
    padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.hub_outlined, size: 54, color: Color(0xFF0B3D3B)), const SizedBox(height: 16),
        Text('SENDOH', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 8), const Text('Organize money. Together.', textAlign: TextAlign.center),
        const SizedBox(height: 32), const Text('Development connection', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8), const Text('Use your original token to access existing collections. This credential stays in memory.'),
        const SizedBox(height: 24), TextField(controller: url, decoration: const InputDecoration(labelText: 'API URL')),
        const SizedBox(height: 16), TextField(controller: token, obscureText: true, decoration: const InputDecoration(labelText: 'Development token')),
        if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(error!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 24), FilledButton(onPressed: busy ? null : connect, child: Text(busy ? 'Connecting…' : 'Open organizer app')),
      ]))))));
}
class Shell extends ConsumerStatefulWidget {
  const Shell({super.key, required this.name});
  final String name;
  @override
  ConsumerState<Shell> createState() => _ShellState();
}
class _ShellState extends ConsumerState<Shell> {
  int tab = 0;
  late Future<List<dynamic>> items;
  @override
  void initState() { super.initState(); items = ref.read(apiProvider).collections(); }
  void reload() => setState(() => items = ref.read(apiProvider).collections());
  Future<void> create() async {
    final api = ref.read(apiProvider);
    final result = await Navigator.of(context).push<Map<String,dynamic>>(MaterialPageRoute(builder: (_) => ProviderScope(overrides: [apiProvider.overrideWithValue(api)], child: const CreateCollection())));
    if (!mounted || result == null) return;
    reload();
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CollectionDetail(data: result)));
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(['Sendoh', 'Activity', 'Profile'][tab])),
    bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (value) => setState(() => tab = value), destinations: const [
      NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
      NavigationDestination(icon: Icon(Icons.history), label: 'Activity'),
      NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile')]),
    body: tab == 2 ? ListView(padding: const EdgeInsets.all(24), children: [
      Text(widget.name, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12), const Text('Development session · payments unavailable'),
      const SizedBox(height: 24), OutlinedButton(onPressed: () async {
        try { await ref.read(apiProvider).request('/auth/logout', body: {}); }
        catch (_) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not reach server. Session will expire automatically.'))); }
        if (context.mounted) Navigator.of(context).pop();
      }, child: const Text('Sign out')),
    ]) : tab == 1 ? const ActivityView() : RefreshIndicator(onRefresh: () async { reload(); await items; }, child: ListView(
      physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(20), children: [
      Text('Let’s organize your next collection', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8), const Text('Create a collection, invite people, and keep a clear record.'),
      const SizedBox(height: 24), FilledButton.icon(onPressed: create, icon: const Icon(Icons.add), label: const Text('Create collection'),
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE8A33D), foregroundColor: const Color(0xFF172C2B))),
      const SizedBox(height: 28), Text('Your collections', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 12),
      FutureBuilder<List<dynamic>>(future: items, builder: (context, snapshot) {
        if (snapshot.hasError) return Column(children: [Text('Could not load collections: ${snapshot.error}'), TextButton(onPressed: reload, child: const Text('Retry'))]);
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Text('No collections yet. Your first collection will appear here.'));
        return Column(children: snapshot.data!.map((item) => Card(child: ListTile(
          contentPadding: const EdgeInsets.all(16), leading: const CircleAvatar(child: Icon(Icons.groups_outlined)),
          title: Text(item['name']), subtitle: Text('${money(item['target_amount'])}\n${item['participants'].length} participants'), isThreeLine: true,
          trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CollectionDetail(data: Map<String,dynamic>.from(item))))))).toList());
      }),
      const SizedBox(height: 24), const Text('Requests and Pay are included in the roadmap and arrive in later increments. Payments are not enabled in this build.'),
    ])),
  );
}
class ActivityView extends ConsumerStatefulWidget {
  const ActivityView({super.key});
  @override
  ConsumerState<ActivityView> createState() => _ActivityViewState();
}
class _ActivityViewState extends ConsumerState<ActivityView> {
  late Future<dynamic> activity;
  @override
  void initState() { super.initState(); activity = ref.read(apiProvider).request('/me/activity'); }
  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(future: activity, builder: (context,s) {
    if(s.hasError) return Center(child: TextButton(onPressed: () => setState(() => activity = ref.read(apiProvider).request('/me/activity')), child: const Text('Could not load activity. Retry')));
    if(!s.hasData) return const Center(child:CircularProgressIndicator());
    final entries = s.data as List;
    if(entries.isEmpty) return const Center(child:Text('No activity yet.'));
    return ListView(children: entries.map((e) => ListTile(leading: const Icon(Icons.add_circle_outline), title:Text(e['message']), subtitle:Text(e['created_at']))).toList());
  });
}
class CollectionDetail extends StatelessWidget {
  const CollectionDetail({super.key, required this.data});
  final Map<String,dynamic> data;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(data['name'])), body: ListView(padding: const EdgeInsets.all(24), children: [
    Text(data['status'], style: const TextStyle(color: Color(0xFF0B3D3B), fontWeight: FontWeight.bold)), const SizedBox(height: 16),
    Text(money(data['collected_amount']), style: Theme.of(context).textTheme.headlineLarge),
    Text(data['target_amount'] == null ? 'Contributed · no target set' : 'Contributed toward ${money(data['target_amount'])}'),
    const SizedBox(height: 16), Text(data['description'] as String),
    const SizedBox(height: 12), Text(data['deadline_at'] == null ? 'No deadline' : 'Deadline: ${data['deadline_at']}'),
    const SizedBox(height: 24), if (data['share_url'] != null) ...[
      SelectableText(data['share_url']), const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: () async { await Clipboard.setData(ClipboardData(text:data['share_url'])); if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Collection link copied'))); }, icon:const Icon(Icons.copy), label:const Text('Copy collection link')),
    ],
    const SizedBox(height: 24), Text('Participants',style:Theme.of(context).textTheme.titleLarge),
    if ((data['participants'] as List).isEmpty) const Padding(padding:EdgeInsets.symmetric(vertical:16),child:Text('No participants added.')),
    ...(data['participants'] as List).map((p) => ListTile(contentPadding:EdgeInsets.zero, leading: const Icon(Icons.person_outline), title:Text(p['name']),subtitle:Text(p['expected_amount']==null?'Any amount':'Expected: ${money(p['expected_amount'])}'))),
    const SizedBox(height:24), const Text('Digital contributions, final cash reconciliation, and settlement will be connected in the next increments.'),
  ]));
}
