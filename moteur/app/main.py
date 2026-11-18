from __future__ import annotations

import os

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

import json

from . import __version__, assistant, catalog, decision, evaluation, learning, photo, precollectors, predict, satellite, scenarios
from .priority import score_dumps
from .routing import HAS_ORTOOLS
from .schemas import (
    AssistantRequest,
    CalibrateRequest,
    CompareRequest,
    EvaluateRequest,
    LearnRequest,
    MaskSet,
    MergeRequest,
    ParetoRequest,
    PlanRequest,
    PriorityRequest,
    RecommendRequest,
    RiskRequest,
    SensitivityRequest,
    SimulateRequest,
)

MAX_PHOTO_BYTES = 8 * 1024 * 1024
MAX_HOUSEHOLDS = 60000

from contextlib import asynccontextmanager


@asynccontextmanager
async def lifespan(_app):
    if os.environ.get("USE_CLIP") == "1":
        photo.clip_status()
    yield


app = FastAPI(title="Moteur Ouaga Assainissement", version=__version__, lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=os.environ.get("CORS_ORIGINS", "*").split(","), allow_methods=["*"], allow_headers=["*"])


def require_key(x_engine_key: str | None = Header(default=None)):
    expected = os.environ.get("ENGINE_API_KEY")
    if expected and x_engine_key != expected:
        raise HTTPException(status_code=401, detail="clé moteur invalide")


def _guard(n: int):
    if n > MAX_HOUSEHOLDS:
        raise HTTPException(status_code=413, detail=f"limite de {MAX_HOUSEHOLDS} enregistrements dépassée")


@app.get("/health")
def health():
    return {"status": "ok", "version": __version__, "ortools": HAS_ORTOOLS, "clip": photo.clip_status()}


@app.get("/v1/controls", dependencies=[Depends(require_key)])
def controls():
    return {"controls": catalog.controls()}


@app.post("/v1/photo/analyze", dependencies=[Depends(require_key)])
async def photo_analyze(file: UploadFile = File(...)):
    data = await file.read()
    if len(data) > MAX_PHOTO_BYTES:
        raise HTTPException(status_code=413, detail="photo trop lourde")
    return photo.analyze(data)


@app.post("/v1/photo/distance", dependencies=[Depends(require_key)])
def photo_distance(body: dict):
    a, b = body.get("a"), body.get("b")
    if not a or not b:
        raise HTTPException(status_code=422, detail="champs a et b requis")
    return {"hamming": photo.hamming_hex(a, b)}


@app.post("/v1/priority/score", dependencies=[Depends(require_key)])
def priority(req: PriorityRequest):
    return {"scores": score_dumps(req.dumps, req.pois, req.rain)}


@app.post("/v1/plan", dependencies=[Depends(require_key)])
def plan(req: PlanRequest):
    _guard(len(req.households))
    return scenarios.plan_only(req)


@app.post("/v1/simulate", dependencies=[Depends(require_key)])
def simulate(req: SimulateRequest):
    _guard(len(req.households))
    return scenarios.plan_and_simulate(req)


@app.post("/v1/scenarios/compare", dependencies=[Depends(require_key)])
def compare(req: CompareRequest):
    _guard(len(req.households))
    return scenarios.compare(req)


@app.post("/v1/sensitivity", dependencies=[Depends(require_key)])
def sensitivity(req: SensitivityRequest):
    _guard(len(req.households))
    return scenarios.sensitivity(req)


@app.post("/v1/assistant/parse", dependencies=[Depends(require_key)])
def assistant_parse(req: AssistantRequest):
    return assistant.parse(req.question)


@app.post("/v1/predict/risk", dependencies=[Depends(require_key)])
def predict_risk(req: RiskRequest):
    _guard(len(req.households))
    return predict.risk_map(req.households, req.history, req.pois, req.open_dumps, req.top)


@app.post("/v1/pareto", dependencies=[Depends(require_key)])
def pareto(req: ParetoRequest):
    _guard(len(req.households))
    return decision.pareto(req)


@app.post("/v1/recommend", dependencies=[Depends(require_key)])
def recommend(req: RecommendRequest):
    _guard(len(req.households))
    return decision.recommend(req)


@app.post("/v1/calibrate", dependencies=[Depends(require_key)])
def calibrate(req: CalibrateRequest):
    _guard(len(req.households))
    return decision.calibrate(req)


@app.post("/v1/satellite/candidates", dependencies=[Depends(require_key)])
async def satellite_candidates(
    file: UploadFile = File(...),
    south: float = Form(...),
    west: float = Form(...),
    north: float = Form(...),
    east: float = Form(...),
    top: int = Form(30),
    min_score: float = Form(1.5),
    merge_m: float = Form(40.0),
    risk_weight: float = Form(0.5),
    road_width_m: float = Form(6.0),
    masks: str | None = Form(None),
    risk_cells: str | None = Form(None),
):
    data = await file.read()
    if len(data) > 25 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="image trop lourde")
    if not (south < north and west < east):
        raise HTTPException(status_code=422, detail="emprise invalide")
    try:
        mask_obj = MaskSet(**json.loads(masks)).model_dump() if masks else None
        cells = json.loads(risk_cells) if risk_cells else None
    except Exception:
        raise HTTPException(status_code=422, detail="masques ou cellules de risque invalides")
    cands, stats = satellite.find_candidates(
        data, (south, west, north, east), top=min(max(top, 1), 100), masks=mask_obj, risk_cells=cells,
        min_score=min_score, merge_m=merge_m, risk_weight=risk_weight, road_width_m=road_width_m, return_stats=True,
    )
    return {"candidates": cands, "stats": stats}


@app.post("/v1/satellite/merge", dependencies=[Depends(require_key)])
def satellite_merge(req: MergeRequest):
    return {"candidates": satellite.merge_candidates(req.candidates, req.merge_m)}


@app.post("/v1/satellite/evaluate", dependencies=[Depends(require_key)])
def satellite_evaluate(req: EvaluateRequest):
    return evaluation.evaluate(req.candidates, [t.model_dump() for t in req.truth], req.radius_m, req.thresholds)


@app.post("/v1/learn/respond", dependencies=[Depends(require_key)])
def learn_respond(req: LearnRequest):
    _guard(len(req.households))
    return learning.learn(req)


@app.post("/v1/precollectors", dependencies=[Depends(require_key)])
def precollectors_plan(req: PlanRequest):
    _guard(len(req.households))
    params, hh, _ = scenarios.apply_events(req.params, req.households, req.events)
    center = (req.center.lat, req.center.lon) if req.center else None
    return precollectors.precollector_plans(hh, params, center)
