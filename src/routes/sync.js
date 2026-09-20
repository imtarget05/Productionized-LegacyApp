'use strict';

const express = require('express');
const { syncInventory } = require('../services/inventoryService');

// Route layer: delegates all work to the service layer.
const router = express.Router();

router.post('/sync', (req, res) => {
    res.status(200).json(syncInventory(req.body));
});

module.exports = router;
