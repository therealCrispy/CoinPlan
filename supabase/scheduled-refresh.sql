-- Deployment template. First create Vault secrets in the dashboard:
-- coinplan_function_url = exact https://<project>.supabase.co/functions/v1/coinplan-bank
-- coinplan_cron_secret = same random value as the function's COINPLAN_CRON_SECRET
-- coinplan_publishable_key = project public publishable key (required by the Supabase gateway)
-- Enable the pg_cron and pg_net integrations, then run this query once.
select cron.schedule(
 'coinplan-bank-refresh',
 '0 3,15 * * *',
 $$select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name='coinplan_function_url'),
    headers := jsonb_build_object('Content-Type','application/json','apikey',
      (select decrypted_secret from vault.decrypted_secrets where name='coinplan_publishable_key'),'x-coinplan-cron',
      (select decrypted_secret from vault.decrypted_secrets where name='coinplan_cron_secret')),
    body := '{"action":"scheduled"}'::jsonb,
    timeout_milliseconds := 120000
 );$$
);
