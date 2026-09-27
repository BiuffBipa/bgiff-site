export const submitUrl = "https://filmfreeway.com/BGIFF";
export const festhomeUrl = "https://festhome.com/f/10633";

export const categories = [
  ["Narrative", "Stories with a distinct cinematic voice."],
  ["Documentary", "Urgent realities, observed with honesty."],
  ["Short Film", "Compact cinema with lasting impact."],
  ["Animation", "Frame-by-frame worlds without limits."],
  ["Experimental", "Form, image and sound reimagined."],
  ["Underground", "Independent work beyond convention."],
  ["Music Video", "Music translated into moving image."],
  ["Student Film", "The next generation, in focus."],
  ["First Film", "A bold first step into cinema."],
  ["AI Film", "Human vision meeting new technology."],
  ["New Media", "Stories built for emerging formats."],
  ["Screenplay", "Cinema beginning on the page."],
  ["Photography", "A complete story in a single frame."],
] as const;

export const dates = [
  ["5 OCT 2026", "Regular Deadline"],
  ["1 NOV 2026", "Late Deadline"],
  ["21 NOV 2026", "Extended · Scripts & Photos"],
  ["21 DEC 2026", "Official Selection"],
  ["24 JAN 2027", "Berlin Event"],
] as const;

export const articles = [
  { slug: "introducing-berlin-gate", type: "Festival News", date: "12 July 2026", title: "Introducing Berlin Gate", excerpt: "A new international festival for independent voices, born in Berlin.", image: "/images/hero-web.png" },
  { slug: "first-edition", type: "Festival Journal", date: "12 July 2026", title: "The First Edition: From Submission to Berlin", excerpt: "The path, the dates and the thinking behind BGIFF's first edition.", image: "/images/timeline.png" },
  { slug: "cinema-new-forms", type: "Perspectives", date: "12 July 2026", title: "Cinema, New Forms and Human Vision", excerpt: "Why emerging tools matter only when they serve an authentic creative voice.", image: "/images/laurels.png" },
] as const;

export const sampleFilms = [
  { slug: "programme-coming-soon", title: "Official Selection Coming Soon", director: "Announced 21 December 2026", country: "International", duration: "First Edition", image: "/images/hero-web.png", category: "Programme" },
] as const;
