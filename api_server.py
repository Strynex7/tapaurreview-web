# ============================================================================
# REVIEW.SPREAD - RENDER BACKEND API SERVER
# ============================================================================
# Serves the dynamic config.js endpoint and SVG logo from environment variables
# Deploy this on Render as a Python Web Service

import os
import re
from flask import Flask, Response, request, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app, origins=["*"])  # Allow all origins since frontend is on Vercel

# ── Health Check ──────────────────────────────────────────────────
@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "ok", "service": "review.spread API"})

# ── Supabase Keep-Alive Ping (Prevents Supabase Pausing) ───────────
@app.route('/api/ping-supabase', methods=['GET'])
def ping_supabase():
    supabase_url = os.environ.get('SUPABASE_URL', '')
    supabase_key = os.environ.get('SUPABASE_ANON_KEY', '')

    if not supabase_url or not supabase_key:
        return jsonify({
            "status": "error",
            "message": "SUPABASE_URL or SUPABASE_ANON_KEY environment variable is not configured."
        }), 500

    try:
        import urllib.request
        req = urllib.request.Request(
            f"{supabase_url}/rest/v1/clients?select=id&limit=1",
            headers={
                "apikey": supabase_key,
                "Authorization": f"Bearer {supabase_key}",
                "User-Agent": "TapAurReview-KeepAlive/1.0"
            }
        )
        with urllib.request.urlopen(req, timeout=10) as response:
            return jsonify({
                "status": "ok",
                "supabase_http_code": response.status,
                "message": "Supabase pinged successfully. Database is active!"
            })
    except Exception as e:
        return jsonify({
            "status": "error",
            "error": str(e),
            "message": "Attempted ping to Supabase."
        }), 500

# ── Dynamic Config.js from Environment Variables ──────────────────
@app.route('/api/config.js', methods=['GET'])
def config_js():
    brand_name = os.environ.get('BRAND_NAME', 'TapAurReview')
    brand_domain = os.environ.get('BRAND_DOMAIN', 'reviewspread.in')
    admin_upi = os.environ.get('ADMIN_UPI_ID', '')
    admin_phone = os.environ.get('ADMIN_PHONE', '')
    supabase_url = os.environ.get('SUPABASE_URL', '')
    supabase_key = os.environ.get('SUPABASE_ANON_KEY', '')
    card_price = os.environ.get('CARD_PRICE', '150')
    shipping_fee = os.environ.get('SHIPPING_FEE', '120')
    min_order_qty = os.environ.get('MIN_ORDER_QTY', '5')

    js_content = f"""// AUTO-GENERATED CONFIGURATION FROM SERVER
const CONFIG = {{
  BRAND_NAME: "{brand_name}",
  BRAND_TAGLINE: "Tap. Review. Spread.",
  BRAND_DOMAIN: window.location.hostname || "{brand_domain}",
  ADMIN_UPI_ID: "{admin_upi}",
  ADMIN_PHONE: "{admin_phone}",
  CARD_PRICE: {card_price},
  SHIPPING_FEE: {shipping_fee},
  MIN_ORDER_QTY: {min_order_qty},
  PRICING_TIERS: {{
    1:  {{ total: 350,  rate: 350, label: '1 Card — Single (₹350/card = ₹350)' }},
    5:  {{ total: 1350, rate: 270, label: '5 Cards — Starter (₹270/card = ₹1,350)' }},
    10: {{ total: 2400, rate: 240, label: '10 Cards — Pro Pack (₹240/card = ₹2,400)' }},
    20: {{ total: 4400, rate: 220, label: '20 Cards — Growth Pack (₹220/card = ₹4,400)' }},
    50: {{ total: 9500, rate: 190, label: '50 Cards — Agency Pack (₹190/card = ₹9,500)' }}
  }},
  SUPABASE_URL: "{supabase_url}",
  SUPABASE_KEY: "{supabase_key}"
}};
window.CONFIG = CONFIG;
"""

    return Response(
        js_content,
        mimetype='application/javascript',
        headers={
            'Cache-Control': 'no-cache, no-store, must-revalidate',
            'Access-Control-Allow-Origin': '*'
        }
    )

# ── Dynamic SVG Logo ──────────────────────────────────────────────
@app.route('/api/logo.svg', methods=['GET'])
def logo_svg():
    brand_name = os.environ.get('BRAND_NAME', 'review.spread')
    svg_path = os.path.join(os.path.dirname(__file__), 'assets', 'reviewspread-logo.svg')

    if not os.path.isfile(svg_path):
        return Response("Logo not found", status=404)

    with open(svg_path, 'r', encoding='utf-8') as f:
        svg_content = f.read()

    if '.' in brand_name:
        parts = brand_name.split('.', 1)
        p1, p2 = parts[0], '.' + parts[1]
    else:
        p1, p2 = brand_name, ''

    replacement = f'<text x="66" y="38" font-family="\'Inter\', system-ui, -apple-system, sans-serif" font-size="24" font-weight="800" fill="#FFFFFF" letter-spacing="-0.5px">{p1}<tspan fill="url(#goldGradient)">{p2}</tspan></text>'
    svg_content = re.sub(r'<text x="66" y="38"[\s\S]*?</text>', replacement, svg_content)

    return Response(
        svg_content,
        mimetype='image/svg+xml',
        headers={
            'Cache-Control': 'no-cache, no-store, must-revalidate',
            'Access-Control-Allow-Origin': '*'
        }
    )


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 10000))
    app.run(host='0.0.0.0', port=port, debug=False)
