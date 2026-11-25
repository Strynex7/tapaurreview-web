-- ============================================================================
-- REVIEW.SPREAD - COMPLETE DATABASE SCHEMA & STORED PROCEDURES (SUPABASE / POSTGRES)
-- ============================================================================

-- Enable pgcrypto for UUID and cryptographic functions if needed
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ----------------------------------------------------------------------------
-- 1. TABLES DEFINITION
-- ----------------------------------------------------------------------------

-- Table: admin_config (Master Admin credentials)
-- Note: Replace 'CHANGE_ME_IN_PRODUCTION' with your secure master password before deploying
CREATE TABLE IF NOT EXISTS public.admin_config (
    id SERIAL PRIMARY KEY,
    admin_password TEXT NOT NULL DEFAULT 'CHANGE_ME_IN_PRODUCTION',
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

INSERT INTO public.admin_config (admin_password) 
SELECT 'CHANGE_ME_IN_PRODUCTION' 
WHERE NOT EXISTS (SELECT 1 FROM public.admin_config);

-- Table: resellers (Partners & Bulk Buyers)
CREATE TABLE IF NOT EXISTS public.resellers (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    phone TEXT UNIQUE NOT NULL,
    pin TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'approved', -- 'pending', 'approved', 'rejected'
    verification_code TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Table: batches (Allocated card ranges to resellers)
CREATE TABLE IF NOT EXISTS public.batches (
    id SERIAL PRIMARY KEY,
    reseller_name TEXT NOT NULL REFERENCES public.resellers(name) ON DELETE CASCADE,
    range_start INTEGER NOT NULL,
    range_end INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Table: clients (Physical Cards, Business links, Taps & Analytics)
CREATE TABLE IF NOT EXISTS public.clients (
    id SERIAL PRIMARY KEY,
    card_code INTEGER UNIQUE NOT NULL,
    slug TEXT UNIQUE,
    business_name TEXT,
    city_location TEXT,
    category TEXT DEFAULT 'Other',
    destination_url TEXT,
    whatsapp_url TEXT,
    whatsapp_group_url TEXT,
    instagram_url TEXT,
    facebook_url TEXT,
    website_url TEXT,
    logo_url TEXT,
    source_url TEXT,
    platform TEXT DEFAULT 'google',
    status TEXT NOT NULL DEFAULT 'unregistered', -- 'unregistered', 'active'
    reseller_name TEXT,
    owner_pin TEXT,
    taps_count INTEGER DEFAULT 0 NOT NULL,
    monthly_taps_count INTEGER DEFAULT 0 NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Schema Migrations for existing deployments:
ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS whatsapp_group_url TEXT;
ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS facebook_url TEXT;
ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS website_url TEXT;
ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS logo_url TEXT;

-- Table: orders (Direct Customer Orders & Reseller Bulk Orders)
CREATE TABLE IF NOT EXISTS public.orders (
    id SERIAL PRIMARY KEY,
    order_type TEXT DEFAULT 'direct', -- 'direct', 'reseller'
    customer_name TEXT NOT NULL,
    phone TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    total_amount NUMERIC(10, 2) NOT NULL,
    shipping_address TEXT,
    status TEXT DEFAULT 'pending', -- 'pending', 'fulfilled', 'cancelled'
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Table: registrations (Audit log for card bindings)
CREATE TABLE IF NOT EXISTS public.registrations (
    id SERIAL PRIMARY KEY,
    card_code INTEGER NOT NULL,
    business_name TEXT,
    action TEXT NOT NULL, -- 'register', 'deregister'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- ----------------------------------------------------------------------------
-- 2. PUBLIC & CORE CLIENT RPCS
-- ----------------------------------------------------------------------------

-- RPC: get_card_details (Used by 404.html when customer taps card)
CREATE OR REPLACE FUNCTION public.get_card_details(p_code INTEGER)
RETURNS JSON AS $$
DECLARE
    v_card RECORD;
    v_is_allotted BOOLEAN;
BEGIN
    -- 1. Check card in clients table
    SELECT * INTO v_card FROM public.clients WHERE card_code = p_code LIMIT 1;

    -- 2. If card is active or has business links configured -> Return immediately for direct display (NO PASSWORD)
    IF v_card IS NOT NULL AND (
        LOWER(TRIM(COALESCE(v_card.status, ''))) = 'active' OR
        NULLIF(TRIM(COALESCE(v_card.destination_url, '')), '') IS NOT NULL OR
        NULLIF(TRIM(COALESCE(v_card.whatsapp_url, '')), '') IS NOT NULL OR
        NULLIF(TRIM(COALESCE(v_card.instagram_url, '')), '') IS NOT NULL OR
        NULLIF(TRIM(COALESCE(v_card.whatsapp_group_url, '')), '') IS NOT NULL OR
        NULLIF(TRIM(COALESCE(v_card.facebook_url, '')), '') IS NOT NULL OR
        NULLIF(TRIM(COALESCE(v_card.website_url, '')), '') IS NOT NULL OR
        NULLIF(TRIM(COALESCE(v_card.logo_url, '')), '') IS NOT NULL
    ) THEN
        RETURN json_build_object(
            'status', 'active',
            'card_code', v_card.card_code,
            'business_name', COALESCE(v_card.business_name, ''),
            'city_location', COALESCE(v_card.city_location, ''),
            'category', COALESCE(v_card.category, 'Other'),
            'destination_url', COALESCE(v_card.destination_url, ''),
            'whatsapp_url', COALESCE(v_card.whatsapp_url, ''),
            'whatsapp_group_url', COALESCE(v_card.whatsapp_group_url, ''),
            'instagram_url', COALESCE(v_card.instagram_url, ''),
            'facebook_url', COALESCE(v_card.facebook_url, ''),
            'website_url', COALESCE(v_card.website_url, ''),
            'logo_url', COALESCE(v_card.logo_url, '')
        );
    END IF;

    -- 3. If not active, check if card is allotted in batches or clients
    SELECT EXISTS (
        SELECT 1 FROM public.batches WHERE p_code BETWEEN range_start AND range_end
        UNION
        SELECT 1 FROM public.clients WHERE card_code = p_code AND reseller_name IS NOT NULL AND length(trim(reseller_name)) > 0
    ) INTO v_is_allotted;

    IF v_is_allotted THEN
        RETURN json_build_object(
            'status', 'unregistered',
            'card_code', p_code
        );
    ELSE
        RETURN json_build_object(
            'status', 'unallotted',
            'card_code', p_code
        );
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: increment_tap (Logs tap analytics on physical card tap)
CREATE OR REPLACE FUNCTION public.increment_tap(client_slug TEXT, client_platform TEXT DEFAULT 'google')
RETURNS JSON AS $$
DECLARE
    v_code INTEGER;
BEGIN
    IF client_slug LIKE 'card-%' THEN
        v_code := substring(client_slug from 6)::INTEGER;
        UPDATE public.clients
        SET taps_count = taps_count + 1,
            monthly_taps_count = monthly_taps_count + 1,
            updated_at = timezone('utc'::text, now())
        WHERE card_code = v_code;
    ELSE
        UPDATE public.clients
        SET taps_count = taps_count + 1,
            monthly_taps_count = monthly_taps_count + 1,
            updated_at = timezone('utc'::text, now())
        WHERE slug = client_slug;
    END IF;

    RETURN json_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: get_platform_stats (Used on homepage hero counter)
CREATE OR REPLACE FUNCTION public.get_platform_stats(req_platform TEXT DEFAULT 'google')
RETURNS JSON AS $$
DECLARE
    v_total_taps INTEGER;
    v_total_biz INTEGER;
BEGIN
    SELECT COALESCE(SUM(taps_count), 0) INTO v_total_taps FROM public.clients;
    SELECT COUNT(*) INTO v_total_biz FROM public.clients WHERE status = 'active';

    RETURN json_build_object(
        'total_taps', v_total_taps,
        'businesses_onboarded', v_total_biz
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: get_monthly_leaderboard (Used on homepage leaderboard)
CREATE OR REPLACE FUNCTION public.get_monthly_leaderboard(
    req_platform TEXT DEFAULT 'google',
    req_category TEXT DEFAULT 'All'
)
RETURNS JSON AS $$
DECLARE
    v_result JSON;
BEGIN
    IF req_category IS NULL OR req_category = 'All' OR req_category = '' THEN
        SELECT json_agg(t) INTO v_result FROM (
            SELECT business_name, city_location, category, monthly_taps_count
            FROM public.clients
            WHERE status = 'active' AND business_name IS NOT NULL
            ORDER BY monthly_taps_count DESC
            LIMIT 25
        ) t;
    ELSE
        SELECT json_agg(t) INTO v_result FROM (
            SELECT business_name, city_location, category, monthly_taps_count
            FROM public.clients
            WHERE status = 'active' 
              AND business_name IS NOT NULL
              AND (
                  category = req_category
                  OR (req_category IN ('Cafes & Restaurants', 'Restaurant & Cafe') AND category IN ('Cafes & Restaurants', 'Restaurant & Cafe'))
                  OR (req_category IN ('Salons & Spas', 'Salon & Spa') AND category IN ('Salons & Spas', 'Salon & Spa'))
                  OR (req_category IN ('Clinics & Healthcare', 'Healthcare & Clinic') AND category IN ('Clinics & Healthcare', 'Healthcare & Clinic'))
                  OR (req_category IN ('Retail Stores', 'Retail & Shopping') AND category IN ('Retail Stores', 'Retail & Shopping'))
                  OR (req_category IN ('Fitness & Gyms', 'Fitness & Gym') AND category IN ('Fitness & Gyms', 'Fitness & Gym'))
                  OR (LOWER(category) LIKE '%' || LOWER(req_category) || '%')
                  OR (LOWER(req_category) LIKE '%' || LOWER(category) || '%')
              )
            ORDER BY monthly_taps_count DESC
            LIMIT 25
        ) t;
    END IF;

    RETURN COALESCE(v_result, '[]'::json);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ----------------------------------------------------------------------------
-- 3. DIRECT CUSTOMER ORDERS RPCS (Homepage)
-- ----------------------------------------------------------------------------

-- RPC: check_reseller_phone
CREATE OR REPLACE FUNCTION public.check_reseller_phone(p_phone TEXT)
RETURNS JSON AS $$
DECLARE
    v_exists BOOLEAN;
    v_name TEXT;
BEGIN
    SELECT true, name INTO v_exists, v_name FROM public.resellers WHERE phone = p_phone LIMIT 1;
    IF v_exists THEN
        RETURN json_build_object('exists', true, 'type', 'reseller', 'name', v_name);
    END IF;

    -- Also check existing client order
    SELECT true, customer_name INTO v_exists, v_name FROM public.orders WHERE phone = p_phone LIMIT 1;
    IF v_exists THEN
        RETURN json_build_object('exists', true, 'type', 'customer', 'name', v_name);
    END IF;

    RETURN json_build_object('exists', false);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: place_direct_order
CREATE OR REPLACE FUNCTION public.place_direct_order(
    p_is_existing BOOLEAN,
    p_name TEXT,
    p_phone TEXT,
    p_pin TEXT,
    p_quantity INTEGER,
    p_notes TEXT,
    p_total_amount NUMERIC
)
RETURNS JSON AS $$
DECLARE
    v_order_id INTEGER;
BEGIN
    INSERT INTO public.orders (order_type, customer_name, phone, quantity, total_amount, shipping_address, notes)
    VALUES ('direct', p_name, p_phone, p_quantity, p_total_amount, p_notes, p_notes)
    RETURNING id INTO v_order_id;

    -- If new customer, auto create customer record with PIN for later card activation
    IF NOT p_is_existing AND p_pin IS NOT NULL AND length(trim(p_pin)) > 0 THEN
        INSERT INTO public.resellers (name, phone, pin, status)
        VALUES (p_name, p_phone, p_pin, 'approved')
        ON CONFLICT (phone) DO UPDATE SET pin = EXCLUDED.pin;
    END IF;

    RETURN json_build_object(
        'success', true,
        'order_id', v_order_id,
        'message', 'Order placed successfully!'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ----------------------------------------------------------------------------
-- 4. CARD ACTIVATION & MANAGEMENT RPCS (/activate)
-- ----------------------------------------------------------------------------

-- RPC: verify_and_get_card
CREATE OR REPLACE FUNCTION public.verify_and_get_card(p_code INTEGER, p_password TEXT)
RETURNS JSON AS $$
DECLARE
    v_card RECORD;
    v_reseller_name TEXT;
    v_reseller RECORD;
BEGIN
    -- 1. Check if card exists in clients table
    SELECT * INTO v_card FROM public.clients WHERE card_code = p_code LIMIT 1;

    -- 2. Determine which reseller owns/is allotted this card:
    IF v_card IS NOT NULL AND v_card.reseller_name IS NOT NULL AND length(trim(v_card.reseller_name)) > 0 THEN
        v_reseller_name := trim(v_card.reseller_name);
    ELSE
        -- Check if card falls inside an allotted batch range in public.batches
        SELECT reseller_name INTO v_reseller_name 
        FROM public.batches 
        WHERE p_code BETWEEN range_start AND range_end 
        ORDER BY id DESC LIMIT 1;
    END IF;

    -- 3. If card is neither in clients with reseller_name NOR in any assigned batch:
    -- IT HAS NOT BEEN ALLOTTED BY ADMIN! Access Denied!
    IF v_reseller_name IS NULL OR length(trim(v_reseller_name)) = 0 THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Card #' || p_code || ' has not been allotted by admin. Access denied.'
        );
    END IF;

    -- 4. Find the specific allotted reseller in public.resellers
    SELECT * INTO v_reseller FROM public.resellers WHERE name = v_reseller_name LIMIT 1;
    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Allotted partner record for Card #' || p_code || ' not found.'
        );
    END IF;

    -- 5. Strict PIN check: Must match the allotted reseller's PIN (or owner_pin if card was previously set)
    IF TRIM(v_reseller.pin) <> TRIM(p_password) AND (v_card IS NULL OR TRIM(COALESCE(v_card.owner_pin, '')) <> TRIM(p_password)) THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Invalid PIN for Card #' || p_code || '. Please enter the correct partner security PIN.'
        );
    END IF;

    -- 6. Card is valid and PIN matches!
    -- If card row doesn't exist in clients table yet, it's a fresh unregistered card in the reseller's batch!
    IF v_card IS NULL THEN
        RETURN json_build_object(
            'success', true,
            'status', 'unregistered',
            'card_code', p_code,
            'reseller_name', v_reseller_name,
            'business_name', '',
            'city_location', '',
            'category', 'Other',
            'destination_url', '',
            'whatsapp_url', '',
            'whatsapp_group_url', '',
            'instagram_url', '',
            'facebook_url', '',
            'website_url', '',
            'logo_url', ''
        );
    END IF;

    -- If card exists in clients table, return its saved data:
    RETURN json_build_object(
        'success', true,
        'status', v_card.status,
        'card_code', v_card.card_code,
        'reseller_name', v_reseller_name,
        'business_name', COALESCE(v_card.business_name, ''),
        'city_location', COALESCE(v_card.city_location, ''),
        'category', COALESCE(v_card.category, 'Other'),
        'destination_url', COALESCE(v_card.destination_url, ''),
        'whatsapp_url', COALESCE(v_card.whatsapp_url, ''),
        'whatsapp_group_url', COALESCE(v_card.whatsapp_group_url, ''),
        'instagram_url', COALESCE(v_card.instagram_url, ''),
        'facebook_url', COALESCE(v_card.facebook_url, ''),
        'website_url', COALESCE(v_card.website_url, ''),
        'logo_url', COALESCE(v_card.logo_url, '')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: register_card
DROP FUNCTION IF EXISTS public.register_card(INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.register_card(INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.register_card(INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.register_card(
    p_code INTEGER,
    p_password TEXT,
    p_business_name TEXT,
    p_destination_url TEXT,
    p_category TEXT,
    p_mode TEXT,
    p_source_url TEXT,
    p_city_location TEXT,
    p_whatsapp_url TEXT,
    p_instagram_url TEXT,
    p_whatsapp_group_url TEXT DEFAULT NULL,
    p_facebook_url TEXT DEFAULT NULL,
    p_website_url TEXT DEFAULT NULL,
    p_logo_url TEXT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    v_card RECORD;
    v_reseller_name TEXT;
    v_reseller RECORD;
BEGIN
    -- 1. Check if card exists in clients table
    SELECT * INTO v_card FROM public.clients WHERE card_code = p_code LIMIT 1;

    -- 2. Determine allotted reseller
    IF v_card IS NOT NULL AND v_card.reseller_name IS NOT NULL AND length(trim(v_card.reseller_name)) > 0 THEN
        v_reseller_name := trim(v_card.reseller_name);
    ELSE
        SELECT reseller_name INTO v_reseller_name 
        FROM public.batches 
        WHERE p_code BETWEEN range_start AND range_end 
        ORDER BY id DESC LIMIT 1;
    END IF;

    -- 3. If not allotted, reject
    IF v_reseller_name IS NULL OR length(trim(v_reseller_name)) = 0 THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Cannot register: Card #' || p_code || ' has not been allotted by admin.'
        );
    END IF;

    -- 4. Verify reseller and PIN match
    SELECT * INTO v_reseller FROM public.resellers WHERE name = v_reseller_name LIMIT 1;
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'message', 'Allotted partner record not found.');
    END IF;

    IF TRIM(v_reseller.pin) <> TRIM(p_password) AND (v_card IS NULL OR TRIM(COALESCE(v_card.owner_pin, '')) <> TRIM(p_password)) THEN
        RETURN json_build_object('success', false, 'message', 'Unauthorized: Invalid PIN for Card #' || p_code);
    END IF;

    -- 5. Upsert into public.clients (preserving reseller_name)
    INSERT INTO public.clients (
        card_code, reseller_name, business_name, destination_url, category,
        status, source_url, city_location, whatsapp_url, whatsapp_group_url, instagram_url,
        facebook_url, website_url, logo_url,
        owner_pin, platform, updated_at
    )
    VALUES (
        p_code, v_reseller_name, p_business_name, p_destination_url, p_category,
        'active', p_source_url, p_city_location, p_whatsapp_url, p_whatsapp_group_url, p_instagram_url,
        p_facebook_url, p_website_url, p_logo_url,
        p_password, 'google', timezone('utc'::text, now())
    )
    ON CONFLICT (card_code) DO UPDATE SET
        reseller_name = v_reseller_name,
        business_name = EXCLUDED.business_name,
        destination_url = EXCLUDED.destination_url,
        category = EXCLUDED.category,
        status = 'active',
        source_url = EXCLUDED.source_url,
        city_location = EXCLUDED.city_location,
        whatsapp_url = EXCLUDED.whatsapp_url,
        whatsapp_group_url = EXCLUDED.whatsapp_group_url,
        instagram_url = EXCLUDED.instagram_url,
        facebook_url = EXCLUDED.facebook_url,
        website_url = EXCLUDED.website_url,
        logo_url = EXCLUDED.logo_url,
        owner_pin = EXCLUDED.owner_pin,
        platform = 'google',
        updated_at = timezone('utc'::text, now());

    INSERT INTO public.registrations (card_code, business_name, action)
    VALUES (p_code, p_business_name, 'register');

    RETURN json_build_object('success', true, 'message', 'Card #' || p_code || ' registered successfully!');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: deregister_card
CREATE OR REPLACE FUNCTION public.deregister_card(p_code INTEGER, p_password TEXT)
RETURNS JSON AS $$
DECLARE
    v_card RECORD;
    v_reseller_name TEXT;
    v_reseller RECORD;
BEGIN
    -- 1. Check if card exists in clients table
    SELECT * INTO v_card FROM public.clients WHERE card_code = p_code LIMIT 1;

    -- 2. Determine allotted reseller
    IF v_card IS NOT NULL AND v_card.reseller_name IS NOT NULL AND length(trim(v_card.reseller_name)) > 0 THEN
        v_reseller_name := trim(v_card.reseller_name);
    ELSE
        SELECT reseller_name INTO v_reseller_name 
        FROM public.batches 
        WHERE p_code BETWEEN range_start AND range_end 
        ORDER BY id DESC LIMIT 1;
    END IF;

    -- 3. If not allotted, reject
    IF v_reseller_name IS NULL OR length(trim(v_reseller_name)) = 0 THEN
        RETURN json_build_object('success', false, 'message', 'Card #' || p_code || ' is not allotted.');
    END IF;

    -- 4. Verify reseller and PIN match
    SELECT * INTO v_reseller FROM public.resellers WHERE name = v_reseller_name LIMIT 1;
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'message', 'Allotted reseller not found.');
    END IF;

    IF TRIM(v_reseller.pin) <> TRIM(p_password) AND (v_card IS NULL OR TRIM(COALESCE(v_card.owner_pin, '')) <> TRIM(p_password)) THEN
        RETURN json_build_object('success', false, 'message', 'Unauthorized: Invalid PIN for Card #' || p_code);
    END IF;

    -- 5. Wipe card back to unregistered (keeps reseller_name intact for re-assignment)
    UPDATE public.clients
    SET status = 'unregistered',
        business_name = NULL,
        destination_url = NULL,
        whatsapp_url = NULL,
        whatsapp_group_url = NULL,
        instagram_url = NULL,
        facebook_url = NULL,
        website_url = NULL,
        logo_url = NULL,
        source_url = NULL,
        city_location = NULL,
        owner_pin = NULL,
        updated_at = timezone('utc'::text, now())
    WHERE card_code = p_code;

    INSERT INTO public.registrations (card_code, business_name, action)
    VALUES (p_code, 'Reset to Available', 'deregister');

    RETURN json_build_object('success', true, 'message', 'Card #' || p_code || ' wiped and reset to available.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ----------------------------------------------------------------------------
-- 5. RESELLER PORTAL RPCS (/reseller)
-- ----------------------------------------------------------------------------

-- RPC: self_register_reseller
CREATE OR REPLACE FUNCTION public.self_register_reseller(
    p_name TEXT,
    p_phone TEXT,
    p_pin TEXT,
    p_code TEXT
)
RETURNS JSON AS $$
BEGIN
    INSERT INTO public.resellers (name, phone, pin, verification_code, status)
    VALUES (p_name, p_phone, p_pin, p_code, 'approved');

    RETURN json_build_object('success', true, 'message', 'Reseller registered successfully!');
EXCEPTION WHEN unique_violation THEN
    RETURN json_build_object('success', false, 'message', 'Phone or name already registered.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: reseller_get_portal
CREATE OR REPLACE FUNCTION public.reseller_get_portal(p_identifier TEXT, p_password TEXT)
RETURNS JSON AS $$
DECLARE
    v_reseller RECORD;
    v_batches JSON;
    v_orders JSON;
BEGIN
    SELECT * INTO v_reseller FROM public.resellers 
    WHERE (phone = p_identifier OR name = p_identifier) AND pin = p_password
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'message', 'Invalid reseller credentials.');
    END IF;

    SELECT COALESCE(json_agg(b), '[]'::json) INTO v_batches 
    FROM (SELECT id, reseller_name, range_start, range_end, created_at FROM public.batches WHERE reseller_name = v_reseller.name) b;

    SELECT COALESCE(json_agg(o), '[]'::json) INTO v_orders 
    FROM (SELECT id, customer_name, quantity, total_amount, status, created_at FROM public.orders WHERE customer_name = v_reseller.name OR phone = v_reseller.phone ORDER BY id DESC) o;

    RETURN json_build_object(
        'success', true,
        'reseller_name', v_reseller.name,
        'reseller', json_build_object('name', v_reseller.name, 'phone', v_reseller.phone, 'status', v_reseller.status),
        'batches', v_batches,
        'orders', v_orders
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: reseller_create_order
CREATE OR REPLACE FUNCTION public.reseller_create_order(
    p_reseller_name TEXT,
    p_password TEXT,
    p_card_quantity INTEGER,
    p_notes TEXT,
    p_total_amount NUMERIC
)
RETURNS JSON AS $$
DECLARE
    v_reseller RECORD;
BEGIN
    SELECT * INTO v_reseller FROM public.resellers WHERE name = p_reseller_name AND pin = p_password;
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'message', 'Authentication failed.');
    END IF;

    INSERT INTO public.orders (order_type, customer_name, phone, quantity, total_amount, notes, status)
    VALUES ('reseller', v_reseller.name, v_reseller.phone, p_card_quantity, p_total_amount, p_notes, 'pending');

    RETURN json_build_object('success', true, 'message', 'Reseller order placed successfully!');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ----------------------------------------------------------------------------
-- 6. ADMIN BACK-OFFICE RPCS (/admin)
-- ----------------------------------------------------------------------------

-- Helper: verify admin password
CREATE OR REPLACE FUNCTION public.check_admin_pass(p_password TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    v_valid BOOLEAN;
BEGIN
    SELECT (admin_password = p_password) INTO v_valid FROM public.admin_config LIMIT 1;
    RETURN COALESCE(v_valid, false);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: admin_get_overview
CREATE OR REPLACE FUNCTION public.admin_get_overview(p_admin_password TEXT)
RETURNS JSON AS $$
DECLARE
    v_resellers JSON;
    v_pending JSON;
    v_batches JSON;
    v_orders JSON;
BEGIN
    IF NOT public.check_admin_pass(p_admin_password) THEN
        RETURN json_build_object('success', false, 'message', 'Unauthorized. Invalid admin password.');
    END IF;

    SELECT COALESCE(json_agg(r), '[]'::json) INTO v_resellers
    FROM (SELECT id, name, phone, pin, status, (status = 'approved') AS is_active, created_at FROM public.resellers WHERE status = 'approved' ORDER BY id DESC) r;

    SELECT COALESCE(json_agg(p), '[]'::json) INTO v_pending
    FROM (SELECT id, name, phone, verification_code, created_at FROM public.resellers WHERE status = 'pending' ORDER BY id DESC) p;

    SELECT COALESCE(json_agg(b), '[]'::json) INTO v_batches
    FROM (SELECT id, reseller_name, range_start, range_end, true AS is_active, created_at FROM public.batches ORDER BY id DESC) b;

    SELECT COALESCE(json_agg(o), '[]'::json) INTO v_orders
    FROM (SELECT id, order_type, customer_name, phone, quantity, total_amount, status, notes, created_at FROM public.orders ORDER BY id DESC) o;

    RETURN json_build_object(
        'success', true,
        'resellers', v_resellers,
        'pending_resellers', v_pending,
        'batches', v_batches,
        'orders', v_orders
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: admin_assign_batch
CREATE OR REPLACE FUNCTION public.admin_assign_batch(
    p_admin_password TEXT,
    p_reseller_name TEXT,
    p_range_start INTEGER,
    p_range_end INTEGER
)
RETURNS JSON AS $$
DECLARE
    i INTEGER;
BEGIN
    IF NOT public.check_admin_pass(p_admin_password) THEN
        RETURN json_build_object('success', false, 'message', 'Unauthorized.');
    END IF;

    INSERT INTO public.batches (reseller_name, range_start, range_end)
    VALUES (p_reseller_name, p_range_start, p_range_end);

    -- Ensure card records exist and are assigned to this reseller
    FOR i IN p_range_start..p_range_end LOOP
        INSERT INTO public.clients (card_code, reseller_name, status, platform)
        VALUES (i, p_reseller_name, 'unregistered', 'google')
        ON CONFLICT (card_code) DO UPDATE SET 
            reseller_name = EXCLUDED.reseller_name,
            platform = 'google';
    END LOOP;

    RETURN json_build_object('success', true, 'message', 'Batch assigned successfully!');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: admin_unassign_batch
CREATE OR REPLACE FUNCTION public.admin_unassign_batch(
    p_admin_password TEXT,
    p_batch_id INTEGER,
    p_reset_cards BOOLEAN DEFAULT false
)
RETURNS JSON AS $$
DECLARE
    v_batch RECORD;
BEGIN
    IF NOT public.check_admin_pass(p_admin_password) THEN
        RETURN json_build_object('success', false, 'message', 'Unauthorized.');
    END IF;

    SELECT * INTO v_batch FROM public.batches WHERE id = p_batch_id;
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'message', 'Batch not found.');
    END IF;

    IF p_reset_cards THEN
        UPDATE public.clients
        SET reseller_name = NULL, status = 'unregistered', business_name = NULL, destination_url = NULL
        WHERE card_code BETWEEN v_batch.range_start AND v_batch.range_end;
    ELSE
        UPDATE public.clients
        SET reseller_name = NULL
        WHERE card_code BETWEEN v_batch.range_start AND v_batch.range_end;
    END IF;

    DELETE FROM public.batches WHERE id = p_batch_id;

    RETURN json_build_object('success', true, 'message', 'Batch unassigned successfully!');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: admin_transfer_single_card
CREATE OR REPLACE FUNCTION public.admin_transfer_single_card(
    p_admin_password TEXT,
    p_card_code INTEGER,
    p_target_reseller TEXT
)
RETURNS JSON AS $$
BEGIN
    IF NOT public.check_admin_pass(p_admin_password) THEN
        RETURN json_build_object('success', false, 'message', 'Unauthorized.');
    END IF;

    UPDATE public.clients
    SET reseller_name = p_target_reseller
    WHERE card_code = p_card_code;

    RETURN json_build_object('success', true, 'message', 'Card transferred successfully.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: admin_update_order_status
CREATE OR REPLACE FUNCTION public.admin_update_order_status(
    p_admin_password TEXT,
    p_order_id INTEGER,
    p_status TEXT
)
RETURNS JSON AS $$
BEGIN
    IF NOT public.check_admin_pass(p_admin_password) THEN
        RETURN json_build_object('success', false, 'message', 'Unauthorized.');
    END IF;

    UPDATE public.orders SET status = p_status WHERE id = p_order_id;
    RETURN json_build_object('success', true, 'message', 'Order status updated.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: admin_approve_reseller
CREATE OR REPLACE FUNCTION public.admin_approve_reseller(
    p_admin_password TEXT,
    p_reseller_id INTEGER,
    p_action TEXT
)
RETURNS JSON AS $$
BEGIN
    IF NOT public.check_admin_pass(p_admin_password) THEN
        RETURN json_build_object('success', false, 'message', 'Unauthorized.');
    END IF;

    IF p_action = 'approve' THEN
        UPDATE public.resellers SET status = 'approved' WHERE id = p_reseller_id;
    ELSE
        UPDATE public.resellers SET status = 'rejected' WHERE id = p_reseller_id;
    END IF;

    RETURN json_build_object('success', true, 'message', 'Reseller status updated.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: admin_create_reseller
CREATE OR REPLACE FUNCTION public.admin_create_reseller(
    p_admin_password TEXT,
    p_reseller_name TEXT,
    p_reseller_password TEXT,
    p_phone TEXT
)
RETURNS JSON AS $$
BEGIN
    IF NOT public.check_admin_pass(p_admin_password) THEN
        RETURN json_build_object('success', false, 'message', 'Unauthorized.');
    END IF;

    INSERT INTO public.resellers (name, pin, phone, status)
    VALUES (p_reseller_name, p_reseller_password, p_phone, 'approved');

    RETURN json_build_object('success', true, 'message', 'Reseller created successfully.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: admin_update_reseller_password
CREATE OR REPLACE FUNCTION public.admin_update_reseller_password(
    p_admin_password TEXT,
    p_reseller_name TEXT,
    p_new_password TEXT
)
RETURNS JSON AS $$
BEGIN
    IF NOT public.check_admin_pass(p_admin_password) THEN
        RETURN json_build_object('success', false, 'message', 'Unauthorized.');
    END IF;

    UPDATE public.resellers SET pin = p_new_password WHERE name = p_reseller_name;
    RETURN json_build_object('success', true, 'message', 'Password updated.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
