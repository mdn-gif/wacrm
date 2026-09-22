-- ============================================================
-- 057_wacrm_conversation_visibility.sql
--
-- SB Land Inbox visibility rules
--
-- Owner/Admin:
--   - dapat melihat seluruh conversation dalam account
--
-- Agent:
--   - hanya dapat melihat conversation yang assigned_agent_id
--     sama dengan auth.uid()
--
-- Viewer:
--   - tidak mendapatkan akses conversation melalui policy ini
--
-- service_role:
--   - tetap dapat bekerja karena service_role bypass RLS
-- ============================================================

DROP POLICY IF EXISTS conversations_select ON public.conversations;

CREATE POLICY conversations_select
ON public.conversations
FOR SELECT
USING (
  -- Owner / Admin dapat melihat semua conversation di account
  is_account_member(account_id, 'admin')

  OR

  -- Agent hanya dapat melihat conversation yang ditugaskan kepadanya
  (
    is_account_member(account_id, 'agent')
    AND assigned_agent_id = auth.uid()
  )
);