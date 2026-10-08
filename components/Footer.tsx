import Link from "next/link";
import {festhomeUrl,instagramUrl,submitUrl} from "@/lib/data";
export default function Footer(){return <footer>
 <div className="footer-brand"><div className="mark">BGIFF</div><p>Where cinema<br/>crosses borders.</p><p className="footer-gate">The gate is open until 1 November 2026.</p></div>
 <div><h4>Festival</h4><Link href="/festival">About</Link><Link href="/festival#reveal">The route to Berlin</Link><Link href="/awards">Awards</Link><Link href="/programme">Programme</Link><a href={instagramUrl} target="_blank" rel="noopener noreferrer">Instagram</a></div>
 <div><h4>Enter</h4><Link href="/submit#categories">Film categories</Link><Link href="/submit#dates">Dates</Link><Link href="/submit#rules">Rules & FAQ</Link><a href={submitUrl} target="_blank" rel="noopener noreferrer">FilmFreeway</a><a href={festhomeUrl} target="_blank" rel="noopener noreferrer">Festhome</a></div>
 <div><h4>Writing</h4><Link href="/writing">Screenplay & Stage Play</Link><Link href="/writing#route">How it works</Link><Link href="/writing#faq">Writing FAQ</Link><h4 className="footer-sub">Journal</h4><Link href="/journal">News</Link></div>
 <div><h4>Legal</h4><Link href="/legal/impressum">Impressum</Link><Link href="/legal/privacy">Privacy</Link><Link href="/legal/terms">Terms</Link><Link href="/legal/cookies">Cookies</Link></div>
 <div className="footer-bottom">Berlin Gate International Film Festival · First Edition · Berlin 2027 · <a className="inline" href="mailto:submissions@bgiff.com">submissions@bgiff.com</a> · © 2026</div>
</footer>}
