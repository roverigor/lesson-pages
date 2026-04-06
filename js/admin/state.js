// Shared mutable state — all admin modules read/write these globals
let overridesCache = [];
let EVENTS = {};
let currentMonth = 2;
let currentYear = 2026;
let attendanceCache = {};
let modalDateKey = null;

let staffList = [];
let classesList = [];
let mentorsList = [];
let cohortsList = [];
let classSchedules = [];
let linkedCohorts = [];

let zoomAllStudents = [];
let zoomParticipantsData = [];

let notifyCohorts = [];
let notifyClasses = [];

let schedClasses = [];
let schedCohorts = [];
