// ============================================================================
// REVIEW.SPREAD - CLIENT ENVIRONMENT CONFIGURATION
// For Vercel: values are injected at build time from environment variables
// For local dev: server.py auto-generates this from .env
// ============================================================================

const CONFIG = {
  BRAND_NAME: "TapAurReview",
  BRAND_TAGLINE: "Tap. Review. Spread.",
  BRAND_DOMAIN: window.location.hostname || "reviewspread.in",

  // Business & Payment Configurations
  ADMIN_UPI_ID: "9860624167@ybl",
  ADMIN_PHONE: "919860624167",

  // Direct Customer Order Pricing
  CARD_PRICE: 150,
  SHIPPING_FEE: 120,
  MIN_ORDER_QTY: 5,

  // Reseller Tier Pricing
  PRICING_TIERS: {
    1:  { total: 350,  rate: 350, label: '1 Card — Single (₹350/card = ₹350)' },
    5:  { total: 1350, rate: 270, label: '5 Cards — Starter (₹270/card = ₹1,350)' },
    10: { total: 2400, rate: 240, label: '10 Cards — Pro Pack (₹240/card = ₹2,400)' },
    20: { total: 4400, rate: 220, label: '20 Cards — Growth Pack (₹220/card = ₹4,400)' },
    50: { total: 9500, rate: 190, label: '50 Cards — Agency Pack (₹190/card = ₹9,500)' }
  },

  // Supabase Backend Credentials (Public Anonymous Client Key)
  SUPABASE_URL: "https://foqdsvfquxakqafqzgtd.supabase.co",
  SUPABASE_KEY: "sb_publishable_IobuS4v7R_538rQ6kjZ_uQ_1nrXVGHT"
};

// Global Exposure
window.CONFIG = CONFIG;
if (typeof module !== 'undefined' && module.exports) {
  module.exports = CONFIG;
}
