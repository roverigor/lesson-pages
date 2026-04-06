# Legacy SQL Files — Already Applied

These files were created before the `supabase/migrations/` system was established.
All schema changes here are already applied to the production database and captured
in `supabase/migrations/20260402190833_baseline_existing_schema.sql`.

**DO NOT re-apply these files** — they will cause errors (tables/constraints already exist).

## Migration History (chronological order applied)

1. `schema.sql` — Original base schema (classes, mentors, cohorts, attendance)
2. `students-schema.sql` — Students table
3. `zoom-schema.sql` — Zoom meetings and participants tables
4. `notifications-schema.sql` — Notifications table (superseded by supabase/migrations/20260402175137)
5. `migration-class-mentors-fix.sql` — Fixed class_mentors role CHECK + weekday column
6. `migration-fix-rls-and-types.sql` — Fixed mentor_attendance RLS + lesson_date type
7. `migration-mentor-attendance.sql` — Mentor attendance table
8. `seed-notifications-setup.sql` — Notification config seed data
9. `set-mentor-passwords.sql` — Initial mentor passwords (sensitive — do not redistribute)
10. `classes-schema.sql` — Classes schema refinements

## Current Migration System

All new schema changes go in `supabase/migrations/` with timestamp prefix.
Apply with: `supabase db push`
