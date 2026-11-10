import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
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
  LatLng? destination;
  String? destinationName;
  List<LatLng> routePoints = [];
  bool searching = false;
  String? explorationError;
  double distanceMiles = 25;
  bool accessibleRoadsOnly = true;
  bool restrictCountry = true;
  bool metricUnits = false;
  final TextEditingController distanceInput = TextEditingController(text: '25');
  final FocusNode distanceFocus = FocusNode();
  static const double milesToMeters = 1609.344;
  static const String accessibilityWarning =
    'Route verified does not guarantee public access, safe conditions, '
    'or that a location is suitable to visit. Check local restrictions and conditions.';
  double get radiusMeters => distanceMiles * milesToMeters;

  // Logarithmic slider: precise at short ranges, useful through 1,000 miles.
  double get radiusSliderPosition => log(distanceMiles / 0.1) / log(10000);
  double radiusFromSlider(double value) => 0.1 * pow(10000, value).toDouble();
  String get radiusLabel => metricUnits
      ? '${(distanceMiles * 1.609344).toStringAsFixed(1)} km'
      : '${distanceMiles.toStringAsFixed(distanceMiles < 10 ? 1 : 0)} mi';

  void setRadius(double miles) {
    final adjusted = miles.clamp(0.1, 1000.0).toDouble();
    setState(() => distanceMiles = adjusted);
    distanceInput.text = adjusted.toStringAsFixed(adjusted < 10 ? 1 : 0);
  }

  void applyDistanceInput() {
    final raw = double.tryParse(distanceInput.text.trim());
    if (raw == null || !raw.isFinite || raw < 0.1 || raw > 1000) {
      showMessage('Enter a distance between 0.1 and 1,000 miles.');
      distanceInput.text = distanceMiles.toStringAsFixed(1);
      return;
    }
    setRadius(raw);
    distanceFocus.unfocus();
  }

  int? roadDistanceMeters;

  Future<void> findRandomDestination() async {
    final origin = mapStart;
    if (origin == null || searching) return;
    applyDistanceInput();
    setState(() {
      searching = true;
      explorationError = null;
      destination = null;
      destinationName = null;
      routePoints = [];
      roadDistanceMeters = null;
    });
    try {
      final rng = Random.secure();
      final distance = const Distance();
      // Uniform sampling by area within a circle, rather than choosing POIs.
      // OSRM snaps the random point to a routable road. This is a prototype,
      // not a guarantee of legal access or complete geographic uniformity.
      // Limit requests to respect public demo service capacity.
      String? originCountry;
      if (restrictCountry) {
        originCountry = await countryCodeFor(origin);
        if (originCountry == null) {
          throw Exception('Country restriction could not be verified. Try again later or disable the restriction.');
        }
      }
      for (var attempt = 0; attempt < 5; attempt++) {
        final bearing = rng.nextDouble() * 360;
        final meters = sqrt(rng.nextDouble()) * radiusMeters;
        final raw = distance.offset(origin, meters, bearing);
        // OSRM nearest: one road-network snap, max 1.5 km away.
        final nearestUrl = Uri.parse(
          'https://router.project-osrm.org/nearest/v1/driving/'
          '${raw.longitude},${raw.latitude}?number=1');
        final nearestRes = await http.get(nearestUrl).timeout(const Duration(seconds: 10));
        if (nearestRes.statusCode != 200) continue;
        final nearest = jsonDecode(nearestRes.body) as Map<String, dynamic>;
        final waypoints = nearest['waypoints'] as List<dynamic>?;
        if (nearest['code'] != 'Ok' || waypoints == null || waypoints.isEmpty) continue;
        final waypoint = waypoints.first as Map<String, dynamic>;
        final snapDistance = (waypoint['distance'] as num?)?.toDouble() ?? double.infinity;
        if (snapDistance > 1500) continue;
        final coords = waypoint['location'] as List<dynamic>;
        final target = LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble());
        final directDistance = distance.as(LengthUnit.Meter, origin, target);
        if (directDistance > radiusMeters || directDistance < 50) continue;
        // With safety enabled, accept only points snapped close to roads.
        if (accessibleRoadsOnly && snapDistance > 100) continue;
        final url = Uri.parse('https://router.project-osrm.org/route/v1/driving/'
            '${origin.longitude},${origin.latitude};${target.longitude},${target.latitude}'
            '?overview=full&geometries=geojson');
        final res = await http.get(url).timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) continue;
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final routes = data['routes'] as List<dynamic>?;
        if (data['code'] != 'Ok' || routes == null || routes.isEmpty) continue;
        final route = routes.first as Map<String, dynamic>;
        final routeDistance = (route['distance'] as num).toDouble();
        if (routeDistance > radiusMeters) continue;
        if (restrictCountry && await countryCodeFor(target) != originCountry) continue;
        final geometry = route['geometry'] as Map<String, dynamic>;
        final line = (geometry['coordinates'] as List<dynamic>)
            .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();
        if (line.length < 2) continue;
        if (!mounted) return;
        setState(() {
          destinationName = 'Unmarked discovery';
          destination = target;
          routePoints = line;
          roadDistanceMeters = routeDistance.round();
          searching = false;
        });
        return;
      }
      throw Exception('No route-verified random point found within this radius. '
          'Try a larger distance or adjust restrictions.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        explorationError = e.toString().replaceFirst('Exception: ', '');
        searching = false;
      });
    }
  }

  // Public Nominatim is used sparingly for a prototype country check.
  // Production requires a suitable hosted country-boundary data service.
  Future<String?> countryCodeFor(LatLng point) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2', 'lat': '${point.latitude}',
        'lon': '${point.longitude}', 'zoom': '3', 'addressdetails': '1',
      });
      final response = await http.get(uri, headers: {
        'User-Agent': 'DriftPrototype/0.5 (testing; contact: https://github.com/teddy617/Drift-App)',
        'Accept-Language': 'en',
      }).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final address = decoded['address'];
      if (address is! Map<String, dynamic>) return null;
      return (address['country_code'] as String?)?.toUpperCase();
    } catch (_) { return null; }
  }


  @override
  void dispose() {
    distanceInput.dispose();
    distanceFocus.dispose();
    super.dispose();
  }

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
    setState(() { transitioning = true; choosingOnGlobe = false; mapStart = point; destination = null; destinationName = null; routePoints = []; explorationError = null; });
    try {
      await globe.runJavaScript('window.flyTo(${point.latitude}, ${point.longitude})');
    } catch (_) { /* Map still opens if globe scripts are unavailable. */ }
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    if (!mounted) return;
    setState(() { onMap = true; transitioning = false; });
  }

  void returnHome() {
    if (onMap) {
      setState(() { onMap = false; mapStart = null; destination = null; routePoints = []; explorationError = null; });
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
            key: ValueKey('${mapStart!.latitude},${mapStart!.longitude},${destination?.latitude},${destination?.longitude}'),
            options: MapOptions(initialCenter: destination == null ? mapStart! : LatLng((mapStart!.latitude + destination!.latitude)/2, (mapStart!.longitude + destination!.longitude)/2), initialZoom: destination == null ? 11 : (distanceMiles >= 150 ? 6 : distanceMiles >= 50 ? 8 : 10)),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.driftapp.drift_globe_poc',
              ),
              if (routePoints.isNotEmpty) PolylineLayer(polylines: [Polyline(
                points: routePoints, strokeWidth: 5, color: brass,
              )]),
              MarkerLayer(markers: [
                Marker(point: mapStart!, width: 42, height: 42,
                  child: const Icon(Icons.my_location, color: brass, size: 34)),
                if (destination != null) Marker(point: destination!, width: 42, height: 42,
                  child: const Icon(Icons.place, color: Color(0xFFE8A47B), size: 38)),
              ]),
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
                  if (mode == 'Random') ...[
                    const Text('Drift generates a random reachable point, not a selected attraction.'),
                    const SizedBox(height: 12),
                    Text('Radius: $radiusLabel', style: const TextStyle(color: brass)),
                    Slider(
                      value: radiusSliderPosition.clamp(0.0, 1.0),
                      min: 0, max: 1,
                      onChanged: searching ? null : (value) => setRadius(radiusFromSlider(value)),
                    ),
                    Row(children: [
                      Expanded(child: TextField(
                        controller: distanceInput,
                        focusNode: distanceFocus,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Distance (miles)', isDense: true),
                        onSubmitted: (_) => applyDistanceInput(),
                      )),
                      TextButton(onPressed: searching ? null : applyDistanceInput,
                        child: const Text('Apply')),
                    ]),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Accessible roads and paths'),
                      subtitle: const Text('Strict road proximity; enabled by default'),
                      value: accessibleRoadsOnly,
                      onChanged: searching ? null : (value) => setState(() => accessibleRoadsOnly = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Stay within starting country'),
                      subtitle: const Text('US-only when your starting point is in the US'),
                      value: restrictCountry,
                      onChanged: searching ? null : (value) => setState(() => restrictCountry = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Use kilometers'),
                      value: metricUnits,
                      onChanged: (value) => setState(() => metricUnits = value),
                    ),
                    const Text(accessibilityWarning,
                      style: TextStyle(color: Color(0xFFE0C7A2), fontSize: 12)),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: searching ? null : findRandomDestination,
                      icon: const Icon(Icons.shuffle),
                      label: Text(destination == null ? 'Find a destination' : 'Find another'),
                    ),
                    if (searching) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
                    if (destinationName != null) ...[
                      const SizedBox(height: 10),
                      Text(destinationName!, style: const TextStyle(color: brass, fontSize: 18)),
                      if (roadDistanceMeters != null) Text('Route verified: ${metricUnits ? (roadDistanceMeters! / 1000).toStringAsFixed(1) + ' km' : (roadDistanceMeters! / 1609.344).toStringAsFixed(1) + ' mi'}'),
                      const Text('Route preview only. No turn-by-turn navigation.'),
                    ],
                    if (explorationError != null) Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(explorationError!, style: const TextStyle(color: Color(0xFFFFB5A7))),
                    ),
                  ] else
                    const Text('Destination generation for this mode comes in a later version.'),
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
