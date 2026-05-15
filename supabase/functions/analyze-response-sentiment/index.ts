// EPIC-017 Story 17.4 — AI sentiment + auto-tag de respostas free-text
// Recebe response_id, busca respostas texto, chama OpenAI ChatGPT mini, escreve em response_metadata.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface RequestBody {
  response_id: string;
}

interface AISentimentResponse {
  sentiment: 'positive' | 'neutral' | 'negative' | 'critical';
  confidence: number;
  themes: string[];
  summary: string;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");

    if (!OPENAI_API_KEY) {
      return new Response(
        JSON.stringify({ error: "OPENAI_API_KEY not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { response_id }: RequestBody = await req.json();

    if (!response_id) {
      return new Response(
        JSON.stringify({ error: "response_id required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Buscar respostas texto livre desta survey response
    const { data: answers, error: aErr } = await sb
      .from("survey_answers")
      .select("value, survey_questions(label, type)")
      .eq("response_id", response_id);

    if (aErr) throw aErr;

    const textAnswers = (answers ?? [])
      .filter((a: any) => a.survey_questions?.type === "text" && a.value && a.value.length > 5)
      .map((a: any) => `Pergunta: ${a.survey_questions.label}\nResposta: ${a.value}`)
      .join("\n\n");

    if (!textAnswers) {
      return new Response(
        JSON.stringify({ ok: true, message: "no text answers to analyze" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Chamar OpenAI gpt-4o-mini (cheap)
    const prompt = `Analise as respostas abaixo de um aluno em uma pesquisa de satisfação de curso. Retorne APENAS JSON válido com:
- sentiment: "positive" | "neutral" | "negative" | "critical"
- confidence: 0.0 a 1.0
- themes: array de até 3 temas (ex: "preço", "conteúdo", "suporte", "instrutor", "ritmo", "bug", "elogio")
- summary: 1 frase resumo (max 120 chars)

Respostas:
${textAnswers}

JSON:`;

    const aiResp = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: "Você é um analista que classifica feedback de alunos. Sempre retorne JSON válido." },
          { role: "user", content: prompt },
        ],
        response_format: { type: "json_object" },
        temperature: 0.3,
        max_tokens: 200,
      }),
    });

    if (!aiResp.ok) {
      const errText = await aiResp.text();
      throw new Error(`OpenAI API: ${aiResp.status} ${errText}`);
    }

    const aiData = await aiResp.json();
    const result: AISentimentResponse = JSON.parse(aiData.choices[0].message.content);

    // Upsert em response_metadata
    const { error: upErr } = await sb
      .from("response_metadata")
      .upsert({
        response_id,
        sentiment: result.sentiment,
        sentiment_confidence: result.confidence,
        themes: result.themes,
      }, { onConflict: "response_id" });

    if (upErr) throw upErr;

    return new Response(
      JSON.stringify({ ok: true, ...result }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (e) {
    console.error("analyze-response-sentiment error:", e);
    return new Response(
      JSON.stringify({ error: String((e as Error).message ?? e) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
