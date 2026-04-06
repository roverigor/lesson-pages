-- Add phone and password for mentor Luciana
UPDATE mentors
SET
  phone         = '558881718135',
  password_hash = extensions.crypt('Academia2026!', extensions.gen_salt('bf', 12))
WHERE name = 'Luciana';
