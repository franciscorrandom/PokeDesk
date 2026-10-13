// Small, bundled outline icons; no network or font dependency in the app.
const paths={
  calendar:'<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M7 3v4m10-4v4M3 11h18m-13 4h2m4 0h2m-8 3h2"/>',
  heart:'<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z"/>',
  timer:'<circle cx="12" cy="14" r="8"/><path d="M12 10v4l3 2M9 2h6m-3 0v4m7 0 2 2"/>',
  notes:'<rect x="5" y="3" width="16" height="18" rx="3"/><path d="M3 7h4m-4 5h4m-4 5h4m4-10h6m-6 5h6m-6 5h4"/>',
  sparkles:'<path d="m12 3 2.6 6.4L21 12l-6.4 2.6L12 21l-2.6-6.4L3 12l6.4-2.6L12 3Zm8-2v4m-2-2h4"/>',
  panel:'<rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/>',
  switch:'<path d="M3 8h17l-4-4m4 4-4 4M21 16H4l4 4m-4-4 4-4"/>',
  close:'<path d="m6 6 12 12M6 18 18 6"/>',
  settings:'<path d="M3 6h5m4 0h9M3 18h9m4 0h5"/><circle cx="10" cy="6" r="2"/><circle cx="14" cy="18" r="2"/>',
  home:'<path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1V10Z"/>',
  tasks:'<circle cx="12" cy="12" r="9"/><path d="m8 12 3 3 5-6"/>',
  pokeball:'<circle cx="12" cy="12" r="9"/><path d="M3 12h6m6 0h6"/><circle cx="12" cy="12" r="3"/>'
};
export function icon(name){return '<svg class="orbit-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'+(paths[name]||paths.panel)+'</svg>';}
