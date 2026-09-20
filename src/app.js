'use strict';

// Composition root: wires middleware + routes into the Express app.
// Layered folders: routes/ (HTTP), services/ (business logic), middleware/ (cross-cutting).
// Exported for tests and for the runtime entry point (server.js).

const express = require('express');
const { requestLogger, notFound, errorHandler } = require('./middleware/http');
const healthRoutes = require('./routes/health');
const syncRoutes = require('./routes/sync');

const app = express();

app.use(express.json());
app.use(requestLogger);

app.use(healthRoutes);
app.use(syncRoutes);

// Terminal middleware: predictable JSON instead of Express HTML dumps.
app.use(notFound);
app.use(errorHandler);

module.exports = app;


