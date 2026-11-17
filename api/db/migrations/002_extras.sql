CREATE TABLE notifications (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind text NOT NULL,
  dump_id uuid REFERENCES dumps(id) ON DELETE SET NULL,
  title text NOT NULL,
  body text NOT NULL,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, dump_id, kind)
);
CREATE INDEX notifications_user_idx ON notifications (user_id, created_at DESC);

CREATE TABLE sensors (
  id text PRIMARY KEY,
  name text NOT NULL,
  geom geography(Point, 4326) NOT NULL,
  height_cm real NOT NULL DEFAULT 120,
  min_cm real NOT NULL DEFAULT 10,
  secret_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE sensor_readings (
  id bigserial PRIMARY KEY,
  sensor_id text NOT NULL REFERENCES sensors(id) ON DELETE CASCADE,
  distance_cm real NOT NULL,
  fill_ratio real NOT NULL,
  battery real,
  at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX sensor_readings_idx ON sensor_readings (sensor_id, at DESC);

CREATE TABLE candidates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  geom geography(Point, 4326) NOT NULL,
  score real NOT NULL,
  source text NOT NULL DEFAULT 'satellite',
  status text NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'confirmed', 'dismissed')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX candidates_geom_idx ON candidates USING gist (geom);

CREATE TABLE subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id),
  provider text NOT NULL CHECK (provider IN ('orange', 'moov')),
  wallet_phone text NOT NULL,
  months integer NOT NULL CHECK (months BETWEEN 1 AND 12),
  amount integer NOT NULL,
  status text NOT NULL,
  reference text NOT NULL UNIQUE,
  simulated boolean NOT NULL DEFAULT true,
  paid_until date,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE chat_sessions (
  phone text PRIMARY KEY,
  lat double precision,
  lon double precision,
  size size_class,
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO settings (key, value) VALUES ('subscription', '{"price_month": 1500, "placeholder": true}');
