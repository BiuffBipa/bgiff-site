import { notFound } from "next/navigation";

export const metadata = { title: "Admin", robots: { index: false, follow: false } };
export const dynamic = "force-dynamic";

/**
 * Admin control centre — Phase A placeholder. Hidden (404) unless PLATFORM_ADMIN_ENABLED=true
 * in the environment; the DB flag `admin_enabled` and role checks are added with the first
 * real module (ticket A-09). Nothing here touches the public site.
 */
export default function AdminHome() {
  if (process.env.PLATFORM_ADMIN_ENABLED !== "true") notFound();
  return (
    <div className="legal-page">
      <h1>BGIFF Control Centre</h1>
      <p>Phase A scaffold. Modules arrive behind feature flags: Overview · Intake · Films · Submitters · Screening · Gates · Jury · Marketing · Commerce · Content · Settings · Reports · Audit.</p>
    </div>
  );
}
