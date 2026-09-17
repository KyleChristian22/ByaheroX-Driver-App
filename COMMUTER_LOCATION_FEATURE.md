# Commuter Location Feature - Implementation Guide

## Overview
This feature allows drivers to see commuter waiting locations on their map, along with the distance from their current GPS position.

## Data Flow

```
┌─────────────────┐     Firestore      ┌─────────────────┐
│   Commuter App  │ ─────────────────> │  Driver App     │
│                 │   commuter_waiting │                 │
│ Share Location  │   _location/{id}   │ Watch Locations │
└─────────────────┘                    └─────────────────┘
                                              │
                                              ▼
                                       Calculate Distance
                                       Driver GPS → Commuter
                                              │
                                              ▼
                                        Show on Map
                                    Distance + Total KM
```

## Files Created

### 1. Service Layer
**`lib/services/commuter_location_service.dart`**
- Watches `commuter_waiting_location` collection from Firestore
- Filters active locations (not expired)
- Provides `CommuterWaitingLocation` model

### 2. ViewModel Layer
**`lib/presentation/viewmodels/commuter_location_viewmodel.dart`**
- Manages commuter location state
- Calculates distance using Haversine formula
- Formats distance for display (m/km)
- Sorts locations by distance (nearest first)

Key methods:
- `startWatching()` - Begin listening to Firestore
- `updateDriverLocation(lat, lng)` - Update driver GPS
- `calculateDistance(from, to)` - Haversine formula
- `commuterLocationsWithDistance` - Get locations with distance info

### 3. UI Layer
**`lib/presentation/widgets/commuter_marker.dart`**
- `CommuterMarker` - Visual marker with distance badge
- `CommuterMarkersLayer` - Layer for FlutterMap
- Shows: distance, waiting count, destination

**`lib/presentation/screens/home/driver_home_screen_example.dart`**
- Example integration in driver home screen
- Shows commuter count badge
- Tap marker to see details + exact distance

## Integration Steps

### Step 1: Add Provider to main.dart
```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => CommuterLocationViewModel()),
    // ... other providers
  ],
  child: MyApp(),
)
```

### Step 2: In Driver Home Screen
```dart
class _DriverHomeScreenState extends State<DriverHomeScreen> {
  @override
  void initState() {
    super.initState();
    // Start watching when screen loads
    context.read<CommuterLocationViewModel>().startWatching();
  }

  @override
  void dispose() {
    context.read<CommuterLocationViewModel>().stopWatching();
    super.dispose();
  }

  // Call this when GPS updates
  void onDriverLocationUpdate(double lat, double lng) {
    context.read<CommuterLocationViewModel>().updateDriverLocation(lat, lng);
  }
}
```

### Step 3: Add Marker Layer to Map
```dart
FlutterMap(
  children: [
    TileLayer(...),
    // Commuter markers
    Consumer<CommuterLocationViewModel>(
      builder: (context, viewModel, _) {
        return CommuterMarkersLayer(
          commuterLocations: viewModel.commuterLocationsWithDistance,
          onCommuterTap: (data) => showCommuterDetails(data),
        );
      },
    ),
  ],
)
```

## Distance Calculation

The Haversine formula calculates the great-circle distance between two points on Earth:

```dart
distance = 2 * R * asin(sqrt(a))
where:
  a = sin²(Δlat/2) + cos(lat1) * cos(lat2) * sin²(Δlon/2)
  R = 6371 km (Earth's radius)
```

Display format:
- < 1 km: Shows meters (e.g., "450 m")
- ≥ 1 km: Shows km with 1 decimal (e.g., "2.5 km")
- ≥ 10 km: Shows km without decimal (e.g., "15 km")

## Firestore Schema

Collection: `commuter_waiting_location/{commuterId}`

```json
{
  "commuterId": "user123",
  "lat": 14.2793,
  "lng": 121.4121,
  "routeId": "ROUTE001",
  "jeepneyId": "JEEP001",
  "waitingCount": 3,
  "destinationTerminal": "Sta.Cruz Terminal",
  "isSharing": true,
  "timestamp": Timestamp,
  "expiresAt": Timestamp (15 min from share)
}
```

## Features

1. **Real-time Updates**: Locations auto-update when commuters share/clear
2. **Distance Calculation**: Live calculation as driver moves
3. **Expiration**: Expired locations auto-removed after 15 minutes
4. **Sorting**: Nearest commuters shown first
5. **Visual Indicators**:
   - Distance badge on marker
   - Waiting count (if > 1)
   - Destination terminal name
6. **Tap Interaction**: Show detailed info with exact distance in km

## Testing

1. Open Commuter app → Share waiting location
2. Open Driver app → Verify marker appears
3. Move driver location → Verify distance updates
4. Wait 15 min → Verify marker disappears

## Dependencies Required

```yaml
dependencies:
  flutter_map: ^6.1.0
  latlong2: ^0.9.0
  cloud_firestore: ^4.x.x
  provider: ^6.x.x
```
