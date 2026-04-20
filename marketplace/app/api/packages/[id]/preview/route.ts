import { NextResponse } from "next/server";
import { supabaseAnon } from "@/lib/supabase";

export const runtime = "nodejs";

export async function GET(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;

  const { data, error } = await supabaseAnon()
    .from("packages")
    .select("preview_png")
    .eq("id", id)
    .single();

  if (error || !data?.preview_png) {
    return NextResponse.json(
      { error: { code: "not_found", message: "Preview not found" } },
      { status: 404 }
    );
  }

  const buf = Buffer.from(data.preview_png, "base64");
  return new NextResponse(buf, {
    status: 200,
    headers: {
      "content-type": "image/png",
      "cache-control": "public, max-age=86400, immutable",
    },
  });
}
