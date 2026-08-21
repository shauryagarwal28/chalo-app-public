// Copy this file to agora_config.dart (gitignored) and fill in real values.
//
// appId: Agora Console > your project > App ID.
//
// tempToken: only needed if your Agora project has an App Certificate
// enabled. Generate it in Agora Console for the exact channelName below —
// a temp token is bound to one specific channel and expires after 24h.
// If your project is in testing mode (no App Certificate), leave this
// empty ('') and the app will pass `token: null` to joinChannel.
//
// channelName: must match party_ready_screen.dart's mock party code
// ('RD7K2X') and whatever channel you generated the token for above.
class AgoraConfig {
  static const String appId = 'YOUR_AGORA_APP_ID';
  static const String tempToken = '';
  static const String channelName = 'RD7K2X';
}
