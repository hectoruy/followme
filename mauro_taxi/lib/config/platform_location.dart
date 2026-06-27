import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Builds platform-appropriate [LocationSettings].
///
/// On iOS we must use [AppleSettings] with [AppleSettings.allowBackgroundLocationUpdates]
/// enabled so the GPS stream keeps delivering updates while the app is in the
/// background (paired with the `location` entry in `UIBackgroundModes`). On
/// Android the foreground service owns background execution, so the default
/// [LocationSettings] are sufficient.
LocationSettings buildLocationSettings({bool background = false}) {
  const accuracy = LocationAccuracy.high;
  const distanceFilter = 5;

  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return AppleSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
      allowBackgroundLocationUpdates: background,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: background,
    );
  }

  return const LocationSettings(
    accuracy: accuracy,
    distanceFilter: distanceFilter,
  );
}
