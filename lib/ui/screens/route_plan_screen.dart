import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_photon/flutter_photon.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:unustasis/domain/nav_destination.dart';
import 'package:unustasis/geo_helper.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/service/photon_service.dart';
import 'package:unustasis/ui/widgets/header.dart';
import 'package:unustasis/ui/widgets/wide_layout.dart';

class RoutePlanScreen extends StatefulWidget {
  const RoutePlanScreen({super.key});

  @override
  State<RoutePlanScreen> createState() => _RoutePlanScreenState();
}

class _RoutePlanScreenState extends State<RoutePlanScreen> {
  bool _loading = true;
  bool _busy = false;
  bool _onlineConsent = true;
  String? _error;
  List<NavDestination> _favorites = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
    SharedPreferencesAsync().getBool('osmConsent').then((consent) {
      if (mounted) setState(() => _onlineConsent = consent ?? true);
    });
  }

  Future<void> _reload() async {
    final service = context.read<ScooterService>();
    if (!service.connected) {
      setState(() {
        _loading = false;
        _error = FlutterI18n.translate(context, 'nav_route_offline');
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await service.refreshRoutePlan();
      final favorites = await service.routePlanFavorites();
      if (!mounted) return;
      setState(() {
        _favorites = favorites;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = FlutterI18n.translate(context, 'nav_route_error', translationParams: {'error': error.toString()});
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(FlutterI18n.translate(context, 'nav_error', translationParams: {'error': error.toString()})),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addStop() async {
    final destination = await showModalBottomSheet<NavDestination>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FavoriteStopPicker(
        favorites: _favorites,
        onlineSearchEnabled: _onlineConsent,
      ),
    );
    if (destination == null || !mounted) return;
    await _run(() => context.read<ScooterService>().addRouteStop(destination));
  }

  Future<void> _removeStop(int index) => _run(() => context.read<ScooterService>().removeRouteStop(index + 1));

  Future<void> _skipStop() => _run(() => context.read<ScooterService>().skipRouteStop());

  Future<void> _clearPlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(FlutterI18n.translate(context, 'nav_route_clear_title')),
        content: Text(FlutterI18n.translate(context, 'nav_route_clear_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(FlutterI18n.translate(context, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(FlutterI18n.translate(context, 'nav_route_clear')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(() => context.read<ScooterService>().clearRoutePlan());
    }
  }

  Future<void> _reorder(List<NavDestination> stops, int oldIndex, int newIndex) async {
    if (newIndex == oldIndex) return;
    final service = context.read<ScooterService>();
    if (service.routePlanStep > 0 || service.vehicle.navigationActive == true) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(FlutterI18n.translate(context, 'nav_route_reorder_title')),
          content: Text(FlutterI18n.translate(context, 'nav_route_reorder_body')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(FlutterI18n.translate(context, 'cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(FlutterI18n.translate(context, 'nav_route_reorder')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    final ordered = List<NavDestination>.from(stops);
    ordered.insert(newIndex, ordered.removeAt(oldIndex));
    await _run(() => service.reorderRoutePlan(ordered));
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ScooterService>();
    final stops = service.routePlanStops;
    final step = service.routePlanStep;
    return Scaffold(
      appBar: AppBar(
        title: Text(FlutterI18n.translate(context, 'nav_route_title')),
        forceMaterialTransparency: true,
        scrolledUnderElevation: 0,
        actions: [
          if (stops.isNotEmpty)
            IconButton(
              tooltip: FlutterI18n.translate(context, 'nav_route_clear'),
              onPressed: _busy ? null : _clearPlan,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Stack(
        children: [
          _body(service, stops, step),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(ScooterService service, List<NavDestination> stops, int step) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && stops.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bluetooth_disabled, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _reload,
                child: Text(FlutterI18n.translate(context, 'nav_route_retry')),
              ),
            ],
          ),
        ),
      );
    }
    if (stops.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.route_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(FlutterI18n.translate(context, 'nav_route_empty_title'),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: Colors.grey)),
              const SizedBox(height: 8),
              Text(FlutterI18n.translate(context, 'nav_route_empty_subtitle'),
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _addStop,
                icon: const Icon(Icons.add),
                label: Text(FlutterI18n.translate(context, 'nav_route_add_stop')),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        Header(
          FlutterI18n.translate(context, 'nav_route_stop_of', translationParams: {
            'current': '${step + 1}',
            'total': '${stops.length}',
          }),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: wideContentPadding(context, base: const EdgeInsets.fromLTRB(8, 8, 8, 8)),
            buildDefaultDragHandles: false,
            itemCount: stops.length,
            onReorderItem: (oldIndex, newIndex) => _reorder(stops, oldIndex, newIndex),
            itemBuilder: (context, index) {
              final stop = stops[index];
              final label = stop.name?.isNotEmpty == true ? stop.name! : _formatCoordinates(stop);
              return Card(
                key: ValueKey('route-stop-$index-$label'),
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: _RouteStopMarker(index: index, count: stops.length, currentStep: step),
                  title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: stop.name?.isNotEmpty == true
                      ? Text(_formatCoordinates(stop), maxLines: 1, overflow: TextOverflow.ellipsis)
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (index == step)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            FlutterI18n.translate(context, 'nav_route_current'),
                            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
                          ),
                        ),
                      IconButton(
                        tooltip: FlutterI18n.translate(context, 'nav_route_remove'),
                        onPressed: _busy ? null : () => _removeStop(index),
                        icon: const Icon(Icons.close),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _addStop,
                    icon: const Icon(Icons.add),
                    label: Text(FlutterI18n.translate(context, 'nav_route_add_stop')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy || step + 1 >= stops.length ? null : _skipStop,
                    icon: const Icon(Icons.skip_next),
                    label: Text(FlutterI18n.translate(context, 'nav_route_skip')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatCoordinates(NavDestination destination) => '${destination.location.latitude.toStringAsFixed(5)}, '
      '${destination.location.longitude.toStringAsFixed(5)}';
}

class _RouteStopMarker extends StatelessWidget {
  const _RouteStopMarker({required this.index, required this.count, required this.currentStep});

  final int index;
  final int count;
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = index == currentStep;
    final completed = index < currentStep;
    return SizedBox(
      width: 40,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (index > 0)
            Positioned(
              top: -16,
              bottom: 28,
              child: Container(
                width: 3,
                color: index <= currentStep ? scheme.primary : scheme.outlineVariant,
              ),
            ),
          if (index + 1 < count)
            Positioned(
              top: 28,
              bottom: -16,
              child: Container(
                width: 3,
                color: completed ? scheme.primary : scheme.outlineVariant,
              ),
            ),
          CircleAvatar(
            radius: 18,
            backgroundColor: current ? scheme.primary : scheme.surfaceContainerHighest,
            foregroundColor: current ? scheme.onPrimary : scheme.onSurfaceVariant,
            child: index + 1 == count ? const Icon(Icons.flag_outlined, size: 19) : Text('${index + 1}'),
          ),
        ],
      ),
    );
  }
}

class _FavoriteStopPicker extends StatelessWidget {
  const _FavoriteStopPicker({
    required this.favorites,
    required this.onlineSearchEnabled,
  });

  final List<NavDestination> favorites;
  final bool onlineSearchEnabled;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Header(
                  FlutterI18n.translate(context, 'nav_route_add_stop'),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                ),
              ),
              if (onlineSearchEnabled)
                Autocomplete<PhotonFeature>(
                  displayStringForOption: GeoHelper.fullNameFromFeature,
                  optionsBuilder: (value) async {
                    final query = value.text.trim();
                    if (query.length < 3) return const [];
                    try {
                      return await photonForwardSearch(query);
                    } catch (_) {
                      return const [];
                    }
                  },
                  onSelected: (feature) => Navigator.of(context).pop(
                    NavDestination(
                      location: LatLng(
                        feature.coordinates.latitude.toDouble(),
                        feature.coordinates.longitude.toDouble(),
                      ),
                      name: GeoHelper.nameFromFeature(feature),
                    ),
                  ),
                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) => TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onSubmitted: (_) => onFieldSubmitted(),
                    decoration: InputDecoration(
                      hintText: FlutterI18n.translate(context, 'nav_search_hint'),
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    FlutterI18n.translate(context, 'nav_route_online_disabled'),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (favorites.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(
                    FlutterI18n.translate(context, 'nav_route_no_favorites'),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: favorites.length,
                    itemBuilder: (context, index) {
                      final destination = favorites[index];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined),
                        title: Text(
                          destination.name ??
                              '${destination.location.latitude}, '
                                  '${destination.location.longitude}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.of(context).pop(destination),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
}
