'use strict';

// Smoke tests for the productionized legacy worker.
// Uses the built-in node:test runner — zero extra dependencies, mirrors the
// "keep legacy deps minimal" principle of this project.

const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');

const app = require('../app');

test('GET /health returns healthy', async () => {
    const server = app.listen(0);
    await new Promise((resolve) => server.once('listening', resolve));
    const port = server.address().port;

    try {
        const body = await fetch(`http://localhost:${port}/health`).then((r) => {
            assert.strictEqual(r.status, 200);
            return r.json();
        });
        assert.strictEqual(body.status, 'healthy');
    } finally {
        server.close();
    }
});

test('POST /sync returns success message', async () => {
    const server = app.listen(0);
    await new Promise((resolve) => server.once('listening', resolve));
    const port = server.address().port;

    try {
        const body = await fetch(`http://localhost:${port}/sync`, { method: 'POST' }).then((r) => {
            assert.strictEqual(r.status, 200);
            return r.json();
        });
        assert.strictEqual(body.message, 'Inventory synced successfully');
    } finally {
        server.close();
    }
});

test('unknown route returns JSON 404', async () => {
    const server = app.listen(0);
    await new Promise((resolve) => server.once('listening', resolve));
    const port = server.address().port;

    try {
        const res = await fetch(`http://localhost:${port}/nope`);
        assert.strictEqual(res.status, 404);
        assert.ok((await res.json()).error);
    } finally {
        server.close();
    }
});
