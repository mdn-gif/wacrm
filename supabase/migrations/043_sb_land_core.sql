-- ============================================================
-- 043_sb_land_core.sql
-- SB LAND CUSTOM CORE DATABASE
-- ============================================================

-- ============================================================
-- UPDATED_AT HELPER
-- ============================================================

CREATE OR REPLACE FUNCTION public.sb_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


-- ============================================================
-- 1. PROJECT MASTER
-- ============================================================

CREATE TABLE public.sb_projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  account_id uuid NOT NULL
    REFERENCES public.accounts(id) ON DELETE CASCADE,

  project_code text NOT NULL,
  project_name text NOT NULL,
  area_name text,

  status_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (account_id, project_code)
);

CREATE INDEX idx_sb_projects_account
ON public.sb_projects(account_id);

CREATE TRIGGER trg_sb_projects_updated_at
BEFORE UPDATE ON public.sb_projects
FOR EACH ROW
EXECUTE FUNCTION public.sb_set_updated_at();


-- ============================================================
-- 2. MARKETING / SPV / MANAGER MASTER
-- ============================================================

CREATE TABLE public.sb_marketing (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  account_id uuid NOT NULL
    REFERENCES public.accounts(id) ON DELETE CASCADE,

  user_id uuid NOT NULL
    REFERENCES auth.users(id) ON DELETE RESTRICT,

  status_active boolean NOT NULL DEFAULT true,

  role text NOT NULL
    CHECK (
      role IN (
        'MARKETING',
        'SPV',
        'MANAGER'
      )
    ),

  -- Urutan fallback / dasar Round Robin.
  base_order integer,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (account_id, user_id)
);

CREATE INDEX idx_sb_marketing_active
ON public.sb_marketing(
  account_id,
  status_active,
  role
);

CREATE TRIGGER trg_sb_marketing_updated_at
BEFORE UPDATE ON public.sb_marketing
FOR EACH ROW
EXECUTE FUNCTION public.sb_set_updated_at();


-- ============================================================
-- 3. MARKETING <-> PROJECT MEMBERSHIP
-- Satu marketing dapat aktif di beberapa project.
-- ============================================================

CREATE TABLE public.sb_marketing_projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  account_id uuid NOT NULL
    REFERENCES public.accounts(id) ON DELETE CASCADE,

  marketing_user_id uuid NOT NULL
    REFERENCES auth.users(id) ON DELETE RESTRICT,

  project_id uuid NOT NULL
    REFERENCES public.sb_projects(id) ON DELETE CASCADE,

  status_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (
    account_id,
    marketing_user_id,
    project_id
  )
);

CREATE INDEX idx_sb_marketing_projects_lookup
ON public.sb_marketing_projects(
  account_id,
  project_id,
  status_active
);

CREATE TRIGGER trg_sb_marketing_projects_updated_at
BEFORE UPDATE ON public.sb_marketing_projects
FOR EACH ROW
EXECUTE FUNCTION public.sb_set_updated_at();


-- ============================================================
-- 4. USER PROJECT SCOPE
-- Terutama untuk scope SPV.
--
-- Contoh:
-- Dhani -> TW / CDW / Citaman
-- Roy   -> GMC
-- ============================================================

CREATE TABLE public.sb_user_project_scope (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  account_id uuid NOT NULL
    REFERENCES public.accounts(id) ON DELETE CASCADE,

  user_id uuid NOT NULL
    REFERENCES auth.users(id) ON DELETE RESTRICT,

  project_id uuid NOT NULL
    REFERENCES public.sb_projects(id) ON DELETE CASCADE,

  scope_role text NOT NULL
    CHECK (
      scope_role IN (
        'SPV',
        'MANAGER'
      )
    ),

  status_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (
    account_id,
    user_id,
    project_id,
    scope_role
  )
);

CREATE INDEX idx_sb_user_project_scope_lookup
ON public.sb_user_project_scope(
  account_id,
  user_id,
  project_id,
  status_active
);

CREATE TRIGGER trg_sb_user_project_scope_updated_at
BEFORE UPDATE ON public.sb_user_project_scope
FOR EACH ROW
EXECUTE FUNCTION public.sb_set_updated_at();


-- ============================================================
-- 5. LEAD DISTRIBUTION POLICY
--
-- Bobot dan urutan ditentukan manual.
-- Policy dapat berubah per project / per periode.
-- ============================================================

CREATE TABLE public.sb_lead_distribution_policy (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  account_id uuid NOT NULL
    REFERENCES public.accounts(id) ON DELETE CASCADE,

  -- Gunakan tanggal awal periode.
  -- Contoh: 2026-09-01
  period date NOT NULL,

  project_id uuid NOT NULL
    REFERENCES public.sb_projects(id) ON DELETE CASCADE,

  marketing_user_id uuid NOT NULL
    REFERENCES auth.users(id) ON DELETE RESTRICT,

  status_active boolean NOT NULL DEFAULT true,

  weight numeric(10,2) NOT NULL DEFAULT 0
    CHECK (weight >= 0),

  priority_order integer,

  notes text,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (
    account_id,
    period,
    project_id,
    marketing_user_id
  )
);

CREATE INDEX idx_sb_distribution_policy_lookup
ON public.sb_lead_distribution_policy(
  account_id,
  period,
  project_id,
  status_active
);

CREATE TRIGGER trg_sb_distribution_policy_updated_at
BEFORE UPDATE ON public.sb_lead_distribution_policy
FOR EACH ROW
EXECUTE FUNCTION public.sb_set_updated_at();


-- ============================================================
-- 6. LEAD MASTER
--
-- CONTACT      = customer
-- LEAD         = peluang / buying cycle
-- CONVERSATION = thread komunikasi WACRM
-- ============================================================

CREATE TABLE public.sb_leads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  account_id uuid NOT NULL
    REFERENCES public.accounts(id) ON DELETE CASCADE,

  contact_id uuid NOT NULL
    REFERENCES public.contacts(id) ON DELETE RESTRICT,

  project_id uuid NOT NULL
    REFERENCES public.sb_projects(id) ON DELETE RESTRICT,

  current_conversation_id uuid
    REFERENCES public.conversations(id) ON DELETE SET NULL,

  lead_status text NOT NULL DEFAULT 'ACTIVE'
    CHECK (
      lead_status IN (
        'ACTIVE',
        'WON',
        'LOST',
        'CLOSED'
      )
    ),

  -- Contoh:
  -- META_ADS
  -- ORGANIC
  -- DATABASE
  -- REFERRAL
  source_type text,

  opened_at timestamptz NOT NULL DEFAULT now(),
  closed_at timestamptz,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);


-- Satu customer + satu project hanya boleh
-- memiliki satu lead ACTIVE pada saat bersamaan.

CREATE UNIQUE INDEX sb_leads_one_active_per_contact_project
ON public.sb_leads (
  account_id,
  contact_id,
  project_id
)
WHERE lead_status = 'ACTIVE';


CREATE INDEX idx_sb_leads_contact
ON public.sb_leads(
  account_id,
  contact_id
);

CREATE INDEX idx_sb_leads_project_status
ON public.sb_leads(
  account_id,
  project_id,
  lead_status
);

CREATE INDEX idx_sb_leads_conversation
ON public.sb_leads(current_conversation_id);

CREATE TRIGGER trg_sb_leads_updated_at
BEFORE UPDATE ON public.sb_leads
FOR EACH ROW
EXECUTE FUNCTION public.sb_set_updated_at();


-- ============================================================
-- 7. CURRENT LEAD / CONVERSATION STATE
--
-- Tabel ini hanya menyimpan kondisi SEKARANG.
-- History PIC disimpan pada sb_pic_assignment_log.
-- ============================================================

CREATE TABLE public.sb_conversation_state (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  account_id uuid NOT NULL
    REFERENCES public.accounts(id) ON DELETE CASCADE,

  lead_id uuid NOT NULL
    REFERENCES public.sb_leads(id) ON DELETE CASCADE,

  conversation_id uuid
    REFERENCES public.conversations(id) ON DELETE SET NULL,

  interaction_type text NOT NULL DEFAULT 'NEW_LEAD'
    CHECK (
      interaction_type IN (
        'NEW_LEAD',
        'RETURNING_LEAD'
      )
    ),

  conversation_state text NOT NULL DEFAULT 'NEW_LEAD'
    CHECK (
      conversation_state IN (
        'NEW_LEAD',
        'WAITING_MARKETING',
        'REASSIGNING',
        'AI_BACKUP',
        'HUMAN_HANDLED',
        'CLOSED'
      )
    ),

  marketing_handle_status text NOT NULL DEFAULT 'NOT_HANDLED'
    CHECK (
      marketing_handle_status IN (
        'NOT_HANDLED',
        'HANDLED',
        'RELEASED'
      )
    ),

  -- TRUE setelah human valid Take Over.
  ownership_locked boolean NOT NULL DEFAULT false,

  -- Jam nol NEW LEAD.
  -- Tidak reset ketika auto-reassign.
  lead_started_at timestamptz,

  -- Assignment PIC current.
  assign_time timestamptz,

  -- Human takeover / handle.
  handle_time timestamptz,

  -- Total waktu dari lead masuk sampai human pertama handle.
  lead_response_minutes numeric(10,2),

  -- Response PIC current sejak assignment.
  current_pic_response_minutes numeric(10,2),

  sla_status text NOT NULL DEFAULT 'UNKNOWN'
    CHECK (
      sla_status IN (
        'ON_TIME',
        'SLOW_RESPONSE',
        'UNKNOWN'
      )
    ),

  ai_status_detail text NOT NULL DEFAULT 'AI_ACTIVE'
    CHECK (
      ai_status_detail IN (
        'AI_ACTIVE',
        'STANDBY',
        'AI_BACKUP',
        'STOP_AI'
      )
    ),

  survey_status text NOT NULL DEFAULT 'NOT_SCHEDULED'
    CHECK (
      survey_status IN (
        'NOT_SCHEDULED',
        'SCHEDULED',
        'RESCHEDULED',
        'DONE',
        'CANCELLED'
      )
    ),

  survey_at timestamptz,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- Satu lead hanya memiliki satu current state.
  UNIQUE (lead_id)
);

CREATE INDEX idx_sb_state_conversation
ON public.sb_conversation_state(conversation_id);

CREATE INDEX idx_sb_state_status
ON public.sb_conversation_state(
  account_id,
  conversation_state
);

CREATE INDEX idx_sb_state_ai
ON public.sb_conversation_state(
  account_id,
  ai_status_detail
);

CREATE INDEX idx_sb_state_handle
ON public.sb_conversation_state(
  account_id,
  marketing_handle_status,
  ownership_locked
);

CREATE TRIGGER trg_sb_conversation_state_updated_at
BEFORE UPDATE ON public.sb_conversation_state
FOR EACH ROW
EXECUTE FUNCTION public.sb_set_updated_at();


-- ============================================================
-- 8. PIC ASSIGNMENT / KPI HISTORY
--
-- Setiap assignment dibuat sebagai record baru.
-- History PIC lama tidak ditimpa.
-- ============================================================

CREATE TABLE public.sb_pic_assignment_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  account_id uuid NOT NULL
    REFERENCES public.accounts(id) ON DELETE CASCADE,

  lead_id uuid NOT NULL
    REFERENCES public.sb_leads(id) ON DELETE CASCADE,

  conversation_id uuid
    REFERENCES public.conversations(id) ON DELETE SET NULL,

  project_id uuid NOT NULL
    REFERENCES public.sb_projects(id) ON DELETE RESTRICT,

  previous_marketing_user_id uuid
    REFERENCES auth.users(id) ON DELETE RESTRICT,

  marketing_user_id uuid NOT NULL
    REFERENCES auth.users(id) ON DELETE RESTRICT,

  event_type text NOT NULL
    CHECK (
      event_type IN (
        'INITIAL_ASSIGN',
        'AUTO_REASSIGN',
        'HUMAN_TAKEOVER',
        'MANUAL_REASSIGN',
        'MANUAL_REASSIGN_CUSTOMER_REQUEST'
      )
    ),

  -- Mulai tanggung jawab PIC.
  assigned_at timestamptz NOT NULL DEFAULT now(),

  -- Berakhir karena handled / reassign / lainnya.
  ended_at timestamptz,

  -- Lama respons PIC tersebut.
  response_minutes numeric(10,2),

  result text NOT NULL DEFAULT 'PENDING'
    CHECK (
      result IN (
        'PENDING',
        'HANDLED',
        'SLOW_RESPONSE',
        'REASSIGNED',
        'MANUAL_REASSIGNED'
      )
    ),

  -- NULL jika dipicu automation/n8n.
  triggered_by_user_id uuid
    REFERENCES auth.users(id) ON DELETE SET NULL,

  notes text,

  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_sb_assignment_lead_time
ON public.sb_pic_assignment_log(
  lead_id,
  assigned_at
);

CREATE INDEX idx_sb_assignment_marketing
ON public.sb_pic_assignment_log(
  account_id,
  marketing_user_id,
  assigned_at
);

CREATE INDEX idx_sb_assignment_project
ON public.sb_pic_assignment_log(
  account_id,
  project_id,
  assigned_at
);

CREATE INDEX idx_sb_assignment_result
ON public.sb_pic_assignment_log(
  account_id,
  result
);


-- ============================================================
-- RLS SAFETY DEFAULT
--
-- RLS diaktifkan sekarang.
-- Policy operasional Marketing / SPV / Manager
-- dibuat pada migration berikutnya setelah core schema PASS.
--
-- Service role / n8n backend tetap dapat bekerja.
-- ============================================================

ALTER TABLE public.sb_projects
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.sb_marketing
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.sb_marketing_projects
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.sb_user_project_scope
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.sb_lead_distribution_policy
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.sb_leads
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.sb_conversation_state
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.sb_pic_assignment_log
ENABLE ROW LEVEL SECURITY;