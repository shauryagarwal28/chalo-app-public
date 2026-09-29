# Chalo (working title)

> "Ride Together" - a group riding companion app for India's biking community.

Group rides fall apart mid-route because riders have no safe way to stay connected once they're moving. Phone calls while riding are illegal under the Motor Vehicles Act, and genuinely dangerous even when they're not. Chalo solves this with a private, real-time mode for riding with friends and a verified mode for discovering rides with strangers.

Built solo, end to end: product decisions, all 28 screens, and the app itself.

*Chalo is a working title. A trademark check found an existing registered transport app with the same name, so the app will be renamed before any public release.*

**Live demo**: https://shauryagarwal28.github.io/chalo-app-public/ (runs in the browser with a built-in mock backend, any phone number works; the map and push-to-talk are switched off in the browser version)

## What's actually built

- **All 28 screens** built and wired in Flutter, not just designs. Android first, iOS next
- **Google Maps** working end to end on both platforms - real tiles, routes, live location
- **Push-to-talk (Agora)** really integrated, not mocked, with secure per-ride access tokens issued by the backend. On Android test phones, mic access, audio setup and hold-to-talk all work; the last step, joining the live voice channel, still needs a real-phone test
- **Backend** (Node.js/Express) with phone login, creating and joining parties, a live member list, and live location during rides over WebSockets
- **Incident reporting** during a ride, or afterwards from a Past Rides screen

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
