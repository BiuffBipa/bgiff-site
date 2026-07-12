import type { Metadata } from "next";
import "./globals.css";
import Header from "@/components/Header";
import Footer from "@/components/Footer";

export const metadata: Metadata = {title:{default:"BGIFF — Berlin Gate International Film Festival",template:"%s — BGIFF"},description:"Berlin Gate International Film Festival. Independent world cinema, from every gate.",metadataBase:new URL("https://bgiff.com"),openGraph:{title:"Berlin Gate International Film Festival",description:"Independent world cinema, from every gate.",images:["/images/hero-web.png"]}};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="en"><body><Header/><main>{children}</main><Footer/></body></html>}
