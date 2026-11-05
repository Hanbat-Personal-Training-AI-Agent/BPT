"""Strict JSON entrypoint: duplicate fields and nonfinite constants are rejected."""
import json
from .engine import evaluate


def loads(text):
    def object_pairs(pairs):
        obj={}
        for key,value in pairs:
            if key in obj:raise ValueError('duplicate JSON field: '+key)
            obj[key]=value
        return obj
    def invalid(value):raise ValueError('nonfinite JSON constant: '+value)
    return json.loads(text,object_pairs_hook=object_pairs,parse_constant=invalid)


def evaluate_json(text):
    return evaluate(loads(text))
