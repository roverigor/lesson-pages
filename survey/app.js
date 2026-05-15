const SUPABASE_URL = "https://gpufcipkajppykmnmdeh.supabase.co";
const SUPABASE_ANON_KEY = "REPLACE_WITH_ANON_KEY_AT_DEPLOY";

const $ = (id) => document.getElementById(id);
const show = (id) => $(id).classList.remove("hidden");
const hide = (id) => $(id).classList.add("hidden");

function showOnly(id) {
  ["loading", "invalid", "expired", "form", "thank-you"].forEach((s) =>
    s === id ? show(s) : hide(s),
  );
}

function getToken() {
  const m = location.pathname.match(/^\/survey\/(grupo|aluno)\/([^/]+)$/);
  if (m) return { mode: m[1] === "grupo" ? "group" : "dm", token: m[2] };

  const params = new URLSearchParams(location.search);
  const token = params.get("token");
  const mode = params.get("mode");
  if (token) return { mode: mode || null, token };

  return null;
}

async function fetchMetadata(token) {
  const url = `${SUPABASE_URL}/rest/v1/rpc/get_nps_link_metadata`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "apikey": SUPABASE_ANON_KEY,
      "Authorization": `Bearer ${SUPABASE_ANON_KEY}`,
    },
    body: JSON.stringify({ p_token: token }),
  });
  if (!res.ok) throw new Error(`metadata_${res.status}`);
  const rows = await res.json();
  return Array.isArray(rows) ? rows[0] : rows;
}

let selectedScore = null;

function renderNpsButtons() {
  const grid = $("nps");
  grid.innerHTML = "";
  for (let i = 0; i <= 10; i++) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "nps-btn";
    btn.textContent = String(i);
    btn.setAttribute("role", "radio");
    btn.setAttribute("aria-checked", "false");
    btn.addEventListener("click", () => selectScore(i));
    grid.appendChild(btn);
  }
}

function selectScore(score) {
  selectedScore = score;
  document.querySelectorAll(".nps-btn").forEach((b, idx) => {
    const isSelected = idx === score;
    b.classList.toggle("selected", isSelected);
    b.setAttribute("aria-checked", String(isSelected));
  });
  $("submit").disabled = false;
}

async function submitResponse(token) {
  hide("error");
  $("submit").disabled = true;
  $("submit").textContent = "Enviando…";

  const comment = $("comment").value.trim();
  const name = $("name").value.trim();

  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/submit-survey-group`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        token,
        nps_score: selectedScore,
        comment: comment || undefined,
        name_provided: name || undefined,
      }),
    });

    const data = await res.json().catch(() => ({}));

    if (res.ok && data.success) {
      $("thank-you-msg").textContent = data.thank_you ?? "Obrigado pelo feedback!";
      showOnly("thank-you");
      return;
    }

    let msg = "Não foi possível enviar. Tente novamente.";
    if (res.status === 410) msg = "Este link expirou. Obrigado pelo interesse!";
    else if (res.status === 429) msg = "Você já respondeu hoje. Obrigado!";
    else if (res.status === 404) msg = "Link inválido.";

    const errEl = $("error");
    errEl.textContent = msg;
    show("error");
    $("submit").disabled = false;
    $("submit").textContent = "Enviar feedback";
  } catch (e) {
    const errEl = $("error");
    errEl.textContent = "Erro de conexão. Verifique sua internet.";
    show("error");
    $("submit").disabled = false;
    $("submit").textContent = "Enviar feedback";
  }
}

async function init() {
  showOnly("loading");
  const parsed = getToken();
  if (!parsed) {
    showOnly("invalid");
    return;
  }

  let meta;
  try {
    meta = await fetchMetadata(parsed.token);
  } catch {
    showOnly("invalid");
    return;
  }

  if (!meta || !meta.valid) {
    showOnly(meta?.expired ? "expired" : "invalid");
    return;
  }

  renderNpsButtons();

  const title = meta.mode === "dm" && meta.student_name
    ? `Olá, ${meta.student_name}!`
    : "Avalie sua aula";
  $("title").textContent = title;
  $("subtitle").textContent = `${meta.class_name} — ${meta.cohort_name}`;

  if (meta.mode === "dm") hide("name-field");

  $("submit").addEventListener("click", () => submitResponse(parsed.token));
  showOnly("form");
}

init();
