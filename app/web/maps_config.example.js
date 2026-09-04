// Copy this file to maps_config.js (gitignored — see .gitignore and the
// Secrets.xcconfig/agora_config.dart pattern this mirrors) and fill in a
// real Google Maps JavaScript API key before running `flutter build web`
// for a deploy that needs working map tiles.
//
// This key is DIFFERENT from the iOS/Android Maps keys in
// ios/Flutter/Secrets.xcconfig and android/local.properties — those are
// "Maps SDK for iOS/Android" keys, this one must have the "Maps JavaScript
// API" enabled instead. Get one at
// https://console.cloud.google.com/google/maps-apis/credentials (same "My
// Maps Project" as the other two keys, per docs/process/build-status.md).
//
// Unlike the iOS/Android keys, a Maps JavaScript API key is inherently
// visible to anyone who opens their browser's network tab or view-source —
// there's no way to ship a web page that uses it without exposing it. The
// security control here is HTTP referrer restriction (Application
// restrictions -> Websites), not secrecy: restrict this key to the exact
// demo domain (e.g. chalo-app-demo.vercel.app/*) before deploying, the same
// way the iOS key is restricted to a bundle ID instead of a domain.
//
// web/index.html loads this file, then only injects the real Google Maps
// <script> tag if this value has actually been filled in — leaving it as
// the placeholder below is safe (no network request, no key exposed) and
// matches how agora_config.dart's empty appId is handled: the map widget's
// screens will render without tiles instead of crashing.
window.GOOGLE_MAPS_WEB_API_KEY = 'YOUR_WEB_MAPS_KEY_HERE';
