import Image from "next/image";import {notFound} from "next/navigation";import {articles} from "@/lib/data";
export function generateStaticParams(){return articles.map(a=>({slug:a.slug}));}
function Body({lines}:{lines:readonly string[]}){
 const out:React.ReactNode[]=[];let list:string[]=[];
 const flush=(k:number)=>{if(list.length){out.push(<ul key={`l${k}`}>{list.map(x=><li key={x}>{x}</li>)}</ul>);list=[];}};
 lines.forEach((l,i)=>{if(l.startsWith("— ")){list.push(l.slice(2));return;}flush(i);const last=i===lines.length-1;out.push(<p key={i} className={i===0?"lead":last?"closing-line":undefined}>{l}</p>);});
 flush(lines.length);
 return <>{out}</>;
}
export default async function Article({params}:{params:Promise<{slug:string}>}){const {slug}=await params;const a=articles.find(x=>x.slug===slug);if(!a)notFound();return <article className="article-page"><header><span>{a.type} · {a.date}</span><h1>{a.title}</h1><p>{a.excerpt}</p></header><div className="article-cover"><Image src={a.image} alt="" fill/></div><div className="article-body">{a.body?<><Body lines={a.body}/><p style={{marginTop:50,color:"var(--gold)",fontSize:11,letterSpacing:".16em",textTransform:"uppercase"}}>Berlin Gate International Film Festival</p></>:<><p className="lead">Berlin Gate begins with a simple belief: independent cinema matters when it carries a voice that could belong to no one else.</p><p>This journal is where the festival continues beyond announcements and laurels. It creates space for filmmakers to speak about process, for critics to look closely at the work, and for new forms of cinema to be discussed with curiosity and care.</p><p>More editorial coverage, interviews and reviews will be published as the First Edition develops.</p></>}</div></article>}
