// ═══════════════════════════════════════════════════════════════════════════
// submit-survey-group — Public endpoint to submit anonymous NPS responses.
//
// Request body:
//   {
//     "token":         string (required),
//     "nps_score":     number 0-10 (required),
//     "comment":       string (optional),
//     "name_provided": string (optional, only honored when link.mode='group')
//   }
//
// Validates token, rate-limits by ip_hash (5 / 24h), inserts response, bumps counter.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendBlockMessage } from "../_shared/slack.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const IP_HASH_SALT = Deno.env.get("NPS_IP_HASH_SALT") ?? "fallback-rotate-me";
const SLACK_DETRACTORS_CHANNEL = Deno.env.get("SLACK_CHANNEL_DETRACTORS") ?? Deno.env.get("SLACK_CHANNEL_PRODUTO") ?? "";
const MAX_SUBMITS_PER_IP_24H = 5;

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function clientIp(req: Request): string {
  return (
    req.headers.get("x-forwarded-for")?.split(",")[0].trim() ??
    req.headers.get("cf-connecting-ip") ??
    req.headers.get("x-real-ip") ??
    "unknown"
  );
}

function dailySaltSuffix(): string {
  return new Date().toISOString().slice(0, 10);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);

  let body: {
    token?: string;
    nps_score?: number;
    comment?: string;
    name_provided?: string;
    csat_score?: number;
    too_technical?: boolean;
    improvement_text?: string;
    detractor_followup_text?: string;
    ps_brought_doubts?: boolean | null;
    ps_doubts_resolved?: string | null;
    ps_unblocked?: string | null;
  };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const token = (body.token ?? "").trim();
  const nps_score = body.nps_score;
  const comment = (body.comment ?? "").trim() || null;
  const nameProvided = (body.name_provided ?? "").trim() || null;
  const csatScore = typeof body.csat_score === "number" ? body.csat_score : null;
  const tooTechnical = typeof body.too_technical === "boolean" ? body.too_technical : null;
  const improvementText = (body.improvement_text ?? "").trim() || null;
  const detractorFollowup = (body.detractor_followup_text ?? "").trim() || null;
  const psBroughtDoubts = typeof body.ps_brought_doubts === "boolean" ? body.ps_brought_doubts : null;
  const psDoubtsResolved = (body.ps_doubts_resolved ?? "").trim() || null;
  const psUnblocked = (body.ps_unblocked ?? "").trim() || null;

  if (!token) return jsonResponse({ error: "missing_token" }, 400);
  if (
    typeof nps_score !== "number" ||
    !Number.isInteger(nps_score) ||
    nps_score < 0 ||
    nps_score > 10
  ) {
    return jsonResponse({ error: "invalid_nps_score" }, 400);
  }

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: link, error: linkErr } = await sb
    .from("nps_class_links")
    .select("id, class_id, cohort_id, mode, student_id, expires_at, session_date")
    .eq("token", token)
    .maybeSingle();

  if (linkErr) return jsonResponse({ error: "internal_error" }, 500);
  if (!link) return jsonResponse({ error: "token_not_found" }, 404);
  if (new Date(link.expires_at).getTime() < Date.now()) {
    return jsonResponse({ error: "token_expired" }, 410);
  }

  // Cross-link phone dedup (DM mode only): aluno cadastrado em múltiplos
  // cohorts gera N student rows → N links DM → sem isso, mesmo phone pode
  // submit N respostas NPS distintas (uma por link). Group mode aceita N
  // respostas por design.
  if (link.mode === "dm" && link.student_id) {
    const { data: linkStu } = await sb
      .from("students")
      .select("phone")
      .eq("id", link.student_id)
      .maybeSingle();
    const phoneRaw = linkStu?.phone ?? "";
    if (phoneRaw && !phoneRaw.startsWith("group_placeholder_")) {
      const { data: twins } = await sb
        .from("students")
        .select("id")
        .eq("phone", phoneRaw);
      const twinIds = (twins ?? [])
        .map((s: { id: string }) => s.id)
        .filter((id: string) => id !== link.student_id);
      if (twinIds.length > 0) {
        const { data: sameSessionLinks } = await sb
          .from("nps_class_links")
          .select("id")
          .eq("class_id", link.class_id)
          .eq("session_date", link.session_date)
          .eq("mode", "dm");
        const lids = (sameSessionLinks ?? [])
          .map((l: { id: string }) => l.id)
          .filter((id: string) => id !== link.id);
        if (lids.length > 0) {
          const { data: twinResp } = await sb
            .from("class_nps_responses")
            .select("id")
            .in("student_id", twinIds)
            .in("link_id", lids)
            .limit(1)
            .maybeSingle();
          if (twinResp) {
            return jsonResponse({ success: true, already: true, dedup: "phone_twin" });
          }
        }
      }
    }
  }

  // Group mode: nome obrigatório (min 2 chars) — pra rastrear detractor
  if (link.mode === "group" && (!nameProvided || nameProvided.length < 2)) {
    return jsonResponse({ error: "name_required" }, 400);
  }

  const ip = clientIp(req);
  const ipHash = await sha256Hex(`${ip}|${IP_HASH_SALT}|${dailySaltSuffix()}`);

  // Rate limit aplica APENAS em DM mode (1 aluno = 1 submit, abuse alto).
  // Group mode: vários alunos no mesmo wifi (casa, escola, sala compartilhada)
  // legitimamente excedem 5/24h. name_provided required já mitiga spam.
  if (link.mode === "dm") {
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const { count: recentCount, error: countErr } = await sb
      .from("class_nps_responses")
      .select("id", { count: "exact", head: true })
      .eq("ip_hash", ipHash)
      .gte("submitted_at", since);
    if (countErr) return jsonResponse({ error: "internal_error" }, 500);
    if ((recentCount ?? 0) >= MAX_SUBMITS_PER_IP_24H) {
      return jsonResponse({ error: "rate_limited" }, 429);
    }
  }

  const userAgent = req.headers.get("user-agent")?.slice(0, 500) ?? null;

  const { error: insertErr } = await sb.from("class_nps_responses").insert({
    link_id: link.id,
    class_id: link.class_id,
    cohort_id: link.cohort_id,
    mode: link.mode,
    student_id: link.mode === "dm" ? link.student_id : null,
    nps_score,
    comment,
    name_provided: link.mode === "group" ? nameProvided : null,
    // ip_hash em DM previne double-submit (unique idx link_id+ip_hash). Em group,
    // ip_hash=NULL permite múltiplos alunos no mesmo wifi (unique idx WHERE NOT NULL).
    ip_hash: link.mode === "dm" ? ipHash : null,
    user_agent: userAgent,
    csat_score: csatScore,
    too_technical: tooTechnical,
    improvement_text: improvementText,
    detractor_followup_text: detractorFollowup,
    ps_brought_doubts: psBroughtDoubts,
    ps_doubts_resolved: psDoubtsResolved,
    ps_unblocked: psUnblocked,
  });

  // Postgres error code 23505 = unique_violation → aluno DM já respondeu.
  // Retorna success amigável em vez de 500.
  if (insertErr && (insertErr as { code?: string }).code === "23505") {
    return jsonResponse({ success: true, already: true });
  }
  if (insertErr) return jsonResponse({ error: "internal_error" }, 500);

  await sb.rpc("increment_nps_link_response_count", { p_link_id: link.id }).then(() => {});

  // ─── P.2: detractor branch — Slack alert for scores 0-6 ───
  if (nps_score <= 6) {
    notifyDetractor(sb, link, {
      nps_score, comment, nameProvided,
      csatScore, tooTechnical, improvementText, detractorFollowup,
    }).catch((e) => {
      console.error("[detractor-alert] failed:", e);
    });
  }

  // ─── P.2: bucketed thank-you ───
  let thankYou;
  let bucket;
  if (nps_score <= 6) {
    bucket = "detractor";
    thankYou = "Obrigado pelo feedback. Um membro do nosso time vai te chamar pra entender melhor e ajustar o que for preciso. 🙏";
  } else if (nps_score <= 8) {
    bucket = "passive";
    thankYou = "Valeu pela nota! Sua avaliação nos ajuda a calibrar a próxima aula. 💛";
  } else {
    bucket = "promoter";
    thankYou = "Que bom que foi bom! 💜 Se conhecer alguém que se beneficiaria, manda nossa página: https://academialendaria.ai";
  }

  return jsonResponse({
    success: true,
    bucket,
    thank_you: thankYou,
  });
});

// ─── Detractor → Slack alert ────────────────────────────────────────────
async function notifyDetractor(
  sb: ReturnType<typeof createClient>,
  link: {
    id: string; class_id: string | null; cohort_id: string;
    mode: string; student_id: string | null;
  },
  payload: {
    nps_score: number;
    comment: string | null;
    nameProvided: string | null;
    csatScore: number | null;
    tooTechnical: boolean | null;
    improvementText: string | null;
    detractorFollowup: string | null;
  },
): Promise<void> {
  if (!SLACK_DETRACTORS_CHANNEL) {
    console.warn("[detractor-alert] no SLACK_CHANNEL_DETRACTORS / SLACK_CHANNEL_PRODUTO env — skipping");
    return;
  }

  // Fetch context
  const [
    { data: cohort },
    { data: klass },
    { data: student },
  ] = await Promise.all([
    sb.from("cohorts").select("name").eq("id", link.cohort_id).maybeSingle(),
    link.class_id
      ? sb.from("classes").select("name").eq("id", link.class_id).maybeSingle()
      : Promise.resolve({ data: null }),
    link.mode === "dm" && link.student_id
      ? sb.from("students").select("name, phone").eq("id", link.student_id).maybeSingle()
      : Promise.resolve({ data: null }),
  ]);

  const cohortName = (cohort as { name?: string } | null)?.name ?? "—";
  const className = (klass as { name?: string } | null)?.name ?? "—";
  const studentName = link.mode === "dm"
    ? (student as { name?: string } | null)?.name ?? "—"
    : payload.nameProvided ?? "Anônimo (form grupo)";
  const studentPhone = link.mode === "dm"
    ? (student as { phone?: string } | null)?.phone ?? "—"
    : "—";

  const scoreLabel = payload.nps_score <= 2 ? "🚨 NOTA CRÍTICA" : "⚠️ Detractor";

  const text = `${scoreLabel} (${payload.nps_score}/10) — ${cohortName} · ${className}`;
  const blocks = [
    {
      type: "section",
      text: { type: "mrkdwn", text: `*${text}*` },
    },
    {
      type: "section",
      fields: [
        { type: "mrkdwn", text: `*Aluno:*\n${studentName}` },
        { type: "mrkdwn", text: `*Telefone:*\n${studentPhone}` },
        { type: "mrkdwn", text: `*Cohort:*\n${cohortName}` },
        { type: "mrkdwn", text: `*Aula:*\n${className}` },
        { type: "mrkdwn", text: `*Nota:*\n${payload.nps_score}/10` },
        { type: "mrkdwn", text: `*Canal:*\n${link.mode === "dm" ? "DM (atribuído)" : "Grupo (anônimo)"}` },
      ],
    },
  ];

  // CSAT + too_technical extras
  const extras: string[] = [];
  if (payload.csatScore != null) extras.push(`*CSAT:* ${payload.csatScore}/5 ⭐`);
  if (payload.tooTechnical === true) extras.push(`*Muito técnica:* Sim ⚠️`);
  if (payload.tooTechnical === false) extras.push(`*Muito técnica:* Não, no nível certo ✓`);
  if (extras.length > 0) {
    blocks.push({ type: "section", text: { type: "mrkdwn", text: extras.join("\n") } });
  }

  if (payload.improvementText) {
    blocks.push({
      type: "section",
      text: { type: "mrkdwn", text: `*O que pode melhorar:*\n>${payload.improvementText.replace(/\n/g, "\n>")}` },
    });
  }

  if (payload.comment) {
    blocks.push({
      type: "section",
      text: { type: "mrkdwn", text: `*Comentário:*\n>${payload.comment.replace(/\n/g, "\n>")}` },
    });
  }

  if (payload.detractorFollowup) {
    blocks.push({
      type: "section",
      text: { type: "mrkdwn", text: `*🚨 O que precisamos fazer:*\n>${payload.detractorFollowup.replace(/\n/g, "\n>")}` },
    });
  }

  blocks.push({
    type: "context",
    elements: [
      { type: "mrkdwn", text: `Ver detalhes em https://painel.academialendaria.ai/admin/nps-results/` },
    ],
  });

  try {
    await sendBlockMessage(SLACK_DETRACTORS_CHANNEL, text, blocks);
  } catch (e) {
    console.error("[detractor-alert] sendBlockMessage failed:", e instanceof Error ? e.message : e);
  }
}
