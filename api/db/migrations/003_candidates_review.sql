ALTER TABLE candidates
  ADD COLUMN base_score real,
  ADD COLUMN signals jsonb,
  ADD COLUMN merged integer NOT NULL DEFAULT 0,
  ADD COLUMN reviewed_by uuid REFERENCES users(id),
  ADD COLUMN reviewed_at timestamptz,
  ADD COLUMN reject_reason text CHECK (reject_reason IN ('batiment', 'route', 'eau', 'vegetation', 'rien_vu', 'deja_signale', 'autre')),
  ADD COLUMN reject_note text,
  ADD COLUMN dump_id uuid REFERENCES dumps(id) ON DELETE SET NULL;

CREATE INDEX candidates_status_idx ON candidates (status, score DESC);

INSERT INTO settings (key, value) VALUES ('detection', '{"min_score": 1.5, "merge_m": 40, "risk_weight": 0.5}');
