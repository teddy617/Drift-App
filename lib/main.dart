import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
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
  bool choosingOnGlobe = false;
  String mode = 'Random';
  LatLng? selectedStart;
  LatLng? mapStart;

  @override
  void initState() {
    super.initState();
    globe = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(ink)
      ..addJavaScriptChannel('DriftBridge', onMessageReceived: (message) {
        if (!mounted || !choosingOnGlobe) return;
        try {
          final data = jsonDecode(message.message) as Map<String, dynamic>;
          final lat = (data['lat'] as num).toDouble();
          final lng = (data['lng'] as num).toDouble();
          if (lat.abs() <= 90 && lng.abs() <= 180) {
            setState(() => selectedStart = LatLng(lat, lng));
          }
        } catch (_) { /* Ignore malformed globe messages. */ }
      })
      ..loadFlutterAsset('assets/globe.html');
  }

  Future<void> selectMode(String chosenMode) async {
    if (transitioning) return;
    setState(() => mode = chosenMode);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1B2D3C),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$mode · Starting point', style: const TextStyle(color: brass, fontSize: 22)),
            const SizedBox(height: 8),
            const Text('Where should your exploration begin? Drift will choose the destination later.'),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.my_location, color: brass),
              title: const Text('Use my current location'),
              subtitle: const Text('Only after you grant permission'),
              onTap: () { Navigator.pop(sheetContext); useCurrentLocation(); },
            ),
            ListTile(
              leading: const Icon(Icons.public, color: brass),
              title: const Text('Choose on the globe'),
              subtitle: const Text('Tap any location to set your starting point'),
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() { choosingOnGlobe = true; selectedStart = null; });
              },
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> useCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        showMessage('Turn on device location services, or choose on the globe.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        showMessage('Location permission unavailable. You can select a point on the globe.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)),
      );
      if (!mounted) return;
      await descendTo(LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      showMessage('Could not get your location. Please choose a starting point on the globe.');
    }
  }

  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> descendTo(LatLng point) async {
    if (transitioning) return;
    setState(() { transitioning = true; choosingOnGlobe = false; mapStart = point; });
    try {
      await globe.runJavaScript('window.flyTo(${point.latitude}, ${point.longitude})');
    } catch (_) { /* Map still opens if globe scripts are unavailable. */ }
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    if (!mounted) return;
    setState(() { onMap = true; transitioning = false; });
  }

  void returnHome() {
    if (onMap) {
      setState(() { onMap = false; mapStart = null; });
      globe.runJavaScript('window.resetGlobe && window.resetGlobe()').catchError((Object _) {});
    } else if (choosingOnGlobe) {
      setState(() { choosingOnGlobe = false; selectedStart = null; });
    }
  }

  Widget modeButton(String label, IconData icon) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: const Color(0xE61B2A3A),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: transitioning ? null : () => selectMode(label),
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
  Widget build(BuildContext context) => PopScope(
    canPop: !onMap && !choosingOnGlobe && !transitioning,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !transitioning) returnHome();
    },
    child: Scaffold(
      body: Stack(children: [
        Positioned.fill(child: WebViewWidget(controller: globe)),
        if (onMap && mapStart != null)
          Positioned.fill(child: FlutterMap(
            options: MapOptions(initialCenter: mapStart!, initialZoom: 11),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.driftapp.drift_globe_poc',
              ),
              MarkerLayer(markers: [Marker(
                point: mapStart!, width: 42, height: 42,
                child: const Icon(Icons.location_on, color: brass, size: 38),
              )]),
            ],
          )),
        if (onMap)
          Positioned(top: 0, left: 0, right: 0, height: 175,
            child: IgnorePointer(child: DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [ink.withOpacity(.76), Colors.transparent],
              )),
            )),
          ),
        SafeArea(child: Stack(children: [
          Positioned(left: 20, right: 20, top: 12, child: Row(children: [
            if (onMap || choosingOnGlobe)
              IconButton(
                tooltip: 'Return to globe', onPressed: returnHome,
                icon: const Icon(Icons.arrow_back, color: brass),
              )
            else
              const Text('D R I F T', style: TextStyle(
                color: brass, letterSpacing: 4, fontWeight: FontWeight.w600,
              )),
            const Spacer(),
            if (onMap || choosingOnGlobe)
              Text(mode.toUpperCase(), style: const TextStyle(
                color: brass, letterSpacing: 2, fontSize: 13,
              )),
            const SizedBox(width: 12),
            const Icon(Icons.explore_outlined, color: brass),
          ])),
          if (!onMap && !choosingOnGlobe) ...[
            Positioned(left: 16, right: 16, bottom: 100, child: Row(children: [
              modeButton('Random', Icons.shuffle),
              modeButton('Intention', Icons.explore_outlined),
              modeButton('Dream', Icons.nights_stay_outlined),
            ])),
            Positioned(left: 34, right: 34, bottom: 18, child: Container(
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0xE6172838), borderRadius: BorderRadius.circular(35),
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                Icon(Icons.public, color: brass), Icon(Icons.route_outlined),
                Icon(Icons.bookmark_border), Icon(Icons.person_outline),
              ]),
            )),
          ],
          if (choosingOnGlobe)
            Positioned(left: 18, right: 18, bottom: 30, child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(22)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Tap the globe to choose your starting point', textAlign: TextAlign.center),
                const SizedBox(height: 10),
                if (selectedStart != null) ...[
                  Text('${selectedStart!.latitude.toStringAsFixed(3)}°, ${selectedStart!.longitude.toStringAsFixed(3)}°',
                    style: const TextStyle(color: brass)),
                  const SizedBox(height: 10),
                  FilledButton(onPressed: () => descendTo(selectedStart!),
                    child: const Text('Continue to exploration')),
                ],
              ]),
            )),
        ])),
        if (onMap)
          SafeArea(top: false, child: DraggableScrollableSheet(
            initialChildSize: .23, minChildSize: .11, maxChildSize: .88,
            snap: true, snapSizes: const [.23, .55],
            builder: (context, scroll) => Container(
              decoration: const BoxDecoration(color: panel,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
              child: ListView(controller: scroll,
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 32), children: [
                  Center(child: Container(width: 42, height: 4,
                    decoration: BoxDecoration(color: Colors.white38,
                      borderRadius: BorderRadius.circular(4)))),
                  const SizedBox(height: 20),
                  Text('$mode exploration', style: const TextStyle(fontSize: 22, color: brass)),
                  const SizedBox(height: 14),
                  const Text('Starting point selected. Destination generation is not implemented yet.'),
                  const SizedBox(height: 16),
                  if (mapStart != null) Text('Start: ${mapStart!.latitude.toStringAsFixed(4)}°, ${mapStart!.longitude.toStringAsFixed(4)}°'),
                ]),
            ),
          )),
        if (transitioning)
          const Positioned(top: 95, left: 0, right: 0,
            child: Center(child: Text('DESCENDING', style: TextStyle(
              color: brass, letterSpacing: 3, fontSize: 11)))),
      ]),
    ),
  );
}
