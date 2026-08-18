import { createClient } from '@supabase/supabase-js';
const URL = 'https://ztyfewkmxpholjlygqrl.supabase.co';
const KEY = 'sb_publishable_PeGzbpVhRxQKMnfWJjTO5g_uYLHcMCE';
const supabase = createClient(URL, KEY);

const { data: clans } = await supabase.from('clans').select('clan_id, name').ilike('name', '%章鱼%');
console.log('部落:', clans);

if (clans && clans.length) {
  const { data: members } = await supabase
    .from('players')
    .select('player_id, game_name, channel, matchable, banned, clan_id')
    .in('clan_id', clans.map((c) => c.clan_id));
  console.log('成员数:', members?.length);
  for (const m of members || []) {
    console.log(`  ${m.game_name} | channel=${m.channel} | matchable=${m.matchable} | banned=${m.banned}`);
  }
}