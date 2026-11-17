import numpy as np
import pytest


@pytest.fixture(scope="session")
def city():
    rng = np.random.default_rng(3)
    hh = [{"lat": 12.37 + rng.normal(0, 0.012), "lon": -1.52 + rng.normal(0, 0.012)} for _ in range(800)]
    return {
        "households": hh,
        "depot": {"lat": 12.36, "lon": -1.53},
        "landfill": {"lat": 12.30, "lon": -1.60},
        "dumps": [{"id": "D1", "lat": 12.371, "lon": -1.52, "est_kg": 400}],
    }
