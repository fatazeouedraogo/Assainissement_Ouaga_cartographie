const P = {
  grid: 'M3 3h7v7H3zM14 3h7v7h-7zM14 14h7v7h-7zM3 14h7v7H3z',
  map: 'M9 4 3 6v14l6-2 6 2 6-2V4l-6 2zM9 4v14M15 6v14',
  shield: 'M12 3 4 6v6c0 5 3.4 8.4 8 9 4.6-.6 8-4 8-9V6zM9 12l2 2 4-4',
  sliders: 'M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M20 18h0M14 4v4M8 10v4M16 16v4',
  pulse: 'M3 12h4l3-8 4 16 3-8h4',
  building: 'M4 21V5l8-2v18M12 8h8v13M8 8h0M8 12h0M8 16h0M16 12h0M16 16h0M2 21h20',
  download: 'M12 3v12M7 10l5 5 5-5M4 20h16',
  bell: 'M6 9a6 6 0 1 1 12 0c0 6 2 7 2 7H4s2-1 2-7M10 20a2 2 0 0 0 4 0',
  truck: 'M2 6h11v10H2zM13 9h5l3 3v4h-8M6 19a2 2 0 1 0 0-4 2 2 0 0 0 0 4zM17 19a2 2 0 1 0 0-4 2 2 0 0 0 0 4z',
  euro: 'M4 10h12M4 14h12M18 6a7 7 0 1 0 0 12',
  check: 'M5 12l4 4 10-10',
  alert: 'M12 3 2 21h20zM12 10v5M12 18h0',
  play: 'M7 4l13 8-13 8z',
  refresh: 'M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7',
  history: 'M3 12a9 9 0 1 0 3-6.7M3 4v5h5M12 7v5l3 2',
  logout: 'M15 4h4a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1h-4M10 8l-4 4 4 4M6 12h10',
};

export function Icon({ name, size = 20 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d={P[name] || ''} />
    </svg>
  );
}
