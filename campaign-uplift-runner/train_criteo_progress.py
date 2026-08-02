from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.compose import TransformedTargetRegressor
from sklearn.dummy import DummyRegressor
from sklearn.ensemble import HistGradientBoostingRegressor, RandomForestRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import GroupShuffleSplit

DAYS = (1, 3, 7)
SECONDS_DAY = 86_400
EXPECTED_SHA256 = "94ac7a465564349bc7ba008602211d5990a3c53cc133abc0aadef61ea2391a98"
USECOLS = [
    "timestamp", "campaign", "conversion", "conversion_timestamp", "conversion_id",
    "attribution", "click", "cost", "cpo",
]
FEATURES = [
    "horizon", "impressions", "clicks", "current_conversions", "current_cost",
    "ctr", "cvr", "cost_per_current_conversion",
]
SEED = 20260802


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def validate_source(path: Path) -> dict:
    digest = sha256(path)
    if digest != EXPECTED_SHA256:
        raise RuntimeError(f"Official Criteo SHA-256 mismatch: {digest}")
    columns = pd.read_csv(path, sep="\t", compression="gzip", nrows=3).columns.tolist()
    missing = sorted(set(USECOLS).difference(columns))
    if missing:
        raise RuntimeError(f"Missing official columns: {missing}")
    return {"sha256": digest, "columns": columns, "bytes": path.stat().st_size}


def aggregate(path: Path) -> pd.DataFrame:
    daily_parts: list[pd.DataFrame] = []
    conversion_parts: list[pd.DataFrame] = []
    raw_rows = 0
    for chunk in pd.read_csv(path, sep="\t", compression="gzip", usecols=USECOLS, chunksize=500_000):
        raw_rows += len(chunk)
        chunk["impression_day"] = (chunk["timestamp"] // SECONDS_DAY).clip(0, 29).astype("int16")
        daily_parts.append(
            chunk.groupby(["campaign", "impression_day"], observed=True)
            .agg(
                impressions=("timestamp", "size"),
                clicks=("click", "sum"),
                attributed=("attribution", "sum"),
                cost=("cost", "sum"),
                cpo=("cpo", "sum"),
            )
            .reset_index()
            .rename(columns={"impression_day": "day"})
        )
        converted = chunk[(chunk["conversion"] == 1) & chunk["conversion_id"].notna()][
            ["campaign", "conversion_id", "conversion_timestamp"]
        ].drop_duplicates(["campaign", "conversion_id"])
        if not converted.empty:
            conversion_parts.append(converted)
        print(f"processed_rows={raw_rows}", flush=True)

    daily = (
        pd.concat(daily_parts, ignore_index=True)
        .groupby(["campaign", "day"], observed=True)
        .sum(numeric_only=True)
        .reset_index()
    )
    conversions = pd.concat(conversion_parts, ignore_index=True).drop_duplicates(["campaign", "conversion_id"])
    conversions = conversions[conversions["conversion_timestamp"].notna()].copy()
    conversions["day"] = (conversions["conversion_timestamp"] // SECONDS_DAY).clip(0, 29).astype("int16")
    conversion_daily = (
        conversions.groupby(["campaign", "day"], observed=True)["conversion_id"]
        .nunique().rename("unique_conversions").reset_index()
    )
    daily = daily.merge(conversion_daily, how="left", on=["campaign", "day"])
    daily["unique_conversions"] = daily["unique_conversions"].fillna(0).astype(int)

    rows: list[dict] = []
    for campaign, group in daily.groupby("campaign", observed=True):
        group = group.sort_values("day")
        final_conversions = float(group["unique_conversions"].sum())
        final_cost = float(group["cost"].sum())
        for horizon in DAYS:
            seen = group[group["day"] < horizon]
            impressions = float(seen["impressions"].sum())
            clicks = float(seen["clicks"].sum())
            current_conversions = float(seen["unique_conversions"].sum())
            current_cost = float(seen["cost"].sum())
            rows.append({
                "campaign": str(campaign),
                "horizon": horizon,
                "impressions": impressions,
                "clicks": clicks,
                "current_conversions": current_conversions,
                "current_cost": current_cost,
                "ctr": clicks / impressions if impressions else 0.0,
                "cvr": current_conversions / impressions if impressions else 0.0,
                "cost_per_current_conversion": current_cost / current_conversions if current_conversions else 0.0,
                "final_conversions": final_conversions,
                "final_cost": final_cost,
                "raw_dataset_rows": raw_rows,
            })
    frame = pd.DataFrame(rows)
    if raw_rows < 16_000_000 or frame["campaign"].nunique() < 600:
        raise RuntimeError(f"Unexpected cardinality rows={raw_rows}, campaigns={frame['campaign'].nunique()}")
    if set(frame["horizon"].unique()) != set(DAYS):
        raise RuntimeError("Missing horizon")
    return frame


def mape(y_true, y_pred):
    y_true = np.asarray(y_true, dtype=float)
    y_pred = np.asarray(y_pred, dtype=float)
    mask = y_true > 0
    return float(np.mean(np.abs((y_true[mask] - y_pred[mask]) / y_true[mask]))) if mask.any() else None


def metrics(y_true, y_pred):
    y_true = np.asarray(y_true, dtype=float)
    y_pred = np.asarray(y_pred, dtype=float)
    denominator = float(np.sum(np.abs(y_true)))
    return {
        "mae": float(mean_absolute_error(y_true, y_pred)),
        "rmse": float(mean_squared_error(y_true, y_pred) ** 0.5),
        "mape": mape(y_true, y_pred),
        "wape": float(np.sum(np.abs(y_true - y_pred)) / denominator) if denominator else None,
        "r2": float(r2_score(y_true, y_pred)) if len(y_true) > 1 else None,
    }


def candidates():
    return {
        "median_baseline": DummyRegressor(strategy="median"),
        "hist_gradient_boosting_log_target": TransformedTargetRegressor(
            regressor=HistGradientBoostingRegressor(
                max_iter=350, learning_rate=0.045, max_leaf_nodes=20,
                min_samples_leaf=12, l2_regularization=1.0, random_state=SEED
            ), func=np.log1p, inverse_func=np.expm1,
        ),
        "random_forest_log_target": TransformedTargetRegressor(
            regressor=RandomForestRegressor(
                n_estimators=500, min_samples_leaf=3, max_features=0.85,
                n_jobs=-1, random_state=SEED
            ), func=np.log1p, inverse_func=np.expm1,
        ),
    }


def fit_predict(model, train, target_frame, target):
    model.fit(train[FEATURES], train[target])
    return np.clip(np.asarray(model.predict(target_frame[FEATURES]), dtype=float), 0, None)


def by_horizon(frame, prediction, target):
    result = {}
    for horizon in DAYS:
        mask = frame["horizon"].to_numpy() == horizon
        result[str(horizon)] = metrics(frame.loc[mask, target], prediction[mask])
    return result


def train_target(train, validation, test, target):
    comparisons = {}
    for name, model in candidates().items():
        pred = fit_predict(model, train, validation, target)
        comparisons[name] = {"overall": metrics(validation[target], pred), "by_horizon": by_horizon(validation, pred, target)}
    selected = min(comparisons, key=lambda name: comparisons[name]["overall"]["mae"])
    final_model = candidates()[selected]
    train_validation = pd.concat([train, validation], ignore_index=True)
    test_prediction = fit_predict(final_model, train_validation, test, target)
    test_metrics = {"overall": metrics(test[target], test_prediction), "by_horizon": by_horizon(test, test_prediction, target)}
    return selected, final_model, comparisons, test_metrics, test_prediction


def main(input_path: Path, output_dir: Path):
    output_dir.mkdir(parents=True, exist_ok=True)
    source = validate_source(input_path)
    frame = aggregate(input_path)
    aggregated_path = output_dir / "campaign_horizon_snapshots.csv"
    frame.to_csv(aggregated_path, index=False)

    outer = GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=SEED)
    tv_idx, test_idx = next(outer.split(frame, groups=frame["campaign"]))
    tv = frame.iloc[tv_idx].copy()
    test = frame.iloc[test_idx].copy()
    inner = GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=SEED + 1)
    train_idx, validation_idx = next(inner.split(tv, groups=tv["campaign"]))
    train = tv.iloc[train_idx].copy()
    validation = tv.iloc[validation_idx].copy()

    conversion_name, conversion_model, conversion_comparison, conversion_test, conversion_prediction = train_target(
        train, validation, test, "final_conversions"
    )
    cost_name, cost_model, cost_comparison, cost_test, cost_prediction = train_target(
        train, validation, test, "final_cost"
    )

    version = "criteo-progress-2026.08.02"
    artifact = {
        "version": version,
        "conversion_model": conversion_model,
        "cost_model": cost_model,
        "features": FEATURES,
        "conversion_model_name": conversion_name,
        "cost_model_name": cost_name,
        "trained_at": datetime.now(timezone.utc).isoformat(),
        "source": "Criteo Attribution Modeling for Bidding Dataset",
        "source_url": "https://ailab.criteo.com/criteo-attribution-modeling-bidding-dataset/",
        "license": "CC BY-NC-SA 4.0",
        "dataset_sha256": source["sha256"],
        "horizons": list(DAYS),
    }
    model_path = output_dir / "criteo_progress_model.joblib"
    joblib.dump(artifact, model_path, compress=3)

    test_output = test.copy()
    test_output["predicted_final_conversions"] = conversion_prediction
    test_output["predicted_final_cost"] = cost_prediction
    test_output["conversion_absolute_error"] = np.abs(test_output["final_conversions"] - conversion_prediction)
    test_output["cost_absolute_error"] = np.abs(test_output["final_cost"] - cost_prediction)
    predictions_path = output_dir / "progress_test_predictions.csv"
    test_output.to_csv(predictions_path, index=False)

    payload = {
        "status": "trained_on_official_data",
        "version": version,
        "source": artifact["source"],
        "source_url": artifact["source_url"],
        "license": artifact["license"],
        "dataset_sha256": source["sha256"],
        "dataset_bytes": source["bytes"],
        "raw_rows": int(frame["raw_dataset_rows"].iloc[0]),
        "aggregated_rows": len(frame),
        "campaigns": int(frame["campaign"].nunique()),
        "train_campaigns": int(train["campaign"].nunique()),
        "validation_campaigns": int(validation["campaign"].nunique()),
        "test_campaigns": int(test["campaign"].nunique()),
        "conversion_validation_comparison": conversion_comparison,
        "cost_validation_comparison": cost_comparison,
        "conversion_test_metrics": conversion_test["overall"],
        "conversion_test_by_horizon": conversion_test["by_horizon"],
        "cost_test_metrics": cost_test["overall"],
        "cost_test_by_horizon": cost_test["by_horizon"],
        "selected_conversion_model": conversion_name,
        "selected_cost_model": cost_name,
        "model_sha256": sha256(model_path),
        "aggregated_sha256": sha256(aggregated_path),
        "test_predictions_sha256": sha256(predictions_path),
        "limitations": [
            "cost and cpo are transformed, not real prices",
            "campaign IDs and contextual features are anonymized",
            "campaigns are disjoint across train, validation and test",
            "model selection uses validation only; test is opened once after selection",
            "this module is independent from Hillstrom",
        ],
    }
    metrics_path = output_dir / "criteo_progress_metrics.json"
    metrics_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    (output_dir / "dataset_manifest.json").write_text(json.dumps(source, indent=2), encoding="utf-8")
    print(json.dumps(payload, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    main(args.input, args.output)
