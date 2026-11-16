"""Comparator 2: the consensus anomaly detector of Ansah-Narh & Asare Afrane (arXiv:2607.21559).

Usage (project folder):  python3 -I scripts/12_consensus.py [MODEL=arm]

Their method, as published (s2.2-2.3): nine features per region-month (total cases, lag-1 total,
seasonal residual = x - mean of that calendar month over all years, within-region z-score over the
whole period, sin/cos of month, year - 2014, under-5 and over-5 counts), standardised; four
detectors (Isolation Forest, 300 trees, contamination 0.10; LOF, k = 20, 90th percentile;
autoencoder 9-4-9, Adam, batch 32, <= 150 epochs, early stopping on a 10% split, 90th percentile
of reconstruction error; Elliptic Envelope / MCD, contamination 0.10); anomaly if S >= 3 of 4 agree.

Adaptations, so it can be scored against our model on the same events:
  * DISTRICT-month (247 units) instead of region-month; confirmed OPD cases (they used admissions);
    over-5 = conf_5_14 + conf_ov15. Year is centred at 2015 (our data start).
  * PROSPECTIVE: for target year Y everything is learnt from years < Y only - the seasonal means,
    the z-score mean and SD, the scaler, the four detectors and their percentile thresholds - and
    the months of Y are scored as new points. As published, all of these used the whole decade,
    including the months being judged (and the months after them), which a real-time system cannot.
  * Autoencoder: scikit-learn MLPRegressor (one hidden layer of 4 units, ReLU) instead of TensorFlow.
  * Besides the published setting (each detector at its 90th percentile, S >= 3), the percentile q
    and the vote threshold S are varied, so the method can be compared at a MATCHED false-alert rate.
Synthetic events: the injected district-months saved by 09_synthetic.R (same events as our model).
An injection also changes next month's lag-1 feature; this is recomputed. Age split of injected
cases follows the district-month's observed under-5 share.
Output: out/synthetic_consensus.csv, out/consensus_real_flags.csv (published setting).
"""
import sys

import numpy as np
import pandas as pd
from sklearn.covariance import EllipticEnvelope
from sklearn.ensemble import IsolationForest
from sklearn.neighbors import LocalOutlierFactor
from sklearn.neural_network import MLPRegressor
from sklearn.preprocessing import StandardScaler

MODEL = sys.argv[1] if len(sys.argv) > 1 else "arm"
QS = [0.10, 0.05, 0.02, 0.01]          # share of training points above each detector's threshold
SS = [2, 3, 4]                         # votes needed
SEED = 20261028

cases = pd.read_csv("data/derived/cases_district_month.csv").sort_values(["unit", "year", "m"])
cases["u5"] = cases.conf_u5
cases["o5"] = cases.conf_5_14 + cases.conf_ov15
cases["t"] = (cases.year - 2015) * 12 + cases.m - 1
inj_all = pd.read_csv(f"out/synthetic_injections_{MODEL}.csv")
FEATS = ["total", "lag1", "residual", "zscore", "msin", "mcos", "yr", "u5", "o5"]


def features(x, smean, mu, sd):
    """x: unit, year, m, t, conf_tot, u5, o5 (consecutive months per unit). Lag-1 from x itself."""
    x = x.sort_values(["unit", "t"]).copy()
    x["total"] = x.conf_tot.astype(float)
    x["lag1"] = x.groupby("unit").total.shift(1)
    x = x.merge(smean, on=["unit", "m"], how="left").merge(mu, on="unit").merge(sd, on="unit")
    x["residual"] = x.total - x.smean
    x["zscore"] = (x.total - x.mu) / x.sd
    x["msin"] = np.sin(2 * np.pi * x.m / 12)
    x["mcos"] = np.cos(2 * np.pi * x.m / 12)
    x["yr"] = x.year - 2015
    return x


def scores(models, X):
    """Higher = more anomalous, for each detector."""
    sc, iso, lof, ae, ee = models
    Z = sc.transform(X)
    return np.column_stack([-iso.score_samples(Z), -lof.score_samples(Z),
                            ((ae.predict(Z) - Z) ** 2).sum(1), -ee.score_samples(Z)])


rows_ev, rows_fa, real_flags = [], [], []
for Y in range(2018, 2026):
    tr = cases[cases.year < Y]
    smean = tr.groupby(["unit", "m"]).conf_tot.mean().rename("smean").reset_index()
    mu = tr.groupby("unit").conf_tot.mean().rename("mu").reset_index()
    sd = tr.groupby("unit").conf_tot.std().rename("sd").reset_index()
    ftr = features(tr, smean, mu, sd).dropna(subset=["lag1"])
    Xtr = ftr[FEATS].to_numpy()
    sc = StandardScaler().fit(Xtr)
    Z = sc.transform(Xtr)
    iso = IsolationForest(n_estimators=300, contamination=0.10, random_state=SEED).fit(Z)
    lof = LocalOutlierFactor(n_neighbors=20, novelty=True, contamination=0.10).fit(Z)
    ae = MLPRegressor(hidden_layer_sizes=(4,), solver="adam", batch_size=32, max_iter=150,
                      early_stopping=True, validation_fraction=0.10, random_state=SEED).fit(Z, Z)
    ee = EllipticEnvelope(contamination=0.10, random_state=SEED).fit(Z)
    models = (sc, iso, lof, ae, ee)
    s_tr = np.column_stack([-iso.score_samples(Z), -lof.negative_outlier_factor_,
                            ((ae.predict(Z) - Z) ** 2).sum(1), -ee.score_samples(Z)])
    thr = {q: np.quantile(s_tr, 1 - q, axis=0) for q in QS}

    # the target year, plus December of Y-1 for the January lag
    base = cases[(cases.year == Y) | ((cases.year == Y - 1) & (cases.m == 12))]

    def votes(x):
        f = features(x, smean, mu, sd)
        f = f[f.year == Y].reset_index(drop=True)
        s = scores(models, f[FEATS].to_numpy())
        return f[["unit", "m"]], {q: (s > thr[q]).sum(1) for q in QS}

    key0, v0 = votes(base)
    real = key0.copy()
    for q in QS:
        for S in SS:
            real[f"f_{q}_{S}"] = v0[q] >= S
    rr = real[["unit", "m", "f_0.1_3"]].rename(columns={"f_0.1_3": "flag"})
    real_flags.append(rr[rr.flag].assign(year=Y).drop(columns="flag"))
    rows_fa.append(pd.DataFrame([dict(year=Y, q=q, S=S, real_rate=real[f"f_{q}_{S}"].mean())
                                 for q in QS for S in SS]))

    inj_y = inj_all[inj_all.year == Y]
    for (typ, k, L, rep), g in inj_y.groupby(["type", "k", "L", "rep"]):
        x = base.merge(g[["unit", "m", "conf", "evid"]], on=["unit", "m"], how="left")
        hit = x.conf.notna() & (x.year == Y)
        share = (x.u5 / x.conf_tot.where(x.conf_tot > 0)).fillna(0.5)
        x.loc[hit, "u5"] = np.round(x.loc[hit, "conf"] * share[hit])
        x.loc[hit, "o5"] = x.loc[hit, "conf"] - x.loc[hit, "u5"]
        x.loc[hit, "conf_tot"] = x.loc[hit, "conf"]
        key, v = votes(x.drop(columns=["conf", "evid"]))
        e = key.merge(g[["unit", "m", "evid"]], on=["unit", "m"], how="left")
        isinj = e.evid.notna().to_numpy()
        for q in QS:
            for S in SS:
                fl = v[q] >= S
                f0 = real[f"f_{q}_{S}"].to_numpy()
                d = pd.DataFrame(dict(evid=e.evid[isinj], m=e.m[isinj], flag=fl[isinj], flag0=f0[isinj]))
                d = d.sort_values(["evid", "m"])
                agg = d.groupby("evid").agg(detected=("flag", "any"), detected0=("flag0", "any"))
                first = d[d.flag].groupby("evid").m.min() - d.groupby("evid").m.min()
                rows_ev.append(pd.DataFrame(dict(type=typ, k=k, L=L, year=Y, rep=rep, q=q, S=S,
                                                 detected=agg.detected.to_numpy(),
                                                 detected0=agg.detected0.to_numpy(),
                                                 delay=first.reindex(agg.index).to_numpy(),
                                                 false_rate=fl[~isinj].mean())))
    print(f"{Y}: real-data flags at published setting (q 0.10, S >= 3): {real['f_0.1_3'].mean():.3f}", flush=True)

ev = pd.concat(rows_ev)
S_ = (ev.groupby(["type", "k", "L", "q", "S"])
        .agg(events=("detected", "size"), sensitivity=("detected", "mean"),
             background=("detected0", "mean"), median_delay=("delay", "median"))
        .reset_index())
fa = ev.groupby(["type", "k", "L", "q", "S", "year", "rep"]).false_rate.first().reset_index()
S_ = S_.merge(fa.groupby(["type", "k", "L", "q", "S"]).false_rate.mean().rename("false_alert_rate").reset_index(),
              on=["type", "k", "L", "q", "S"])
S_["method"] = "consensus"
S_.to_csv("out/synthetic_consensus.csv", index=False)
pd.concat(real_flags).to_csv("out/consensus_real_flags.csv", index=False)
fr = pd.concat(rows_fa).groupby(["q", "S"]).real_rate.mean().unstack()
print("\nShare of real district-months flagged, 2018-2025 (rows q, columns S):\n", fr.round(4))
print("\nOutbreaks:")
print(S_[S_.type == "outbreak"][["q", "S", "k", "L", "sensitivity", "false_alert_rate"]]
      .round(3).to_string(index=False))
