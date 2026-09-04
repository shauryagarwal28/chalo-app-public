import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import '../services/agora_ptt_service.dart';
import '../services/api_exception.dart';
import '../services/auth_service.dart';
import '../services/location_ws_service.dart';
import '../services/mock_user_state.dart';
import '../services/party_service.dart';
import '../theme/colors.dart';
import '../widgets/emergency_stage1_banner.dart';
import '../widgets/metallic_card.dart';
import '../widgets/rider_marker_icon.dart';
import 'emergency_stage2_screen.dart';
import 'emergency_stage3_screen.dart';
import 'home_screen.dart';
import 'post_ride_rating_rider_screen.dart';
import 'report_incident_screen.dart';
import 'ride_chat_screen.dart';

class LiveRideScreen extends StatefulWidget {
  final String partyId;
  final String rideName;
  final String partyCode;
  final int maxRiders;
  final bool isOrganiser;

  /// userId -> name for members already in the party before this screen's
  /// WS connection opened — see waiting_room_screen.dart's doc comment on
  /// the same field for why this is needed (the organiser path passes the
  /// default empty map, since POST /parties has no roster to seed from).
  final Map<String, String> initialMemberNames;

  /// Whether this live party originated from a Community Mode ride (as
  /// opposed to a private Active Ride Mode "ride with friends" party) —
  /// added 2026-08-20 to close `process/build-status.md` Next Steps item
  /// 31's remaining gap. This screen (S9) is shared infrastructure between
  /// both modes (`product/ux/user-flows.md` Flow D/E: a Community Mode
  /// ride's live party *is* S9 once the organiser taps Start Ride) — before
  /// this field existed, S9 had no way to tell the two apart at all.
  ///
  /// Defaults to `false`, and neither of this app's two current, real
  /// `LiveRideScreen(...)` call sites (`party_ready_screen.dart`,
  /// `waiting_room_screen.dart` — both Active Ride Mode's S8) pass it, so
  /// both are provably unaffected by this field's existence — per
  /// `product/decisions/12-rider-initiated-leave.md`'s "Scope Reversal",
  /// Active Ride Mode's Leave Party is not allowed to change behaviour.
  ///
  /// **Honesty note for whoever reads this next**: Community Mode's own
  /// ride-day screens (`ride_day_screen.dart`/S16,
  /// `rider_ride_day_screen.dart`) do not construct a `LiveRideScreen` at
  /// all today — their "Start Ride"/"End Ride (mock)" controls are still
  /// fully local mock state (see `process/build-status.md`'s item 31 write-up
  /// dated 2026-08-20). So while the consequence logic gated on this flag
  /// (see `_leaveParty` below) is real, live-verifiable code, no live path
  /// in the current build ever sets it to `true` — wiring Community Mode's
  /// Start Ride to actually reach this screen would mean giving Community
  /// Mode a real backend party, which the standing "no Community Mode
  /// wiring ahead of Active Ride Mode validation" phase gate
  /// (`docs/process/roadmap.md`'s 2026-07-03 amendment) does not authorize
  /// doing silently as a side effect of this task. Flagged for the PM, not
  /// decided here.
  final bool isCommunityRide;

  /// The organiser's userId, needed to resolve their display name (via
  /// `_nameFor`) when [isCommunityRide] triggers the immediate mid-ride
  /// rating flow on Leave Party. Only meaningful when [isCommunityRide] is
  /// `true` — Active Ride Mode's private parties have no organiser-rating
  /// concept at all (`product/features/active-ride-mode.md`) and never set
  /// this. Nullable/defaulted rather than required because, per the note
  /// above, nothing in this build constructs this screen with
  /// `isCommunityRide: true` yet.
  final String? organiserId;

  const LiveRideScreen({
    super.key,
    required this.partyId,
    required this.rideName,
    required this.partyCode,
    required this.maxRiders,
    required this.isOrganiser,
    this.initialMemberNames = const {},
    this.isCommunityRide = false,
    this.organiserId,
  });

  @override
  State<LiveRideScreen> createState() => _LiveRideScreenState();
}

/// Hold-to-arm delay before a press actually starts transmitting, per the
/// state machine in docs/technical/systems/ptt-audio.md
/// (IDLE -> [hold 500ms] -> TRANSMITTING).
const _pttHoldDelay = Duration(milliseconds: 500);

/// Which of the two independent paths — the demo "Simulate" buttons, or a
/// real `emergency:*` server event — currently owns the emergency banner /
/// full-screen slot. See this file's "Demo vs real collision" note on
/// `_LiveRideScreenState` for the full policy this drives.
enum _EmergencySource { demo, real }

class _LiveRideScreenState extends State<LiveRideScreen> {
  // Only used as GoogleMap's initialCameraPosition (a fixed starting point
  // before a real GPS fix arrives) — no longer where any rider marker is
  // actually drawn. Camera re-centers to the real first fix in
  // _onPositionUpdate below.
  static const _fallbackCenter = LatLng(12.9716, 77.5946);

  /// Sample route polyline near `_fallbackCenter`, per S9's "Map Layer"
  /// spec ("Shared route highlighted on the map (orange line)"). This app
  /// has no real routing/directions API integration (out of scope for this
  /// visual pass — see docs/product/features/active-ride-mode.md) so these
  /// points are hand-picked Bangalore-area coordinates, not a real route —
  /// just enough to look like a plausible curved road on the map.
  static const _routePoints = <LatLng>[
    LatLng(12.9716, 77.5946),
    LatLng(12.9742, 77.5952),
    LatLng(12.9769, 77.5938),
    LatLng(12.9788, 77.5901),
    LatLng(12.9805, 77.5865),
    LatLng(12.9830, 77.5840),
    LatLng(12.9862, 77.5820),
  ];

  final _ptt = AgoraPttService();
  Timer? _holdTimer;
  bool _transmitting = false;
  bool _micPermissionGranted = false;

  final _locationWs = LocationWsService();
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSub;
  Timer? _locationSendTimer;
  Position? _lastPosition;

  /// Rebuilt asynchronously by `_updateMarkers` (custom bitmap rasterization
  /// can't happen synchronously inside `build()`) whenever rider data or
  /// this device's own position changes.
  Set<Marker> _markers = {};

  /// Real S10a/b/c emergency alert wiring (docs/product/features/
  /// emergency-alert.md), backed by the real backend engine
  /// (technical/systems/emergency-detection.md) over the same
  /// `_locationWs` connection this screen already opens for location. The
  /// two "Simulate" party-menu buttons from the original demo-only wiring
  /// (2026-07-08) are kept — there's no way to choreograph a real
  /// stop-while-moving pattern from a single simulator/emulator — but now
  /// share the same banner/full-screen state below as the real path, per
  /// the "Demo vs real collision" note immediately below.
  ///
  /// **Demo vs real collision policy** (both triggers now genuinely can
  /// fire on the same device — the old demo-only version never had to
  /// reason about this):
  /// - A real event always preempts an in-flight demo one: a real
  ///   `emergency:stage1` clears an active demo banner (with a SnackBar
  ///   explaining why); a real `emergency:confirm`/`emergency:full_alert`
  ///   pops an open demo Stage 2/3 screen before pushing the real one.
  /// - A demo trigger refuses outright (SnackBar, no-op) if a real
  ///   banner/full-screen is currently active — the demo is for UI
  ///   testing, it must never visually stomp a genuine safety alert.
  /// - `_bannerSource`/`_fullScreenSource` below are the two independent
  ///   "who currently owns this UI slot" flags this policy is built on;
  ///   `_claimFullScreenSlot` and `_realEmergencyActive` are where the
  ///   policy is actually enforced. See build-status.md's dated entry for
  ///   this task for the full reasoning.
  Timer? _emergencyTimer;
  _EmergencySource? _bannerSource;
  String _bannerRiderName = '';
  String? _bannerStoppedUserId; // real only — matches emergency:resolved/full_alert to the right banner
  int? _bannerSecondsRemaining; // null = no live countdown (real emergency:stage1 carries none, see EmergencyStage1Banner's doc comment)

  /// Guards the Stage 2 / Stage 3 full-screen route slot (only one can
  /// ever be pushed at a time) — see `_claimFullScreenSlot`. Bumped on
  /// every push so a preempted push's own `await Navigator.push(...)`
  /// continuation (which resolves later, asynchronously) can tell it's no
  /// longer the current owner and skip clearing `_fullScreenSource` out
  /// from under whatever preempted it.
  _EmergencySource? _fullScreenSource;
  int _emergencyGen = 0;

  bool get _realEmergencyActive =>
      _bannerSource == _EmergencySource.real || _fullScreenSource == _EmergencySource.real;

  @override
  void initState() {
    super.initState();
    _ptt.lastError.addListener(_onPttError);
    // Deferred to after the first frame: init() can fail synchronously
    // (e.g. no App ID configured yet), and the error listener needs a
    // fully-mounted context to show a SnackBar via ScaffoldMessenger.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ptt.init().then((_) => _ptt.join());
    });

    _locationWs.riderLocations.addListener(_onRiderDataChanged);
    _locationWs.riderNames.addListener(_onRiderDataChanged);
    _locationWs.lastError.addListener(_onLocationError);
    _locationWs.stage1Event.addListener(_onEmergencyStage1);
    _locationWs.confirmEvent.addListener(_onEmergencyConfirm);
    _locationWs.resolvedEvent.addListener(_onEmergencyResolved);
    _locationWs.fullAlertEvent.addListener(_onEmergencyFullAlert);
    _locationWs.pttStartedEvent.addListener(_onPttStarted);
    _locationWs.pttEndedEvent.addListener(_onPttEnded);
    _locationWs.partyEndedEvent.addListener(_onPartyEnded);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Populates the curated-place-pin marker (fuel stop) immediately,
      // ahead of any real GPS/WS rider data arriving.
      _updateMarkers();
      _initLocation();
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _emergencyTimer?.cancel();
    _ptt.lastError.removeListener(_onPttError);
    _ptt.dispose();

    _locationSendTimer?.cancel();
    _positionSub?.cancel();
    _locationWs.riderLocations.removeListener(_onRiderDataChanged);
    _locationWs.riderNames.removeListener(_onRiderDataChanged);
    _locationWs.lastError.removeListener(_onLocationError);
    _locationWs.stage1Event.removeListener(_onEmergencyStage1);
    _locationWs.confirmEvent.removeListener(_onEmergencyConfirm);
    _locationWs.resolvedEvent.removeListener(_onEmergencyResolved);
    _locationWs.fullAlertEvent.removeListener(_onEmergencyFullAlert);
    _locationWs.pttStartedEvent.removeListener(_onPttStarted);
    _locationWs.pttEndedEvent.removeListener(_onPttEnded);
    _locationWs.partyEndedEvent.removeListener(_onPartyEnded);
    _locationWs.dispose();
    super.dispose();
  }

  void _onPttError() {
    final message = _ptt.lastError.value;
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _onRiderDataChanged() {
    if (mounted) setState(() {});
    _updateMarkers();
  }

  void _onLocationError() {
    final message = _locationWs.lastError.value;
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// `ptt:started`/`ptt:ended` — per ptt-audio.md's "Audio Cue Playback"
  /// section, this should trigger a short local start/end beep on every
  /// other party member's device. **Deliberately not implemented here**:
  /// this app has no audio-playback package or sound asset anywhere in
  /// `pubspec.yaml`/`app/assets`, and adding one wasn't authorized as part
  /// of this task (new dependency, and this project has a documented
  /// history of `ffi`/AGP conflicts from exactly this kind of casual
  /// package add — see build-status.md's "Android build environment"
  /// section). Flagged back to the senior/PM rather than guessed at. The
  /// relay itself (`ptt:state` out, these two listeners in) is real and
  /// wired — only the actual beep playback is the open gap, confirmable
  /// via this `debugPrint` in `adb logcat` in the meantime.
  void _onPttStarted() {
    final event = _locationWs.pttStartedEvent.value;
    if (event == null) return;
    debugPrint('ptt:started — ${event.userId} is now transmitting (no audio cue wired yet)');
  }

  void _onPttEnded() {
    final event = _locationWs.pttEndedEvent.value;
    if (event == null) return;
    debugPrint('ptt:ended — ${event.userId} stopped transmitting (no audio cue wired yet)');
  }

  /// Opens the party WS connection and starts the real GPS stream, per
  /// technical/systems/real-time-location.md — foreground cadence (every
  /// 3 seconds) and technical/architecture/api-design.md's WS handshake
  /// (`ws://<host>/ws?token=<accessToken>`).
  ///
  /// **Background tracking, built 2026-08-17** (previously foreground-only
  /// — see build-status.md's dated entries for the full before/after): once
  /// the foreground permission below is granted, [_requestBackgroundLocationExtras]
  /// requests each platform's background-capable permission as a *second*,
  /// separate step (never bundled with the foreground request — that's the
  /// one rule both platforms actually enforce), and [_buildLocationSettings]
  /// configures the platform-specific mechanism that keeps the position
  /// stream alive while backgrounded: `AndroidSettings.foregroundNotificationConfig`
  /// (a real Android foreground service + persistent notification) on
  /// Android, `AppleSettings.allowBackgroundLocationUpdates` (paired with
  /// `UIBackgroundModes: location` in Info.plist and "Always" permission)
  /// on iOS. Neither of these blocks the (already-working) foreground
  /// stream from starting — a decline on the background step just means
  /// sharing keeps working exactly as before while the app is in the
  /// foreground, per this doc comment's own "never block on the extras"
  /// discipline.
  Future<void> _initLocation() async {
    final token = AuthSession.accessToken;
    if (token == null) {
      // Shouldn't happen — this screen is only reachable after the real
      // phone/OTP flow — but fail loudly rather than silently never
      // connecting, same discipline as agora_ptt_service.dart's "no App ID"
      // guard.
      _locationWs.lastError.value =
          'Not signed in — cannot share your live location with the party.';
      return;
    }

    await _locationWs.connect(token);

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _locationWs.lastError.value =
          'Location services are off — turn them on to share your position with your party.';
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _locationWs.lastError.value =
          'Location permission is needed to share your position with your party.';
      return;
    }

    if (!mounted) return;

    await _requestBackgroundLocationExtras();
    if (!mounted) return;

    _positionSub = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(),
    ).listen(_onPositionUpdate, onError: (Object e) {
      _locationWs.lastError.value = 'Location stream error: $e';
    });

    // Foreground send cadence, per real-time-location.md's "Update
    // Frequency" table ("Foreground: Every 3 seconds"). Independent of the
    // position stream's own event rate — sends whatever the latest known
    // fix is, so a stationary rider still refreshes their own TTL server-
    // side (Task 6's 30s Redis TTL) instead of going stale. Deliberately
    // kept at a flat 3s even while backgrounded — real-time-location.md's
    // Update Frequency table specs a 3s -> 10s drop once backgrounded, but
    // this task's own scope explicitly kept the existing cadence intact
    // rather than making it lifecycle-aware; see build-status.md's write-up
    // for this task and that doc's status line for the resulting gap.
    _locationSendTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final position = _lastPosition;
      if (position == null) return;
      final speedKmph = position.speed.isFinite && position.speed > 0
          ? position.speed * 3.6
          : 0.0;
      _locationWs.sendLocationUpdate(
        partyId: widget.partyId,
        lat: position.latitude,
        lng: position.longitude,
        speedKmph: speedKmph,
        timestamp: DateTime.now(),
      );
    });
  }

  /// Requests each platform's background-capable location permission as a
  /// **second, separate** step from the foreground permission already
  /// granted by the time this is called — never bundled into one request,
  /// per each platform's own rule:
  /// - Android 11+ silently denies `ACCESS_BACKGROUND_LOCATION` outright if
  ///   it's requested in the same `requestPermissions()` call as
  ///   `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` — confirmed by
  ///   reading `geolocator_android`'s own `PermissionManager.java`, which
  ///   does exactly this bundling on a second call and would silently never
  ///   deliver a real background grant on Android 11+. `permission_handler`'s
  ///   `Permission.locationAlways` avoids this — its own Android
  ///   implementation sends a runtime request containing *only*
  ///   `ACCESS_BACKGROUND_LOCATION` (confirmed by reading
  ///   `PermissionUtils.getManifestNames`), which is what's used here
  ///   instead of `Geolocator.requestPermission()` for this step.
  /// - iOS only offers the "Always" upgrade dialog on a *later* request
  ///   after "When In Use" is already granted — `geolocator_apple`'s own
  ///   `requestPermission()` can't drive this at all (it only ever calls
  ///   `requestWhenInUseAuthorization` while `NSLocationWhenInUseUsageDescription`
  ///   is present, confirmed by reading `PermissionHandler.m`), so
  ///   `permission_handler`'s `Permission.locationAlways` — which
  ///   implements the correct two-step escalation — is used here too, for
  ///   the same reason. Requires the `PERMISSION_LOCATION` preprocessor
  ///   macro set for the `permission_handler_apple` pod target (`ios/Podfile`)
  ///   or this silently never resolves on iOS at all.
  ///
  /// Every request here is best-effort and never blocks the (already
  /// granted, already working) foreground stream this method is called
  /// from — see this file's real-time-location.md cross-reference and
  /// `AndroidManifest.xml`'s comment on why the Android foreground service
  /// (started unconditionally by [_buildLocationSettings], not gated on
  /// anything requested here) is the primary background-delivery mechanism
  /// regardless of how the user answers these prompts.
  Future<void> _requestBackgroundLocationExtras() async {
    if (kIsWeb) return; // no background-tracking concept on the web build

    if (defaultTargetPlatform == TargetPlatform.android) {
      // Android 13+ gate on whether the foreground service's persistent
      // notification is actually visible — the service itself still runs
      // either way (see ForegroundNotificationConfig's own doc comment),
      // but per real-time-location.md's Android Considerations the
      // notification is a hard requirement, so this is requested even
      // though it isn't strictly required for tracking to function.
      await Permission.notification.request();
      if (!mounted) return;

      // Battery optimisation exemption, per real-time-location.md's
      // Battery Optimisation Strategy table ("requested at first launch of
      // an active ride"). Best-effort — declining doesn't block the ride,
      // just makes background delivery less reliable on aggressive OEM
      // battery managers (Xiaomi/Realme/Samsung, per that same doc's
      // "Must be tested on" note).
      await Permission.ignoreBatteryOptimizations.request();
      if (!mounted) return;
    }

    final status = await Permission.locationAlways.request();
    if (!mounted) return;
    if (!status.isGranted) {
      // Deliberately not surfaced via the same lastError/SnackBar channel
      // as a real failure — foreground sharing is completely unaffected,
      // and on Android the foreground service is the primary mechanism
      // regardless of this permission. An FYI, not an error.
      debugPrint(
        'Background/"Always" location not granted ($status) — foreground '
        'sharing still works; background delivery may be less reliable, '
        'especially on iOS once the app is fully backgrounded.',
      );
    }
  }

  /// Platform-specific stream settings so the position stream keeps
  /// delivering fixes while the app is backgrounded during an active ride
  /// — see [_requestBackgroundLocationExtras]'s doc comment and
  /// `technical/systems/real-time-location.md`'s iOS/Android Considerations
  /// sections. `distanceFilter`/`accuracy` are unchanged from before this
  /// task (foreground behaviour is additive, not rewritten, per this task's
  /// own scope boundary).
  LocationSettings _buildLocationSettings() {
    if (kIsWeb) {
      return const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        // Starts geolocator_android's own foreground service
        // (GeolocatorLocationService, foregroundServiceType="location") with
        // this persistent notification, unconditionally — this, not the
        // ACCESS_BACKGROUND_LOCATION permission requested above, is what
        // actually keeps location delivery going while the app is
        // backgrounded/screen-locked (Android's official recommended
        // pattern for continuous-tracking apps; a running foreground
        // service is exempt from the background location limits that
        // ACCESS_BACKGROUND_LOCATION exists to lift). Text per
        // real-time-location.md's Android Considerations section exactly.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Chalo',
          notificationText:
              'Chalo is tracking your location for your active ride',
          notificationChannelName: 'Active Ride Location',
          setOngoing: true,
        ),
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        activityType: ActivityType.automotiveNavigation,
        // Safe to set unconditionally regardless of whether "Always" was
        // actually granted above — geolocator_apple's own native code only
        // cross-checks that Info.plist declares `UIBackgroundModes:
        // location` before honouring this (confirmed by reading
        // GeolocationHandler.m's shouldEnableBackgroundLocationUpdates), it
        // doesn't crash or misbehave on a lower authorization level; it
        // simply won't get backgrounded deliveries until the user grants
        // "Always" (iOS's own restriction, not this app's).
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }

    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );
  }

  void _onPositionUpdate(Position position) {
    if (!mounted) return;
    final isFirstFix = _lastPosition == null;
    setState(() => _lastPosition = position);
    _updateMarkers();
    if (isFirstFix) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(position.latitude, position.longitude),
          15,
        ),
      );
    }
  }

  /// Resolves a display name for [userId] — own name locally
  /// (mock_user_state.dart, since there's no way to display it any other
  /// way client-side), otherwise whatever's been learned about that rider
  /// so far: a `party:member_joined` event received on this connection,
  /// then the initial roster passed in from the join response, then a
  /// short userId-derived fallback label. See party_service.dart's
  /// file-level note — the backend has no way to persist a user's name in
  /// MVP scope, so the first two sources are very likely empty in
  /// practice; the fallback below is the common case, not an edge case,
  /// until that backend gap is closed.
  String _nameFor(String userId) {
    if (userId == AuthSession.userId) {
      final name = MockUserState.riderName;
      return (name != null && name.trim().isNotEmpty) ? name : 'You';
    }
    final wsName = _locationWs.riderNames.value[userId];
    if (wsName != null && wsName.isNotEmpty) return wsName;
    final initialName = widget.initialMemberNames[userId];
    if (initialName != null && initialName.isNotEmpty) return initialName;
    final shortId = userId.length >= 4 ? userId.substring(0, 4) : userId;
    return 'Rider ${shortId.toUpperCase()}';
  }

  /// Every rider currently known to be live on this map — self (if a GPS
  /// fix has arrived yet) plus every other rider this connection has
  /// received at least one `location:broadcast` for. Note this undercounts
  /// the full party roster (a member who hasn't granted location
  /// permission, or hasn't sent an update yet, won't appear) — there's no
  /// separate roster-fetch wired into this screen, only the location
  /// stream itself.
  List<String> _liveRiderIds() {
    final selfId = AuthSession.userId;
    return [
      if (selfId != null && _lastPosition != null) selfId,
      ..._locationWs.riderLocations.value.keys,
    ];
  }

  /// Rebuilds `_markers` with custom circular bitmap markers per S9's
  /// "Rider Dots" spec (own: 20px + glow ring, others: 16px, unique colour
  /// + initials — docs/product/features/active-ride-mode.md). Async because
  /// rasterizing a bitmap marker (RiderMarkerIcon.build) can't happen
  /// synchronously inside `build()`; results are cached there by
  /// initials/colour/size, so repeated calls (e.g. every 3s location tick)
  /// are cheap once each distinct marker has been rendered once.
  Future<void> _updateMarkers() async {
    if (!mounted) return;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final markers = <Marker>{};
    final selfId = AuthSession.userId;
    final position = _lastPosition;

    if (selfId != null && position != null) {
      final icon = await RiderMarkerIcon.build(
        initials: initialsFor(_nameFor(selfId)),
        color: ChaloColors.primary,
        diameter: 20,
        glow: true,
        devicePixelRatio: devicePixelRatio,
      );
      markers.add(
        Marker(
          markerId: MarkerId(selfId),
          position: LatLng(position.latitude, position.longitude),
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(title: _nameFor(selfId)),
        ),
      );
    }

    for (final entry in _locationWs.riderLocations.value.entries) {
      final userId = entry.key;
      if (userId == selfId) continue; // defensive — server never echoes self
      final loc = entry.value;
      final icon = await RiderMarkerIcon.build(
        initials: initialsFor(_nameFor(userId)),
        color: riderColorFor(userId),
        diameter: 16,
        glow: false,
        devicePixelRatio: devicePixelRatio,
      );
      markers.add(
        Marker(
          markerId: MarkerId(userId),
          position: LatLng(loc.lat, loc.lng),
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(title: _nameFor(userId)),
        ),
      );
    }

    // Curated Place Pin — untouched, not in scope for this pass (see
    // active-ride-mode.md's "Curated Place Pins" subsection).
    markers.add(
      Marker(
        markerId: const MarkerId('fuel_stop'),
        position: const LatLng(12.9750, 77.5930),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Fuel stop'),
      ),
    );

    if (!mounted) return;
    setState(() => _markers = markers);
  }

  Future<void> _onPttDown() async {
    if (!_micPermissionGranted) {
      final granted = await _ptt.requestMicPermission();
      if (!mounted) return;
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission needed for push-to-talk'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
      _micPermissionGranted = true;
    }

    _holdTimer?.cancel();
    _holdTimer = Timer(_pttHoldDelay, () {
      _ptt.startTalking();
      // Relay-only — Agora already carries the real audio peer-to-peer
      // regardless of this call; this just lets other party members' local
      // audio-cue listener know a transmission has started. Per ptt.ts /
      // ptt-audio.md's state machine, sent alongside (not instead of) the
      // Agora call above.
      _locationWs.sendPttState(partyId: widget.partyId, state: 'start');
      if (mounted) setState(() => _transmitting = true);
    });
  }

  void _onPttUp() {
    _holdTimer?.cancel();
    if (_transmitting) {
      _ptt.stopTalking();
      _locationWs.sendPttState(partyId: widget.partyId, state: 'end');
      setState(() => _transmitting = false);
    }
  }

  void _shareCode() {
    Share.share(
      'Join my Chalo ride — ${widget.rideName}!\n\nParty code: ${widget.partyCode}\n\nOpen in Chalo: https://chalo.app/join/${widget.partyCode}',
      subject: 'Join my ride on Chalo',
    );
  }

  void _returnToHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  /// Organiser-only, per api-design.md's `POST /parties/:id/end` and the
  /// red "End Ride" button below (only ever rendered `if
  /// (widget.isOrganiser)`). Previously this button just called
  /// [_returnToHome] with no server call at all — found 2026-08-15 (see
  /// build-status.md's "Full end-to-end regression..." section): the
  /// party's Redis state (`:state`/`:members`/`:location:*`) survived
  /// indefinitely, and a still-connected member's device never learned the
  /// ride had ended.
  ///
  /// On failure, deliberately does NOT navigate home — an organiser who
  /// taps End Ride and sees an error should get the chance to retry rather
  /// than silently leaving orphaned party state in Redis, same "don't
  /// navigate past a failed server call" discipline
  /// `create_party_screen.dart`'s `_createParty` already uses.
  ///
  /// **Known gap, not fixed here**: there's no `party:ended` WS broadcast
  /// (see `party_service.dart`'s `endParty` doc comment), so a still-open
  /// member device is not proactively notified — it just stops receiving
  /// any further `location:broadcast`/`party:*` events for this party and
  /// the map goes stale in place. Flagged, not silently patched around,
  /// since inventing that broadcast is new backend scope beyond this fix.
  bool _endingRide = false;

  Future<void> _endRide() async {
    if (_endingRide) return;
    Navigator.pop(context); // close the party menu
    _endingRide = true;
    try {
      await PartyService.endParty(widget.partyId);
    } on ApiException catch (e) {
      _endingRide = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not end the ride: ${e.message}. Party state was not '
            'cleared — try again.',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    if (!mounted) return;
    _returnToHome();
  }

  /// Member-only, matching "End Ride" above. Deliberately makes no REST
  /// call — per api-design.md there is no `POST /parties/leave` endpoint,
  /// and Task 5's own senior review confirmed `party:member_left` is
  /// intentionally WS-disconnect-driven, not REST-triggered (a member
  /// leaving is communicated purely by their WS connection closing, which
  /// [_returnToHome] already causes via this screen's own `dispose()` ->
  /// `_locationWs.dispose()`). The rest of the party learns via
  /// `party:member_left` after the existing 3-minute reconnect grace
  /// window elapses with no reconnect — same as any other disconnect, by
  /// design, not a gap.
  ///
  /// **Leave Party's own UX/behaviour is unchanged** — per
  /// `product/decisions/12-rider-initiated-leave.md`'s "Scope Reversal",
  /// this button still has no reason prompt, no toast, no roster
  /// annotation, regardless of party type. The one branch added 2026-08-20
  /// is what happens *after* the tap, and only for a party flagged
  /// [LiveRideScreen.isCommunityRide] — see [_leaveAndRateOrganiser].
  void _leaveParty() {
    Navigator.pop(context); // close the party menu
    if (widget.isCommunityRide) {
      _leaveAndRateOrganiser();
      return;
    }
    _returnToHome();
  }

  /// Community Mode's mid-ride-leave consequence, per
  /// `product/decisions/12-rider-initiated-leave.md`'s "Mid-Ride Leave —
  /// Rating Flow": the leaving rider rates the organiser immediately,
  /// reusing the existing S18 (`PostRideRatingRiderScreen`) rider-view
  /// rating component/pattern rather than a bespoke mini rating screen, per
  /// that section's explicit correction.
  ///
  /// Uses `pushReplacement`, not `push` — this screen (and its WS
  /// connection/location stream) genuinely ends the moment a rider leaves;
  /// the rating step happens *after* leaving, not as an overlay on top of
  /// a still-live party. `pushReplacement` triggers this State's normal
  /// `dispose()` (closing `_locationWs`) exactly as [_returnToHome] would
  /// have, and leaves no stale "back to the party" route for the rating
  /// screen to accidentally return to — which is also why
  /// `returnToHomeOnSubmit: true` is passed: a bare `Navigator.pop()` on
  /// Submit would have nothing left on the stack to land on.
  void _leaveAndRateOrganiser() {
    final organiserId = widget.organiserId;
    final selfId = AuthSession.userId;
    // Defensive fallback only — every real construction path with
    // isCommunityRide: true is expected to also pass organiserId (see that
    // field's doc comment); this just avoids a null display-name crash if
    // that contract is ever violated rather than assuming it never will be.
    final organiserName = organiserId != null ? _nameFor(organiserId) : 'the organiser';
    final otherRiders = _liveRiderIds()
        .where((id) => id != selfId && id != organiserId)
        .map(_nameFor)
        .toList();

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PostRideRatingRiderScreen(
          organiserName: organiserName,
          otherRiders: otherRiders,
          returnToHomeOnSubmit: true,
        ),
      ),
    );
  }

  /// Closes the gap flagged (not solved) in
  /// `product/decisions/13-incident-reporting.md`'s "Where it lives"
  /// section: once a Community Mode ride goes live, riders land on this
  /// screen (S9) — which had no chat or incident-report entry point at all.
  /// Gated on [LiveRideScreen.isCommunityRide] in the party menu below, same
  /// pattern as `_leaveParty`'s branching — Active Ride Mode's party menu
  /// never shows either of these two new items, since neither real call
  /// site (`party_ready_screen.dart`, `waiting_room_screen.dart`) sets that
  /// flag.
  ///
  /// `RideChatScreen` only takes `rideName` — it already carries its own
  /// hardcoded mock roster (`_kMockOrganiserName`/`_kMockRiderNames`) for
  /// its own "Report an Incident" header icon, so there's nothing from S9's
  /// real roster to thread through here. Uses `push`, not `pushReplacement`
  /// — unlike leaving, opening chat doesn't end this screen's WS/location
  /// connection, so the party stays live underneath and the rider returns
  /// to it via the normal back button.
  void _openChat() {
    Navigator.pop(context); // close the party menu
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RideChatScreen(rideName: widget.rideName)),
    );
  }

  /// Same roster-resolution pattern as [_leaveAndRateOrganiser] (self and
  /// organiser excluded from `riders`, organiser passed separately so
  /// `ReportIncidentScreen` can show it as a selectable, ORGANISER-badged
  /// target per Decision 13's symmetric-reporting rule) — reused here
  /// rather than re-derived, since it's the same "who's on this live ride"
  /// question either flow needs answered. `push`, not `pushReplacement`,
  /// for the same reason as [_openChat]: reporting an incident doesn't end
  /// the rider's participation in the still-live party.
  ///
  /// `organiserName` is left `null` when the viewer *is* the organiser
  /// (`organiserId == selfId`) — same "can't report yourself" rule
  /// `ride_day_screen.dart`'s organiser-side entry point already follows —
  /// rather than always resolving it whenever [LiveRideScreen.organiserId]
  /// is non-null.
  void _openReportIncident() {
    Navigator.pop(context); // close the party menu
    final organiserId = widget.organiserId;
    final selfId = AuthSession.userId;
    final organiserName =
        (organiserId != null && organiserId != selfId) ? _nameFor(organiserId) : null;
    final otherRiders = _liveRiderIds()
        .where((id) => id != selfId && id != organiserId)
        .map(_nameFor)
        .toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportIncidentScreen(
          rideName: widget.rideName,
          riders: otherRiders,
          organiserName: organiserName,
        ),
      ),
    );
  }

  /// `party:ended` — the organiser tapped End Ride and the backend's
  /// `POST /parties/:id/end` succeeded (added 2026-08-17, closing
  /// process/build-status.md Next Steps item 30). Before this, a member
  /// whose device was still connected when the ride ended got no signal at
  /// all — their screen just kept showing the last state it had
  /// indefinitely (confirmed live during the same regression pass that
  /// found the gap).
  ///
  /// Gated on `!widget.isOrganiser`: the server broadcasts this to every
  /// party member with no exclusion (`websocket/broadcast.ts`'s
  /// `broadcastPartyEnded`, fired right after `endParty()` succeeds, before
  /// the room registry is torn down), so the organiser's own connection
  /// receives an echo of the exact action they just took. Their device is
  /// already handling that locally via [_endRide] (and may already be
  /// mid-navigation-home, with this widget on its way to being disposed, by
  /// the time the echo arrives over the same connection) — there's nothing
  /// for this handler to usefully add there, and running it anyway risks a
  /// redundant SnackBar/double-navigation on the one device that doesn't
  /// need either.
  ///
  /// **Product/UX call, made explicitly rather than left unspecified**
  /// (per `product/features/active-ride-mode.md`'s Ride End spec, "All
  /// party members return to home screen" — unconditional, no branch for
  /// *how*): a SnackBar, not a blocking dialog, immediately followed by the
  /// same [_returnToHome] `_endRide` already uses. Rationale: a member on
  /// this screen may still be riding — requiring a tap to dismiss a
  /// blocking dialog before they can put their phone away is a worse
  /// safety trade than a brief, glanceable notice plus an automatic return
  /// home, especially since (unlike the emergency flow's Stage 2 prompt)
  /// there's no real choice for the member to make here. [_returnToHome]'s
  /// `pushAndRemoveUntil(..., (route) => false)` also correctly clears the
  /// whole navigation stack regardless of what's on top of it — including
  /// an open Emergency Stage 2/3 screen, if a member happened to be
  /// mid-emergency-flow when the ride ended — confirmed by reading the
  /// existing implementation (the same mechanism `_claimFullScreenSlot`
  /// already relies on to preempt a demo screen with a real one), not a new
  /// code path built for this.
  void _onPartyEnded() {
    final event = _locationWs.partyEndedEvent.value;
    if (event == null || !mounted || widget.isOrganiser) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('The organiser ended this ride.'),
        duration: Duration(seconds: 2),
      ),
    );
    _returnToHome();
  }

  /// Enforces the "Demo vs real collision policy" documented on this
  /// class's field declarations: real always preempts (pops) whatever's
  /// currently in the full-screen slot; demo refuses outright if the slot
  /// is already occupied by anything (demo or real). Returns whether
  /// [source] may proceed to claim the slot — callers must still set
  /// `_fullScreenSource = source` and bump `_emergencyGen` themselves
  /// immediately afterward (kept out of this function so the two
  /// `Navigator.push` call sites below stay in control of exactly when
  /// that happens, right before their own `await`).
  bool _claimFullScreenSlot(_EmergencySource source) {
    if (source == _EmergencySource.real) {
      if (_fullScreenSource != null) {
        Navigator.of(context).pop(); // safety wins — dismiss whatever's open
      }
      return true;
    }
    if (_fullScreenSource != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An emergency alert is already active'),
          duration: Duration(seconds: 2),
        ),
      );
      return false;
    }
    return true;
  }

  /// Pushes `EmergencyStage2Screen`, shared by both the demo "You Stopped"
  /// trigger and the real `emergency:confirm` handler below.
  Future<void> _pushStage2({
    required _EmergencySource source,
    required String riderName,
    required int initialCountdownSeconds,
    required bool autoResolveOnTimeout,
    void Function(String response)? onRespond,
  }) async {
    if (!_claimFullScreenSlot(source)) return;
    final myGen = ++_emergencyGen;
    _fullScreenSource = source;

    final needsHelp = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EmergencyStage2Screen(
          riderName: riderName,
          initialCountdownSeconds: initialCountdownSeconds,
          autoResolveOnTimeout: autoResolveOnTimeout,
          onRespond: onRespond,
        ),
      ),
    );
    if (_emergencyGen == myGen) _fullScreenSource = null;
    if (!mounted) return;

    if (source == _EmergencySource.demo) {
      if (needsHelp == true) {
        // "I Need Help" or the 60s timeout — represents what the rest of
        // the party would now see arriving via FCM in the real design.
        await _pushStage3(
          source: _EmergencySource.demo,
          riderName: 'You',
          lastKnownLocation: 'MG Road, Bengaluru',
          timeElapsed: const Duration(seconds: 60),
          distanceBehindKm: 2.4,
        );
      } else if (needsHelp == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Alert cancelled — party not notified'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      // needsHelp == null means this screen was popped externally (a real
      // trigger preempted it, see _claimFullScreenSlot) — the real path's
      // own UI already communicates what actually happened, so nothing
      // extra to show here; showing "cancelled" would be misleading.
    } else if (needsHelp == false) {
      // Real path, "I Am Fine": confirm to the responding rider locally.
      // The server's own `emergency:resolved` broadcast (which also
      // reaches this same rider, per emergency.ts's no-exclusion
      // broadcast) is what clears any *other* member's banner — see
      // _onEmergencyResolved.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alert cancelled — party not notified'),
          duration: Duration(seconds: 2),
        ),
      );
    }
    // Real path "I Need Help" / externally-popped: nothing to do — the
    // server's emergency:full_alert broadcast (which reaches this same
    // rider too) is what pushes Stage 3, see _onEmergencyFullAlert.
  }

  /// Pushes `EmergencyStage3Screen`, shared by the demo escalation path
  /// and the real `emergency:full_alert` handler below.
  Future<void> _pushStage3({
    required _EmergencySource source,
    required String riderName,
    String? lastKnownLocation,
    DateTime? stoppedAt,
    required Duration timeElapsed,
    double? distanceBehindKm,
  }) async {
    if (!_claimFullScreenSlot(source)) return;
    final myGen = ++_emergencyGen;
    _fullScreenSource = source;
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmergencyStage3Screen(
          riderName: riderName,
          lastKnownLocation: lastKnownLocation,
          stoppedAt: stoppedAt,
          timeElapsed: timeElapsed,
          distanceBehindKm: distanceBehindKm,
        ),
      ),
    );
    if (_emergencyGen == myGen) _fullScreenSource = null;
  }

  /// Demo path 1: this device's own stopped-rider experience (S10b, then
  /// S10c if unresolved) — see docs/product/features/emergency-alert.md
  /// Resolution Paths table. No-op (SnackBar) if a real emergency is
  /// currently active, per the collision policy above.
  Future<void> _simulateYouStopped() async {
    Navigator.pop(context); // close the party menu
    if (_realEmergencyActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A real emergency alert is active — demo disabled'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    await _pushStage2(
      source: _EmergencySource.demo,
      riderName: 'You',
      initialCountdownSeconds: 60,
      autoResolveOnTimeout: true,
    );
  }

  /// Demo path 2: the rest of the party's view of another rider (`Host`)
  /// going through S10a, escalating automatically to S10c after 60s with no
  /// response (Resolution Paths: "No response after 1 minute"). No-op
  /// (SnackBar) if a real emergency is currently active.
  void _simulateRiderEmergency() {
    Navigator.pop(context); // close the party menu
    if (_realEmergencyActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A real emergency alert is active — demo disabled'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    _emergencyTimer?.cancel();
    setState(() {
      _bannerSource = _EmergencySource.demo;
      _bannerRiderName = 'Host';
      _bannerSecondsRemaining = 60;
    });
    _emergencyTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_bannerSource != _EmergencySource.demo) {
        // Preempted by a real emergency:stage1 mid-countdown — see
        // _onEmergencyStage1. That handler already cleared/replaced the
        // banner state; this timer has nothing left to do.
        _emergencyTimer?.cancel();
        return;
      }
      if ((_bannerSecondsRemaining ?? 0) <= 1) {
        _emergencyTimer?.cancel();
        setState(() => _bannerSource = null);
        _pushStage3(
          source: _EmergencySource.demo,
          riderName: 'Host',
          lastKnownLocation: 'Outer Ring Road, Bengaluru',
          timeElapsed: const Duration(seconds: 60),
          distanceBehindKm: 3.1,
        );
        return;
      }
      setState(() => _bannerSecondsRemaining = (_bannerSecondsRemaining ?? 60) - 1);
    });
  }

  /// Real trigger: `emergency:stage1` arrived — this device is a party
  /// member other than the stopped rider (the server excludes R from this
  /// broadcast; the identity check below is defensive only).
  void _onEmergencyStage1() {
    final event = _locationWs.stage1Event.value;
    if (event == null || !mounted) return;
    if (event.stoppedUserId == AuthSession.userId) return;

    if (_bannerSource == _EmergencySource.demo) {
      _emergencyTimer?.cancel();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A real emergency alert arrived — demo cleared'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    setState(() {
      _bannerSource = _EmergencySource.real;
      _bannerRiderName =
          event.stoppedUserName.isNotEmpty ? event.stoppedUserName : 'A rider';
      _bannerStoppedUserId = event.stoppedUserId;
      _bannerSecondsRemaining = null; // no countdown on the wire — see EmergencyStage1Banner's doc comment
    });
  }

  /// Real trigger: `emergency:confirm` arrived — this device is the
  /// stopped rider (the server only ever sends this to R).
  void _onEmergencyConfirm() {
    final event = _locationWs.confirmEvent.value;
    if (event == null || !mounted) return;
    _pushStage2(
      source: _EmergencySource.real,
      riderName: 'You',
      initialCountdownSeconds: event.countdownSeconds,
      autoResolveOnTimeout: false,
      onRespond: (response) {
        _locationWs.sendEmergencyRespond(partyId: widget.partyId, response: response);
      },
    );
  }

  /// Real trigger: `emergency:resolved` arrived (stopped rider tapped "I
  /// Am Fine" in time). Broadcast to the whole party with no exclusion —
  /// only acts if it matches a currently-shown real banner (a member who
  /// never saw the banner, or the stopped rider's own device, has nothing
  /// to clear).
  void _onEmergencyResolved() {
    final event = _locationWs.resolvedEvent.value;
    if (event == null || !mounted) return;
    if (_bannerSource == _EmergencySource.real && _bannerStoppedUserId == event.userId) {
      setState(() {
        _bannerSource = null;
        _bannerStoppedUserId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency alert resolved — rider is fine'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Real trigger: `emergency:full_alert` arrived — broadcast to the whole
  /// party with no exclusion, so this fires identically on the stopped
  /// rider's own device and every other member's device (per
  /// emergency-detection.md's Stage 3 "who sees it: all party members").
  void _onEmergencyFullAlert() {
    final event = _locationWs.fullAlertEvent.value;
    if (event == null || !mounted) return;

    if (_bannerSource == _EmergencySource.real && _bannerStoppedUserId == event.userId) {
      setState(() {
        _bannerSource = null;
        _bannerStoppedUserId = null;
      });
    }

    _pushStage3(
      source: _EmergencySource.real,
      riderName: event.name.isNotEmpty ? event.name : 'A rider',
      lastKnownLocation: (event.lat != null && event.lng != null)
          ? '${event.lat!.toStringAsFixed(4)}, ${event.lng!.toStringAsFixed(4)}'
          : null,
      stoppedAt: event.stoppedAt,
      timeElapsed: Duration(seconds: event.elapsedSeconds),
      distanceBehindKm: event.distanceBehindKm,
    );
  }

  void _showPartyMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        minChildSize: 0.25,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: ChaloColors.bgCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ChaloColors.borderShine,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.rideName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: ChaloColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Party code ${widget.partyCode} · ${_liveRiderIds().length}/${widget.maxRiders} riders',
                style: const TextStyle(
                  fontSize: 13,
                  color: ChaloColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ..._liveRiderIds().map(
                (userId) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 12,
                        color: userId == AuthSession.userId
                            ? ChaloColors.primary
                            : riderColorFor(userId),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _nameFor(userId),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ChaloColors.textPrimary,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _shareCode,
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('Share Code'),
              ),
              const SizedBox(height: 10),
              // No backend/FCM yet to fire the real two-device emergency
              // sequence — demo-only triggers, same pattern as waiting
              // room's "Simulate: Host Started Ride". See
              // docs/product/features/emergency-alert.md.
              OutlinedButton.icon(
                onPressed: _simulateYouStopped,
                icon: const Icon(Icons.emergency_outlined, size: 18),
                label: const Text('Simulate: You Stopped (demo)'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _simulateRiderEmergency,
                icon: const Icon(Icons.warning_amber_rounded, size: 18),
                label: const Text('Simulate: Rider Emergency (demo)'),
              ),
              // Chat + Report an Incident — Community Mode only, per
              // `product/decisions/13-incident-reporting.md`'s "Where it
              // lives" gap. Gated the same way `_leaveParty`'s Leave Party
              // branch already is (`widget.isCommunityRide`), so Active Ride
              // Mode's party menu is provably unchanged: neither real
              // `LiveRideScreen(...)` call site (`party_ready_screen.dart`,
              // `waiting_room_screen.dart`) sets this flag.
              if (widget.isCommunityRide) ...[
                OutlinedButton.icon(
                  onPressed: _openChat,
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Chat'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _openReportIncident,
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  label: const Text('Report an Incident'),
                ),
                const SizedBox(height: 10),
              ],
              if (widget.isOrganiser)
                ElevatedButton.icon(
                  onPressed: _endRide,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
                  icon: const Icon(Icons.stop_circle_outlined, size: 18, color: Colors.white),
                  label: const Text('End Ride', style: TextStyle(color: Colors.white)),
                )
              else
                OutlinedButton.icon(
                  onPressed: _leaveParty,
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade400),
                  icon: Icon(Icons.exit_to_app, size: 18, color: Colors.red.shade400),
                  label: const Text('Leave Party'),
                ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaloColors.bgApp,
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: _fallbackCenter,
                zoom: 14,
              ),
              onMapCreated: (controller) => _mapController = controller,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              markers: _markers,
              polylines: {
                const Polyline(
                  polylineId: PolylineId('route'),
                  points: _routePoints,
                  color: ChaloColors.primary,
                  width: 5,
                  jointType: JointType.round,
                  startCap: Cap.roundCap,
                  endCap: Cap.roundCap,
                ),
              },
            ),
          ),
          // Scrim behind the status bar so its (light) icons stay legible
          // over light map tiles — scoped to this map screen only, not a
          // global status-bar brightness change.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).padding.top,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.45),
                      Colors.black.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _bannerSource != null
                    ? EmergencyStage1Banner(
                        riderName: _bannerRiderName,
                        secondsRemaining: _bannerSecondsRemaining,
                      )
                    : MetallicCard(
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.turn_slight_right,
                                color: ChaloColors.primary,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Continue straight',
                                      style: TextStyle(
                                        color: ChaloColors.textPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                    Text(
                                      '${widget.rideName} · ${_liveRiderIds().length}/${widget.maxRiders} riders',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: ChaloColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: const Icon(
                                  Icons.close,
                                  color: ChaloColors.textSecondary,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 120,
            child: Center(
              child: GestureDetector(
                onTap: _showPartyMenu,
                // Previously just a bare white-on-transparent bar, which was
                // only ever legible against this screen's old flat dark mock
                // background — on the real (light) Google Maps basemap it
                // rendered essentially invisible, leaving the party menu with
                // no discoverable entry point. Wrapped in an opaque pill with
                // a shadow so it reads against any map tile colour, and given
                // real padding so the tap target isn't just a 48x5 sliver.
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: ChaloColors.bgCard,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: Center(
              child: GestureDetector(
                onTapDown: (_) => _onPttDown(),
                onTapUp: (_) => _onPttUp(),
                onTapCancel: _onPttUp,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _transmitting
                        ? ChaloColors.primary
                        : ChaloColors.bgCard,
                    border: Border.all(
                      color: _transmitting
                          ? ChaloColors.primaryGlow
                          : ChaloColors.borderShine,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (_transmitting ? ChaloColors.primary : Colors.black)
                                .withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.mic,
                    color: _transmitting
                        ? Colors.white
                        : ChaloColors.textPrimary,
                    size: 32,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
