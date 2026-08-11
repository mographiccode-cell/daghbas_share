import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app_locale.dart';
import '../models/ai_status.dart';
import '../models/place.dart';
import '../services/api_service.dart';
import '../widgets/model_status_banner.dart';
import '../widgets/place_card.dart';
import 'ai_status_screen.dart';
import 'favorites_screen.dart';
import 'map_screen.dart';
import 'place_screen.dart';
import 'preferences_screen.dart';
import 'settings_screen.dart';
import 'top_rated_screen.dart';

class AppShellScreen extends StatefulWidget {
  final ApiService api;
  final VoidCallback onLogout;
  const AppShellScreen({super.key, required this.api, required this.onLogout});

  @override
  State<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends State<AppShellScreen> {
  final search = TextEditingController();
  final country = TextEditingController();
  final city = TextEditingController();
  final area = TextEditingController();

  int tab = 0;
  bool loading = false;
  bool locationUnavailable = false;
  String? error;
  String activeLocationLabel = '';
  Map<String, dynamic>? health;
  AiStatus? aiStatus;

  List<Place> places = [];
  final Set<String> compareSelection = {};

  double? lastLat;
  double? lastLng;

  double minRating = 0;
  double minPrice = 1;
  double maxPrice = 4;
  double maxDistance = 50;
  int minReviews = 0;
  String placeType = 'all';
  String cuisine = 'all';
  String sortMode = 'ai';

  String get languageCode => appLocale.value.languageCode;
  bool get ar => languageCode == 'ar';
  String tr(BuildContext context, String en, String arabic) => ar ? arabic : en;

  static const cuisineOptions = [
    'all', 'restaurant', 'cafe', 'italian', 'mexican', 'chinese', 'japanese', 'indian',
    'thai', 'mediterranean', 'middle_eastern', 'burger', 'barbecue', 'seafood',
    'coffee', 'dessert', 'breakfast', 'bakery', 'vegetarian',
  ];

  @override
  void initState() {
    super.initState();
    appLocale.addListener(_localeChanged);
    _loadSystemStatus();
  }

  @override
  void dispose() {
    appLocale.removeListener(_localeChanged);
    search.dispose();
    country.dispose();
    city.dispose();
    area.dispose();
    super.dispose();
  }

  void _localeChanged() {
    if (!mounted) return;
    setState(() {});
    if (places.isNotEmpty || country.text.isNotEmpty || city.text.isNotEmpty || area.text.isNotEmpty) {
      runSearch();
    }
  }

  Future<void> _loadSystemStatus() async {
    try {
      final results = await Future.wait([widget.api.health(), widget.api.aiStatus()]);
      if (!mounted) return;
      setState(() {
        health = results[0] as Map<String, dynamic>;
        aiStatus = results[1] as AiStatus;
      });
    } catch (_) {
      // A friendly discovery error is shown only when the user starts a search.
    }
  }

  Future<void> useCurrentLocation() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => locationUnavailable = true);
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final result = await widget.api.nearby(pos.latitude, pos.longitude, radius: 50000, languageCode: languageCode);
      if (!mounted) return;
      setState(() {
        lastLat = pos.latitude;
        lastLng = pos.longitude;
        locationUnavailable = false;
        activeLocationLabel = tr(context, 'Current location', 'الموقع الحالي');
        country.clear();
        city.clear();
        area.clear();
        places = result;
        compareSelection.clear();
        tab = 0;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> runSearch() async {
    final query = search.text.trim();
    final locationParts = [area.text.trim(), city.text.trim(), country.text.trim()].where((x) => x.isNotEmpty).toList();
    if (query.length < 2 && locationParts.isEmpty && lastLat == null) {
      await showLocationPicker();
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = locationParts.isNotEmpty
          ? await widget.api.discover(
              country: country.text.trim(),
              city: city.text.trim(),
              area: area.text.trim(),
              query: query,
              languageCode: languageCode,
            )
          : query.isNotEmpty
              ? await widget.api.searchPlaces(query, lat: lastLat, lng: lastLng, languageCode: languageCode)
              : await widget.api.nearby(lastLat!, lastLng!, radius: 50000, languageCode: languageCode);
      if (!mounted) return;
      setState(() {
        places = result;
        compareSelection.clear();
        if (locationParts.isNotEmpty) activeLocationLabel = locationParts.join(', ');
        tab = 0;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> showLocationPicker() async {
    var tempCountry = country.text;
    var tempCity = city.text;
    var tempArea = area.text;

    final selection = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(sheetContext).bottom),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Theme.of(sheetContext).colorScheme.primaryContainer,
                      child: const Icon(Icons.public_rounded),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(tr(sheetContext, 'Choose where to explore', 'اختر مكان الاستكشاف'), style: Theme.of(sheetContext).textTheme.headlineSmall)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(tr(sheetContext, 'Search any country, city, or area worldwide, or use your current location.', 'ابحث في أي دولة أو مدينة أو منطقة حول العالم، أو استخدم موقعك الحالي.')),
                const SizedBox(height: 18),
                TextFormField(
                  initialValue: tempCountry,
                  textInputAction: TextInputAction.next,
                  onChanged: (value) => tempCountry = value,
                  decoration: InputDecoration(labelText: tr(sheetContext, 'Country', 'الدولة'), prefixIcon: const Icon(Icons.public_outlined)),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: tempCity,
                  textInputAction: TextInputAction.next,
                  onChanged: (value) => tempCity = value,
                  decoration: InputDecoration(labelText: tr(sheetContext, 'City', 'المدينة'), prefixIcon: const Icon(Icons.location_city_outlined)),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: tempArea,
                  textInputAction: TextInputAction.done,
                  onChanged: (value) => tempArea = value,
                  decoration: InputDecoration(labelText: tr(sheetContext, 'Area / district', 'المنطقة / الحي'), prefixIcon: const Icon(Icons.map_outlined)),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    final values = [tempCountry.trim(), tempCity.trim(), tempArea.trim()];
                    if (values.every((x) => x.isEmpty)) return;
                    Navigator.pop(sheetContext, {
                      'mode': 'manual',
                      'country': values[0],
                      'city': values[1],
                      'area': values[2],
                    });
                  },
                  icon: const Icon(Icons.travel_explore_rounded),
                  label: Text(tr(sheetContext, 'Explore this location', 'استكشف هذا الموقع')),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(sheetContext, {'mode': 'gps'}),
                  icon: const Icon(Icons.my_location_rounded),
                  label: Text(tr(sheetContext, 'Use current location', 'استخدم الموقع الحالي')),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!mounted || selection == null) return;
    if (selection['mode'] == 'gps') {
      await useCurrentLocation();
      return;
    }

    country.text = selection['country'] ?? '';
    city.text = selection['city'] ?? '';
    area.text = selection['area'] ?? '';
    setState(() {
      lastLat = null;
      lastLng = null;
      if (sortMode == 'distance') sortMode = 'ai';
    });
    await runSearch();
  }

  bool _matchesType(Place p, String wanted) {
    final values = p.types.map((x) => x.toLowerCase().replaceAll('-', '_')).toList();
    return values.any((x) {
      if (x == wanted || x.contains(wanted)) return true;
      if (wanted == 'cafe' && x.contains('coffee')) return true;
      if (wanted == 'burger' && (x.contains('burger') || x.contains('hamburger'))) return true;
      if (wanted == 'middle_eastern' && (x.contains('middle_eastern') || x.contains('middle eastern'))) return true;
      if (wanted == 'barbecue' && (x.contains('grill') || x.contains('barbecue') || x.contains('bbq'))) return true;
      return false;
    });
  }

  List<Place> get filtered {
    final result = places.where((p) {
      return (placeType == 'all' || _matchesType(p, placeType)) &&
          (cuisine == 'all' || _matchesType(p, cuisine)) &&
          p.rating >= minRating &&
          p.reviewCount >= minReviews &&
          ((minPrice <= 1 && maxPrice >= 4) || (p.priceLevel > 0 && p.priceLevel >= minPrice && p.priceLevel <= maxPrice)) &&
          ((lastLat == null || lastLng == null) || !p.distanceKnown || p.distanceKm <= maxDistance);
    }).toList();

    if (sortMode == 'rating') {
      result.sort((a, b) {
        final ratingCmp = b.rating.compareTo(a.rating);
        return ratingCmp != 0 ? ratingCmp : b.reviewCount.compareTo(a.reviewCount);
      });
    } else if (sortMode == 'distance') {
      result.sort((a, b) {
        if (a.distanceKnown != b.distanceKnown) return a.distanceKnown ? -1 : 1;
        return a.distanceKm.compareTo(b.distanceKm);
      });
    } else {
      result.sort((a, b) => a.aiRank.compareTo(b.aiRank));
    }
    return result;
  }

  List<Place> get topRated {
    final list = [...filtered];
    list.sort((a, b) {
      final ratingCmp = b.rating.compareTo(a.rating);
      return ratingCmp != 0 ? ratingCmp : b.reviewCount.compareTo(a.reviewCount);
    });
    return list;
  }

  int get activeFilterCount {
    var count = 0;
    if (placeType != 'all') count++;
    if (cuisine != 'all') count++;
    if (minRating > 0) count++;
    if (minReviews > 0) count++;
    if (minPrice > 1 || maxPrice < 4) count++;
    if (lastLat != null && lastLng != null && maxDistance < 50) count++;
    if (sortMode != 'ai') count++;
    return count;
  }

  String cuisineLabel(String value) {
    const labels = {
      'all': ['All cuisines', 'كل المطابخ'],
      'restaurant': ['Restaurants', 'مطاعم'],
      'cafe': ['Cafes', 'مقاهي'],
      'italian': ['Italian', 'إيطالي'],
      'mexican': ['Mexican', 'مكسيكي'],
      'chinese': ['Chinese', 'صيني'],
      'japanese': ['Japanese', 'ياباني'],
      'indian': ['Indian', 'هندي'],
      'thai': ['Thai', 'تايلندي'],
      'mediterranean': ['Mediterranean', 'متوسطي'],
      'middle_eastern': ['Middle Eastern', 'شرق أوسطي'],
      'burger': ['Burgers', 'برجر'],
      'barbecue': ['Barbecue', 'مشويات'],
      'seafood': ['Seafood', 'مأكولات بحرية'],
      'coffee': ['Coffee', 'قهوة'],
      'dessert': ['Dessert', 'حلويات'],
      'breakfast': ['Breakfast', 'إفطار'],
      'bakery': ['Bakery', 'مخبوزات'],
      'vegetarian': ['Vegetarian', 'نباتي'],
    };
    final pair = labels[value] ?? [value, value];
    return ar ? pair[1] : pair[0];
  }

  Future<void> showFilters() async {
    var rating = minRating;
    var priceRange = RangeValues(minPrice, maxPrice);
    var distance = maxDistance;
    var reviews = minReviews;
    var type = placeType;
    var category = cuisine;
    var sort = (lastLat == null || lastLng == null) && sortMode == 'distance' ? 'ai' : sortMode;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.viewInsetsOf(sheetContext).bottom),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(child: Text(tr(sheetContext, 'Filter and sort', 'التصفية والترتيب'), style: Theme.of(sheetContext).textTheme.headlineSmall)),
                    TextButton(
                      onPressed: () => setSheetState(() {
                        rating = 0;
                        priceRange = const RangeValues(1, 4);
                        distance = 50;
                        reviews = 0;
                        type = 'all';
                        category = 'all';
                        sort = 'ai';
                      }),
                      child: Text(tr(sheetContext, 'Reset', 'إعادة ضبط')),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'all', label: Text(tr(sheetContext, 'All', 'الكل')), icon: const Icon(Icons.apps_rounded)),
                      ButtonSegment(value: 'restaurant', label: Text(tr(sheetContext, 'Restaurants', 'مطاعم')), icon: const Icon(Icons.restaurant_rounded)),
                      ButtonSegment(value: 'cafe', label: Text(tr(sheetContext, 'Cafes', 'مقاهي')), icon: const Icon(Icons.local_cafe_rounded)),
                    ],
                    selected: {type},
                    onSelectionChanged: (s) => setSheetState(() => type = s.first),
                  ),
                  const SizedBox(height: 18),
                  Text('${tr(sheetContext, 'Minimum rating', 'أقل تقييم')}: ${rating == 0 ? tr(sheetContext, 'Any', 'الكل') : rating.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Slider(value: rating, min: 0, max: 5, divisions: 10, onChanged: (v) => setSheetState(() => rating = v)),
                  Text('${tr(sheetContext, 'Minimum review count', 'أقل عدد مراجعات')}: $reviews', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Slider(value: reviews.toDouble(), min: 0, max: 1000, divisions: 20, label: '$reviews', onChanged: (v) => setSheetState(() => reviews = v.round())),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: InputDecoration(labelText: tr(sheetContext, 'Cuisine', 'المطبخ')),
                    items: cuisineOptions.map((c) => DropdownMenuItem(value: c, child: Text(cuisineLabel(c)))).toList(),
                    onChanged: (v) => setSheetState(() => category = v ?? 'all'),
                  ),
                  const SizedBox(height: 18),
                  Text(tr(sheetContext, 'Price range', 'نطاق السعر'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Text(List.filled(priceRange.start.round().clamp(1, 4).toInt(), r'$').join(), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text(List.filled(priceRange.end.round().clamp(1, 4).toInt(), r'$').join(), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                  RangeSlider(values: priceRange, min: 1, max: 4, divisions: 3, labels: RangeLabels(priceRange.start.round().toString(), priceRange.end.round().toString()), onChanged: (v) => setSheetState(() => priceRange = v)),
                  const SizedBox(height: 8),
                  Text('${tr(sheetContext, 'Maximum distance', 'أقصى مسافة')}: ${distance.round()} km', style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (lastLat != null && lastLng != null)
                    Slider(value: distance, min: 1, max: 50, divisions: 49, onChanged: (v) => setSheetState(() => distance = v))
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(tr(sheetContext, 'Distance filtering requires current location. Manual country/city search has no precise distance reference.', 'فلترة المسافة تتطلب استخدام الموقع الحالي. البحث اليدوي بالدولة أو المدينة لا يملك مرجع مسافة دقيقًا.'), style: TextStyle(color: Theme.of(sheetContext).colorScheme.onSurfaceVariant)),
                    ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: sort,
                    decoration: InputDecoration(labelText: tr(sheetContext, 'Sort results', 'ترتيب النتائج')),
                    items: [
                      DropdownMenuItem(value: 'ai', child: Text(tr(sheetContext, 'Best match for me', 'الأفضل لي'))),
                      DropdownMenuItem(value: 'rating', child: Text(tr(sheetContext, 'Highest rated', 'الأعلى تقييمًا'))),
                      DropdownMenuItem(value: 'distance', enabled: lastLat != null && lastLng != null, child: Text(tr(sheetContext, 'Nearest first', 'الأقرب أولًا'))),
                    ],
                    onChanged: (v) => setSheetState(() => sort = v ?? 'ai'),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        minRating = rating;
                        minPrice = priceRange.start;
                        maxPrice = priceRange.end;
                        if (lastLat != null && lastLng != null) maxDistance = distance;
                        minReviews = reviews;
                        placeType = type;
                        cuisine = category;
                        sortMode = (lastLat == null || lastLng == null) && sort == 'distance' ? 'ai' : sort;
                      });
                      Navigator.pop(sheetContext);
                    },
                    child: Text(tr(sheetContext, 'Show results', 'عرض النتائج')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openPlace(Place place) async {
    try {
      unawaited(widget.api.recordInteraction(place.id, 'detail', position: place.aiRank));
    } catch (_) {}
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaceScreen(api: widget.api, place: place)));
    if (mounted) setState(() {});
  }

  Widget _discoveryError(BuildContext context) {
    final message = error ?? '';
    final missingPlaces = message.contains('503') || message.toLowerCase().contains('not configured');
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline_rounded, color: Theme.of(context).colorScheme.onErrorContainer),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            missingPlaces ? tr(context, 'Live place discovery is unavailable', 'اكتشاف الأماكن المباشر غير متاح') : tr(context, 'We could not complete that search', 'تعذر إكمال البحث'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(missingPlaces
              ? tr(context, 'The live places service has not been configured for this installation. Ask the administrator to complete the service setup.', 'لم يتم إعداد خدمة الأماكن المباشرة لهذا التثبيت. اطلب من المشرف إكمال إعداد الخدمة.')
              : tr(context, 'Check the location or search text and try again.', 'تحقق من الموقع أو نص البحث ثم حاول مرة أخرى.')),
        ])),
      ]),
    );
  }

  Widget _emptyDiscovery(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 50, 22, 24),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, shape: BoxShape.circle),
            child: Icon(Icons.travel_explore_rounded, size: 44, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 22),
          Text(tr(context, 'Start with a location', 'ابدأ باختيار موقع'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            tr(context, 'TasteAI does not assume a city. Use your current location, or choose any country, city, and area worldwide.', 'TasteAI لا يفترض مدينة محددة. استخدم موقعك الحالي أو اختر أي دولة ومدينة ومنطقة حول العالم.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.45),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(onPressed: showLocationPicker, icon: const Icon(Icons.public_rounded), label: Text(tr(context, 'Choose location', 'اختيار الموقع'))),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: useCurrentLocation, icon: const Icon(Icons.my_location_rounded), label: Text(tr(context, 'Use current location', 'استخدم الموقع الحالي'))),
          if (locationUnavailable) ...[
            const SizedBox(height: 12),
            Text(tr(context, 'Location permission is unavailable. Manual search remains available.', 'صلاحية الموقع غير متاحة. يمكنك الاستمرار بالبحث اليدوي.'), textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  Widget _discover(BuildContext context) {
    final list = filtered;
    final top = topRated.take(6).toList();
    return RefreshIndicator(
      onRefresh: runSearch,
      child: ListView(
        key: const PageStorageKey('discover-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withValues(alpha: 0.82)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('TasteAI', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(tr(context, 'Find a place worth going to.', 'اكتشف مكانًا يستحق الزيارة.'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
                  ])),
                  IconButton.filledTonal(onPressed: showLocationPicker, tooltip: tr(context, 'Change location', 'تغيير الموقع'), icon: const Icon(Icons.location_on_rounded)),
                ]),
                const SizedBox(height: 14),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: showLocationPicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      const Icon(Icons.public_rounded, color: Colors.white, size: 19),
                      const SizedBox(width: 8),
                      Expanded(child: Text(activeLocationLabel.isEmpty ? tr(context, 'Choose a country, city, area, or current location', 'اختر دولة أو مدينة أو منطقة أو موقعك الحالي') : activeLocationLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                      const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: search,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => runSearch(),
                      decoration: InputDecoration(
                        hintText: tr(context, 'Restaurant, cafe, cuisine, or place', 'مطعم أو مقهى أو مطبخ أو مكان'),
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Badge(
                    isLabelVisible: activeFilterCount > 0,
                    label: Text('$activeFilterCount'),
                    child: IconButton.filledTonal(onPressed: showFilters, tooltip: tr(context, 'Filters', 'الفلاتر'), icon: const Icon(Icons.tune_rounded)),
                  ),
                ]),
              ]),
            ),
          ),
          if (loading) const LinearProgressIndicator(minHeight: 3),
          if (error != null) _discoveryError(context),
          if (places.isEmpty && !loading && error == null) _emptyDiscovery(context),
          if (places.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Row(children: [
                Expanded(child: Text(tr(context, 'Top rated', 'الأعلى تقييمًا'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TopRatedScreen(api: widget.api, places: topRated))),
                  child: Text(tr(context, 'See all', 'عرض الكل')),
                ),
              ]),
            ),
            SizedBox(
              height: 196,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: top.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) => CompactPlaceCard(api: widget.api, place: top[i], onTap: () => _openPlace(top[i])),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(context, 'Recommended for you', 'مقترح لك'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  Text(tr(context, 'Ranked using your preferences and the selected filters.', 'مرتبة حسب تفضيلاتك والفلاتر المختارة.'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ])),
                if (compareSelection.length >= 2)
                  FilledButton.tonalIcon(onPressed: _openCompare, icon: const Icon(Icons.compare_arrows_rounded), label: Text('${tr(context, 'Compare', 'مقارنة')} ${compareSelection.length}')),
              ]),
            ),
            ...list.map((p) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: PlaceCard(
                    api: widget.api,
                    place: p,
                    onTap: () => _openPlace(p),
                    selectedForCompare: compareSelection.contains(p.id),
                    onCompareChanged: (checked) {
                      setState(() {
                        if (checked && compareSelection.length < 3) {
                          compareSelection.add(p.id);
                        } else {
                          compareSelection.remove(p.id);
                        }
                      });
                    },
                  ),
                )),
            const SizedBox(height: 26),
          ],
        ],
      ),
    );
  }

  void _openCompare() {
    final selected = places.where((p) => compareSelection.contains(p.id)).take(3).toList();
    if (selected.length < 2) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompareScreen(places: selected)));
  }

  Widget _mapTab(BuildContext context) {
    if (places.isEmpty) {
      return SafeArea(child: _emptyDiscovery(context));
    }
    return MapScreen(api: widget.api, places: filtered, userLat: lastLat, userLng: lastLng, embedded: true);
  }

  Widget _profile(BuildContext context) {
    return SettingsScreen(
      api: widget.api,
      onLogout: widget.onLogout,
      embedded: true,
      onPreferences: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PreferencesScreen(api: widget.api))),
      onAiStatus: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AiStatusScreen(api: widget.api))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _discover(context),
      _mapTab(context),
      FavoritesScreen(api: widget.api, embedded: true),
      _profile(context),
    ];

    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.explore_outlined), selectedIcon: const Icon(Icons.explore_rounded), label: tr(context, 'Discover', 'اكتشف')),
          NavigationDestination(icon: const Icon(Icons.map_outlined), selectedIcon: const Icon(Icons.map_rounded), label: tr(context, 'Map', 'الخريطة')),
          NavigationDestination(icon: const Icon(Icons.favorite_border_rounded), selectedIcon: const Icon(Icons.favorite_rounded), label: tr(context, 'Favorites', 'المفضلة')),
          NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: tr(context, 'Profile', 'الحساب')),
        ],
      ),
    );
  }
}
