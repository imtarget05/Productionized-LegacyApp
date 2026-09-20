'use strict';

// Service layer: the legacy inventory sync logic lives here, independent from
// HTTP concerns (routes/middleware) — easy to unit test and to reuse from a cron.
// This is deliberately a no-op simulation of the legacy behaviour.

function syncInventory() {
    return { message: 'Inventory synced successfully' };
}

module.exports = { syncInventory };
