import type {MetadataRoute} from 'next';

export default function robots():MetadataRoute.Robots {
 const siteUrl=process.env.NEXT_PUBLIC_SITE_URL??'https://sendoh.vercel.app';
 return {rules:{userAgent:'*',allow:'/',disallow:['/api/']},sitemap:new URL('/sitemap.xml',siteUrl).href};
}
