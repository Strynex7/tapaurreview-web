# 🚀 review.spread — Tap. Review. Spread.

Complete contactless NFC Smart Review Card system cloned, re-architected, and re-branded to **review.spread**.

---

## 📁 Project Structure

```
review/
├── index.html            # Main Landing Page + Direct UPI Order Funnel + Live Leaderboard
├── activate.html         # Card Onboarding & Google Maps Review Link Setup Portal
├── reseller.html         # B2B Reseller & Agency Partner Portal (Bulk Pricing & Batches)
├── admin.html            # Master Back-Office Admin Panel
├── 404.html              # Smart Dynamic NFC Tap Router (/r/:code & /:slug Micro-Landing Page)
├── schema.sql            # Complete PostgreSQL Schema & 17 Stored Procedures for Supabase
├── server.py             # Local development server with SPA routing & clean URLs
├── config.example.js     # Central configuration template
├── .env.example          # Environment variables reference
├── css/
│   └── styles.css        # Responsive dark-gold glassmorphism styling
├── js/
│   ├── config.js         # Active client configuration (Supabase & Brand variables)
│   └── app.js            # Frontend interactivity, platform counters, accordion & scroll
├── assets/
│   ├── reviewspread-logo.svg # Vector SVG Logo for review.spread
│   ├── favicon.svg       # Browser tab icon
│   ├── black_card.jpg    # Matte Black NFC Smart Card Visual
│   └── white_card.jpg    # Minimalist White NFC Smart Card Visual
└── supabase/
    └── functions/
        └── generate-review-link/
            └── index.ts  # Edge Function for resolving Google Maps place review URLs
```

---

## ⚙️ Quick Start (Local Testing)

1. Make sure your Python 3 environment is available.
2. Run the local development server:
   ```bash
   python server.py
   ```
3. Open your browser:
   * **Homepage**: [http://localhost:8080/](http://localhost:8080/)
   * **Card Activation**: [http://localhost:8080/activate](http://localhost:8080/activate)
   * **Reseller Portal**: [http://localhost:8080/reseller](http://localhost:8080/reseller)
   * **Admin Panel**: [http://localhost:8080/admin](http://localhost:8080/admin) (Default pass: `admin@reviewspread123`)
   * **Simulated NFC Card Tap**: [http://localhost:8080/r/1](http://localhost:8080/r/1)

---

## 🌐 Production Deployment (GitHub Pages)

1. Push this folder's contents to a GitHub repository (e.g. `yourusername/review-spread`).
2. Go to **Repository Settings** > **Pages**.
3. Under **Branch**, select `main` (root) and click **Save**.
4. That's it! GitHub Pages automatically serves `404.html` for any dynamic NFC tap link (`/r/{cardCode}`), which handles client-side routing, tap analytics, and micro-landing page display.

---

## 🔐 Credentials & Config Management

All client-side configuration is managed in **[js/config.js](js/config.js)**:
* `SUPABASE_URL`: Your Supabase project URL (`https://foqdsvfquxakqafqzgtd.supabase.co`).
* `SUPABASE_KEY`: Your Supabase publishable anonymous key.
* `ADMIN_UPI_ID`: Your receiving UPI VPA (`7620952720@ybl`).
* `ADMIN_PHONE`: Your WhatsApp contact number (`917620952720`).
* `PRICING_TIERS`: Bulk reseller pack rates and single card rates.

---

## 💡 Key Features Replicated

1. **Zero-Fee UPI Checkout**: Dynamic QR code generation via UPI deep-linking without Razorpay/gateway transaction fees.
2. **Dynamic Tap Router**: `404.html` reads the card code from the URL path, increments the tap counter in Supabase, and displays the business review link.
3. **Secret Triple-Tap Backdoor**: Quick 3 taps on the business name heading in `404.html` allows the owner/reseller to quickly open the card settings at `/activate`.
4. **B2B Reseller Portal**: Self-registration, tiered pricing, batch card inventory management, and quick activation triggers.
5. **Master Admin Back-Office**: Manage reseller approvals, batch assignments, card transfers, and orders fulfillment.
