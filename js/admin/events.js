// ═══════════════════════════════════════
// BUILD EVENTS MAP (applies overrides)
// ═══════════════════════════════════════
function buildEventsMap() {
  const map = {};
  for (const teacher of TEACHERS) {
    for (const a of teacher.assignments) {
      for (const date of a.dates) {
        if (!map[date]) map[date] = {};
        if (!map[date][a.course]) map[date][a.course] = { course: a.course, mentors: [] };
        const already = map[date][a.course].mentors.some(m => m.name === teacher.name);
        if (!already) map[date][a.course].mentors.push({ name: teacher.name, role: a.role });
      }
    }
  }
  for (const ov of overridesCache) {
    if (ov.action === 'remove') {
      if (map[ov.lesson_date] && map[ov.lesson_date][ov.course]) {
        map[ov.lesson_date][ov.course].mentors = map[ov.lesson_date][ov.course].mentors.filter(m => m.name !== ov.teacher_name);
      }
    } else if (ov.action === 'add') {
      if (!map[ov.lesson_date]) map[ov.lesson_date] = {};
      if (!map[ov.lesson_date][ov.course]) map[ov.lesson_date][ov.course] = { course: ov.course, mentors: [] };
      const already = map[ov.lesson_date][ov.course].mentors.some(m => m.name === ov.teacher_name);
      if (!already) map[ov.lesson_date][ov.course].mentors.push({ name: ov.teacher_name, role: ov.role });
    }
  }
  return map;
}

// Build EVENTS map from DB data (class_mentors + classes + mentors)
// Falls back to hardcoded TEACHERS if DB data not yet loaded
function buildEventsFromDB() {
  const map = {};

  for (const c of classesList) {
    if (!c.start_date || !c.end_date) continue;

    const mentors = c._mentors || [];

    const weekdays = mentors.length > 0
      ? [...new Set(mentors.map(cm => cm.weekday ?? c.weekday).filter(w => w != null))]
      : c.weekday != null ? [c.weekday] : [];

    for (const wd of weekdays) {
      const dates = generateDates(c.start_date, c.end_date, wd);

      for (const date of dates) {
        const isoDate = date.toISOString().split('T')[0];
        const dayMentors = mentors.filter(cm => {
          if ((cm.weekday ?? c.weekday) !== wd) return false;
          if (cm.valid_from && isoDate < cm.valid_from) return false;
          if (cm.valid_until && isoDate > cm.valid_until) return false;
          return true;
        });

        const key = fmtDate(date);
        if (!map[key]) map[key] = {};
        if (!map[key][c.name]) map[key][c.name] = { course: c.name, mentors: [] };

        for (const cm of dayMentors) {
          const mentorName = getMentorName(cm.mentor_id);
          if (mentorName === '?') continue;
          const already = map[key][c.name].mentors.some(m => m.name === mentorName);
          if (!already) map[key][c.name].mentors.push({ name: mentorName, role: cm.role });
        }
      }
    }

    // Fallback: classes with no class_mentors rows but old professor/host fields
    if (mentors.length === 0 && (c.professor || c.host) && c.weekday != null) {
      const dates = generateDates(c.start_date, c.end_date, c.weekday);
      for (const date of dates) {
        const key = fmtDate(date);
        if (!map[key]) map[key] = {};
        if (!map[key][c.name]) map[key][c.name] = { course: c.name, mentors: [] };
        if (c.professor && !map[key][c.name].mentors.some(m => m.name === c.professor))
          map[key][c.name].mentors.push({ name: c.professor, role: 'Professor' });
        if (c.host && !map[key][c.name].mentors.some(m => m.name === c.host))
          map[key][c.name].mentors.push({ name: c.host, role: 'Host' });
      }
    }
  }

  for (const ov of overridesCache) {
    if (ov.action === 'remove') {
      if (map[ov.lesson_date]?.[ov.course]) {
        map[ov.lesson_date][ov.course].mentors = map[ov.lesson_date][ov.course].mentors.filter(m => m.name !== ov.teacher_name);
      }
    } else if (ov.action === 'add') {
      if (!map[ov.lesson_date]) map[ov.lesson_date] = {};
      if (!map[ov.lesson_date][ov.course]) map[ov.lesson_date][ov.course] = { course: ov.course, mentors: [] };
      const already = map[ov.lesson_date][ov.course].mentors.some(m => m.name === ov.teacher_name);
      if (!already) map[ov.lesson_date][ov.course].mentors.push({ name: ov.teacher_name, role: ov.role });
    }
  }

  return map;
}

async function loadOverrides() {
  const { data } = await sb.from('schedule_overrides').select('*');
  overridesCache = data || [];
  EVENTS = classesList.length ? buildEventsFromDB() : buildEventsMap();
}

// Initialise EVENTS from hardcoded data (DB data not yet loaded)
EVENTS = buildEventsMap();
