export const submitUrl = "https://filmfreeway.com/BGIFF";
export const festhomeUrl = "https://festhome.com/f/10633";
export const instagramUrl = "https://www.instagram.com/bgiff.festival/";

/** The Reveal: 24 November 2026, 00:00 Berlin time (CET, UTC+1). */
export const revealAt = "2026-11-23T23:00:00Z";

/** The 14 film categories, matching the FilmFreeway listing. */
export const categories = [
  ["Feature Film (Narrative)", "Fiction over 40 minutes."],
  ["Feature Documentary", "Documentary over 40 minutes."],
  ["Low-Budget Feature", "Features made under €250,000."],
  ["Short Film (Narrative)", "Fiction up to 40 minutes."],
  ["Short Documentary", "Documentary up to 40 minutes."],
  ["Animation", "Short or feature, any technique."],
  ["Experimental Film", "Non-narrative, avant-garde, visual work."],
  ["Music Video", "Any style or genre."],
  ["Web / New Media", "Series, episodic and online work."],
  ["AI Film", "Work where AI played a meaningful, declared role."],
  ["Underground Film", "Independent, unconventional work, any length."],
  ["Student Film", "Made while enrolled in study."],
  ["First Film", "A director’s first short or feature."],
  ["LGBTQ+ Film", "Films by or about LGBTQ+ people, any length."],
] as const;

/** The route to Berlin. Deadlines first, then the fixed milestones. */
export const route = [
  ["1 NOV 2026", "The gate closes for films"],
  ["21 NOV 2026", "The gate closes for writing & photography"],
  ["24 NOV 2026", "The Reveal"],
  ["21 DEC 2026", "Official Selection"],
  ["23 JAN 2027", "The Gates Open"],
  ["BERLIN 2027", "The films that pass the last gate, on screen"],
] as const;

/** Writing track dates (every date public from today). */
export const writingDates = [
  ["21 NOV 2026", "The gate closes"],
  ["1 DEC 2026", "Script pages close"],
  ["14 DEC 2026", "Official Selection"],
  ["JAN–MAR 2027", "Quarter-Finalists · Semi-Finalists · Finalists · Nominees"],
  ["APR 2027", "Winners"],
] as const;

export type Article = {
  slug: string;
  type: string;
  date: string;
  title: string;
  excerpt: string;
  image: string;
  /** Optional full body; paragraphs. Lines starting with "— " render as a list item. */
  body?: readonly string[];
};

export const manifesto: readonly string[] = [
  "Most festivals end at the Official Selection. Berlin Gate begins there.",
  "On 23 January 2027, the gates open. From that day, a selected film is no longer a title on a list. It is in play: stage after stage, each one dated, each one public, each one watched — by people who chose to watch it, whole, not three minutes of a screener. At every stage you know exactly where your film stands, on the date we said.",
  "How a film gets from the day the gates open to Berlin is the part we have told no one. It is written, dated and sealed, and it is published before a single film is selected — so no film is ever judged by a rule it did not know. It is the reason this festival exists, and the reason it looks like no festival you have entered. 24 November 2026. Write it down.",
  "This is Berlin’s habit, applied to cinema. The city had a wall and turned it into a gallery. It had a gate that stood shut for twenty-eight years and made it the one picture of itself the world keeps. Berlin does not repeat the old form. It invents the new one, and then everyone arrives.",
  "What is certain today:",
  "— Your film has a page here from day one: your title, your name, your status, every announcement that concerns it. One place. Yours.",
  "— The Official Selection is the last time your film is a name on a list.",
  "— The milestones of the First Edition are published once and do not move.",
  "— The First Edition ends in Berlin in 2027: the films that pass the last gate on screen, their makers in the room, the awards — in a city that treats a premiere like a premiere.",
  "— Writers have a gate of their own, entirely online. Photographers too.",
  "The gate is open until 1 November 2026. There will be other editions. There is only one first.",
  "Your film belongs in Berlin.",
];

export const articles: readonly Article[] = [
  { slug: "berlin-gate-begins-there", type: "Festival News", date: "October 2026", title: "Most festivals end at the Official Selection. Berlin Gate begins there.", excerpt: "On 23 January 2027, the gates open. The route to Berlin is published on 24 November.", image: "/images/hero-clean.png", body: manifesto },
  { slug: "introducing-berlin-gate", type: "Festival News", date: "12 July 2026", title: "Introducing Berlin Gate", excerpt: "A new international festival for independent voices, born in Berlin.", image: "/images/hero-clean.png" },
  { slug: "first-edition", type: "Festival Journal", date: "12 July 2026", title: "The First Edition", excerpt: "The thinking behind Berlin Gate’s First Edition.", image: "/images/hero-clean.png" },
  { slug: "cinema-new-forms", type: "Perspectives", date: "12 July 2026", title: "Cinema, New Forms and Human Vision", excerpt: "Why emerging tools matter only when they serve an authentic creative voice.", image: "/images/laurels.png" },
];

export const sampleFilms = [
  { slug: "programme-coming-soon", title: "Official Selection", director: "Published 21 December 2026", country: "International", duration: "First Edition", image: "/images/hero-clean.png", category: "Programme" },
] as const;
