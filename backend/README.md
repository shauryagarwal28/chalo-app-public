# Chalo — Backend

Node.js API server with PostgreSQL and Redis.

## Stack
- Runtime: Node.js
- Framework: Express
- Database: PostgreSQL
- Cache / real-time: Redis
- WebSocket: ws or Socket.io
- Push notifications: Firebase Admin SDK (FCM)

## Structure
```
backend/
├── src/
│   ├── routes/       — REST API endpoints
│   ├── services/     — business logic
│   ├── models/       — database models
│   ├── websocket/    — real-time location + party state
│   └── middleware/   — auth, validation
└── README.md
```

## Setup (once Node.js is installed)
1. `npm init -y`
2. `npm install express pg redis ws firebase-admin`
