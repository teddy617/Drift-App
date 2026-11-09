import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() => runApp(const DriftApp());

const ink = Color(0xFF07121E);
const brass = Color(0xFFD0B27D);

class DriftApp extends StatelessWidget {
  const DriftApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: ink, colorScheme: const ColorScheme.dark(primary: brass)),
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
  String mode = 'Random';
  LatLng start = const LatLng(40.0, -76.0); // Demo start only; never presumed to be the user's location.

  @override
  void initState() {
    super.initState();
    globe = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(ink)
      ..loadFlutterAsset('assets/globe.html');
  }

  Future<void> enter(String selected) async {
    setState(() => mode = selected);
    // Prototype uses a fixed demo start. Production must request location permission
    // or let the user select a starting point before initiating this transition.
    await globe.runJavaScript('window.flyTo(${start.latitude}, ${start.longitude})');
    await Future<void>.delayed(const Duration(milliseconds: 2250));
    if (mounted) setState(() => onMap = true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(children: [
      Positioned.fill(child: WebViewWidget(controller: globe)),
      if (onMap) Positioned.fill(child: FlutterMap(
        options: MapOptions(initialCenter: start, initialZoom: 11),
        children: [TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.drift_globe_poc')],
      )),
      SafeArea(child: Padding(padding: const EdgeInsets.all(18), child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          onMap ? IconButton(onPressed: () => setState(() => onMap = false), icon: const Icon(Icons.arrow_back, color: brass)) : const Text('D R I F T', style: TextStyle(color: brass, letterSpacing: 4, fontWeight: FontWeight.w600)),
          if (onMap) Text(mode.toUpperCase(), style: const TextStyle(color: brass, letterSpacing: 2)),
          const Icon(Icons.explore_outlined, color: brass),
        ],
      ))),
      if (!onMap) Positioned(left: 18, right: 18, bottom: 100, child: Row(children: [
        for (final m in ['Random','Intention','Dream']) Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FilledButton(style: FilledButton.styleFrom(backgroundColor: const Color(0xDD1B2A3A), foregroundColor: brass, padding: const EdgeInsets.symmetric(vertical: 18)),
            onPressed: () => enter(m), child: Text(m, style: const TextStyle(fontSize: 12))),
        )),
      ])),
      if (!onMap) Positioned(left: 50, right: 50, bottom: 20, child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: const Color(0xDD172838), borderRadius: BorderRadius.circular(40)),
        child: const Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [Icon(Icons.public,color:brass),Icon(Icons.route),Icon(Icons.bookmark_border),Icon(Icons.person_outline)]),
      )),
      if (onMap) DraggableScrollableSheet(initialChildSize: .25, minChildSize: .12, maxChildSize: .78,
        builder: (context, scroll) => Container(
          decoration: const BoxDecoration(color: Color(0xF21B2D3C), borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          child: ListView(controller: scroll, padding: const EdgeInsets.all(24), children: [
            Center(child: Container(width: 42,height: 4,decoration: BoxDecoration(color: Colors.white38,borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 20),Text('$mode exploration',style: const TextStyle(fontSize: 22,color:brass)),
            const SizedBox(height: 14),const Text('Prototype: mode-specific settings and destination generation are not implemented.'),
            const SizedBox(height: 20),const Text('Demo starting point only. Location permission and manual selection come next.'),
          ]),
        )),
    ]),
  );
}
