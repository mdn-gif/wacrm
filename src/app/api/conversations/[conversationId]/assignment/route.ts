import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { requireRole, toErrorResponse } from '@/lib/auth/account'
import { dispatchWebhookEvent } from '@/lib/webhooks/deliver'
import { checkRateLimit, rateLimitResponse, RATE_LIMITS } from '@/lib/rate-limit'

type Params = {
  params: Promise<{ conversationId: string }>
}

let _adminClient: any = null

function supabaseAdmin() {
  if (!_adminClient) {
    _adminClient = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.SUPABASE_SERVICE_ROLE_KEY!,
    )
  }

  return _adminClient
}

export async function PATCH(request: Request, { params }: Params) {
  try {
    const { supabase, accountId, userId, role } =
      await requireRole('agent')

    const limit = checkRateLimit(
      `conversation-assignment:${userId}`,
      RATE_LIMITS.send,
    )

    if (!limit.success) {
      return rateLimitResponse(limit)
    }

    const { conversationId } = await params
    const body = await request.json().catch(() => null)

    if (!body || !('agent_id' in body)) {
      return NextResponse.json(
        { error: 'agent_id is required' },
        { status: 400 },
      )
    }

    const agentId =
      typeof body.agent_id === 'string' && body.agent_id.trim()
        ? body.agent_id
        : null

    const { data: conversation, error: conversationError } = await supabase
      .from('conversations')
      .select('id, account_id, contact_id, assigned_agent_id')
      .eq('id', conversationId)
      .eq('account_id', accountId)
      .maybeSingle()

    if (conversationError) {
      console.error(
        '[conversation-assignment] conversation lookup error:',
        conversationError,
      )

      return NextResponse.json(
        { error: 'Failed to load conversation' },
        { status: 500 },
      )
    }

    if (!conversation) {
      return NextResponse.json(
        { error: 'Conversation not found' },
        { status: 404 },
      )
    }

    if (agentId) {
      const { data: agent, error: agentError } = await supabase
        .from('profiles')
        .select('user_id, full_name, account_id, account_role')
        .eq('user_id', agentId)
        .eq('account_id', accountId)
        .maybeSingle()

      if (agentError) {
        console.error(
          '[conversation-assignment] agent lookup error:',
          agentError,
        )

        return NextResponse.json(
          { error: 'Failed to validate agent' },
          { status: 500 },
        )
      }

      if (!agent) {
        return NextResponse.json(
          { error: 'Agent not found in this account' },
          { status: 400 },
        )
      }
    }

    const previousAgentId = conversation.assigned_agent_id ?? null

    if (role === 'agent') {
      if (agentId && agentId !== userId) {
        return NextResponse.json(
          {
            error: 'Agents can only assign conversations to themselves',
          },
          { status: 403 },
        )
      }

      if (
        agentId === userId &&
        previousAgentId &&
        previousAgentId !== userId
      ) {
        return NextResponse.json(
          {
            error:
              'This conversation is already assigned to another agent',
          },
          { status: 403 },
        )
      }

      if (
        agentId === null &&
        previousAgentId &&
        previousAgentId !== userId
      ) {
        return NextResponse.json(
          {
            error: 'Agents can only unassign their own conversations',
          },
          { status: 403 },
        )
      }
    }

    if (previousAgentId === agentId) {
      return NextResponse.json({
        success: true,
        changed: false,
        assigned_agent_id: agentId,
      })
    }

    const { error: updateError } = await supabase
      .from('conversations')
      .update({ assigned_agent_id: agentId })
      .eq('id', conversationId)
      .eq('account_id', accountId)

    if (updateError) {
      console.error(
        '[conversation-assignment] assignment update error:',
        updateError,
      )

      return NextResponse.json(
        { error: 'Failed to update assignment' },
        { status: 500 },
      )
    }

    await dispatchWebhookEvent(
      supabaseAdmin(),
      accountId,
      'conversation.assigned',
      {
        conversation_id: conversationId,
        contact_id: conversation.contact_id,
        assigned_agent_id: agentId,
        previous_assigned_agent_id: previousAgentId,
        actor_user_id: userId,
      },
    )

    return NextResponse.json({
      success: true,
      changed: true,
      assigned_agent_id: agentId,
    })
  } catch (err) {
    return toErrorResponse(err)
  }
}