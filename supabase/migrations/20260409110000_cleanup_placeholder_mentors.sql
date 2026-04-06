-- ═══════════════════════════════════════
-- Remove placeholder mentor records added incorrectly
-- All mentors are already properly registered with real phones
-- ═══════════════════════════════════════

DELETE FROM public.mentors
WHERE phone IN ('placeholder_tais', 'placeholder_luharrais');
