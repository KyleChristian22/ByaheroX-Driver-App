import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/router/app_router.dart';
import '../../../data/repositories/route_repository_impl.dart';
import '../../../domain/entities/route.dart' as commuter_route;
import '../../../domain/models/route_filter.dart';
import '../../widgets/common/app_background.dart';

class FaresScreen extends StatefulWidget {
  const FaresScreen({super.key});

  @override
  State<FaresScreen> createState() => _FaresScreenState();
}

class _FaresScreenState extends State<FaresScreen> {
  late final RouteRepositoryImpl _routeRepository;
  late Future<List<commuter_route.Route>> _routesFuture;
  final TextEditingController _fareSearchController = TextEditingController();

  String _origin = 'lucban';
  String _destination = 'sta_cruz';
  _PassengerFareType _fareType = _PassengerFareType.regular;
  String _fareSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _routeRepository = RouteRepositoryImpl();
    _routesFuture = _routeRepository.getRoutes();
  }

  @override
  void dispose() {
    _fareSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _returnToPreviousOrDashboard(context);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _returnToPreviousOrDashboard(context),
          ),
          title: const Text('Pamasahe Guide'),
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.textPrimary,
        ),
        body: SafeArea(
          child: FutureBuilder<List<commuter_route.Route>>(
            future: _routesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return _StateMessage(
                  icon: Icons.error_outline,
                  title: 'Could not load fares',
                  message: 'Please check your connection and try again.',
                  actionLabel: 'Retry',
                  onAction: _reloadFares,
                );
              }

              final routes = snapshot.data ?? const <commuter_route.Route>[];
              final selected = _selectedFare(routes);

              return ListView(
                padding: const EdgeInsets.all(AppDimensions.md),
                children: [
                  _buildFilterPanel(routes),
                  const SizedBox(height: AppDimensions.md),
                  _FareHeroCard(
                    origin: _terminalLabel(_origin),
                    destination: _terminalLabel(_destination),
                    fareType: _fareType,
                    selectedFare: selected,
                  ),
                  const SizedBox(height: AppDimensions.md),
                  _buildCompleteTable(routes),
                  const SizedBox(height: AppDimensions.lg),
                  _buildReturnButtons(context),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFilterPanel(List<commuter_route.Route> routes) {
    final stopOptions = _fareStopOptions(routes);

    return GlassSurface(
      padding: const EdgeInsets.all(AppDimensions.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: AppDimensions.borderRadiusSm,
                ),
                child: const Icon(
                  Icons.payments_outlined,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppDimensions.sm),
              Expanded(
                child: Text(
                  'Filter by destination',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _TerminalDropdown(
                  label: 'From',
                  value: _origin,
                  options: stopOptions,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _origin = value;
                      if (_destination == value) {
                        _destination = _firstDifferentStop(stopOptions, value);
                      }
                    });
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.xs,
                ),
                child: IconButton.filledTonal(
                  tooltip: 'Swap terminals',
                  onPressed: _swapTerminals,
                  icon: const Icon(Icons.swap_horiz),
                ),
              ),
              Expanded(
                child: _TerminalDropdown(
                  label: 'To',
                  value: _destination,
                  options: stopOptions,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _destination = value;
                      if (_origin == value) {
                        _origin = _firstDifferentStop(stopOptions, value);
                      }
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.md),
          SegmentedButton<_PassengerFareType>(
            segments: const [
              ButtonSegment(
                value: _PassengerFareType.regular,
                label: Text('Regular'),
                icon: Icon(Icons.person_outline),
              ),
              ButtonSegment(
                value: _PassengerFareType.discounted,
                label: Text('Discounted'),
                icon: Icon(Icons.school_outlined),
              ),
            ],
            selected: {_fareType},
            onSelectionChanged: (selection) {
              setState(() => _fareType = selection.first);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteTable(List<commuter_route.Route> routes) {
    final entries = _allFareRows(routes);
    final filteredEntries = _filteredFareRows(entries);
    final hasSearch = _fareSearchQuery.trim().isNotEmpty;

    return GlassSurface(
      padding: const EdgeInsets.all(AppDimensions.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.table_chart_outlined, color: AppColors.primary),
              const SizedBox(width: AppDimensions.sm),
              Expanded(
                child: Text(
                  'Complete fare list',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.sm),
          _buildFareSearchField(),
          const SizedBox(height: AppDimensions.sm),
          if (entries.isEmpty)
            const _InlineEmptyFare()
          else if (filteredEntries.isEmpty && hasSearch)
            _InlineEmptyFare(
              message: 'No fares match "${_fareSearchQuery.trim()}".',
            )
          else
            Column(
              children: [
                const _FareTableHeader(),
                const SizedBox(height: AppDimensions.xs),
                for (final row in filteredEntries) _FareTableRow(row: row),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildFareSearchField() {
    return TextField(
      controller: _fareSearchController,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search stop, route, or fare',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _fareSearchQuery.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _fareSearchController.clear();
                  setState(() => _fareSearchQuery = '');
                },
              ),
        filled: true,
        fillColor: AppColors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.md,
          vertical: AppDimensions.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: AppDimensions.borderRadiusSm,
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: (value) => setState(() => _fareSearchQuery = value),
    );
  }

  Widget _buildReturnButtons(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () => context.go(AppRouter.home),
          icon: const Icon(Icons.map_outlined),
          label: const Text('Return to Map'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(AppDimensions.buttonHeightLg),
          ),
        ),
        const SizedBox(height: AppDimensions.sm),
        OutlinedButton.icon(
          onPressed: () => _returnToDashboard(context),
          icon: const Icon(Icons.home_outlined),
          label: const Text('Back to Dashboard'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            minimumSize: const Size.fromHeight(AppDimensions.buttonHeightLg),
          ),
        ),
      ],
    );
  }

  void _reloadFares() {
    setState(() {
      _routesFuture = _routeRepository.getRoutes();
    });
  }

  void _swapTerminals() {
    setState(() {
      final oldOrigin = _origin;
      _origin = _destination;
      _destination = oldOrigin;
    });
  }

  void _returnToPreviousOrDashboard(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRouter.dashboard);
  }

  void _returnToDashboard(BuildContext context) {
    context.go(AppRouter.dashboard);
  }

  _ResolvedFare _selectedFare(List<commuter_route.Route> routes) {
    commuter_route.Route? route;
    commuter_route.RouteFareEntry? entry;

    for (final candidate in routes) {
      for (final fareEntry in candidate.fareEntries) {
        if (_fareEntryMatchesDirection(fareEntry, _origin, _destination)) {
          route = candidate;
          entry = fareEntry;
          break;
        }
      }
      if (entry != null) break;
    }

    for (final candidate in routes) {
      if (entry != null) break;

      for (final fareEntry in candidate.fareEntries) {
        if (_fareEntryMatchesReverse(fareEntry, _origin, _destination)) {
          route = candidate;
          entry = fareEntry;
          break;
        }
      }
    }

    route ??= _routeForDirection(routes);
    final routeFare = route == null ? null : _routeFareSummary(route);
    final fallbackFare = route?.fare ?? 0;

    return _ResolvedFare(
      routeName: route?.name ?? '',
      regular: entry?.regular ?? routeFare?.regular ?? fallbackFare,
      discounted: entry?.studentSenior ?? routeFare?.discounted ?? 0,
      isConfigured: entry != null || routeFare != null || fallbackFare > 0,
    );
  }

  commuter_route.Route? _routeForDirection(List<commuter_route.Route> routes) {
    final routeId = RouteDirections.getRouteIdForDirection(
      _origin,
      _destination,
    );

    for (final route in routes) {
      if (route.id == routeId) return route;
    }

    for (final route in routes) {
      final hasMatchingEntry = route.fareEntries.any(
        (entry) => _fareEntryMatchesPair(entry, _origin, _destination),
      );
      if (hasMatchingEntry) return route;
    }

    for (final route in routes) {
      if (_routeMatchesSelectedDirection(route)) return route;
    }

    return null;
  }

  bool _routeMatchesSelectedDirection(commuter_route.Route route) {
    final originKey = _compactTerminalKey(_origin);
    final destinationKey = _compactTerminalKey(_destination);

    for (final value in [route.id, route.name, route.description]) {
      final routeKey = _compactTerminalKey(value);
      final originIndex = routeKey.indexOf(originKey);
      final destinationIndex = routeKey.indexOf(destinationKey);
      if (originIndex >= 0 &&
          destinationIndex >= 0 &&
          originIndex < destinationIndex) {
        return true;
      }
    }

    return false;
  }

  _FareAmounts? _routeFareSummary(commuter_route.Route route) {
    double regular = 0;
    double discounted = 0;

    for (final entry in route.fareEntries) {
      if (entry.regular > regular) regular = entry.regular;
      if (entry.studentSenior > discounted) {
        discounted = entry.studentSenior;
      }
    }

    if (regular <= 0 && discounted <= 0) return null;
    return _FareAmounts(regular: regular, discounted: discounted);
  }

  bool _fareEntryMatchesPair(
    commuter_route.RouteFareEntry entry,
    String origin,
    String destination,
  ) {
    return _fareEntryMatchesDirection(entry, origin, destination) ||
        _fareEntryMatchesReverse(entry, origin, destination);
  }

  bool _fareEntryMatchesDirection(
    commuter_route.RouteFareEntry entry,
    String origin,
    String destination,
  ) {
    final fromKey = _fareStopKey(entry.from);
    final toKey = _fareStopKey(entry.to);
    final originKey = _fareStopKey(origin);
    final destinationKey = _fareStopKey(destination);

    return fromKey == originKey && toKey == destinationKey;
  }

  bool _fareEntryMatchesReverse(
    commuter_route.RouteFareEntry entry,
    String origin,
    String destination,
  ) {
    final fromKey = _fareStopKey(entry.from);
    final toKey = _fareStopKey(entry.to);
    final originKey = _fareStopKey(origin);
    final destinationKey = _fareStopKey(destination);

    return fromKey == destinationKey && toKey == originKey;
  }

  List<_StopOption> _fareStopOptions(List<commuter_route.Route> routes) {
    final optionsByKey = <String, _StopOption>{
      _fareStopKey('lucban'): const _StopOption(
        value: 'lucban',
        label: 'Lucban',
      ),
      _fareStopKey('sta_cruz'): const _StopOption(
        value: 'sta_cruz',
        label: 'Sta. Cruz',
      ),
    };

    for (final route in routes) {
      for (final entry in route.fareEntries) {
        _addStopOption(optionsByKey, entry.from);
        _addStopOption(optionsByKey, entry.to);
      }
    }

    final options = optionsByKey.values.toList();
    options.sort((a, b) {
      final aTerminal = _isTerminalOption(a.value);
      final bTerminal = _isTerminalOption(b.value);
      if (aTerminal != bTerminal) return aTerminal ? -1 : 1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return options;
  }

  void _addStopOption(Map<String, _StopOption> optionsByKey, String stop) {
    final trimmed = stop.trim();
    if (trimmed.isEmpty) return;

    final key = _fareStopKey(trimmed);
    optionsByKey.putIfAbsent(
      key,
      () => _StopOption(value: trimmed, label: _terminalLabel(trimmed)),
    );
  }

  bool _isTerminalOption(String value) {
    final key = _fareStopKey(value);
    return key == _fareStopKey('lucban') || key == _fareStopKey('sta_cruz');
  }

  String _firstDifferentStop(List<_StopOption> options, String selected) {
    for (final option in options) {
      if (_fareStopKey(option.value) != _fareStopKey(selected)) {
        return option.value;
      }
    }
    return selected;
  }

  List<_FareRowData> _allFareRows(List<commuter_route.Route> routes) {
    final rows = <_FareRowData>[];
    for (final route in routes) {
      if (route.fareEntries.isEmpty && route.fare > 0) {
        rows.add(
          _FareRowData(
            routeName: route.name,
            from: 'Route',
            to: route.description.trim().isEmpty ? route.id : route.description,
            regular: route.fare,
            discounted: 0,
          ),
        );
        continue;
      }

      for (final entry in route.fareEntries) {
        rows.add(
          _FareRowData(
            routeName: route.name,
            from: entry.from,
            to: entry.to,
            regular: entry.regular,
            discounted: entry.studentSenior,
          ),
        );
      }
    }
    return rows;
  }

  List<_FareRowData> _filteredFareRows(List<_FareRowData> rows) {
    final query = _normalizeSearchText(_fareSearchQuery);
    if (query.isEmpty) return rows;

    return rows.where((row) {
      final searchable = [
        row.from,
        row.to,
        _terminalLabel(row.from),
        _terminalLabel(row.to),
        '${_terminalLabel(row.from)} to ${_terminalLabel(row.to)}',
        row.regular.toStringAsFixed(2),
        row.discounted.toStringAsFixed(2),
        _money(row.regular),
        _money(row.discounted),
      ].map(_normalizeSearchText).join(' ');
      return searchable.contains(query);
    }).toList();
  }
}

class _TerminalDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<_StopOption> options;
  final ValueChanged<String?> onChanged;

  const _TerminalDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppDimensions.xs),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.primarySurface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.sm,
              vertical: AppDimensions.xs,
            ),
            border: OutlineInputBorder(
              borderRadius: AppDimensions.borderRadiusSm,
              borderSide: BorderSide.none,
            ),
          ),
          items: options
              .map(
                (option) => DropdownMenuItem(
                  value: option.value,
                  child: Text(option.label, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _FareHeroCard extends StatelessWidget {
  final String origin;
  final String destination;
  final _PassengerFareType fareType;
  final _ResolvedFare selectedFare;

  const _FareHeroCard({
    required this.origin,
    required this.destination,
    required this.fareType,
    required this.selectedFare,
  });

  @override
  Widget build(BuildContext context) {
    final amount = fareType == _PassengerFareType.regular
        ? selectedFare.regular
        : selectedFare.discounted;
    final hasAmount = amount > 0;

    return GlassSurface(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.lg),
      backgroundColor: AppColors.primaryBlueSurface.withValues(alpha: 0.32),
      borderColor: AppColors.neonBlue.withValues(alpha: 0.46),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$origin to $destination',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.primaryBlueDark,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppDimensions.sm),
          Text(
            hasAmount ? _money(amount) : 'Fare not set',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppDimensions.sm),
          Wrap(
            spacing: AppDimensions.sm,
            runSpacing: AppDimensions.sm,
            children: [
              _FarePill(
                label: fareType == _PassengerFareType.regular
                    ? 'Regular fare'
                    : 'Student / Senior / PWD',
              ),
              if (selectedFare.routeName.trim().isNotEmpty)
                _FarePill(label: selectedFare.routeName.trim()),
            ],
          ),
          if (selectedFare.regular > 0 || selectedFare.discounted > 0) ...[
            const SizedBox(height: AppDimensions.md),
            Row(
              children: [
                Expanded(
                  child: _MiniFareMetric(
                    label: 'Regular',
                    value: selectedFare.regular > 0
                        ? _money(selectedFare.regular)
                        : '-',
                  ),
                ),
                const SizedBox(width: AppDimensions.sm),
                Expanded(
                  child: _MiniFareMetric(
                    label: 'Discounted',
                    value: selectedFare.discounted > 0
                        ? _money(selectedFare.discounted)
                        : '-',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FarePill extends StatelessWidget {
  final String label;

  const _FarePill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.sm,
        vertical: AppDimensions.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.24),
        borderRadius: AppDimensions.borderRadiusFull,
        border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: AppColors.primaryBlue,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MiniFareMetric extends StatelessWidget {
  final String label;
  final String value;

  const _MiniFareMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDimensions.sm),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.24),
        borderRadius: AppDimensions.borderRadiusSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _FareTableHeader extends StatelessWidget {
  const _FareTableHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          flex: 5,
          child: Padding(
            padding: EdgeInsets.only(right: AppDimensions.sm),
            child: _HeaderText('Route'),
          ),
        ),
        Expanded(flex: 3, child: _HeaderText('Regular', alignEnd: true)),
        Expanded(flex: 3, child: _HeaderText('Discount', alignEnd: true)),
      ],
    );
  }
}

class _HeaderText extends StatelessWidget {
  final String text;
  final bool alignEnd;

  const _HeaderText(this.text, {this.alignEnd = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: alignEnd ? TextAlign.end : TextAlign.start,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _FareTableRow extends StatelessWidget {
  final _FareRowData row;

  const _FareTableRow({required this.row});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppDimensions.sm),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.only(right: AppDimensions.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_terminalLabel(row.from)} to ${_terminalLabel(row.to)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              row.regular > 0 ? _money(row.regular) : '-',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              row.discounted > 0 ? _money(row.discounted) : '-',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineEmptyFare extends StatelessWidget {
  final String message;

  const _InlineEmptyFare({
    this.message = 'Fare prices are not configured yet.',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.md),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: AppDimensions.borderRadiusSm,
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _StateMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: AppColors.textTertiary),
            const SizedBox(height: AppDimensions.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppDimensions.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppDimensions.md),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _ResolvedFare {
  final String routeName;
  final double regular;
  final double discounted;
  final bool isConfigured;

  const _ResolvedFare({
    required this.routeName,
    required this.regular,
    required this.discounted,
    required this.isConfigured,
  });
}

class _FareAmounts {
  final double regular;
  final double discounted;

  const _FareAmounts({required this.regular, required this.discounted});
}

class _StopOption {
  final String value;
  final String label;

  const _StopOption({required this.value, required this.label});
}

class _FareRowData {
  final String routeName;
  final String from;
  final String to;
  final double regular;
  final double discounted;

  const _FareRowData({
    required this.routeName,
    required this.from,
    required this.to,
    required this.regular,
    required this.discounted,
  });
}

enum _PassengerFareType { regular, discounted }

String _terminalLabel(String terminal) {
  final value = terminal.trim().toLowerCase();
  if (value == 'sta_cruz' || value.contains('sta')) return 'Sta. Cruz';
  if (value == 'lucban' || value.contains('lucban')) return 'Lucban';
  return terminal.trim().isEmpty ? '-' : terminal.trim();
}

String _compactTerminalKey(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('sta. cruz', 'stacruz')
      .replaceAll('sta cruz', 'stacruz')
      .replaceAll('sta_cruz', 'stacruz')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

String _fareStopKey(String value) => _compactTerminalKey(value);

String _normalizeSearchText(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9.]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}

String _money(double amount) => 'PHP ${amount.toStringAsFixed(2)}';
