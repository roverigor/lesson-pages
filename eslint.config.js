// ESLint flat config — lesson-pages
// Lints js/*.js (public browser scripts)
// Note: inline JS in HTML files is not linted (no build system)

/** @type {import('eslint').Linter.Config[]} */
const config = [
  {
    files: ['js/**/*.js'],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'script',
      globals: {
        window: 'readonly',
        document: 'readonly',
        console: 'readonly',
        fetch: 'readonly',
        alert: 'readonly',
        confirm: 'readonly',
        setTimeout: 'readonly',
        clearTimeout: 'readonly',
        setInterval: 'readonly',
        clearInterval: 'readonly',
        URL: 'readonly',
        URLSearchParams: 'readonly',
        AbortController: 'readonly',
        FormData: 'readonly',
        Blob: 'readonly',
        localStorage: 'readonly',
        sessionStorage: 'readonly',
        navigator: 'readonly',
        location: 'readonly',
        history: 'readonly',
        Event: 'readonly',
        MutationObserver: 'readonly',
        IntersectionObserver: 'readonly',
        ResizeObserver: 'readonly',
        Promise: 'readonly',
        JSON: 'readonly',
        Math: 'readonly',
        Date: 'readonly',
        Array: 'readonly',
        Object: 'readonly',
        Set: 'readonly',
        Map: 'readonly',
        Error: 'readonly',
        Symbol: 'readonly',
        parseInt: 'readonly',
        parseFloat: 'readonly',
        isNaN: 'readonly',
        isFinite: 'readonly',
        encodeURIComponent: 'readonly',
        decodeURIComponent: 'readonly',
        // ── Supabase client globals ──
        SUPABASE_URL: 'readonly',     // supabase-client.js
        SUPABASE_KEY: 'readonly',     // supabase-client.js
        // ── Admin module globals (defined across script files, loaded in order) ──
        sb: 'readonly',               // supabase-client.js
        showToast: 'readonly',        // utils.js
        showDeleteConfirm: 'readonly',// utils.js
        checkAuth: 'readonly',        // auth.js
        renderAll: 'readonly',        // attendance.js
        loadClasses: 'readonly',      // classes.js
        loadStaff: 'readonly',        // staff.js
        loadAttendance: 'readonly',   // attendance.js
        loadOverrides: 'readonly',    // events.js
        loadNotifyView: 'readonly',   // notifications.js
        loadSchedulesView: 'readonly',// schedules.js
        loadZoomMeetings: 'readonly', // zoom.js
        autoMatchParticipants: 'readonly', // zoom.js
        loadAbstractsView: 'readonly',// abstracts.js
        loadSurveysView: 'readonly',  // surveys.js
        prvNext: 'readonly',          // surveys.js preview
        prvBack: 'readonly',          // surveys.js preview
        prvEnableNext: 'readonly',    // surveys.js preview
        prvSelectNPS: 'readonly',     // surveys.js preview
        prvSelectStar: 'readonly',    // surveys.js preview
        prvHoverStar: 'readonly',     // surveys.js preview
        prvUnhoverStar: 'readonly',   // surveys.js preview
        prvSelectOption: 'readonly',  // surveys.js preview
        prvSelectScale: 'readonly',   // surveys.js preview
        renderReport: 'readonly',     // views.js
        switchView: 'readonly',       // views.js
        getCfg: 'readonly',           // config.js
        mentorColor: 'readonly',      // config.js
        initials: 'readonly',         // config.js
        todayDate: 'readonly',        // utils.js
        dateStr: 'readonly',          // utils.js
        generateDates: 'readonly',    // utils.js
        fmtDate: 'readonly',          // utils.js
        getMentorName: 'readonly',    // utils.js
        goToMonth: 'readonly',        // utils.js
        buildEventsMap: 'readonly',   // events.js
        buildEventsFromDB: 'readonly',// events.js
        renderGrid: 'readonly',       // attendance.js
        closeModal: 'readonly',       // attendance.js
        // State globals (defined in state.js)
        EVENTS: 'writable',
        overridesCache: 'writable',
        currentMonth: 'writable',
        currentYear: 'writable',
        attendanceCache: 'writable',
        modalDateKey: 'writable',
        staffList: 'writable',
        classesList: 'writable',
        mentorsList: 'writable',
        cohortsList: 'writable',
        classSchedules: 'writable',
        linkedCohorts: 'writable',
        zoomAllStudents: 'writable',
        zoomParticipantsData: 'writable',
        notifyCohorts: 'writable',
        notifyClasses: 'writable',
        schedClasses: 'writable',
        schedCohorts: 'writable',
        abstractsList: 'writable',
        // Config globals (defined in config.js)
        TEACHERS: 'readonly',
        COURSE_CFG: 'readonly',
        MENTOR_COLORS: 'readonly',
        NOTIFY_TEMPLATES: 'readonly',
        SCHED_TEMPLATES: 'readonly',
        WEEKDAY_NAMES: 'readonly',
        WEEKDAY_LABELS: 'readonly',
        WEEKDAY_FULL: 'readonly',
        MONTHS: 'readonly',
        MONTH_NAMES: 'readonly',
        FERIADOS_2026: 'readonly',    // config.js
      },
    },
    rules: {
      'no-unused-vars': 'warn',
      'no-undef': 'error',
      'no-console': 'off',
      'eqeqeq': ['error', 'always'],
      'no-var': 'warn',
    },
  },
];

export default config;
