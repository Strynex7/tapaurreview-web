# ============================================================================
# REVIEW.SPREAD - LOCAL DEVELOPMENT SERVER WITH SPA ROUTING
# ============================================================================
# Simulates GitHub Pages clean URLs and 404.html NFC dynamic routing

import http.server
import socketserver
import os
import urllib.parse
import mimetypes

# Register .webp MIME type (not in Python's default map)
mimetypes.add_type('image/webp', '.webp')

PORT = 8080
DIRECTORY = os.path.dirname(os.path.abspath(__file__))

def load_env():
    env_path = os.path.join(DIRECTORY, '.env')
    env_vars = {}
    if os.path.isfile(env_path):
        try:
            with open(env_path, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        k, v = line.split('=', 1)
                        env_vars[k.strip()] = v.strip().strip('"').strip("'")
        except Exception:
            pass
    return env_vars

class ReviewSpreadHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def do_GET(self):
        try:
            parsed = urllib.parse.urlparse(self.path)
            path = parsed.path.strip('/')

            # Security: Never serve .env or secret backend files to client
            norm_path = path.lower()
            if (norm_path == '.env' or norm_path.startswith('.env') or '/.env' in norm_path or '\\.env' in norm_path
                or norm_path.startswith('.git') or norm_path.endswith('.sql') or norm_path.endswith('.py')):
                self.send_error(403, "Access Denied: Protected file.")
                return

            # Dynamic Configuration from .env for js/config.js
            if path == 'js/config.js':
                env = load_env()
                supabase_url = env.get('SUPABASE_URL', '')
                supabase_key = env.get('SUPABASE_ANON_KEY', '')
                admin_upi = env.get('ADMIN_UPI_ID', '')
                admin_phone = env.get('ADMIN_PHONE', '')
                brand_name = env.get('BRAND_NAME', 'review.spread')
                brand_domain = env.get('BRAND_DOMAIN', 'reviewspread.in')

                js_content = f"""// AUTO-GENERATED CONFIGURATION FROM .env
const CONFIG = {{
  BRAND_NAME: "{brand_name}",
  BRAND_TAGLINE: "Tap. Review. Spread.",
  BRAND_DOMAIN: window.location.hostname || "{brand_domain}",
  ADMIN_UPI_ID: "{admin_upi}",
  ADMIN_PHONE: "{admin_phone}",
  CARD_PRICE: 150,
  SHIPPING_FEE: 120,
  MIN_ORDER_QTY: 5,
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
if (typeof module !== 'undefined' && module.exports) {{ module.exports = CONFIG; }}
"""
                payload = js_content.encode('utf-8')
                self.send_response(200)
                self.send_header('Content-Type', 'application/javascript; charset=utf-8')
                self.send_header('Content-Length', str(len(payload)))
                self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
                self.end_headers()
                self.wfile.write(payload)
                return

            # Dynamic Vector Logo from .env
            if path == 'assets/reviewspread-logo.svg':
                env = load_env()
                brand_name = env.get('BRAND_NAME', 'review.spread')
                svg_path = os.path.join(DIRECTORY, 'assets', 'reviewspread-logo.svg')
                if os.path.isfile(svg_path):
                    with open(svg_path, 'r', encoding='utf-8') as f:
                        svg_content = f.read()
                    if '.' in brand_name:
                        parts = brand_name.split('.', 1)
                        p1, p2 = parts[0], '.' + parts[1]
                    else:
                        p1, p2 = brand_name, ''
                    import re
                    replacement = f'<text x="66" y="38" font-family="\'Inter\', system-ui, -apple-system, sans-serif" font-size="24" font-weight="800" fill="#FFFFFF" letter-spacing="-0.5px">{p1}<tspan fill="url(#goldGradient)">{p2}</tspan></text>'
                    svg_content = re.sub(r'<text x="66" y="38"[\s\S]*?</text>', replacement, svg_content)
                    payload = svg_content.encode('utf-8')
                    self.send_response(200)
                    self.send_header('Content-Type', 'image/svg+xml')
                    self.send_header('Content-Length', str(len(payload)))
                    self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
                    self.end_headers()
                    self.wfile.write(payload)
                    return

            # 1. Direct file match
            full_path = os.path.join(DIRECTORY, path)
            if os.path.isfile(full_path):
                return super().do_GET()

            # 2. Clean URLs
            if path == 'reseller' and os.path.isfile(os.path.join(DIRECTORY, 'reseller.html')):
                self.path = '/reseller.html'
                return super().do_GET()

            if path == 'activate' and os.path.isfile(os.path.join(DIRECTORY, 'activate.html')):
                self.path = '/activate.html'
                return super().do_GET()

            if path == 'admin' and os.path.isfile(os.path.join(DIRECTORY, 'admin.html')):
                self.path = '/admin.html'
                return super().do_GET()

            # 3. Dynamic NFC Card Tap Routes: /r/1, /r/105, or /{slug}
            if path.startswith('r/') or path.isdigit() or (path and not '.' in path):
                self.path = '/404.html'
                return super().do_GET()

            return super().do_GET()
        except (ConnectionResetError, ConnectionAbortedError, BrokenPipeError):
            pass

    def log_message(self, format, *args):
        # Keep console clean
        try:
            super().log_message(format, *args)
        except Exception:
            pass

class ReusableThreadingServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def handle_error(self, request, client_address):
        # Suppress client disconnect noise
        pass

if __name__ == '__main__':
    os.chdir(DIRECTORY)
    try:
        httpd = ReusableThreadingServer(("", PORT), ReviewSpreadHandler)
    except OSError as e:
        print(f"\n❌ Error: Port {PORT} is already in use by another running server or app.")
        print(f"   To free port {PORT}, close the other terminal or run in PowerShell:")
        print(f"   Stop-Process -Name python -Force\n")
        exit(1)

    with httpd:
        print(f"🚀 review.spread development server running at:")
        print(f"   ► Home:       http://localhost:{PORT}/")
        print(f"   ► Activate:   http://localhost:{PORT}/activate")
        print(f"   ► Reseller:   http://localhost:{PORT}/reseller")
        print(f"   ► Admin:      http://localhost:{PORT}/admin")
        print(f"   ► Card Tap:   http://localhost:{PORT}/r/1")
        print("\nPress Ctrl+C to stop.")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nServer stopped.")
