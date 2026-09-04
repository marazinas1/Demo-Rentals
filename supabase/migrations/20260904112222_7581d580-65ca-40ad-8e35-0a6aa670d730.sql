CREATE OR REPLACE FUNCTION public.analytics_summary(_from date, _to date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  result jsonb;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'not authorised';
  END IF;

  IF _from IS NULL OR _to IS NULL OR _to < _from OR (_to - _from) > 400 THEN
    RAISE EXCEPTION 'invalid date range';
  END IF;

  WITH pv AS (
    SELECT
      (created_at AT TIME ZONE 'utc')::date AS day,
      path,
      session_id,
      CASE
        WHEN coalesce(referrer, '') = '' THEN 'direct'
        WHEN referrer ILIKE '%google.%' THEN 'google'
        WHEN referrer ILIKE '%bing.%' OR referrer ILIKE '%duckduckgo.%' OR referrer ILIKE '%yahoo.%' THEN 'search'
        WHEN referrer ILIKE '%facebook.%' OR referrer ILIKE '%fb.%' THEN 'facebook'
        WHEN referrer ILIKE '%instagram.%' THEN 'instagram'
        WHEN referrer ILIKE '%booking.com%' THEN 'booking'
        WHEN referrer ILIKE '%airbnb.%' THEN 'airbnb'
        ELSE 'other'
      END AS source,
      CASE
        WHEN user_agent ILIKE '%ipad%' OR user_agent ILIKE '%tablet%' THEN 'tablet'
        WHEN user_agent ILIKE '%mobi%' OR user_agent ILIKE '%iphone%' OR user_agent ILIKE '%android%' THEN 'mobile'
        WHEN coalesce(user_agent, '') = '' THEN 'unknown'
        ELSE 'desktop'
      END AS device
    FROM public.page_views
    WHERE (created_at AT TIME ZONE 'utc')::date BETWEEN _from AND _to
  )
  SELECT jsonb_build_object(
    'totals', (
      SELECT jsonb_build_object('views', count(*), 'visitors', count(DISTINCT session_id)) FROM pv
    ),
    'previous', (
      SELECT jsonb_build_object('views', count(*), 'visitors', count(DISTINCT session_id))
      FROM public.page_views
      WHERE (created_at AT TIME ZONE 'utc')::date
            BETWEEN (_from - (_to - _from) - 1) AND (_from - 1)
    ),
    'daily', COALESCE((
      SELECT jsonb_agg(row_to_json(d) ORDER BY d.day)
      FROM (SELECT day, count(*) AS views, count(DISTINCT session_id) AS visitors FROM pv GROUP BY day) d
    ), '[]'::jsonb),
    'top_pages', COALESCE((
      SELECT jsonb_agg(row_to_json(p))
      FROM (SELECT path, count(*) AS views FROM pv GROUP BY path ORDER BY count(*) DESC LIMIT 15) p
    ), '[]'::jsonb),
    'sources', COALESCE((
      SELECT jsonb_agg(row_to_json(s))
      FROM (SELECT source, count(*) AS views FROM pv GROUP BY source ORDER BY count(*) DESC) s
    ), '[]'::jsonb),
    'devices', COALESCE((
      SELECT jsonb_agg(row_to_json(v))
      FROM (SELECT device, count(*) AS views FROM pv GROUP BY device) v
    ), '[]'::jsonb),
    'leads', (
      SELECT count(*) FROM public.bookings
      WHERE (created_at AT TIME ZONE 'utc')::date BETWEEN _from AND _to
    )
  ) INTO result;

  RETURN result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.analytics_summary(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.analytics_summary(date, date) TO authenticated;