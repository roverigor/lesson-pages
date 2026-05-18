-- Fix: nps_next_variant — column "body_template" ambiguous between PL/pgSQL
-- variable and table column. Qualify column refs inside FOR loop.

CREATE OR REPLACE FUNCTION public.nps_next_variant(p_channel TEXT)
RETURNS TABLE (
  variant_id     TEXT,
  body_template  TEXT,
  meta_template_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_chosen   TEXT;
  v_total    INT;
  v_rand     INT;
  v_running  INT := 0;
  v_rec      RECORD;
BEGIN
  IF p_channel NOT IN ('group','dm') THEN
    RAISE EXCEPTION 'invalid channel: %', p_channel;
  END IF;

  PERFORM 1 FROM public.nps_variant_rotation_state
   WHERE channel = p_channel FOR UPDATE;

  SELECT COALESCE(SUM(v.weight), 0) INTO v_total
  FROM public.nps_message_variants v
  WHERE v.channel = p_channel AND v.active = true;

  IF v_total = 0 THEN
    RETURN;
  END IF;

  v_rand := 1 + (floor(random() * v_total))::INT;
  IF v_rand > v_total THEN v_rand := v_total; END IF;

  -- Use qualified column refs to avoid clash with RETURNS TABLE names
  FOR v_rec IN
    SELECT v.id AS vid, v.weight AS vweight
    FROM public.nps_message_variants v
    WHERE v.channel = p_channel AND v.active = true
    ORDER BY v.id
  LOOP
    v_running := v_running + v_rec.vweight;
    IF v_running >= v_rand THEN
      v_chosen := v_rec.vid;
      EXIT;
    END IF;
  END LOOP;

  IF v_chosen IS NULL THEN
    SELECT v.id INTO v_chosen
    FROM public.nps_message_variants v
    WHERE v.channel = p_channel AND v.active = true
    ORDER BY v.id LIMIT 1;
  END IF;

  UPDATE public.nps_variant_rotation_state
     SET last_variant_id = v_chosen,
         rotation_count = rotation_count + 1,
         updated_at = NOW()
   WHERE channel = p_channel;

  RETURN QUERY
    SELECT v.id, v.body_template, v.meta_template_name
    FROM public.nps_message_variants v
    WHERE v.id = v_chosen;
END;
$$;

REVOKE ALL ON FUNCTION public.nps_next_variant(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nps_next_variant(TEXT) TO service_role;
