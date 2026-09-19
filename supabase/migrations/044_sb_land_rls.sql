-- ============================================================
-- 044_sb_land_rls.sql
-- SB LAND OPERATIONAL ACCESS / RLS
-- ============================================================


-- ============================================================
-- HELPER 1
-- Apakah user adalah MANAGER SB Land aktif pada account ini?
-- ============================================================

CREATE OR REPLACE FUNCTION public.sb_is_manager(
  target_account_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.sb_marketing m
    WHERE m.account_id = target_account_id
      AND m.user_id = auth.uid()
      AND m.status_active = true
      AND m.role = 'MANAGER'
  );
$$;

ALTER FUNCTION public.sb_is_manager(uuid) OWNER TO postgres;

GRANT EXECUTE
ON FUNCTION public.sb_is_manager(uuid)
TO authenticated, service_role;


-- ============================================================
-- HELPER 2
-- Akses user terhadap PROJECT tertentu.
--
-- TRUE jika:
-- 1. WACRM owner/admin account
-- 2. SB Land Manager aktif
-- 3. SPV memiliki scope project
-- 4. Marketing aktif pada project
-- ============================================================

CREATE OR REPLACE FUNCTION public.sb_has_project_access(
  target_account_id uuid,
  target_project_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.sb_projects p
    WHERE p.id = target_project_id
      AND p.account_id = target_account_id
      AND (
        public.is_account_member(target_account_id, 'admin')
        OR public.sb_is_manager(target_account_id)

        OR EXISTS (
          SELECT 1
          FROM public.sb_user_project_scope s
          WHERE s.account_id = target_account_id
            AND s.project_id = target_project_id
            AND s.user_id = auth.uid()
            AND s.status_active = true
            AND s.scope_role IN ('SPV', 'MANAGER')
        )

        OR EXISTS (
          SELECT 1
          FROM public.sb_marketing_projects mp
          JOIN public.sb_marketing m
            ON m.account_id = mp.account_id
           AND m.user_id = mp.marketing_user_id

          WHERE mp.account_id = target_account_id
            AND mp.project_id = target_project_id
            AND mp.marketing_user_id = auth.uid()
            AND mp.status_active = true

            AND m.status_active = true
            AND m.role = 'MARKETING'
        )
      )
  );
$$;

ALTER FUNCTION public.sb_has_project_access(uuid, uuid)
OWNER TO postgres;

GRANT EXECUTE
ON FUNCTION public.sb_has_project_access(uuid, uuid)
TO authenticated, service_role;


-- ============================================================
-- HELPER 3
-- Apakah user adalah PIC CURRENT lead?
--
-- Mengikuti WACRM:
-- conversations.assigned_agent_id = auth.uid()
-- ============================================================

CREATE OR REPLACE FUNCTION public.sb_is_current_pic(
  target_lead_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1

    FROM public.sb_leads l

    JOIN public.conversations c
      ON c.id = l.current_conversation_id

    JOIN public.sb_marketing m
      ON m.account_id = l.account_id
     AND m.user_id = auth.uid()

    JOIN public.sb_marketing_projects mp
      ON mp.account_id = l.account_id
     AND mp.marketing_user_id = auth.uid()
     AND mp.project_id = l.project_id

    WHERE l.id = target_lead_id

      AND c.assigned_agent_id = auth.uid()

      AND m.status_active = true
      AND m.role = 'MARKETING'

      AND mp.status_active = true
  );
$$;

ALTER FUNCTION public.sb_is_current_pic(uuid)
OWNER TO postgres;

GRANT EXECUTE
ON FUNCTION public.sb_is_current_pic(uuid)
TO authenticated, service_role;


-- ============================================================
-- HELPER 4
-- Akses terhadap LEAD.
--
-- Owner/Admin  -> seluruh account
-- Manager      -> seluruh account
-- SPV          -> sesuai project scope
-- Marketing    -> hanya jika current PIC
-- ============================================================

CREATE OR REPLACE FUNCTION public.sb_can_access_lead(
  target_lead_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1

    FROM public.sb_leads l

    WHERE l.id = target_lead_id
      AND (
        public.is_account_member(l.account_id, 'admin')

        OR public.sb_is_manager(l.account_id)

        OR EXISTS (
          SELECT 1
          FROM public.sb_user_project_scope s
          WHERE s.account_id = l.account_id
            AND s.project_id = l.project_id
            AND s.user_id = auth.uid()
            AND s.status_active = true
            AND s.scope_role IN ('SPV', 'MANAGER')
        )

        OR public.sb_is_current_pic(l.id)
      )
  );
$$;

ALTER FUNCTION public.sb_can_access_lead(uuid)
OWNER TO postgres;

GRANT EXECUTE
ON FUNCTION public.sb_can_access_lead(uuid)
TO authenticated, service_role;


-- ============================================================
-- DROP POLICY SAFELY
-- ============================================================


-- sb_projects
DROP POLICY IF EXISTS sb_projects_select
ON public.sb_projects;

DROP POLICY IF EXISTS sb_projects_insert
ON public.sb_projects;

DROP POLICY IF EXISTS sb_projects_update
ON public.sb_projects;

DROP POLICY IF EXISTS sb_projects_delete
ON public.sb_projects;


-- sb_marketing
DROP POLICY IF EXISTS sb_marketing_select
ON public.sb_marketing;

DROP POLICY IF EXISTS sb_marketing_insert
ON public.sb_marketing;

DROP POLICY IF EXISTS sb_marketing_update
ON public.sb_marketing;

DROP POLICY IF EXISTS sb_marketing_delete
ON public.sb_marketing;


-- sb_marketing_projects
DROP POLICY IF EXISTS sb_marketing_projects_select
ON public.sb_marketing_projects;

DROP POLICY IF EXISTS sb_marketing_projects_insert
ON public.sb_marketing_projects;

DROP POLICY IF EXISTS sb_marketing_projects_update
ON public.sb_marketing_projects;

DROP POLICY IF EXISTS sb_marketing_projects_delete
ON public.sb_marketing_projects;


-- sb_user_project_scope
DROP POLICY IF EXISTS sb_user_project_scope_select
ON public.sb_user_project_scope;

DROP POLICY IF EXISTS sb_user_project_scope_insert
ON public.sb_user_project_scope;

DROP POLICY IF EXISTS sb_user_project_scope_update
ON public.sb_user_project_scope;

DROP POLICY IF EXISTS sb_user_project_scope_delete
ON public.sb_user_project_scope;


-- sb_lead_distribution_policy
DROP POLICY IF EXISTS sb_distribution_select
ON public.sb_lead_distribution_policy;

DROP POLICY IF EXISTS sb_distribution_insert
ON public.sb_lead_distribution_policy;

DROP POLICY IF EXISTS sb_distribution_update
ON public.sb_lead_distribution_policy;

DROP POLICY IF EXISTS sb_distribution_delete
ON public.sb_lead_distribution_policy;


-- sb_leads
DROP POLICY IF EXISTS sb_leads_select
ON public.sb_leads;

DROP POLICY IF EXISTS sb_leads_insert
ON public.sb_leads;

DROP POLICY IF EXISTS sb_leads_update
ON public.sb_leads;

DROP POLICY IF EXISTS sb_leads_delete
ON public.sb_leads;


-- sb_conversation_state
DROP POLICY IF EXISTS sb_state_select
ON public.sb_conversation_state;

DROP POLICY IF EXISTS sb_state_insert
ON public.sb_conversation_state;

DROP POLICY IF EXISTS sb_state_update
ON public.sb_conversation_state;

DROP POLICY IF EXISTS sb_state_delete
ON public.sb_conversation_state;


-- sb_pic_assignment_log
DROP POLICY IF EXISTS sb_assignment_log_select
ON public.sb_pic_assignment_log;


-- ============================================================
-- 1. SB_PROJECTS
-- ============================================================

CREATE POLICY sb_projects_select
ON public.sb_projects
FOR SELECT
USING (
  public.sb_has_project_access(account_id, id)
);

CREATE POLICY sb_projects_insert
ON public.sb_projects
FOR INSERT
WITH CHECK (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
);

CREATE POLICY sb_projects_update
ON public.sb_projects
FOR UPDATE
USING (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
)
WITH CHECK (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
);

CREATE POLICY sb_projects_delete
ON public.sb_projects
FOR DELETE
USING (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
);


-- ============================================================
-- 2. SB_MARKETING
--
-- Semua member account boleh melihat roster/nama.
-- Perubahan hanya Admin / Manager.
-- ============================================================

CREATE POLICY sb_marketing_select
ON public.sb_marketing
FOR SELECT
USING (
  public.is_account_member(account_id)
);

CREATE POLICY sb_marketing_insert
ON public.sb_marketing
FOR INSERT
WITH CHECK (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
);

CREATE POLICY sb_marketing_update
ON public.sb_marketing
FOR UPDATE
USING (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
)
WITH CHECK (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
);

CREATE POLICY sb_marketing_delete
ON public.sb_marketing
FOR DELETE
USING (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
);


-- ============================================================
-- 3. SB_MARKETING_PROJECTS
-- ============================================================

CREATE POLICY sb_marketing_projects_select
ON public.sb_marketing_projects
FOR SELECT
USING (
  public.sb_has_project_access(account_id, project_id)
);

CREATE POLICY sb_marketing_projects_insert
ON public.sb_marketing_projects
FOR INSERT
WITH CHECK (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
);

CREATE POLICY sb_marketing_projects_update
ON public.sb_marketing_projects
FOR UPDATE
USING (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
)
WITH CHECK (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
);

CREATE POLICY sb_marketing_projects_delete
ON public.sb_marketing_projects
FOR DELETE
USING (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
);


-- ============================================================
-- 4. SB_USER_PROJECT_SCOPE
-- ============================================================

CREATE POLICY sb_user_project_scope_select
ON public.sb_user_project_scope
FOR SELECT
USING (
  user_id = auth.uid()
  OR public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
);

CREATE POLICY sb_user_project_scope_insert
ON public.sb_user_project_scope
FOR INSERT
WITH CHECK (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
);

CREATE POLICY sb_user_project_scope_update
ON public.sb_user_project_scope
FOR UPDATE
USING (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
)
WITH CHECK (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
);

CREATE POLICY sb_user_project_scope_delete
ON public.sb_user_project_scope
FOR DELETE
USING (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
);


-- ============================================================
-- 5. DISTRIBUTION POLICY
--
-- Marketing dapat membaca policy project tempat dia aktif.
-- Hanya Admin / Manager dapat mengubah bobot.
-- ============================================================

CREATE POLICY sb_distribution_select
ON public.sb_lead_distribution_policy
FOR SELECT
USING (
  public.sb_has_project_access(account_id, project_id)
);

CREATE POLICY sb_distribution_insert
ON public.sb_lead_distribution_policy
FOR INSERT
WITH CHECK (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
);

CREATE POLICY sb_distribution_update
ON public.sb_lead_distribution_policy
FOR UPDATE
USING (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
)
WITH CHECK (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
);

CREATE POLICY sb_distribution_delete
ON public.sb_lead_distribution_policy
FOR DELETE
USING (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
);


-- ============================================================
-- 6. SB_LEADS
--
-- Marketing: current PIC
-- SPV: project scope
-- Manager/Admin: full account
--
-- Creation utama dilakukan service_role / n8n.
-- ============================================================

CREATE POLICY sb_leads_select
ON public.sb_leads
FOR SELECT
USING (
  public.sb_can_access_lead(id)
);

CREATE POLICY sb_leads_insert
ON public.sb_leads
FOR INSERT
WITH CHECK (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
);

CREATE POLICY sb_leads_update
ON public.sb_leads
FOR UPDATE
USING (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
)
WITH CHECK (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
);

CREATE POLICY sb_leads_delete
ON public.sb_leads
FOR DELETE
USING (
  public.is_account_member(account_id, 'admin')
);


-- ============================================================
-- 7. SB_CONVERSATION_STATE
--
-- Marketing current PIC boleh READ + UPDATE.
-- Insert biasanya dilakukan n8n/service_role.
-- ============================================================

CREATE POLICY sb_state_select
ON public.sb_conversation_state
FOR SELECT
USING (
  public.sb_can_access_lead(lead_id)
);

CREATE POLICY sb_state_insert
ON public.sb_conversation_state
FOR INSERT
WITH CHECK (
  public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)
);

CREATE POLICY sb_state_update
ON public.sb_conversation_state
FOR UPDATE
USING (
  public.sb_is_current_pic(lead_id)
  OR public.is_account_member(account_id, 'admin')
  OR public.sb_is_manager(account_id)

  OR EXISTS (
    SELECT 1
    FROM public.sb_leads l
    JOIN public.sb_user_project_scope s
      ON s.account_id = l.account_id
     AND s.project_id = l.project_id
    WHERE l.id = sb_conversation_state.lead_id
      AND s.user_id = auth.uid()
      AND s.status_active = true
      AND s.scope_role = 'SPV'
  )
)
WITH CHECK (
  public.sb_can_access_lead(lead_id)
);

CREATE POLICY sb_state_delete
ON public.sb_conversation_state
FOR DELETE
USING (
  public.is_account_member(account_id, 'admin')
);


-- ============================================================
-- 8. PIC ASSIGNMENT LOG
--
-- Append-only operational audit.
--
-- Marketing -> hanya history miliknya sendiri.
-- SPV       -> project scope.
-- Manager   -> seluruh account.
-- Admin     -> seluruh account.
--
-- INSERT/UPDATE/DELETE tidak diberikan kepada authenticated.
-- n8n/service_role yang menulis audit.
-- ============================================================

CREATE POLICY sb_assignment_log_select
ON public.sb_pic_assignment_log
FOR SELECT
USING (
  marketing_user_id = auth.uid()

  OR public.is_account_member(account_id, 'admin')

  OR public.sb_is_manager(account_id)

  OR EXISTS (
    SELECT 1
    FROM public.sb_user_project_scope s
    WHERE s.account_id = sb_pic_assignment_log.account_id
      AND s.project_id = sb_pic_assignment_log.project_id
      AND s.user_id = auth.uid()
      AND s.status_active = true
      AND s.scope_role = 'SPV'
  )
);


-- ============================================================
-- DATA API PRIVILEGES
--
-- Project dibuat dengan automatic expose tables OFF.
-- Karena itu grants dibuat eksplisit.
-- RLS tetap menjadi lapisan pembatas data.
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.sb_projects
TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.sb_marketing
TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.sb_marketing_projects
TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.sb_user_project_scope
TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.sb_lead_distribution_policy
TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.sb_leads
TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.sb_conversation_state
TO authenticated;

GRANT SELECT
ON public.sb_pic_assignment_log
TO authenticated;


-- Backend / n8n
GRANT ALL
ON public.sb_projects,
   public.sb_marketing,
   public.sb_marketing_projects,
   public.sb_user_project_scope,
   public.sb_lead_distribution_policy,
   public.sb_leads,
   public.sb_conversation_state,
   public.sb_pic_assignment_log
TO service_role;