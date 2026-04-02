// ═══════════════════════════════════════
// Edge Function: send-whatsapp
// Triggered by Database Webhook on notifications INSERT
// Sends WhatsApp messages via Evolution API
// ═══════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

// ─── Configuration ───

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "https://gpufcipkajppykmnmdeh.supabase.co";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const EVOLUTION_API_URL = Deno.env.get("EVOLUTION_API_URL") ?? "";
const EVOLUTION_API_KEY = Deno.env.get("EVOLUTION_API_KEY") ?? "";
const EVOLUTION_INSTANCE = Deno.env.get("EVOLUTION_INSTANCE") ?? "";

// ─── Types ───

interface NotificationRecord {
  id: string;
  type: string;
  class_id: string | null;
  cohort_id: string | null;
  mentor_id: string | null;
  target_type: string;
  target_phone: string | null;
  target_group_jid: string | null;
  message_template: string;
  message_rendered: string | null;
  metadata: Record<string, unknown>;
  status: string;
  retry_count: number;
  max_retries: number;
}

interface ClassRecord {
  id: string;
  name: string;
  weekday: number;
  time_start: string;
  time_end: string;
  professor: string | null;
  host: string | null;
  color: string | null;
}

interface CohortRecord {
  id: string;
  name: string;
  whatsapp_group_jid: string | null;
  zoom_link: string | null;
}

interface MentorRecord {
  id: string;
  name: string;
  phone: string;
  role: string;
}

interface EvolutionResponse {
  key: { remoteJid: string; id: string };
  message: Record<string, unknown>;
  status: string;
}

// ─── Supabase Client (service_role bypasses RLS) ───

function getSupabaseClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

// ─── Evolution API Helpers ───

async function sendTextMessage(
  remoteJid: string,
  text: string
): Promise<{ success: boolean; response?: EvolutionResponse; error?: string }> {
  const url = `${EVOLUTION_API_URL}/message/sendText/${EVOLUTION_INSTANCE}`;

  try {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: EVOLUTION_API_KEY,
      },
      body: JSON.stringify({
        number: remoteJid,
        text: text,
      }),
    });

    if (!res.ok) {
      const errBody = await res.text();
      return { success: false, error: `HTTP ${res.status}: ${errBody}` };
    }

    const data = (await res.json()) as EvolutionResponse;
    return { success: true, response: data };
  } catch (err) {
    return {
      success: false,
      error: err instanceof Error ? err.message : "Unknown fetch error",
    };
  }
}

// ─── Template Rendering ───

function renderTemplate(
  template: string,
  vars: Record<string, string | undefined>
): string {
  let rendered = template;
  for (const [key, value] of Object.entries(vars)) {
    rendered = rendered.replaceAll(`{{${key}}}`, value ?? "");
  }
  return rendered;
}

const WEEKDAY_NAMES: Record<number, string> = {
  0: "Domingo",
  1: "Segunda",
  2: "Terca",
  3: "Quarta",
  4: "Quinta",
  5: "Sexta",
  6: "Sabado",
};

// ─── Core Processing ───

async function processNotification(notification: NotificationRecord): Promise<{
  finalStatus: string;
  errorMessage: string | null;
  evolutionResponse: Record<string, unknown> | null;
  renderedMessage: string;
}> {
  const sb = getSupabaseClient();
  const responses: Record<string, unknown>[] = [];
  const errors: string[] = [];

  // 1. Fetch related data for template rendering
  let classData: ClassRecord | null = null;
  let cohortData: CohortRecord | null = null;
  let mentorData: MentorRecord | null = null;
  let classMentors: MentorRecord[] = [];

  if (notification.class_id) {
    const { data } = await sb
      .from("classes")
      .select("*")
      .eq("id", notification.class_id)
      .single();
    classData = data as ClassRecord | null;

    // Fetch cohorts linked to this class
    if (classData) {
      const { data: bridges } = await sb
        .from("class_cohorts")
        .select("cohort_id")
        .eq("class_id", notification.class_id);

      if (bridges?.length) {
        const cohortIds = bridges.map((b: { cohort_id: string }) => b.cohort_id);
        const { data: cohorts } = await sb
          .from("cohorts")
          .select("*")
          .in("id", cohortIds);
        // Use first cohort as primary (or the one specified)
        if (cohorts?.length) {
          cohortData = (notification.cohort_id
            ? cohorts.find((c: CohortRecord) => c.id === notification.cohort_id)
            : cohorts[0]) as CohortRecord;
        }
      }

      // Fetch mentors for this class
      const { data: mentorBridges } = await sb
        .from("class_mentors")
        .select("mentor_id, role")
        .eq("class_id", notification.class_id);

      if (mentorBridges?.length) {
        const mentorIds = mentorBridges.map(
          (m: { mentor_id: string }) => m.mentor_id
        );
        const { data: mentors } = await sb
          .from("mentors")
          .select("*")
          .in("id", mentorIds)
          .eq("active", true);
        classMentors = (mentors ?? []) as MentorRecord[];
      }
    }
  }

  if (notification.cohort_id && !cohortData) {
    const { data } = await sb
      .from("cohorts")
      .select("*")
      .eq("id", notification.cohort_id)
      .single();
    cohortData = data as CohortRecord | null;
  }

  if (notification.mentor_id) {
    const { data } = await sb
      .from("mentors")
      .select("*")
      .eq("id", notification.mentor_id)
      .single();
    mentorData = data as MentorRecord | null;
  }

  // 2. Build template variables
  const templateVars: Record<string, string | undefined> = {
    class_name: classData?.name,
    class_time_start: classData?.time_start,
    class_time_end: classData?.time_end,
    class_weekday: classData ? WEEKDAY_NAMES[classData.weekday] : undefined,
    class_professor: classData?.professor ?? undefined,
    class_host: classData?.host ?? undefined,
    cohort_name: cohortData?.name,
    zoom_link: cohortData?.zoom_link ?? undefined,
    mentor_name: mentorData?.name,
    mentor_phone: mentorData?.phone,
    mentors_list: classMentors.map((m) => m.name).join(", "),
    ...(notification.metadata as Record<string, string>),
  };

  // 3. Render message
  const renderedMessage =
    notification.message_rendered ??
    renderTemplate(notification.message_template, templateVars);

  // 4. Send to group(s)
  if (
    notification.target_type === "group" ||
    notification.target_type === "both"
  ) {
    const groupJid =
      notification.target_group_jid ?? cohortData?.whatsapp_group_jid;

    if (groupJid) {
      const result = await sendTextMessage(groupJid, renderedMessage);
      if (result.success) {
        responses.push(result.response as Record<string, unknown>);
      } else {
        errors.push(`Group ${groupJid}: ${result.error}`);
      }
    } else {
      errors.push("No group JID found for this notification");
    }
  }

  // 5. Send individual messages to mentors
  if (
    notification.target_type === "individual" ||
    notification.target_type === "both"
  ) {
    // If specific mentor, send to that mentor
    if (mentorData) {
      const mentorMessage = renderTemplate(notification.message_template, {
        ...templateVars,
        mentor_name: mentorData.name,
      });
      const result = await sendTextMessage(mentorData.phone, mentorMessage);
      if (result.success) {
        responses.push(result.response as Record<string, unknown>);
      } else {
        errors.push(`Mentor ${mentorData.name}: ${result.error}`);
      }
    }
    // If class_reminder with target=both, send to all class mentors
    else if (
      notification.type === "class_reminder" &&
      classMentors.length > 0
    ) {
      for (const mentor of classMentors) {
        const mentorMessage = renderTemplate(notification.message_template, {
          ...templateVars,
          mentor_name: mentor.name,
        });

        // For individual messages, use phone number directly
        const result = await sendTextMessage(mentor.phone, mentorMessage);
        if (result.success) {
          responses.push(result.response as Record<string, unknown>);
        } else {
          errors.push(`Mentor ${mentor.name}: ${result.error}`);
        }
      }
    } else {
      // Fallback: use target_phone if provided
      if (notification.target_phone) {
        const result = await sendTextMessage(
          notification.target_phone,
          renderedMessage
        );
        if (result.success) {
          responses.push(result.response as Record<string, unknown>);
        } else {
          errors.push(`Phone ${notification.target_phone}: ${result.error}`);
        }
      } else {
        errors.push("No mentor or phone target found for individual message");
      }
    }
  }

  // 6. Determine final status
  let finalStatus: string;
  if (errors.length === 0) {
    finalStatus = "sent";
  } else if (responses.length > 0 && errors.length > 0) {
    finalStatus = "partial";
  } else {
    finalStatus = "failed";
  }

  return {
    finalStatus,
    errorMessage: errors.length > 0 ? errors.join(" | ") : null,
    evolutionResponse: responses.length > 0 ? { results: responses } : null,
    renderedMessage,
  };
}

// ─── HTTP Handler ───

serve(async (req: Request) => {
  // CORS headers for Supabase
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
  };

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const sb = getSupabaseClient();

    // Parse webhook payload
    const payload = await req.json();

    // Database webhook sends: { type, table, record, schema, old_record }
    const record = payload.record as NotificationRecord | undefined;

    // Also support direct invocation with { notification_id }
    let notification: NotificationRecord | null = null;

    if (record?.id && record?.status === "pending") {
      notification = record;
    } else if (payload.notification_id) {
      const { data } = await sb
        .from("notifications")
        .select("*")
        .eq("id", payload.notification_id)
        .eq("status", "pending")
        .single();
      notification = data as NotificationRecord | null;
    }

    if (!notification) {
      return new Response(
        JSON.stringify({
          ok: false,
          reason: "No pending notification found",
        }),
        {
          status: 200, // 200 to avoid webhook retries for non-pending
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Guard: only process 'pending' status
    if (notification.status !== "pending") {
      return new Response(
        JSON.stringify({
          ok: false,
          reason: `Notification status is '${notification.status}', not 'pending'`,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Mark as processing
    await sb
      .from("notifications")
      .update({
        status: "processing",
        processed_at: new Date().toISOString(),
      })
      .eq("id", notification.id);

    // Process the notification
    const result = await processNotification(notification);

    // Update with final status
    await sb
      .from("notifications")
      .update({
        status: result.finalStatus,
        message_rendered: result.renderedMessage,
        error_message: result.errorMessage,
        evolution_response: result.evolutionResponse,
        sent_at:
          result.finalStatus === "sent" || result.finalStatus === "partial"
            ? new Date().toISOString()
            : null,
        retry_count: notification.retry_count + 1,
      })
      .eq("id", notification.id);

    // If failed and retries remaining, reset to pending for retry
    if (
      result.finalStatus === "failed" &&
      notification.retry_count + 1 < notification.max_retries
    ) {
      // Delay retry by re-inserting as pending after a brief wait
      // (In production, use pg_cron or a scheduled function for exponential backoff)
      console.log(
        `Notification ${notification.id} failed, retry ${notification.retry_count + 1}/${notification.max_retries}`
      );
    }

    return new Response(
      JSON.stringify({
        ok: true,
        notification_id: notification.id,
        status: result.finalStatus,
        error: result.errorMessage,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err) {
    console.error("Edge Function error:", err);

    return new Response(
      JSON.stringify({
        ok: false,
        error: err instanceof Error ? err.message : "Unknown error",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
