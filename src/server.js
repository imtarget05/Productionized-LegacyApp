'use strict';

// Entry point (runtime only — not required by tests).
// Graceful shutdown so the platform can drain connections on SIGTERM.

const app = require('./app');

const port = process.env.PORT || 3000;

const server = app.listen(port, () => {
    console.log(JSON.stringify({ level: 'info', time: new Date().toISOString(), msg: `listening on ${port}` }));
});

function shutdown(signal) {
    console.log(JSON.stringify({ level: 'info', time: new Date().toISOString(), msg: `received ${signal}, draining` }));
    server.close(() => process.exit(0));
    // Hard stop if something hangs (platform will SIGKILL anyway).
    setTimeout(() => process.exit(1), 10_000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
