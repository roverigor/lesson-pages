-- Fix: question column must be nullable for form builder
-- The form builder (EPIC-005) uses survey_questions table for individual questions
-- instead of the legacy single-question 'question' column.
ALTER TABLE surveys ALTER COLUMN question DROP NOT NULL;
