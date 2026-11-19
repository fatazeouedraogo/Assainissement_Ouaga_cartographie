import { Area, Bar, CartesianGrid, Cell, ComposedChart, Legend, Line, Pie, PieChart, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';

const axis = { stroke: '#8fa0b3', fontSize: 11, tickLine: false, axisLine: false };

export function BandChart({ rows, color = '#33a1de', unit = '', cursor, height = 260, name = 'Moyenne' }) {
  return (
    <ResponsiveContainer width="100%" height={height}>
      <ComposedChart data={rows} margin={{ top: 8, right: 8, left: -8, bottom: 0 }}>
        <CartesianGrid stroke="#edf1f5" vertical={false} />
        <XAxis dataKey="day" {...axis} />
        <YAxis {...axis} width={52} />
        <Tooltip formatter={(v, n) => [Array.isArray(v) ? `${v[0]} – ${v[1]} ${unit}` : `${v} ${unit}`, n]} labelFormatter={(d) => `Jour ${d}`} />
        <Area type="monotone" dataKey="band" name="Fourchette 5–95 %" stroke="none" fill={color} fillOpacity={0.14} />
        <Line type="monotone" dataKey="mean" name={name} stroke={color} strokeWidth={2.5} dot={false} />
        {cursor ? <ReferenceLine x={cursor} stroke="#2c7a2f" strokeDasharray="4 4" /> : null}
      </ComposedChart>
    </ResponsiveContainer>
  );
}

export function PairBars({ rows, a, b, unit = '', height = 280, cursor }) {
  return (
    <ResponsiveContainer width="100%" height={height}>
      <ComposedChart data={rows} margin={{ top: 8, right: 8, left: -8, bottom: 0 }}>
        <CartesianGrid stroke="#edf1f5" vertical={false} />
        <XAxis dataKey="day" {...axis} />
        <YAxis {...axis} width={52} />
        <Tooltip formatter={(v, n) => [`${v} ${unit}`, n]} labelFormatter={(d) => `Jour ${d}`} />
        <Legend iconType="circle" wrapperStyle={{ fontSize: 12 }} />
        <Bar dataKey={a.key} name={a.name} fill={a.color} radius={[6, 6, 0, 0]} />
        <Bar dataKey={b.key} name={b.name} fill={b.color} radius={[6, 6, 0, 0]} />
        {cursor ? <ReferenceLine x={cursor} stroke="#2c7a2f" strokeDasharray="4 4" /> : null}
      </ComposedChart>
    </ResponsiveContainer>
  );
}

export function Donut({ parts, center, sub }) {
  return (
    <div style={{ position: 'relative', height: 230 }}>
      <ResponsiveContainer width="100%" height="100%">
        <PieChart>
          <Pie data={parts} dataKey="value" innerRadius={72} outerRadius={100} paddingAngle={2} stroke="none" startAngle={90} endAngle={-270}>
            {parts.map((p) => (
              <Cell key={p.name} fill={p.color} />
            ))}
          </Pie>
          <Tooltip formatter={(v, n) => [`${(v * 100).toFixed(1)} %`, n]} />
        </PieChart>
      </ResponsiveContainer>
      <div style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', pointerEvents: 'none', textAlign: 'center' }}>
        <div>
          <div style={{ fontSize: 28, fontWeight: 800, fontFamily: 'Plus Jakarta Sans, Inter, sans-serif' }}>{center}</div>
          <div className="muted small">{sub}</div>
        </div>
      </div>
    </div>
  );
}
