/* supabaseClient.js — cliente de Supabase para el navegador.
   La URL y la anon key son seguras de exponer aquí: el control de acceso
   real lo hace Row Level Security en la base de datos, no este archivo.
   Debe cargarse después del <script> del SDK (@supabase/supabase-js) y
   antes de store.js/main.js. */
const SUPABASE_URL = 'https://djekhabomlvkjmysmwvw.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRqZWtoYWJvbWx2a2pteXNtd3Z3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcyMzA5NzQsImV4cCI6MjEwMjgwNjk3NH0.-K159b-osDxPFZ6tNPk8lwDAAL4XTCvGp5-FIpYeLek';

// window.supabase es la librería (createClient); nuestro cliente se llama
// `supa` para no pisar ese nombre global.
const supa = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
