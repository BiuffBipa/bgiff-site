"use client";
import Link from "next/link";
import Image from "next/image";
import { useState } from "react";
import RevealBar from "@/components/RevealBar";

const links = [["Festival","/festival"],["Submit","/submit"],["Writing","/writing"],["Awards","/awards"],["Programme","/programme"],["Journal","/journal"],["Contact","/contact"]];
export default function Header(){
 const [open,setOpen]=useState(false);
 return <><RevealBar/><header className="site-header"><Link href="/" className="brand"><Image src="/images/logo.png" alt="BGIFF" width={50} height={50}/><span>BERLIN GATE</span></Link>
 <button className="menu-toggle" aria-label="Toggle menu" onClick={()=>setOpen(!open)}>{open?"×":"☰"}</button>
 <nav className={open?"open":""}>{links.map(([n,h])=><Link key={h} href={h} onClick={()=>setOpen(false)}>{n}</Link>)}<Link className="button button-small" href="/submit" onClick={()=>setOpen(false)}>Enter your film</Link></nav></header></>
}
