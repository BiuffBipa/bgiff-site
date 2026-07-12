"use client";
import Link from "next/link";
import Image from "next/image";
import { useState } from "react";
import { submitUrl } from "@/lib/data";

const links = [["Festival","/festival"],["Submit","/submit"],["Awards","/awards"],["Programme","/programme"],["Journal","/journal"],["Contact","/contact"]];
export default function Header(){
 const [open,setOpen]=useState(false);
 return <header className="site-header"><Link href="/" className="brand"><Image src="/images/logo.png" alt="BGIFF" width={50} height={50}/><span>BERLIN GATE</span></Link>
 <button className="menu-toggle" aria-label="Toggle menu" onClick={()=>setOpen(!open)}>{open?"×":"☰"}</button>
 <nav className={open?"open":""}>{links.map(([n,h])=><Link key={h} href={h} onClick={()=>setOpen(false)}>{n}</Link>)}<a className="button button-small" href={submitUrl} target="_blank">Submit your work</a></nav></header>
}
