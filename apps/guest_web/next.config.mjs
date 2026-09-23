/** @type {import('next').NextConfig} */
const allowedDevOrigins = (process.env.SENDOH_ALLOWED_DEV_ORIGINS ?? '')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);

const config = {
  devIndicators: false,
  turbopack: {root: process.cwd()},
  ...(allowedDevOrigins.length > 0 ? {allowedDevOrigins} : {}),
};
export default config;
