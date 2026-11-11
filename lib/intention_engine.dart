import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

const intentionCategories = <String>['Peace', 'Mystery', 'Adventure', 'Inspiration', 'Discovery', 'Connection'];

class IntentionResult {
  final LatLng point;
  final List<LatLng> route;
  final int roadMeters;
  final String explanation;
  const IntentionResult(this.point, this.route, this.roadMeters, this.explanation);
}

class _Influence {
  final LatLng center;
  final String tag;
  final double extent;
  const _Influence(this.center, this.tag, this.extent);
}

class IntentionEngine {
  final http.Client client;
  final Random random;
  IntentionEngine({http.Client? client, Random? random}) : client = client ?? http.Client(), random = random ?? Random();
  static const _tags = <String, List<String>>{
    'Peace': ['natural=wood', 'landuse=forest', 'leisure=park', 'natural=water'],
    'Mystery': ['historic=ruins', 'historic=archaeological_site', 'historic=monument', 'historic=castle'],
    'Adventure': ['natural=peak', 'natural=cliff', 'natural=wood', 'tourism=viewpoint'],
    'Inspiration': ['tourism=viewpoint', 'tourism=artwork', 'historic=monument', 'natural=water'],
    'Discovery': ['natural=wood', 'waterway=river', 'historic=monument', 'tourism=viewpoint'],
    'Connection': ['leisure=park', 'natural=beach', 'leisure=promenade', 'place=square'],
  };

  // Categories always win over contradictory descriptions. Only recognized, compatible
  // keywords contribute small bonuses; free text never becomes a destination query.
  static double descriptionBonus(String category, String description, String tag) {
    final text = description.toLowerCase();
    const hints = <String, Map<String, String>>{
      'Peace': {'forest':'wood', 'trees':'wood', 'water':'water', 'lake':'water', 'park':'park'},
      'Mystery': {'ruins':'ruins', 'ancient':'archaeological', 'castle':'castle', 'history':'historic'},
      'Adventure': {'mountain':'peak', 'cliff':'cliff', 'forest':'wood', 'view':'viewpoint'},
      'Inspiration': {'art':'artwork', 'view':'viewpoint', 'water':'water', 'history':'monument'},
      'Discovery': {'forest':'wood', 'river':'river', 'history':'monument', 'view':'viewpoint'},
      'Connection': {'beach':'beach', 'park':'park', 'square':'square', 'walk':'promenade'},
    };
    for (final entry in (hints[category] ?? {}).entries) {
      if (text.contains(entry.key) && tag.contains(entry.value)) return 8;
    }
    return 0;
  }

  Future<IntentionResult> generate({required LatLng origin, required double radiusMeters,
    required String category, String description = '', bool roadsOnly = true,
    Future<bool> Function(LatLng)? countryAllowed}) async {
    if (!intentionCategories.contains(category)) throw ArgumentError('Unknown intention');
    final distance = const Distance();
    final tags = _tags[category]!;
    // Cap public Overpass radius to avoid huge worldwide requests. Wider travel
    // radii still constrain generated points by the user's actual radius.
    final queryRadius = min(radiusMeters, 20000.0).round();
    final filters = tags.map((t) {
      final parts = t.split('=');
      return 'nwr["${parts[0]}"="${parts[1]}"](around:$queryRadius,${origin.latitude},${origin.longitude});';
    }).join();
    final query = '[out:json][timeout:18];($filters);out center 80;';
    final response = await client.post(Uri.parse('https://overpass.kumi.systems/api/interpreter'),
      headers: {'Content-Type':'application/x-www-form-urlencoded', 'User-Agent':'DriftPrototype/0.6'},
      body: {'data':query}).timeout(const Duration(seconds: 24));
    if (response.statusCode != 200) throw StateError('Geographic context is temporarily unavailable. Try again.');
    final data = jsonDecode(response.body) as Map<String,dynamic>;
    final elements = data['elements'] as List<dynamic>? ?? [];
    final influences = <_Influence>[];
    for (final raw in elements) {
      if (raw is! Map<String,dynamic>) continue;
      final center = raw['center'] is Map ? raw['center'] as Map : raw;
      final lat = center['lat']; final lon = center['lon'];
      if (lat is! num || lon is! num) continue;
      final point = LatLng(lat.toDouble(), lon.toDouble());
      if (distance.as(LengthUnit.Meter, origin, point) > radiusMeters + 3000) continue;
      final attrs = raw['tags'] is Map ? raw['tags'] as Map : <String,dynamic>{};
      final match = tags.firstWhere((t) { final p=t.split('='); return attrs[p[0]] == p[1]; }, orElse:()=>tags.first);
      final large = match.contains('wood') || match.contains('forest') || match.contains('water') || match.contains('river') || match.contains('beach');
      influences.add(_Influence(point, match, large ? 2500 : 500));
    }
    influences.shuffle(random);
    final candidates = <({LatLng point, double score, String reason})>[];
    final hour = DateTime.now().hour; // Approximation: device time, not destination local time.
    for (var i=0; i<28; i++) {
      final useInfluence = influences.isNotEmpty && (i < 21 || random.nextDouble() < .7);
      final influence = useInfluence ? influences[random.nextInt(influences.length)] : null;
      final base = influence?.center ?? origin;
      final extent = influence?.extent ?? radiusMeters;
      final meters = sqrt(random.nextDouble()) * min(extent, radiusMeters);
      final point = distance.offset(base, meters, random.nextDouble()*360);
      final direct = distance.as(LengthUnit.Meter, origin, point);
      if (direct > radiusMeters || direct < 50) continue;
      final temporal = category == 'Connection' && (hour >= 8 && hour <= 19) ? 8.0 : 0.0;
      final score = (influence == null ? 53.0 : 67.0) +
          (influence == null ? 0 : descriptionBonus(category, description, influence.tag)) + temporal + random.nextDouble()*10;
      candidates.add((point:point, score:score, reason:influence == null
        ? 'Exploratory geographic discovery' : 'Influenced by nearby ${influence.tag.replaceAll('=', ' / ')} terrain or features'));
    }
    candidates.sort((a,b)=>b.score.compareTo(a.score));
    // Verify a small shortlist to conserve public OSRM calls.
    final verified = <({IntentionResult result, double score})>[];
    for (final candidate in candidates.take(9)) {
      try {
        final raw = candidate.point;
        final nearest = await client.get(Uri.parse('https://router.project-osrm.org/nearest/v1/driving/${raw.longitude},${raw.latitude}?number=1'))
          .timeout(const Duration(seconds: 9));
        if (nearest.statusCode != 200) continue;
        final snap = jsonDecode(nearest.body) as Map<String,dynamic>;
        final ways = snap['waypoints'] as List?;
        if (ways == null || ways.isEmpty) continue;
        final way = ways.first as Map;
        final snapMeters = (way['distance'] as num?)?.toDouble() ?? double.infinity;
        if (snapMeters > (roadsOnly ? 100 : 1500)) continue;
        final coords = way['location'] as List;
        final point = LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble());
        if (distance.as(LengthUnit.Meter, origin, point) > radiusMeters ||
            distance.as(LengthUnit.Meter, origin, point) < 50) continue;
        final routeResponse = await client.get(Uri.parse('https://router.project-osrm.org/route/v1/driving/${origin.longitude},${origin.latitude};${point.longitude},${point.latitude}?overview=full&geometries=geojson'))
          .timeout(const Duration(seconds: 12));
        if (routeResponse.statusCode != 200) continue;
        final routeData = jsonDecode(routeResponse.body) as Map<String,dynamic>;
        final routes = routeData['routes'] as List?;
        if (routes == null || routes.isEmpty) continue;
        final route = routes.first as Map;
        final length = (route['distance'] as num).toDouble();
        if (length > radiusMeters) continue;
        if (countryAllowed != null && !await countryAllowed(point)) continue;
        final line = ((route['geometry'] as Map)['coordinates'] as List)
          .map((c)=>LatLng((c[1] as num).toDouble(),(c[0] as num).toDouble())).toList();
        if (line.length < 2) continue;
        verified.add((result:IntentionResult(point,line,length.round(),candidate.reason),score:candidate.score));
        if (verified.length >= 4) break;
      } catch (_) { continue; }
    }
    if (verified.isEmpty) throw StateError('No matching route-verified point found. Try a larger radius or different intention.');
    final pool = verified.where((e)=>e.score>=65).toList();
    final eligible = pool.isEmpty ? verified.where((e)=>e.score>=50).toList() : pool;
    final weights = eligible.map((e)=>pow(max(1,e.score-(pool.isEmpty?50:65)+1),2).toDouble()).toList();
    var ticket = random.nextDouble()*weights.reduce((a,b)=>a+b);
    for (var i=0;i<eligible.length;i++) { ticket-=weights[i]; if(ticket<=0) return eligible[i].result; }
    return eligible.last.result;
  }
}
