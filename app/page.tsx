import Image from "next/image";
import Link from "next/link";
import Section from "@/components/Section";
import {articles,categories,dates,submitUrl} from "@/lib/data";

export default function Home(){return <>
 <section className="hero"><Image src="/images/hero-web.png" alt="Berlin Gate International Film Festival" fill priority sizes="100vw" className="hero-image"/><div className="hero-shade"/><div className="hero-content"><div className="eyebrow">First Edition · Berlin</div><h1>Where cinema<br/><span>crosses borders.</span></h1><p>Independent world cinema, from every gate.</p><div className="actions"><a href={submitUrl} target="_blank" className="button">Submit your work</a><Link href="/festival" className="text-link">Discover the festival <b>↗</b></Link></div><div className="hero-date"><b>23</b><span>JANUARY<br/>2027</span></div></div><div className="scroll-cue">SCROLL TO ENTER <i/></div></section>

 <Section eyebrow="Berlin Gate · International Film Festival" title="This isn’t just another film festival — it’s a gateway." className="intro"><div className="split"><p className="lead">Born in Berlin, BGIFF is an international home for bold filmmaking, creative risk-taking and visual storytelling in every form.</p><div><p>We are here to find real talent and give independent work somewhere to be seen. A platform for filmmakers, screenwriters and photographers who dare to be different.</p><Link href="/festival" className="text-link">Our story <b>↗</b></Link></div></div></Section>

 <Section eyebrow="Competition" title="Every form. One gate." className="dark-section"><div className="category-grid">{categories.map(([name,desc],i)=><Link href="/submit#categories" className="category" key={name}><span>{String(i+1).padStart(2,"0")}</span><h3>{name}</h3><p>{desc}</p><b>↗</b></Link>)}</div></Section>

 <Section eyebrow="Recognition" title="One entry. Every relevant opportunity."><div className="split"><p className="lead">Enter once in the appropriate category. Your work is also considered for every relevant craft, technical, thematic and special honour.</p><div className="path-list">{["Submission","Official Selection","Nominee","Award Winner","Berlin Gate Grand Prize"].map((x,i)=><div key={x} className="path-item"><span>{String(i+1).padStart(2,"0")}</span>{x}</div>)}</div></div></Section>

 <Section id="dates" eyebrow="The First Edition" title="From submission to Berlin." className="timeline-section"><div className="timeline">{dates.map(([date,name],i)=><div className="milestone" key={name}><span>0{i+1}</span><i/><h3>{name}</h3><p>{date}</p></div>)}</div><div className="wide-image"><Image src="/images/timeline.png" alt="BGIFF First Edition timeline" fill sizes="100vw"/></div></Section>

 <Section eyebrow="Highest Honour" title="The Berlin Gate Grand Prize." className="prize-section"><div className="prize-grid"><div className="trophy"><Image src="/images/trophy.png" alt="Berlin Gate Grand Prize trophy" fill sizes="(max-width: 800px) 100vw, 45vw"/></div><div className="prize-copy"><p className="lead">The festival’s highest distinction, honouring one outstanding work that brings originality, craft, creative courage and lasting impact together.</p><ul><li>Exclusive Berlin Gate trophy</li><li>Official Grand Prize title and laurel</li><li>Festival certificate</li><li>Special editorial feature</li></ul><Link href="/awards" className="button outline">Discover the awards</Link></div></div></Section>

 <Section eyebrow="23 January 2027" title="It all comes together in Berlin." className="berlin"><div className="event-facts"><div><b>01</b><span>Selected<br/>screenings</span></div><div><b>02</b><span>Talks &<br/>encounters</span></div><div><b>03</b><span>Winner<br/>announcements</span></div></div><p>The full screening and event programme will be announced after the Official Selection.</p><Link href="/programme" className="text-link">Explore the programme <b>↗</b></Link></Section>

 <Section eyebrow="Editorial" title="From the BGIFF Journal." className="dark-section"><div className="article-grid">{articles.map(a=><Link href={`/journal/${a.slug}`} key={a.slug} className="article-card"><div className="article-image"><Image src={a.image} alt="" fill sizes="(max-width:800px) 100vw, 33vw"/></div><span>{a.type} · {a.date}</span><h3>{a.title}</h3><p>{a.excerpt}</p></Link>)}</div><Link href="/journal" className="button outline">Visit the journal</Link></Section>

 <section className="closing"><div className="closing-mark">BGIFF</div><h2>Your film<br/>belongs in Berlin.</h2><p>Submissions open 20 July 2026.</p><a href={submitUrl} target="_blank" className="button">Submit on FilmFreeway</a></section>
 </>}
