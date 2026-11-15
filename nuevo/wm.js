/* ============================================================
   WeekMenuIA — conexión con Supabase, compartida por todas las páginas.
   Los dos datos de abajo son públicos (la seguridad la pone la base
   de datos con Row Level Security).
   ============================================================ */
(function(){
  const SUPABASE_URL = "https://qnskxjdxaczepupdrajz.supabase.co";
  const SUPABASE_KEY = "sb_publishable_6k-RYwVTcTsRmT8v0eopHQ_2fMbOMQt";
  const ENTRAR = '../entrar.html';
  const HOGAR_KEY = 'wmHogar';

  const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

  function hoyISO(){
    const d = new Date();
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  }
  function leerHogar(){ try{ return JSON.parse(localStorage.getItem(HOGAR_KEY)); }catch(e){ return null; } }
  function guardarHogar(h){ try{ localStorage.setItem(HOGAR_KEY, JSON.stringify(h)); }catch(e){} }

  /* Revisa que haya sesión y hogar. Si no, manda a la página de entrar.
     Devuelve { sb, user, hogar, soloLectura, sinConexion }.
     Sin internet usa el hogar guardado en este celular, para que la
     lista se pueda ver y anotar igual. */
  async function iniciar(){
    const { data: { session } } = await sb.auth.getSession();
    if(!session){ location.replace(ENTRAR); return new Promise(() => {}); }

    let hogar = null, sinConexion = false;
    try{
      const { data: hid, error } = await sb.rpc('mi_hogar');
      if(error) throw error;
      if(!hid){ location.replace(ENTRAR); return new Promise(() => {}); }
      const r = await sb.from('hogares').select('*').eq('id', hid).single();
      if(r.error) throw r.error;
      hogar = r.data;
      guardarHogar(Object.assign({ user_id: session.user.id }, hogar));
    }catch(err){
      const guardado = leerHogar();
      if(guardado && guardado.user_id === session.user.id){ hogar = guardado; sinConexion = true; }
      else throw err;
    }
    return {
      sb, user: session.user, hogar, sinConexion,
      soloLectura: hogar.activo_hasta < hoyISO()
    };
  }

  async function salir(){
    try{ localStorage.removeItem(HOGAR_KEY); }catch(e){}
    await sb.auth.signOut();
    location.replace(ENTRAR);
  }

  /* Escucha cambios de una tabla de este hogar (otros celulares) y llama a fn */
  function escuchar(tabla, filtro, fn){
    let t = null;
    const avisar = () => { clearTimeout(t); t = setTimeout(fn, 250); };
    return sb.channel(tabla + ':' + filtro)
      .on('postgres_changes', { event: '*', schema: 'public', table: tabla, filter: filtro }, avisar)
      .subscribe();
  }

  /* Traduce los errores más comunes */
  function traducir(err){
    const m = String((err && err.message) || err || '');
    const l = m.toLowerCase();
    if(l.includes('failed to fetch') || l.includes('network')) return 'No hay conexión';
    if(l.includes('row-level security') || l.includes('permission denied')) return 'No tienes permiso para hacer este cambio';
    if(l.includes('jwt')) return 'Tu sesión venció, vuelve a entrar';
    return m || 'Ocurrió un error';
  }
  function esDeRed(err){
    const l = String((err && err.message) || err || '').toLowerCase();
    return l.includes('failed to fetch') || l.includes('network') || l.includes('load failed') || navigator.onLine === false;
  }

  window.WM = { sb, iniciar, salir, escuchar, traducir, esDeRed, hoyISO, ENTRAR };
})();
