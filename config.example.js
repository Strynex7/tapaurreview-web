// ============================================================================
// REVIEW.SPREAD - CENTRAL ENVIRONMENT & BRAND CONFIGURATION
// ============================================================================

const CONFIG = {
  // Brand Identity
  BRAND_NAME: "review.spread",
  BRAND_TAGLINE: "Tap. Review. Spread.",
  BRAND_DOMAIN: "reviewspread.in", // change to your domain or localhost

  // Payment Details (P2P UPI Zero-Fee)
  ADMIN_UPI_ID: "yourupi@okhdfcbank", // Your receiving UPI ID (e.g. name@upi)
  ADMIN_PHONE: "919876543210",       // 10/12-digit phone for WhatsApp order confirmations

  // Product Pricing (in INR)
  PRICING: {
    CARD_PRICE: 150,                 // Direct unit price per card
    SHIPPING_FEE: 120,               // Flat shipping fee
    MIN_ORDER_QTY: 5,                // Minimum order quantity on homepage
    RESELLER_TIERS: {
      1:  { total: 350,  rate: 350, label: '1 Card — Single (₹350/card = ₹350)' },
      5:  { total: 1350, rate: 270, label: '5 Cards — Starter (₹270/card = ₹1,350)' },
      10: { total: 2400, rate: 240, label: '10 Cards — Pro Pack (₹240/card = ₹2,400)' },
      20: { total: 4400, rate: 220, label: '20 Cards — Growth Pack (₹220/card = ₹4,400)' },
      50: { total: 9500, rate: 190, label: '50 Cards — Agency Pack (₹190/card = ₹9,500)' }
    }
  },

  // Supabase Backend Credentials
  // Create a free project at https://supabase.com and paste your Project URL & Anon Key here:
  SUPABASE: {
    URL: "https://YOUR_PROJECT_ID.supabase.co",
    ANON_KEY: "YOUR_SUPABASE_ANON_PUBLIC_KEY"
  },

  // Master Admin Portal Default Pass (Can be changed in database)
  DEFAULT_ADMIN_PASSWORD: "admin@reviewspread123"
};

// Export for module environments or window for browsers
if (typeof window !== 'undefined') {
  window.CONFIG = CONFIG;
}
if (typeof module !== 'undefined' && module.exports) {
  module.exports = CONFIG;
}
