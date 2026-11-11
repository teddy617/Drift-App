import 'features/intention/intention_engine.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final MapController mapController = MapController();
  final DraggableScrollableController sheetController = DraggableScrollableController();
  bool onMap = false;
  bool transitioning = false;
  bool choosingOnGlobe = false;
  String mode = 'Random';
  String intentionCategory = 'Peace';
  final TextEditingController intentionDescription = TextEditingController();
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

  Future<void> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      accessibleRoadsOnly = prefs.getBool('roads') ?? true;
      restrictCountry = prefs.getBool('country') ?? true;
      metricUnits = prefs.getBool('metric') ?? false;
    });
  }

  Future<void> savePreference(String key, bool value) async {
    setState(() {
      if (key == 'roads') accessibleRoadsOnly = value;
      if (key == 'country') restrictCountry = value;
      if (key == 'metric') metricUnits = value;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> openSettings() async {
    await Navigator.push(context, MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Settings'), backgroundColor: ink),
        body: StatefulBuilder(builder: (context, refresh) => ListView(
          padding: const EdgeInsets.all(16), children: [
            SwitchListTile(
              title: const Text('Accessible roads and paths'),
              subtitle: const Text('Prefer points close to mapped driving roads'),
              value: accessibleRoadsOnly,
              onChanged: (v) { savePreference('roads', v); refresh(() {}); }),
            SwitchListTile(
              title: const Text('Stay within starting country'),
              value: restrictCountry,
              onChanged: (v) { savePreference('country', v); refresh(() {}); }),
            SwitchListTile(
              title: const Text('Use kilometers'),
              subtitle: const Text('Off: miles'),
              value: metricUnits,
              onChanged: (v) { savePreference('metric', v); refresh(() {}); }),
            const Divider(),
            const Text(accessibilityWarning),
            const SizedBox(height: 12),
            const Text('Road routing cannot verify legal access, closures or pedestrian paths.',
              style: TextStyle(color: Colors.white70)),
          ])),
      )));
  }

  void fitRoute() {
    if (!mounted || routePoints.isEmpty || destination == null || mapStart == null) return;
    final bounds = LatLngBounds.fromPoints([mapStart!, ...routePoints, destination!]);
    mapController.fitCamera(CameraFit.bounds(
      bounds: bounds,
      padding: EdgeInsets.fromLTRB(35, MediaQuery.of(context).padding.top + 90,
          35, MediaQuery.of(context).size.height * .20 + 45),
      maxZoom: 17,
    ));
    if (sheetController.isAttached) {
      sheetController.animateTo(.038,
        duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
    }
  }

  int? roadDistanceMeters;

  Future<void> openGoogleMaps() async {
    if (destination == null) return;
    final d = destination!;
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1', 'destination': '${d.latitude},${d.longitude}',
      'travelmode': 'driving',
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      showMessage('Could not open Google Maps.');
    }
  }

  Future<void> startJourney() async {
    if (destination == null || routePoints.isEmpty) return;
    if (!await Geolocator.isLocationServiceEnabled()) {
      showMessage('Enable location services to start a journey.'); return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      showMessage('Location permission is required for live journey tracking.'); return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => JourneyScreen(
      destination: destination!, route: List.of(routePoints),
      metricUnits: metricUnits, warning: accessibilityWarning,
    )));
  }


  Future<void> findIntentionDestination() async {
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
      String? originCountry;
      if (restrictCountry) {
        originCountry = await countryCodeFor(origin);
        if (originCountry == null) throw StateError('Could not verify starting country.');
      }
      final result = await IntentionEngine().generate(
        origin: origin,
        radiusMeters: radiusMeters,
        category: intentionCategory,
        description: intentionDescription.text,
        roadsOnly: accessibleRoadsOnly,
        countryAllowed: originCountry == null ? null : (point) async =>
          await countryCodeFor(point) == originCountry,
      );
      if (!mounted) return;
      setState(() {
        destination = result.point;
        destinationName = 'Unmarked ${intentionCategory.toLowerCase()} discovery';
        routePoints = result.route;
        roadDistanceMeters = result.roadMeters;
        searching = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => fitRoute());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        searching = false;
        explorationError = e.toString().replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');
      });
    }
  }

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
        WidgetsBinding.instance.addPostFrameCallback((_) => fitRoute());
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
    intentionDescription.dispose();
    distanceInput.dispose();
    distanceFocus.dispose();
    sheetController.dispose();
    mapController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    loadPreferences();
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
    await Future<void>.delayed(const Duration(milliseconds: 3800));
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
            mapController: mapController,
            options: MapOptions(initialCenter: mapStart!, initialZoom: 11),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.driftapp.drift_globe_poc',
              ),
              if (routePoints.isNotEmpty) ...[
                PolylineLayer(polylines: [Polyline(
                  points: routePoints, strokeWidth: 13, color: brass.withOpacity(.25),
                )]),
                PolylineLayer(polylines: [Polyline(
                  points: routePoints, strokeWidth: 5, color: const Color(0xFFFFD58B),
                )]),
              ],
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
            IconButton(tooltip: 'Settings', onPressed: openSettings,
              icon: const Icon(Icons.settings_outlined, color: brass)),
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
            controller: sheetController,
            initialChildSize: .23, minChildSize: .038, maxChildSize: .88,
            snap: true, snapSizes: const [.038, .23, .55],
            builder: (context, scroll) => Container(
              decoration: const BoxDecoration(color: panel,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
              child: ListView(controller: scroll,
                padding: const EdgeInsets.fromLTRB(24, 9, 24, 32), children: [
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
                      const SizedBox(height: 10),
                      FilledButton.icon(onPressed: startJourney,
                        icon: const Icon(Icons.explore), label: const Text('Start Journey')),
                      OutlinedButton.icon(onPressed: openGoogleMaps,
                        icon: const Icon(Icons.map_outlined), label: const Text('Open in Google Maps')),

                    ],
                    if (explorationError != null) Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(explorationError!, style: const TextStyle(color: Color(0xFFFFB5A7))),
                    ),
                  ] else if (mode == 'Intention') ...[
                    const Text('Choose what you seek. Drift generates an unexpected point influenced by the surroundings, not an attraction entrance.'),
                    const SizedBox(height: 12),
                    Wrap(spacing: 6, runSpacing: 6, children: intentionCategories.map((category) =>
                      ChoiceChip(label: Text(category), selected: intentionCategory == category,
                        onSelected: searching ? null : (_) => setState(() => intentionCategory = category))).toList()),
                    const SizedBox(height: 10),
                    TextField(controller: intentionDescription, maxLength: 140, maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Describe your intention (optional)')),
                    Text('Radius: $radiusLabel', style: const TextStyle(color: brass)),
                    Slider(value: radiusSliderPosition.clamp(0.0, 1.0), min: 0, max: 1,
                      onChanged: searching ? null : (value) => setRadius(radiusFromSlider(value))),
                    Row(children: [
                      Expanded(child: TextField(controller: distanceInput, focusNode: distanceFocus,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Distance (miles)', isDense: true),
                        onSubmitted: (_) => applyDistanceInput())),
                      TextButton(onPressed: searching ? null : applyDistanceInput, child: const Text('Apply')),
                    ]),
                    const SizedBox(height: 8),
                    FilledButton.icon(onPressed: searching ? null : findIntentionDestination,
                      icon: const Icon(Icons.explore_outlined),
                      label: Text(destination == null ? 'Find my Drift' : 'Find another')),
                    if (searching) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
                    if (destinationName != null) ...[
                      const SizedBox(height: 10),
                      Text(destinationName!, style: const TextStyle(color: brass, fontSize: 18)),
                      if (roadDistanceMeters != null) Text('Route verified: ${metricUnits ? (roadDistanceMeters! / 1000).toStringAsFixed(1) + ' km' : (roadDistanceMeters! / 1609.344).toStringAsFixed(1) + ' mi'}'),
                      const Text('Context is estimated. A routable road does not guarantee a suitable stopping place.'),
                      FilledButton.icon(onPressed: startJourney, icon: const Icon(Icons.explore), label: const Text('Start Journey')),
                      OutlinedButton.icon(onPressed: openGoogleMaps, icon: const Icon(Icons.map_outlined), label: const Text('Open in Google Maps')),
                    ],
                    if (explorationError != null) Text(explorationError!, style: const TextStyle(color: Color(0xFFFFB5A7))),
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


/// Full-screen, foreground-only journey tracking. No background tracking or turn-by-turn guidance.
class JourneyScreen extends StatefulWidget {
  final LatLng destination;
  final List<LatLng> route;
  final bool metricUnits;
  final String warning;
  const JourneyScreen({super.key, required this.destination, required this.route,
    required this.metricUnits, required this.warning});
  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  final MapController map = MapController();
  StreamSubscription<Position>? gps;
  StreamSubscription<CompassEvent>? compass;
  LatLng? current;
  double? heading;
  bool paused = false;
  bool phoneAway = false;
  bool follow = true;
  bool northUp = false;
  bool mapReady = false;
  String status = 'Waiting for GPS';
  late final String noteKey = 'journey_note_${widget.destination.latitude.toStringAsFixed(5)}_${widget.destination.longitude.toStringAsFixed(5)}';
  final TextEditingController note = TextEditingController();

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) note.text = prefs.getString(noteKey) ?? '';
    });
    startSensors();
    acquireInitialLocation();
  }

  Future<void> acquireInitialLocation() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12));
      if (!mounted) return;
      final point = LatLng(p.latitude, p.longitude);
      setState(() { current = point; status = 'Tracking location'; });
      if (mapReady && follow) map.move(point, 18);
    } catch (_) {
      if (mounted && current == null) setState(() => status = 'Waiting for GPS — tap recenter when available');
    }
  }

  void startSensors() {
    gps?.cancel();
    compass?.cancel();
    gps = Geolocator.getPositionStream(locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high, distanceFilter: 5,
    )).listen((p) {
      if (!mounted || paused) return;
      final point = LatLng(p.latitude, p.longitude);
      setState(() { current = point; status = 'Tracking location'; });
      if (follow && mapReady) map.move(point, map.camera.zoom < 17.5 ? 18 : map.camera.zoom);
    }, onError: (_) { if (mounted) setState(() => status = 'GPS unavailable'); });
    compass = FlutterCompass.events?.listen((event) {
      if (!mounted || paused) return;
      final value = event.heading;
      if (value == null || !value.isFinite) return;
      setState(() => heading = value);
      if (!northUp && mapReady) map.rotate(-value);
    });
  }

  String get remaining {
    if (current == null) return 'Locating…';
    final meters = const Distance().as(LengthUnit.Meter, current!, widget.destination);
    return widget.metricUnits ? '${(meters / 1000).toStringAsFixed(1)} km away'
        : '${(meters / 1609.344).toStringAsFixed(1)} mi away';
  }

  void recenter() {
    if (current == null || !mapReady) return;
    setState(() => follow = true);
    map.move(current!, 18);
  }

  Future<void> openNotebook() async {
    await showModalBottomSheet<void>(context: context, isScrollControlled: true,
      backgroundColor: const Color(0xFF1B2D3C),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(sheetContext).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Journey notebook', style: TextStyle(fontSize: 22, color: brass)),
            const SizedBox(height: 12),
            TextField(controller: note, maxLines: 6, minLines: 3,
              decoration: const InputDecoration(hintText: 'What do you notice?', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            FilledButton.icon(icon: const Icon(Icons.save_outlined), label: const Text('Save note'),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(noteKey, note.text);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              }),
          ]),
      ));
  }

  Future<void> finishJourney({bool arrived = false}) async {
    if (arrived) {
      final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        title: const Text('Confirm arrival'),
        content: const Text('Have you reached your destination?'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('I have arrived'))],
      ));
      if (yes != true || !mounted) return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(noteKey, note.text);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    gps?.cancel(); compass?.cancel(); note.dispose(); map.dispose(); super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) { if (!didPop) finishJourney(); },
    child: Scaffold(body: Stack(children: [
      Positioned.fill(child: FlutterMap(
        mapController: map,
        options: MapOptions(initialCenter: current ?? widget.route.first, initialZoom: 18,
          onMapReady: () { mapReady = true; if (current != null) recenter(); },
          onPositionChanged: (_, hasGesture) { if (hasGesture && follow) setState(() => follow = false); }),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.driftapp.drift_globe_poc'),
          PolylineLayer(polylines: [Polyline(points: widget.route, strokeWidth: 15,
            color: brass.withOpacity(.28))]),
          PolylineLayer(polylines: [Polyline(points: widget.route, strokeWidth: 5,
            color: const Color(0xFFFFD58B))]),
          MarkerLayer(markers: [
            Marker(point: widget.destination, width: 48, height: 48,
              child: const Icon(Icons.place, color: Color(0xFFFFC18B), size: 42)),
            if (current != null) Marker(point: current!, width: 42, height: 42,
              child: const Icon(Icons.navigation, color: Colors.lightBlueAccent, size: 32)),
          ]),
        ])),
      Positioned(top: 0, left: 0, right: 0, height: 170, child: IgnorePointer(
        child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [ink.withOpacity(.9), Colors.transparent]))))),
      SafeArea(child: Stack(children: [
        Positioned(top: 8, left: 12, right: 12, child: Row(children: [
          IconButton(onPressed: () => finishJourney(), icon: const Icon(Icons.arrow_back, color: brass)),
          const Text('J O U R N E Y', style: TextStyle(color: brass, letterSpacing: 3)),
          const Spacer(),
          IconButton(tooltip: 'Notebook', onPressed: openNotebook,
            icon: const Icon(Icons.menu_book_outlined, color: brass)),
          IconButton(tooltip: 'Phone away', onPressed: () => setState(() => phoneAway = true),
            icon: const Icon(Icons.nights_stay_outlined, color: brass)),
        ])),
        Positioned(top: 70, right: 18, child: GestureDetector(
          onTap: () { setState(() => northUp = !northUp); if (mapReady) map.rotate(northUp ? 0 : -(heading ?? 0)); },
          child: Container(width: 86, height: 86,
            decoration: BoxDecoration(color: panel, shape: BoxShape.circle,
              border: Border.all(color: brass.withOpacity(.7))),
            child: Transform.rotate(angle: (northUp ? 0 : -(heading ?? 0)) * pi / 180,
              child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.navigation, color: brass, size: 29),
                Text('N', style: TextStyle(color: brass, fontSize: 12)),
              ])),
          ))),
        Positioned(right: 16, bottom: 170, child: FloatingActionButton.small(
          heroTag: 'recenter', backgroundColor: panel, foregroundColor: brass,
          onPressed: recenter, child: const Icon(Icons.my_location))),
        Positioned(bottom: 10, left: 12, right: 12, child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(20)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(remaining, style: const TextStyle(color: brass, fontSize: 21)),
            Text(status, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 7),
            Text(widget.warning, style: const TextStyle(fontSize: 10, color: Colors.white70)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => setState(() {
                paused = !paused; status = paused ? 'Paused' : 'Tracking location';
                if (!paused) startSensors();
              }), child: Text(paused ? 'Resume' : 'Pause'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: () => finishJourney(arrived: true),
                child: const Text('I arrived'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton(onPressed: () => finishJourney(),
                child: const Text('End'))),
            ]),
          ]))),
      ])),
      if (phoneAway) Positioned.fill(child: Material(color: ink,
        child: InkWell(onTap: () => setState(() => phoneAway = false),
          child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.nights_stay_outlined, color: brass, size: 64),
            SizedBox(height: 20),
            Text('THE JOURNEY CONTINUES', style: TextStyle(color: brass, letterSpacing: 3)),
            SizedBox(height: 16),
            Text('Tap to return to the map', style: TextStyle(color: Colors.white70)),
          ]))))),
    ])));
}
