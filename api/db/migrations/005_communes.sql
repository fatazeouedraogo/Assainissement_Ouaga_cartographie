INSERT INTO settings (key, value) VALUES
  ('communes', '[{"slug":"ouagadougou","name":"Commune de Ouagadougou","region":"Centre","lat":12.3714,"lon":-1.5197,"radius_km":18,"population":null,"trucks":null,"fuel_price_fcfa":null,"depot":null,"landfill":null}]'),
  ('active_commune', '"ouagadougou"')
ON CONFLICT (key) DO NOTHING;
