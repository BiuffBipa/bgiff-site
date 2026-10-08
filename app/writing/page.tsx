import Section from "@/components/Section";import {festhomeUrl,submitUrl,writingDates} from "@/lib/data";
export const metadata={title:"Writing — Screenplay & Stage Play",description:"Screenplays and stage plays have a gate of their own at Berlin Gate: a selection confirmed in stages, a laurel at every stage, winners in April 2027."};
const route=[
 ["01","Submit","On FilmFreeway or Festhome, until 21 November 2026."],
 ["02","Your script’s page","Opens on bgiff.com by invitation, until 1 December 2026: confirm the details, sign the entry terms, choose the section your script competes in. Further sections can be added there."],
 ["03","Official Selection","Confirmed privately as scripts are read; published on 14 December 2026, with laurels."],
 ["04","Stages","Quarter-Finalist · Semi-Finalist · Finalist · Nominee. Each stage is published on bgiff.com with its own laurel; the next date comes with each announcement."],
 ["05","Winners","April 2027. An award in each section, plus Honorable Mentions."],
];
const receive=[
 ["Official Selection","Laurel, certificate, a page in the Berlin Gate showcase."],
 ["Each stage","A new laurel and an updated showcase page."],
 ["Nominees and winners","Winner laurels and certificates, and a permanent entry in the First Edition record."],
];
const faqs=[
 ["Can I submit a stage play?","Yes. Stage plays are read in their own section."],
 ["Can I submit more than one script?","Yes. Each script has its own page."],
 ["Which language?","English, or any language with a full English translation."],
 ["Will I hear back?","Every script with a claimed page receives its result by 14 December 2026."],
 ["Do I need to come to Berlin?","No. The Writing track is entirely online."],
 ["Who sees my script?","The selection committee and the jury. Scripts are never shared without the writer’s consent; the showcase shows title, logline and writer."],
];
export default function Writing(){return <><div className="page-hero submit-hero"><div><span>Writing · First Edition</span><h1>Most competitions send one email. This one publishes your script’s route.</h1><p>Screenplays and stage plays have a gate of their own at Berlin Gate: a selection confirmed in stages, a laurel on the record at every stage, winners in April 2027. Entirely online. Every date is on this page. The writing route is its own; the film route is published on 24 November.</p><div className="submission-actions"><a href={submitUrl} target="_blank" rel="noopener noreferrer" className="button">Submit on FilmFreeway</a><a href={festhomeUrl} target="_blank" rel="noopener noreferrer" className="button outline">Submit on Festhome</a></div><p style={{marginTop:22,fontSize:11,letterSpacing:".12em",textTransform:"uppercase",color:"#bdb6a8"}}>The gate is open until 21 November 2026</p></div></div>
<Section eyebrow="What we read" title="Every format. Every stage."><div className="split"><p className="lead">Screenplays of any length and format — feature, short, TV pilot, series and web, animation — and stage plays.</p><div><p>Unproduced work, in English or with a full English translation, as PDF. Submit under Feature Screenplay, Short Screenplay or Stage Play; the exact section is chosen on your script’s page.</p></div></div></Section>
<Section id="route" eyebrow="The route" title="From the page to the winners." className="dark-section"><div className="recognition five">{route.map(([n,t,d])=><div key={n}><span>{n}</span><h3>{t}</h3><p style={{color:"#bbb",fontSize:13}}>{d}</p></div>)}</div><div className="date-list" style={{marginTop:70}}>{writingDates.map(([d,n])=><div key={n}><h3>{n}</h3><b>{d}</b></div>)}</div></Section>
<Section eyebrow="What writers receive" title="A laurel at every stage."><p className="lead narrow">No cash prize, no event you must attend. A laurel at every stage, a showcase page that moves with you, and a record of the First Edition that keeps your name. We make sure it is seen.</p><div className="certain-list">{receive.map(([t,d],i)=><div key={t}><span>{String(i+1).padStart(2,"0")}</span><p style={{margin:0}}><b>{t}</b> — {d}</p></div>)}</div></Section>
<Section eyebrow="How scripts are read" title="Read in stages." className="dark-section"><p className="lead narrow">Entries are evaluated through a multi-stage selection process combining technology-assisted analysis with review by our selection committee and jury. Decisions are final.</p></Section>
<Section id="faq" eyebrow="Questions" title="Writing FAQ." className="faq"><div>{faqs.map(([q,a])=><details key={q}><summary>{q}</summary><p>{a}</p></details>)}</div></Section></>}
