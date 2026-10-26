import type {MetadataRoute} from 'next';

export default function sitemap():MetadataRoute.Sitemap {
 const siteUrl=process.env.NEXT_PUBLIC_SITE_URL??'https://sendoh.vercel.app';
 return [{url:new URL('/',siteUrl).href}];
}
