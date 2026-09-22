import { createHmac, timingSafeEqual } from 'node:crypto'
import { NextResponse } from 'next/server'
import { POST as metaWebhookPost } from '@/app/api/whatsapp/webhook/route'

function safeEqual(a: string, b: string) {
  const aa = Buffer.from(a)
  const bb = Buffer.from(b)

  if (aa.length !== bb.length) return false
  return timingSafeEqual(aa, bb)
}

export async function POST(request: Request) {
  const relaySecret = process.env.N8N_WACRM_RELAY_SECRET

  if (!relaySecret) {
    console.error('[n8n-relay] N8N_WACRM_RELAY_SECRET is not configured')
    return NextResponse.json(
      { error: 'Relay not configured' },
      { status: 500 },
    )
  }

  const providedSecret = request.headers.get('x-sbland-relay-secret') ?? ''

  if (!safeEqual(providedSecret, relaySecret)) {
    console.warn('[n8n-relay] rejected request with invalid relay secret')
    return NextResponse.json(
      { error: 'Unauthorized' },
      { status: 401 },
    )
  }

  const rawBody = await request.text()

  const metaSecret = process.env.META_APP_SECRET
    ?.split(',')
    .map((value) => value.trim())
    .find(Boolean)

  if (!metaSecret) {
    console.error('[n8n-relay] META_APP_SECRET is not configured')
    return NextResponse.json(
      { error: 'Meta secret not configured' },
      { status: 500 },
    )
  }

  const signature = createHmac('sha256', metaSecret)
    .update(rawBody)
    .digest('hex')

  const internalRequest = new Request(
    'http://internal/api/whatsapp/webhook',
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-hub-signature-256': `sha256=${signature}`,
      },
      body: rawBody,
    },
  )

  return metaWebhookPost(internalRequest)
}