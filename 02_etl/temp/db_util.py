#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Wspolny modul polaczenia do SQL Server (pyodbc) dla skryptow ETL/testow NFX."""
import json, os
import pyodbc


def load_config(path=None):
    path = path or os.path.join(os.path.dirname(__file__), "config.json")
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def connect(cfg=None, database=None):
    cfg = cfg or load_config()
    db = database or cfg["database"]
    parts = [
        f"DRIVER={{{cfg['driver']}}}",
        f"SERVER={cfg['server']}",
        f"DATABASE={db}",
        "TrustServerCertificate=yes",
    ]
    if cfg.get("trusted_connection", True):
        parts.append("Trusted_Connection=yes")
    else:
        parts.append(f"UID={cfg['uid']}")
        parts.append(f"PWD={cfg['pwd']}")
    conn = pyodbc.connect(";".join(parts), autocommit=False)
    return conn


def connect_master(cfg=None):
    return connect(cfg, database="master")
