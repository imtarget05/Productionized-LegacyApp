'use strict';

const express = require('express');

// Route layer: HTTP mapping only — no business logic here.
const router = express.Router();

router.get('/health', (req, res) => {
    res.status(200).json({ status: 'healthy', version: '1.0.0' });
});

module.exports = router;
