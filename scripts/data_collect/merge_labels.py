"""Merge two independent hand-labelling passes into one label CSV (labels_template.csv columns + provenance).

usage: python3 -I merge_labels.py <pass1.csv> <pass2.csv> <split.csv> <sources.json> <out.csv> [--exclude names.txt]
pass CSVs: file,reps,partial,rep_conf,rep_times,form,wrong_keys,form_conf,view_check,people,notes (LABEL_RULES.md).
sources.json: {"default": {...}} or per-file overrides with keys source, licence, person_id, exercise, angle_deg, url.
For files named like Mendeley (subject_NNN_<ex>_<good|bad>_<view>) those fields are derived from the name.
Rules: reps agree exactly -> rep_status ok, else uncertain (excluded from rep accuracy).
form: both normal -> normal; both wrong with >=1 shared key -> wrong (wrong_key = shared keys);
anything else -> form_status uncertain (excluded from warning rates). Keys named by one pass only -> uncertain_keys.
"""
import csv, json, re, sys

EX = {"squat": "squat", "push_up": "pushup", "back": "row"}
VIEW = {"side": "side", "diagonal": "diag", "front": "front", "back": "back"}
COLUMNS = ["file", "exercise", "angle_deg", "form", "wrong_key", "reps", "source", "licence", "person_id", "split",
           "rep_status", "form_status", "partial", "rep_conf", "wrong_reps", "wrong_conf", "uncertain_keys",
           "other_errors", "dataset_label", "people", "url", "notes"]


def keys(s):
    out = {}
    for item in filter(None, (s or "").split(";")):
        k, _, rest = item.strip().partition(":")
        if k == "other":
            out.setdefault("other", []).append(rest)
            continue
        reps, _, conf = rest.rpartition(":")
        out[k] = (reps, conf)
    return out


def merge(a, b, meta, split):
    k1, k2 = keys(a["wrong_keys"]), keys(b["wrong_keys"])
    o1, o2 = k1.pop("other", []), k2.pop("other", [])
    shared = sorted(set(k1) & set(k2))
    if a["form"] == b["form"] == "normal":
        form, fstat = "normal", "ok"
    elif a["form"] == b["form"] == "wrong" and shared:
        form, fstat = "wrong", "ok"
    else:
        form, fstat = a["form"] + "|" + b["form"], "uncertain"
    reps_ok = a["reps"].strip() == b["reps"].strip() and a["reps"].strip() != ""
    views = {a["view_check"].split("+")[0].strip(), b["view_check"].split("+")[0].strip()}
    angle = meta.get("angle_deg")
    if len(views) == 1 and VIEW.get(views.pop()) not in (None, angle):  # both annotators see another view
        angle = VIEW[a["view_check"].split("+")[0].strip()]
    return {**meta, "angle_deg": angle, "split": split.get((meta["source"], meta["person_id"]), "?"),
            "form": form if fstat == "ok" else "uncertain", "form_status": fstat,
            "wrong_key": ";".join(shared) if form == "wrong" else "",
            "wrong_reps": ";".join(f"{k1[k][0]}|{k2[k][0]}" for k in shared) if form == "wrong" else "",
            "wrong_conf": ";".join(f"{k1[k][1]}|{k2[k][1]}" for k in shared) if form == "wrong" else "",
            "uncertain_keys": ";".join(sorted(set(k1) ^ set(k2))),
            "other_errors": " / ".join(sorted(set(o1) | set(o2))),
            "reps": a["reps"].strip() if reps_ok else f"{a['reps']}|{b['reps']}",
            "rep_status": "ok" if reps_ok else "uncertain",
            "partial": f"{a['partial']}|{b['partial']}", "rep_conf": f"{a['rep_conf']}|{b['rep_conf']}",
            "people": a["people"] if a["people"] == b["people"] else f"{a['people']}|{b['people']}",
            "notes": f"p1: {a['notes']} // p2: {b['notes']}"}


def mendeley_meta(name):
    m = re.fullmatch(r"subject_(\d+)_(squat|push_up|back)_(good|bad)_(side|diagonal|front)", name)
    if not m:
        return None
    return {"file": name, "exercise": EX[m[2]], "angle_deg": VIEW[m[4]], "source": "mendeley_mv7",
            "licence": "CC BY 4.0", "person_id": f"s{m[1]}", "dataset_label": m[3],
            "url": "https://data.mendeley.com/datasets/kgbb3yn47p/3"}


def main(p1, p2, split_csv, sources, out, *flags):
    rd = lambda p: {r["file"]: r for r in csv.DictReader(open(p))}
    a, b = rd(p1), rd(p2)
    split = {(r["source"], r["person_id"]): r["split"] for r in csv.DictReader(open(split_csv))}
    src = json.load(open(sources)) if sources != "-" else {}
    excl = set(open(flags[flags.index("--exclude") + 1]).read().split()) if "--exclude" in flags else set()
    rows = []
    for f in sorted(set(a) | set(b)):
        meta = {**(mendeley_meta(f) or {}), **src.get("default", {}), **src.get(f, {}), "file": f}
        if f not in a or f not in b:
            r = {**meta, "rep_status": "missing_pass", "form_status": "missing_pass"}
        else:
            r = merge(a[f], b[f], meta, split)
        if f in excl:
            r.update(rep_status="excluded_duplicate", form_status="excluded_duplicate", form="excluded")
        rows.append(r)
    with open(out, "w", newline="") as fh:
        w = csv.DictWriter(fh, COLUMNS, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    ok = sum(r["rep_status"] == "ok" for r in rows)
    print(f"{len(rows)} files, reps agreed {ok}, form agreed {sum(r['form_status'] == 'ok' for r in rows)}")


if __name__ == "__main__":
    t = {"reps": "5", "partial": "0", "rep_conf": "high", "form": "wrong", "view_check": "side", "people": "1", "notes": ""}
    r = merge({**t, "wrong_keys": "squat_shallow:all:high;other:lean"}, {**t, "wrong_keys": "squat_shallow:1,2:low;squat_hips_first:all:low"},
              mendeley_meta("subject_001_squat_bad_side"), {("mendeley_mv7", "s001"): "tuning"})
    assert r["wrong_key"] == "squat_shallow" and r["uncertain_keys"] == "squat_hips_first" and r["rep_status"] == "ok" and r["split"] == "tuning"
    assert merge({**t, "wrong_keys": "", "form": "normal", "reps": "4"}, {**t, "wrong_keys": ""}, mendeley_meta("subject_001_squat_bad_side"), {})["form_status"] == "uncertain"
    main(*sys.argv[1:])
