import Image from "next/image";
import Link from "next/link";
import Section from "@/components/Section";
import {articles,festhomeUrl,route,submitUrl} from "@/lib/data";

const certain = [
  "Your film has a page here from day one — your title, your name, your status, every announcement that concerns it. One place. Yours.",
  "A selected film is watched whole, by people who chose to watch it. Not three minutes of a screener.",
  "The Official Selection is the last time your film is a name on a list. At every stage after it, you know exactly where your film stands, on the date we said.",
  "The First Edition ends in Berlin in 2027: the films that pass the last gate on screen, their makers in the room, the awards — in a city that treats a premiere like a premiere.",
];

const gates = [
  ["Film","Fourteen categories, from feature to music video. The gate is open until 1 November 2026.","/submit#categories"],
  ["Writing","Screenplays of any length, and stage plays. A gate of their own, entirely online, every date published today.","/writing"],
  ["Photography","Cinematic, documentary, conceptual. Open until 21 November 2026.","/submit#photography"],
] as const;

export default function Home(){return <>
 <section className="hero long"><Image src="/images/hero-clean.png" alt="Berlin Gate International Film Festival" fill priority sizes="100vw" className="hero-image"/><div className="hero-shade"/><div className="hero-content"><div className="eyebrow">First Edition · Berlin · 2027</div><h1>Most festivals end at the Official Selection.<br/><span>Berlin Gate begins there.</span></h1><p>On 23 January 2027, the gates open. From that day a selected film is in play: stage after stage, each one dated, each one public, each one watched. How it gets from there to Berlin is written, dated and sealed — and published on 24 November 2026, before a single film is selected.</p><div className="actions"><Link href="/submit" className="button">Enter your film</Link><Link href="/festival#reveal" className="text-link">The route to Berlin <b>↗</b></Link></div><p className="hero-note">Submit on FilmFreeway or Festhome · The gate closes 1 November 2026</p><div className="hero-date"><b>24.11</b><span>2026<br/>THE REVEAL</span></div></div><div className="scroll-cue">SCROLL TO ENTER <i/></div></section>

 <Section eyebrow="Born in Berlin" title="This is Berlin’s habit, applied to cinema." className="intro"><div className="split"><p className="lead">The city had a wall and turned it into a gallery. It had a gate that stood shut for twenty-eight years and made it the one picture of itself the world keeps.</p><div><p>Berlin does not repeat the old form. It invents the new one, and then everyone arrives. Berlin Gate was founded here, for independent film, to do exactly that.</p><Link href="/festival" className="text-link">Our story <b>↗</b></Link></div></div></Section>

 <Section id="dates" eyebrow="The route to Berlin" title="The milestones are published once. They do not move." className="timeline-section"><div className="timeline six">{route.map(([date,name],i)=><div className="milestone" key={name}><span>0{i+1}</span><i/><h3>{name}</h3><p>{date}</p></div>)}</div><p className="route-note">The dates between 23 January and Berlin are published on 24 November 2026.</p></Section>

 <Section eyebrow="First Edition" title="What is certain today."><div className="certain-list">{certain.map((x,i)=><div key={i}><span>{String(i+1).padStart(2,"0")}</span><p style={{margin:0}}>{x}</p></div>)}</div></Section>

 <Section eyebrow="Three gates" title="Three ways into the First Edition." className="dark-section"><div className="gate-grid">{gates.map(([n,d,h],i)=><Link href={h} key={n}><span>{String(i+1).padStart(2,"0")}</span><h3>{n}</h3><p>{d}</p><b>↗</b></Link>)}</div></Section>

 <Section eyebrow="Highest Honour" title="The Berlin Gate Grand Prize." className="prize-section"><div className="prize-grid"><div className="trophy"><Image src="/images/trophy.png" alt="Berlin Gate Grand Prize trophy" fill sizes="(max-width: 800px) 100vw, 45vw"/></div><div className="prize-copy"><p className="lead">The festival’s highest distinction, honouring one work that brings originality, craft, creative courage and lasting impact together.</p><ul><li>The Berlin Gate trophy</li><li>The Grand Prize title and laurel</li><li>The festival certificate</li><li>A feature in the Journal</li></ul><Link href="/awards" className="button outline">Discover the awards</Link></div></div></Section>

 <Section eyebrow="Editorial" title="From the BGIFF Journal." className="dark-section"><div className="article-grid">{articles.slice(0,3).map(a=><Link href={`/journal/${a.slug}`} key={a.slug} className="article-card"><div className="article-image"><Image src={a.image} alt="" fill sizes="(max-width:800px) 100vw, 33vw"/></div><span>{a.type} · {a.date}</span><h3>{a.title}</h3><p>{a.excerpt}</p></Link>)}</div><Link href="/journal" className="button outline">Visit the journal</Link></Section>

 <section className="closing"><div className="closing-mark">BGIFF</div><p>There will be other editions. There is only one first.</p><h2>Your film<br/>belongs in Berlin.</h2><p>The gate is open until 1 November 2026.</p><div className="actions"><a href={submitUrl} target="_blank" rel="noopener noreferrer" className="button">Submit on FilmFreeway</a><a href={festhomeUrl} target="_blank" rel="noopener noreferrer" className="button outline">Submit on Festhome</a></div></section>
 </>}
