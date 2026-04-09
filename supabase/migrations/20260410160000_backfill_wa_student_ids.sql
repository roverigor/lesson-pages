-- Backfill whatsapp_group_messages where student_id IS NULL
-- but sender_phone matches an active student's phone.
-- Also handles common Brazilian phone normalization variants.

-- Direct match
UPDATE whatsapp_group_messages wgm
SET student_id = s.id
FROM students s
WHERE wgm.student_id IS NULL
  AND s.active = true
  AND s.phone = wgm.sender_phone;

-- Match with 55 prefix added
UPDATE whatsapp_group_messages wgm
SET student_id = s.id
FROM students s
WHERE wgm.student_id IS NULL
  AND s.active = true
  AND LENGTH(wgm.sender_phone) >= 10
  AND LENGTH(wgm.sender_phone) <= 11
  AND s.phone = '55' || wgm.sender_phone;

-- Match without 55 prefix
UPDATE whatsapp_group_messages wgm
SET student_id = s.id
FROM students s
WHERE wgm.student_id IS NULL
  AND s.active = true
  AND wgm.sender_phone LIKE '55%'
  AND LENGTH(wgm.sender_phone) >= 12
  AND s.phone = SUBSTRING(wgm.sender_phone FROM 3);

-- Match toggling 9th digit (Brazilian mobile)
-- Add 9: 55+DD+8digits → 55+DD+9+8digits
UPDATE whatsapp_group_messages wgm
SET student_id = s.id
FROM students s
WHERE wgm.student_id IS NULL
  AND s.active = true
  AND wgm.sender_phone LIKE '55%'
  AND LENGTH(wgm.sender_phone) = 12
  AND s.phone = SUBSTRING(wgm.sender_phone, 1, 4) || '9' || SUBSTRING(wgm.sender_phone FROM 5);

-- Remove 9: 55+DD+9+8digits → 55+DD+8digits
UPDATE whatsapp_group_messages wgm
SET student_id = s.id
FROM students s
WHERE wgm.student_id IS NULL
  AND s.active = true
  AND wgm.sender_phone LIKE '55%'
  AND LENGTH(wgm.sender_phone) = 13
  AND SUBSTRING(wgm.sender_phone, 5, 1) = '9'
  AND s.phone = SUBSTRING(wgm.sender_phone, 1, 4) || SUBSTRING(wgm.sender_phone FROM 6);
