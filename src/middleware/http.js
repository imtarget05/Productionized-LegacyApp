'use strict';

// Middleware layer: cross-cutting HTTP concerns (logging, 404, errors).
// Structured single-line JSON so Azure Log Analytics can parse it directly.

function requestLogger(req, res, next) {
    const start = process.hrtime.bigint();
    res.on('finish', () => {
        const durationMs = Number(process.hrtime.bigint() - start) / 1e6;
        console.log(JSON.stringify({
            level: 'info',
            time: new Date().toISOString(),
            msg: 'request',
            method: req.method,
            path: req.path,
            status: res.statusCode,
            durationMs: Number(durationMs.toFixed(1)),
        }));
    });
    next();
}

function notFound(req, res) {
    res.status(404).json({ error: 'not found' });
}

// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, _next) {
    console.error(JSON.stringify({ level: 'error', time: new Date().toISOString(), msg: err.message }));
    res.status(500).json({ error: 'internal error' });
}

module.exports = { requestLogger, notFound, errorHandler };
