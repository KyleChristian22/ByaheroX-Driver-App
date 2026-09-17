import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../viewmodels/commuter_location_viewmodel.dart';

/// Marker widget for displaying a commuter waiting location on the driver's map
class CommuterMarker extends StatelessWidget {
  final CommuterLocationWithDistance commuterData;
  final VoidCallback? onTap;

  const CommuterMarker({
    super.key,
    required this.commuterData,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Total Distance badge (driver GPS + commuter GPS = total km)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.orange.shade700,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Total',
                  style: TextStyle(
                    color: Colors.orange.shade100,
                    fontSize: 8,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  commuterData.formattedDistance,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          // Waiting count badge (if more than 1)
          if (commuterData.location.waitingCount > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.blue.shade600,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${commuterData.location.waitingCount} waiting',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                ),
              ),
            ),
          // Marker icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.orange.shade500,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.person_pin,
              color: Colors.white,
              size: 24,
            ),
          ),
          // Destination info (if available)
          if (commuterData.location.destinationTerminal != null)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 2,
                  ),
                ],
              ),
              child: Text(
                commuterData.location.destinationTerminal!,
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontSize: 8,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

/// Helper to build marker layers for all commuter locations
class CommuterMarkersLayer extends StatelessWidget {
  final List<CommuterLocationWithDistance> commuterLocations;
  final Function(CommuterLocationWithDistance)? onCommuterTap;

  const CommuterMarkersLayer({
    super.key,
    required this.commuterLocations,
    this.onCommuterTap,
  });

  @override
  Widget build(BuildContext context) {
    return MarkerLayer(
      markers: commuterLocations.map((commuterData) {
        return Marker(
          point: commuterData.location.location,
          width: 80,
          height: 100,
          child: CommuterMarker(
            commuterData: commuterData,
            onTap: onCommuterTap != null
                ? () => onCommuterTap!(commuterData)
                : null,
          ),
        );
      }).toList(),
    );
  }
}
