GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLE public.whatsapp_config
TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLE public.whatsapp_config
TO service_role;

GRANT SELECT
ON TABLE public.account_invitations
TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLE public.account_invitations
TO service_role;