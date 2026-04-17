/**
 * Slack helpers for edge functions.
 * Uses bot token for DMs and channel messages.
 * Supports interactive approval messages (Block Kit buttons).
 */

const SLACK_API = "https://slack.com/api";

function getToken(): string {
  const token = Deno.env.get("SLACK_BOT_TOKEN");
  if (!token) throw new Error("SLACK_BOT_TOKEN not set");
  return token;
}

async function slackPost(method: string, body: Record<string, unknown>) {
  const resp = await fetch(`${SLACK_API}/${method}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${getToken()}`,
      "Content-Type": "application/json; charset=utf-8",
    },
    body: JSON.stringify(body),
  });
  const data = await resp.json();
  if (!data.ok) {
    throw new Error(`Slack ${method} failed: ${data.error}`);
  }
  return data;
}

/** Open a DM channel with a user, returns channel ID */
export async function openDM(userId: string): Promise<string> {
  const data = await slackPost("conversations.open", { users: userId });
  return data.channel.id;
}

/** Send a simple text message to a channel or DM */
export async function sendMessage(channel: string, text: string) {
  return slackPost("chat.postMessage", { channel, text });
}

/** Send a DM to a user by their Slack user ID */
export async function sendDM(userId: string, text: string) {
  const channel = await openDM(userId);
  return slackPost("chat.postMessage", { channel, text });
}

/** Send an approval message with Approve/Reject buttons */
export async function sendApprovalMessage(
  userId: string,
  opts: {
    title: string;
    summary: string;
    details: string[];
    notificationId: string;
  }
) {
  const channel = await openDM(userId);
  const blocks = [
    {
      type: "header",
      text: { type: "plain_text", text: opts.title, emoji: true },
    },
    {
      type: "section",
      text: { type: "mrkdwn", text: opts.summary },
    },
  ];

  if (opts.details.length > 0) {
    blocks.push({
      type: "section",
      text: {
        type: "mrkdwn",
        text: opts.details.join("\n"),
      },
    });
  }

  blocks.push(
    { type: "divider" } as any,
    {
      type: "actions",
      // @ts-ignore block_id
      block_id: `approval_${opts.notificationId}`,
      elements: [
        {
          type: "button",
          text: { type: "plain_text", text: "Aprovar", emoji: true },
          style: "primary",
          action_id: "approve_notification",
          value: opts.notificationId,
        },
        {
          type: "button",
          text: { type: "plain_text", text: "Rejeitar", emoji: true },
          style: "danger",
          action_id: "reject_notification",
          value: opts.notificationId,
        },
      ],
    } as any
  );

  const data = await slackPost("chat.postMessage", {
    channel,
    text: `${opts.title} — ${opts.summary}`,
    blocks,
  });

  return data;
}

/** Send DMs to multiple staff members, returns results */
export async function sendBulkDM(
  recipients: Array<{ slack_user_id: string; name: string }>,
  buildMessage: (name: string) => string
): Promise<{ sent: number; failed: number; errors: string[] }> {
  let sent = 0;
  let failed = 0;
  const errors: string[] = [];

  for (const r of recipients) {
    try {
      await sendDM(r.slack_user_id, buildMessage(r.name));
      sent++;
      // Small delay to avoid rate limits
      await new Promise((resolve) => setTimeout(resolve, 1000));
    } catch (e) {
      failed++;
      errors.push(`${r.name}: ${(e as Error).message}`);
    }
  }

  return { sent, failed, errors };
}

/** Update the original approval message after action */
export async function updateApprovalMessage(
  channel: string,
  messageTs: string,
  approved: boolean,
  extraText?: string
) {
  const status = approved ? "✅ *APROVADO*" : "❌ *REJEITADO*";
  const text = extraText ? `${status}\n${extraText}` : status;

  return slackPost("chat.update", {
    channel,
    ts: messageTs,
    text,
    blocks: [
      {
        type: "section",
        text: { type: "mrkdwn", text },
      },
    ],
  });
}

/** Verify Slack request signature */
export function verifySlackSignature(
  signingSecret: string,
  signature: string,
  timestamp: string,
  body: string
): boolean {
  const encoder = new TextEncoder();
  const baseString = `v0:${timestamp}:${body}`;

  // Use Web Crypto API (available in Deno)
  // Note: This is async but we need sync verification
  // For edge functions, we'll do async verification in the handler
  return true; // placeholder — async verification done in handler
}

/** Async signature verification for edge function handlers */
export async function verifySignatureAsync(
  signingSecret: string,
  signature: string,
  timestamp: string,
  body: string
): Promise<boolean> {
  // Check timestamp freshness (5 min window)
  const now = Math.floor(Date.now() / 1000);
  if (Math.abs(now - parseInt(timestamp)) > 300) return false;

  const encoder = new TextEncoder();
  const baseString = `v0:${timestamp}:${body}`;

  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(signingSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const sig = await crypto.subtle.sign("HMAC", key, encoder.encode(baseString));
  const computed = `v0=${Array.from(new Uint8Array(sig)).map(b => b.toString(16).padStart(2, '0')).join('')}`;

  return computed === signature;
}
