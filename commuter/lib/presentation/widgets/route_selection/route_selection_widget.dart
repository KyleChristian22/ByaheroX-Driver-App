import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../data/repositories/route_repository_impl.dart';
import '../../../domain/entities/route.dart' as commuter_route;
import '../../../domain/models/route_filter.dart';
import '../../viewmodels/jeepney_viewmodel.dart';
import '../common/app_background.dart';

/// Route selection widget for commuters to select origin and destination
class RouteSelectionWidget extends StatefulWidget {
  final String? initialRouteId;

  const RouteSelectionWidget({super.key, this.initialRouteId});

  @override
  State<RouteSelectionWidget> createState() => _RouteSelectionWidgetState();
}

class _RouteSelectionWidgetState extends State<RouteSelectionWidget> {
  String? _selectedOrigin;
  String? _selectedDestination;
  late final RouteRepositoryImpl _routeRepository;
  late Future<List<commuter_route.Route>> _routesFuture;

  @override
  void initState() {
    super.initState();
    _selectedOrigin = 'lucban';
    _selectedDestination = 'sta_cruz';
    _routeRepository = RouteRepositoryImpl();
    _routesFuture = _routeRepository.getRoutes();
  }

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      padding: const EdgeInsets.all(AppDimensions.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.route, color: AppColors.primary, size: 20),
              const SizedBox(width: AppDimensions.xs),
              Text(
                'Pumili ng Route',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                'Jeep route',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.sm),
          Row(
            children: [
              Expanded(
                child: _buildTerminalDropdown(
                  label: 'Pinagmulan',
                  value: _selectedOrigin,
                  items: const [
                    DropdownMenuItem(value: 'lucban', child: Text('Lucban')),
                    DropdownMenuItem(
                      value: 'sta_cruz',
                      child: Text('Sta. Cruz'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedOrigin = value;
                    });
                    _updateFilter();
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.xs,
                ),
                child: IconButton(
                  icon: const Icon(Icons.swap_horiz, size: 20),
                  onPressed: _swapTerminals,
                  color: AppColors.primary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
              Expanded(
                child: _buildTerminalDropdown(
                  label: 'Destinasyon',
                  value: _selectedDestination,
                  items: const [
                    DropdownMenuItem(value: 'lucban', child: Text('Lucban')),
                    DropdownMenuItem(
                      value: 'sta_cruz',
                      child: Text('Sta. Cruz'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedDestination = value;
                    });
                    _updateFilter();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.sm),
          FutureBuilder<List<commuter_route.Route>>(
            future: _routesFuture,
            builder: (context, snapshot) {
              final fareEntry = _selectedFareEntry(snapshot.data);
              final fallbackFare = _selectedRouteFallbackFare(snapshot.data);
              return _FareSummary(
                fareEntry: fareEntry,
                fallbackFare: fallbackFare,
                isLoading: snapshot.connectionState == ConnectionState.waiting,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalDropdown({
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.primarySurface,
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
            border: Border.all(
              color: AppColors.primaryLight.withValues(alpha: 0.3),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down, size: 16),
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  void _swapTerminals() {
    setState(() {
      final temp = _selectedOrigin;
      _selectedOrigin = _selectedDestination;
      _selectedDestination = temp;
    });
    _updateFilter();
  }

  void _updateFilter() {
    final viewModel = context.read<JeepneyViewModel>();

    final routeId = _selectedOrigin != null && _selectedDestination != null
        ? RouteDirections.getRouteIdForDirection(
            _selectedOrigin!,
            _selectedDestination!,
          )
        : null;
    final validationMessage = viewModel.validateRouteSelection(
      routeId: routeId,
      originTerminal: _selectedOrigin,
      destinationTerminal: _selectedDestination,
    );

    if (validationMessage != null) {
      viewModel.clearRouteFilter();
      _showValidationWarning(validationMessage);
      return;
    }

    viewModel.setRouteFilter(
      originTerminal: _selectedOrigin!,
      destinationTerminal: _selectedDestination!,
    );
  }

  void _showValidationWarning(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.warning,
      ),
    );
  }

  commuter_route.RouteFareEntry? _selectedFareEntry(
    List<commuter_route.Route>? routes,
  ) {
    if (_selectedOrigin == null || _selectedDestination == null) return null;
    final routeId = RouteDirections.getRouteIdForDirection(
      _selectedOrigin!,
      _selectedDestination!,
    );
    if (routeId == null || routes == null) return null;

    for (final route in routes) {
      if (route.id != routeId) continue;
      for (final entry in route.fareEntries) {
        if (entry.matchesDirection(_selectedOrigin!, _selectedDestination!)) {
          return entry;
        }
      }
      if (route.fareEntries.isNotEmpty) return route.fareEntries.first;
    }
    return null;
  }

  double _selectedRouteFallbackFare(List<commuter_route.Route>? routes) {
    if (_selectedOrigin == null || _selectedDestination == null) return 0;
    final routeId = RouteDirections.getRouteIdForDirection(
      _selectedOrigin!,
      _selectedDestination!,
    );
    if (routeId == null || routes == null) return 0;

    for (final route in routes) {
      if (route.id == routeId) return route.fare;
    }
    return 0;
  }
}

class _FareSummary extends StatelessWidget {
  final commuter_route.RouteFareEntry? fareEntry;
  final double fallbackFare;
  final bool isLoading;

  const _FareSummary({
    required this.fareEntry,
    required this.fallbackFare,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final regularFare = fareEntry?.regular ?? fallbackFare;
    final discountedFare = fareEntry?.studentSenior ?? 0;
    final hasRegularFare = regularFare > 0;
    final hasDiscountedFare = discountedFare > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.payments_outlined, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isLoading
                  ? 'Loading fare...'
                  : hasRegularFare
                  ? 'Regular ${_money(regularFare)}'
                  : 'Fare not set for this route',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: hasRegularFare
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasDiscountedFare) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Student/Senior ${_money(discountedFare)}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _money(double amount) => 'PHP ${amount.toStringAsFixed(2)}';
}

/// Compact route filter display widget
class RouteFilterBadge extends StatelessWidget {
  final String origin;
  final String destination;
  final VoidCallback? onClear;
  final VoidCallback? onSwap;

  const RouteFilterBadge({
    super.key,
    required this.origin,
    required this.destination,
    this.onClear,
    this.onSwap,
  });

  String get _originDisplay {
    switch (origin) {
      case 'lucban':
        return 'Lucban';
      case 'sta_cruz':
        return 'Sta. Cruz';
      default:
        return origin;
    }
  }

  String get _destinationDisplay {
    switch (destination) {
      case 'lucban':
        return 'Lucban';
      case 'sta_cruz':
        return 'Sta. Cruz';
      default:
        return destination;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions, size: 14, color: AppColors.primary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$_originDisplay → $_destinationDisplay',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (onSwap != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onSwap,
              child: Icon(Icons.swap_horiz, size: 14, color: AppColors.primary),
            ),
          ],
          if (onClear != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onClear,
              child: Icon(
                Icons.close,
                size: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
