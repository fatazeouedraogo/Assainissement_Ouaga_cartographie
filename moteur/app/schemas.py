from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field, field_validator

SizeClass = Literal["small", "medium", "large"]
WasteType = Literal["household", "rubble", "plastic", "organic", "mixed"]


class GeoPoint(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)


class Household(GeoPoint):
    weight: float = Field(default=1.0, gt=0)
    narrow: bool = False


class Dump(GeoPoint):
    id: str
    est_kg: float = Field(default=200.0, ge=0)
    size: SizeClass = "medium"
    age_days: float = Field(default=0.0, ge=0)
    waste_type: WasteType = "mixed"
    confidence: float = Field(default=1.0, ge=0, le=1)


class Poi(GeoPoint):
    kind: Literal["school", "market", "health", "drain", "water"]
    name: str | None = None


class Params(BaseModel):
    persons_per_household: float = Field(default=5.0, gt=0)
    waste_kg_per_person_day: float = Field(default=0.45, gt=0)
    subscription_rate: float = Field(default=0.35, ge=0, le=1)
    precollectors: int = Field(default=40, ge=0)
    precollector_capacity_kg: float = Field(default=250.0, gt=0)

    max_walk_m: float = Field(default=300.0, ge=50, le=1500)
    target_coverage: float = Field(default=0.9, gt=0, le=1)
    point_capacity_kg: float = Field(default=3000.0, gt=0)
    min_points: int = Field(default=1, ge=1)
    equity_boost: float = Field(default=1.0, ge=0, le=4)
    max_points: int = Field(default=400, ge=1)

    trucks: int = Field(default=6, ge=0)
    truck_capacity_kg: float = Field(default=8000.0, gt=0)
    truck_speed_kmh: float = Field(default=22.0, gt=0)
    truck_hours: float = Field(default=8.0, gt=0)
    trips_per_day: int = Field(default=2, ge=1, le=6)
    truck_cost_km: float = Field(default=350.0, ge=0)
    truck_fixed_day: float = Field(default=15000.0, ge=0)
    service_min_per_stop: float = Field(default=6.0, ge=0)
    unload_min: float = Field(default=20.0, ge=0)

    tricycles: int = Field(default=0, ge=0)
    tricycle_capacity_kg: float = Field(default=350.0, gt=0)
    tricycle_speed_kmh: float = Field(default=10.0, gt=0)
    tricycle_cost_km: float = Field(default=60.0, ge=0)
    tricycle_fixed_day: float = Field(default=3000.0, ge=0)
    tricycle_trips_per_day: int = Field(default=4, ge=1, le=10)
    narrow_access_share: float = Field(default=0.0, ge=0, le=1)

    frequency_days: int = Field(default=2, ge=1, le=7)
    budget_month: float = Field(default=8_400_000.0, ge=0)
    laabal_kg_day: float = Field(default=800.0, ge=0)

    rain: bool = False
    rain_speed_factor: float = Field(default=0.6, gt=0, le=1)
    rain_waste_factor: float = Field(default=1.15, gt=0)
    rain_walk_factor: float = Field(default=0.8, gt=0, le=1)
    breakdown_prob: float = Field(default=0.03, ge=0, le=1)
    repair_days: int = Field(default=3, ge=1)
    detour_factor: float = Field(default=1.35, ge=1.0)
    co2_kg_per_km_truck: float = Field(default=0.9, ge=0)

    organic_share: float = Field(default=0.55, ge=0, le=1)
    plastic_share: float = Field(default=0.08, ge=0, le=1)
    organic_recovery: float = Field(default=0.0, ge=0, le=1)
    plastic_recovery: float = Field(default=0.0, ge=0, le=1)
    compost_price_kg: float = Field(default=15.0, ge=0)
    plastic_price_kg: float = Field(default=100.0, ge=0)
    precollector_income_month: float = Field(default=60000.0, ge=0)
    household_income_month: float = Field(default=120000.0, gt=0)
    exposure_radius_m: float = Field(default=150.0, ge=20, le=1000)

    horizon_days: int = Field(default=30, ge=1, le=365)
    replications: int = Field(default=20, ge=1, le=200)
    seed: int = 7

    @field_validator("trucks")
    @classmethod
    def _trucks_cap(cls, v: int) -> int:
        return min(v, 500)


class Event(BaseModel):
    kind: Literal["truck_breakdown", "rain_season", "new_district", "budget_cut", "subscription_drop", "more_trucks"]
    value: float | None = None
    households: list[Household] | None = None
    label: str | None = None


class PlanRequest(BaseModel):
    households: list[Household] = Field(min_length=1)
    dumps: list[Dump] = []
    depot: GeoPoint
    landfill: GeoPoint
    params: Params = Params()
    events: list[Event] = []
    center: GeoPoint | None = None
    time_limit_s: int = Field(default=5, ge=1, le=60)


class SimulateRequest(PlanRequest):
    plan: dict | None = None


class CompareItem(BaseModel):
    name: str
    params: dict = {}
    events: list[Event] = []


class CompareRequest(BaseModel):
    households: list[Household] = Field(min_length=1)
    dumps: list[Dump] = []
    depot: GeoPoint
    landfill: GeoPoint
    base_params: Params = Params()
    scenarios: list[CompareItem] = Field(min_length=1, max_length=8)
    time_limit_s: int = Field(default=3, ge=1, le=30)


class SensitivityRequest(PlanRequest):
    delta: float = Field(default=0.2, gt=0, lt=0.9)
    parameters: list[str] | None = None


class PriorityRequest(BaseModel):
    dumps: list[Dump]
    pois: list[Poi] = []
    rain: bool = False


class ParetoRequest(PlanRequest):
    candidates: int = Field(default=8, ge=3, le=18)


class RecommendRequest(PlanRequest):
    pass


class CalibrateRequest(PlanRequest):
    metric: Literal["collection_rate", "leakage_rate", "stock_in_points_kg", "dump_stock_kg", "active_dumps"] = "collection_rate"
    target: float
    parameter: str = "subscription_rate"
    low: float
    high: float
    iterations: int = Field(default=7, ge=2, le=14)
    replications: int = Field(default=6, ge=2, le=30)

    @field_validator("parameter")
    @classmethod
    def _known(cls, v: str) -> str:
        if v not in Params.model_fields:
            raise ValueError("paramètre inconnu")
        return v


class AssistantRequest(BaseModel):
    question: str = Field(min_length=3, max_length=500)


class RiskRequest(BaseModel):
    households: list[Household] = Field(min_length=1)
    history: list[dict] = []
    pois: list[Poi] = []
    open_dumps: list[Dump] = []
    top: int = Field(default=25, ge=1, le=100)


class MaskSet(BaseModel):
    buildings: list[list[list[float]]] = []
    water: list[list[list[float]]] = []
    roads: list[list[list[float]]] = []


class MergeRequest(BaseModel):
    candidates: list[dict]
    merge_m: float = Field(default=40.0, ge=5, le=300)


class EvaluateRequest(BaseModel):
    candidates: list[dict]
    truth: list[GeoPoint] = Field(min_length=1)
    radius_m: float = Field(default=40.0, ge=5, le=300)
    thresholds: list[float] | None = None
