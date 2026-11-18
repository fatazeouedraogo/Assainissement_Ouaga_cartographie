CREATE TABLE rl_state (
  context text NOT NULL,
  arm text NOT NULL,
  n integer NOT NULL DEFAULT 0,
  mean real NOT NULL DEFAULT 0,
  m2 real NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (context, arm)
);

CREATE TABLE observations (
  id bigserial PRIMARY KEY,
  metric text NOT NULL CHECK (metric IN ('collection_rate', 'leakage_rate')),
  value real NOT NULL CHECK (value BETWEEN 0 AND 1),
  observed_on date NOT NULL DEFAULT CURRENT_DATE,
  note text,
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

UPDATE settings SET value = '{"lat": 12.328877, "lon": -1.458722, "placeholder": true, "source": "lien Google Maps fourni par l''équipe, à confirmer"}' WHERE key = 'landfill';
INSERT INTO settings (key, value) VALUES
  ('sites', '[{"name": "Site 2 fourni par l''équipe (à préciser : garage ou décharge)", "lat": 12.325206, "lon": -1.459381}]');
