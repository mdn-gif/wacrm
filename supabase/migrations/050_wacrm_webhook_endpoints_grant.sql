-- Allow WACRM server-side webhook delivery and management
-- to access outbound webhook endpoints.
-- RLS remains enabled; no anon access is granted.

GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLE public.webhook_endpoints
TO service_role;