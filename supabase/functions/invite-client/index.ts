import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Verify the requesting user is an admin
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Create admin client with service role (has full access)
    const adminClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    // Verify caller is authenticated and is an admin
    const userClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )
    const { data: { user }, error: authError } = await userClient.auth.getUser()
    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    if (!user.app_metadata?.is_admin) {
      return new Response(JSON.stringify({ error: 'Admin access required' }), {
        status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Get request body
    const { email, client_id } = await req.json()
    if (!email || !client_id) {
      return new Response(JSON.stringify({ error: 'email and client_id are required' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Invite the user — sends a branded email with a signup link
    const { data: inviteData, error: inviteError } = await adminClient.auth.admin.inviteUserByEmail(
      email,
      {
        redirectTo: 'https://hq.ebgcreative.ca/hq/reset.html',
        data: { client_id }
      }
    )

    if (inviteError) {
      // If user already exists, just link them and send a password reset instead
      if (inviteError.message.includes('already been registered')) {
        const { data: existingUser } = await adminClient.auth.admin.listUsers()
        const found = existingUser?.users?.find(u => u.email === email)
        if (found) {
          await adminClient.from('clients').update({ user_id: found.id }).eq('id', client_id)
          // Send password reset email
          await adminClient.auth.resetPasswordForEmail(email, {
            redirectTo: 'https://hq.ebgcreative.ca/hq/reset.html'
          })
          return new Response(JSON.stringify({
            success: true,
            message: 'User already exists — password reset email sent and client linked.'
          }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
        }
      }
      return new Response(JSON.stringify({ error: inviteError.message }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Link the new user to the client record
    if (inviteData?.user?.id) {
      await adminClient.from('clients').update({ user_id: inviteData.user.id }).eq('id', client_id)
    }

    return new Response(JSON.stringify({
      success: true,
      message: `Invite sent to ${email}. They'll receive an email to set their password and access Brand HQ.`
    }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})
