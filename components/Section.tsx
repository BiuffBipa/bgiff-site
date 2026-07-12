import { ReactNode } from "react";
export default function Section({eyebrow,title,children,id,className=""}:{eyebrow?:string,title?:string,children:ReactNode,id?:string,className?:string}){return <section id={id} className={`section ${className}`}><div className="section-inner">{eyebrow&&<div className="eyebrow">{eyebrow}</div>}{title&&<h2>{title}</h2>}{children}</div></section>}
