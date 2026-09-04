# Chalo (working title)

> "Ride Together" - a group riding companion app for India's biking community.

Group rides fall apart mid-route because riders have no safe way to stay connected once they're moving. Phone calls while riding are illegal under the Motor Vehicles Act, and genuinely dangerous even when they're not. Chalo solves this with a private, real-time mode for riding with friends and a verified mode for discovering rides with strangers.

Built solo, end to end: product decisions, all 27 screens, and the app itself.

**Live demo**: https://shauryagarwal28.github.io/chalo-app-public/

## What's actually built

- **All 27 screens** built and wired in Flutter, for iOS and Android, not just designs
- **Google Maps** working end to end on both platforms - real tiles, routes, live location
- **Push-to-talk (Agora)** really integrated into the live ride screen, not mocked. Audio itself still needs a physical phone to verify, since simulators can't run real-time audio
- **Backend** (Node.js/Express) with real-time party updates and live location tracking in progress

Full write-up, screenshots, and an honest status breakdown: [read the case study](https://shauryagarwal28.github.io/chalo-case-study.html)

## Two modes

- **Active Ride Mode** - a private group of friends riding together right now. No sign-up friction. Live map, one-button push-to-talk, automatic emergency detection if someone stops suddenly.
- **Community Mode** - discover public rides organised by verified strangers. Gated behind KYC and a mutual rating system, since this side needs trust that Active Ride Mode doesn't.

## Repo layout

```
app/      Flutter client (Android + iOS)
backend/  Node.js/Express API - real-time party and location features
```

This is a code snapshot, refreshed from the working repo. It won't run without your own Google Maps and Agora accounts (see `app/README.md` for setup), but it's real, current code.

## Stack

Flutter · Node.js/Express · Google Maps SDK · Agora (push-to-talk)

## Author

Shaurya Agarwal - [portfolio](https://shauryagarwal28.github.io) · [LinkedIn](https://www.linkedin.com/in/shauryaagarwal28/)
