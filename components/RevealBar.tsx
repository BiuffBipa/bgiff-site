"use client";
import Link from "next/link";
import { useEffect, useState } from "react";
import { revealAt } from "@/lib/data";

function parts(ms: number) {
  const s = Math.max(0, Math.floor(ms / 1000));
  return {
    d: Math.floor(s / 86400),
    h: Math.floor((s % 86400) / 3600),
    m: Math.floor((s % 3600) / 60),
  };
}

const pad = (n: number) => String(n).padStart(2, "0");

export default function RevealBar() {
  const target = new Date(revealAt).getTime();
  const [now, setNow] = useState<number | null>(null);

  useEffect(() => {
    setNow(Date.now());
    const t = setInterval(() => setNow(Date.now()), 30000);
    return () => clearInterval(t);
  }, []);

  const passed = now !== null && now >= target;
  const p = now === null ? null : parts(target - now);

  return (
    <Link href="/festival#reveal" className="reveal-bar" aria-label="The Reveal, 24 November 2026">
      <span className="reveal-date">24.11.2026</span>
      <span className="reveal-title">{passed ? "The route to Berlin is published" : "The Reveal"}</span>
      {!passed && (
        <span className="reveal-count" aria-hidden={p === null}>
          {p ? (
            <>
              <b>{pad(p.d)}</b>d <b>{pad(p.h)}</b>h <b>{pad(p.m)}</b>m
            </>
          ) : (
            <>&nbsp;</>
          )}
        </span>
      )}
    </Link>
  );
}
