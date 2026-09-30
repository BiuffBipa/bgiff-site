import { NextResponse } from "next/server";
import { isDatabaseConfigured, serviceClient } from "@/lib/server/supabase";

export const dynamic = "force-dynamic";

/** Uptime / health probe. Reveals no secrets and no settings; only whether the DB answers. */
export async function GET() {
  const startedAt = Date.now();
  let database: "ok" | "unconfigured" | "error" = "unconfigured";
  if (isDatabaseConfigured()) {
    try {
      const { error } = await serviceClient().from("feature_flags").select("key", { count: "exact", head: true });
      database = error ? "error" : "ok";
    } catch {
      database = "error";
    }
  }
  return NextResponse.json(
    { ok: database !== "error", database, env: process.env.APP_ENV ?? "development", latencyMs: Date.now() - startedAt, at: new Date().toISOString() },
    { status: database === "error" ? 503 : 200, headers: { "cache-control": "no-store" } },
  );
}
