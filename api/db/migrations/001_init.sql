CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TYPE user_role AS ENUM ('citizen', 'agent', 'verifier', 'admin');
CREATE TYPE size_class AS ENUM ('small', 'medium', 'large');
CREATE TYPE waste_type AS ENUM ('household', 'rubble', 'plastic', 'organic', 'mixed');
CREATE TYPE report_status AS ENUM ('accepted', 'flagged', 'rejected');
CREATE TYPE dump_status AS ENUM ('pending', 'verified', 'rejected', 'scheduled', 'cleaned');
CREATE TYPE poi_kind AS ENUM ('school', 'market', 'health', 'drain', 'water');

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  phone text NOT NULL UNIQUE,
  password_hash text NOT NULL,
  role user_role NOT NULL DEFAULT 'citizen',
  points integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE dumps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  geom geography(Point, 4326) NOT NULL,
  size size_class NOT NULL DEFAULT 'medium',
  waste_type waste_type NOT NULL DEFAULT 'mixed',
  est_kg real NOT NULL DEFAULT 300,
  status dump_status NOT NULL DEFAULT 'pending',
  confidence real NOT NULL DEFAULT 0,
  report_count integer NOT NULL DEFAULT 0,
  reporter_count integer NOT NULL DEFAULT 0,
  priority_score real NOT NULL DEFAULT 0,
  priority_detail jsonb,
  recurrence_of uuid REFERENCES dumps(id),
  first_reported_at timestamptz NOT NULL DEFAULT now(),
  last_reported_at timestamptz NOT NULL DEFAULT now(),
  scheduled_for date,
  verified_by uuid REFERENCES users(id),
  verified_at timestamptz,
  cleaned_at timestamptz,
  cleaned_by uuid REFERENCES users(id),
  before_photo text,
  after_photo text,
  reject_reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX dumps_geom_idx ON dumps USING gist (geom);
CREATE INDEX dumps_status_idx ON dumps (status);
CREATE INDEX dumps_priority_idx ON dumps (priority_score DESC);

CREATE TABLE reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL UNIQUE,
  user_id uuid NOT NULL REFERENCES users(id),
  dump_id uuid REFERENCES dumps(id) ON DELETE SET NULL,
  geom geography(Point, 4326) NOT NULL,
  accuracy_m real,
  size size_class NOT NULL,
  waste_type waste_type NOT NULL DEFAULT 'mixed',
  note text,
  photo_path text,
  photo_hash bit(64),
  photo_analysis jsonb,
  credibility real NOT NULL DEFAULT 0,
  status report_status NOT NULL,
  flags text[] NOT NULL DEFAULT '{}',
  reject_reasons text[] NOT NULL DEFAULT '{}',
  captured_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX reports_geom_idx ON reports USING gist (geom);
CREATE INDEX reports_user_idx ON reports (user_id, created_at DESC);
CREATE INDEX reports_dump_idx ON reports (dump_id);

CREATE TABLE poi (
  id bigserial PRIMARY KEY,
  kind poi_kind NOT NULL,
  name text,
  geom geography(Point, 4326) NOT NULL
);
CREATE INDEX poi_geom_idx ON poi USING gist (geom);

CREATE TABLE buildings (
  id bigserial PRIMARY KEY,
  geom geography(Point, 4326) NOT NULL,
  weight real NOT NULL DEFAULT 1,
  narrow boolean NOT NULL DEFAULT false,
  source text NOT NULL DEFAULT 'import'
);
CREATE INDEX buildings_geom_idx ON buildings USING gist (geom);

CREATE TABLE scenarios (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  params jsonb NOT NULL DEFAULT '{}',
  events jsonb NOT NULL DEFAULT '[]',
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE simulation_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scenario_id uuid REFERENCES scenarios(id) ON DELETE SET NULL,
  kind text NOT NULL,
  request jsonb NOT NULL,
  result jsonb NOT NULL,
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE point_ledger (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id),
  dump_id uuid REFERENCES dumps(id) ON DELETE SET NULL,
  reason text NOT NULL,
  delta integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, dump_id, reason)
);

CREATE TABLE settings (
  key text PRIMARY KEY,
  value jsonb NOT NULL
);

INSERT INTO settings (key, value) VALUES
  ('depot', '{"lat": 12.3714, "lon": -1.5197, "placeholder": true}'),
  ('landfill', '{"lat": 12.3200, "lon": -1.4600, "placeholder": true}'),
  ('thresholds', '{"auto_verify_confidence": 0.9, "auto_verify_reporters": 3, "duplicate_radius_m": 30}');
