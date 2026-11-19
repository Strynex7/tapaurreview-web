// ============================================================================
// SUPABASE EDGE FUNCTION: generate-review-link
// ============================================================================
// Takes a Google Maps URL and returns a direct 5-star write-review link

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { url, platform } = await req.json();

    if (!url) {
      return new Response(
        JSON.stringify({ success: false, message: "URL is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    let destination_url = url;

    // Follow redirect if short link (maps.app.goo.gl or goo.gl)
    if (url.includes("goo.gl") || url.includes("maps.app.goo.gl")) {
      try {
        const response = await fetch(url, { redirect: "follow" });
        destination_url = response.url || url;
      } catch (err) {
        console.error("Redirect expansion failed:", err);
      }
    }

    // Check if Place ID or CID is present in expanded URL
    const placeIdMatch = destination_url.match(/place_id[:=]([a-zA-Z0-9_\-]+)/);
    const dataMatch = destination_url.match(/!1s(0x[0-9a-fA-F]+:0x[0-9a-fA-F]+)/);

    if (placeIdMatch && placeIdMatch[1]) {
      destination_url = `https://search.google.com/local/writereview?placeid=${placeIdMatch[1]}`;
    }

    return new Response(
      JSON.stringify({
        success: true,
        destination_url: destination_url,
        platform: platform || "google"
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ success: false, error: err.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
