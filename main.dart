import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() => runApp(const DriftApp());

const ink = Color(0xFF07121E);
const brass = Color(0xFFD0B27D);
const panel = Color(0xF21B2D3C);

class DriftApp extends StatelessWidget {
  const DriftApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: ink,
      colorScheme: const ColorScheme.dark(primary: brass),
    ),
    home: const DriftHome(),
  );
}

class DriftHome extends StatefulWidget {
  const DriftHome({super.key});
  @override
  State<DriftHome> createState() => _DriftHomeState();
}

class _DriftHomeState extends State<DriftHome> {
  late final WebViewController globe;
  bool onMap = false;
  bool transitioning = false;
  String mode = 'Random';
  // Demonstration point only; not the device's actual location.
  final LatLng start = const LatLng(40.0, -76.0);

  @override
  void initState() {
    super.initState();
    globe = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(ink)
      ..loadFlutterAsset('assets/globe.html');
  }

  Future<void> enter(String selected) async {
    if (transitioning) return;
    setState(() {
      mode = selected;
      transitioning = true;
    });
    try {
      await globe.runJavaScript(
        'window.flyTo(${start.latitude}, ${start.longitude})',
      );
      await Future<void>.delayed(const Duration(milliseconds: 2200));
    } catch (_) {
      // Map remains available if globe scripts fail or are offline.
    }
    if (!mounted) return;
    setState(() {
      onMap = true;
      transitioning = false;
    });
  }

  void returnHome() {
    setState(() => onMap = false);
    globe.runJavaScript('window.resetGlobe && window.resetGlobe()')
      .catchError((Object _) {});
  }

  Widget modeButton(String label, IconData icon) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: const Color(0xE61B2A3A),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: transitioning ? null : () => enter(label),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 3),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: brass, size: 21),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
            ]),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(children: [
      // Globe fills the display, independently of overlays.
      Positioned.fill(child: WebViewWidget(controller: globe)),
      if (onMap)
        Positioned.fill(child: FlutterMap(
          options: MapOptions(initialCenter: start, initialZoom: 11),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.driftapp.drift_globe_poc',
            ),
          ],
        )),
      // Overlay controls stay within Android status/navigation safe areas.
      SafeArea(child: Stack(children: [
        Positioned(
          left: 20, right: 20, top: 12,
          child: Row(children: [
            if (onMap)
              IconButton(
                tooltip: 'Return to globe',
                onPressed: returnHome,
                icon: const Icon(Icons.arrow_back, color: brass),
              )
            else
              const Text('D R I F T',
                style: TextStyle(color: brass, letterSpacing: 4, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (onMap)
              Text(mode.toUpperCase(),
                style: const TextStyle(color: brass, letterSpacing: 2, fontSize: 13)),
            const SizedBox(width: 12),
            const Icon(Icons.explore_outlined, color: brass),
          ]),
        ),
        if (!onMap) ...[
          Positioned(
            left: 16, right: 16, bottom: 100,
            child: Row(children: [
              modeButton('Random', Icons.shuffle),
              modeButton('Intention', Icons.explore_outlined),
              modeButton('Dream', Icons.nights_stay_outlined),
            ]),
          ),
          Positioned(
            left: 34, right: 34, bottom: 18,
            child: Container(
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0xE6172838),
                borderRadius: BorderRadius.circular(35),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Icon(Icons.public, color: brass),
                  Icon(Icons.route_outlined),
                  Icon(Icons.bookmark_border),
                  Icon(Icons.person_outline),
                ],
              ),
            ),
          ),
        ],
      ])),
      if (onMap)
        SafeArea(
          top: false,
          child: DraggableScrollableSheet(
            initialChildSize: .23,
            minChildSize: .11,
            maxChildSize: .88,
            snap: true,
            snapSizes: const [.23, .55],
            builder: (context, scroll) => Container(
              decoration: const BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 32),
                children: [
                  Center(child: Container(
                    width: 42, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white38,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  )),
                  const SizedBox(height: 20),
                  Text('$mode exploration',
                    style: const TextStyle(fontSize: 22, color: brass)),
                  const SizedBox(height: 14),
                  const Text('Prototype: mode-specific controls and destination generation are not implemented.'),
                  const SizedBox(height: 18),
                  const Text('Using a demonstration starting point. Location permission and manual selection come later.'),
                ],
              ),
            ),
          ),
        ),
      if (transitioning)
        const Positioned(
          top: 95, left: 0, right: 0,
          child: Center(child: Text('DESCENDING',
            style: TextStyle(color: brass, letterSpacing: 3, fontSize: 11))),
        ),
    ]),
  );
}
