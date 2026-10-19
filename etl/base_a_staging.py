#!/usr/bin/env python3
"""
Paso 1 de la carga: hoja BASE del Excel de macroinsumos -> staging.base (SQL).

Uso:
    python3 etl/base_a_staging.py "MACROINSUMOS_2025-2026.xlsx" etl/out/staging_base.sql

Genera un .sql que crea staging.base y la llena con una fila por lote (nave x
material) tal como viene en la hoja BASE. No transforma nada: la lógica de
negocio vive en etl/transformar_base.sql (paso 2).

El archivo generado contiene datos operativos y de costos de la empresa:
queda en etl/out/ (ignorado por git) y NO debe subirse al repositorio.

Requiere: pandas, openpyxl.
"""
import math
import sys
from pathlib import Path

import pandas as pd

# columna en staging.base -> encabezado exacto en la hoja BASE (se compara sin
# espacios al inicio/fin ni dobles espacios, RESPETANDO mayúsculas: la hoja
# tiene "PUERTO" (Callao/Chancay) y "Puerto" (costo real de terminal))
COLUMNAS = {
    "anio": "AÑO", "mes_txt": "MES", "mn": "MN", "lote_sap": "LOTE",
    "producto": "PRODUCTO", "material": "MATERIAL", "clave": "ID",
    "puerto": "PUERTO", "origen": "ORIGEN", "tm_manifestadas": "CANTIDAD MANIFESTADA",
    # salida de terminal (peso balanza puerto) por destino
    "d_5001": "CANTIDAD PUERTO 5001 LURIN", "d_1028": "CANTIDAD PUERTO 1028 LURIN 2",
    "d_5003": "CANTIDAD PUERTO 5003 CHANCAY", "d_5029": "CANTIDAD PUERTO GHCORP 5029",
    "d_2111": "CANTIDAD PUERTO ALM 2111 RANSA ARGENTINA", "d_2110": "CANTIDAD PUERTO ALM 2110 BULKBOX",
    "d_2129": "CANTIDAD PUERTO ALM 2129 DIEF", "d_2130": "CANTIDAD PUERTO ALM 2130 RANSA OQUENDO",
    # ingreso en destino (EM SAP)
    "i_5001": "CANTIDAD INGRESO 5001", "i_1028": "CANTIDAD INGRESO 1028",
    "i_5003": "CANTIDAD INGRESO 5003", "i_5029": "CANTIDAD INGRESO 5029",
    "i_2111": "CANTIDAD INGRESO 2111 RANSA ARGENTINA", "i_2110": "CANTIDAD INGRESO 2110 BULKBOX",
    "i_2129": "CANTIDAD INGRESO ALM 2129 DIEF", "i_2130": "CANTIDAD INGRESO ALM 2130 RANSA OQUENDO",
    # salida de almacén tercero
    "s_2111": "CANTIDAD SALIDA ALM 2111 RANSA ARGENTINA", "s_2110": "CANTIDAD SALIDA ALM 2110 RANSA PRIMAX",
    "s_2129": "CANTIDAD SALIDA ALM 2129 DIEF", "s_2130": "CANTIDAD SALIDA ALM 2130 RANSA OQUENDO",
    # llegada a planta desde almacén tercero
    "a_5001": "CANTIDAD INGRESO AT - 5001", "a_1028": "CANTIDAD INGRESO AT - 1028",
    "a_5003": "CANTIDAD INGRESO AT 5003", "a_5029": "CANTIDAD INGRESO AT 5029",
    "merma_almacenamiento": "MERMA DE ALMACENAMIENTO",
    "pen_pto_pab_kg": "PENALIDAD DE TRANSPORTE PUERTO - PAB+AT",
    "pen_at_pab_kg": "PENALIDAD DE TRASLADO AT - PAB",
    "cif_usd_tm": "COSTO DEL PRODUCTO x TM (CIF ) USD",
    "recupero_merma": "RECUPERADO/DESCONTADO MERMA TRAVESIA",
    "tarifa_descarga": "TARIFAS",
    # plan de distribución (TM)
    "plan_5001": "PLAN PAB LURIN", "plan_1028": "PLAN PAB LURIN 2", "plan_5003": "PLAN PAB CHANCAY",
    "plan_5029": "PLAN PAB GH", "plan_2111": "PLAN RANSA ARGENTINA", "plan_2130": "PLAN RANSA OQUENDO",
    "plan_2129": "PLAN DIEF",
    # costos plan (S/)
    "pl_terminal": "Puerto Plan", "pl_surveyor": "Surveyor Plan", "pl_agencia": "AG Maritimo Plan",
    "pl_balanza": "Balanza Plan", "pl_pto_pab": "PTO-PAB Plan", "pl_pto_alm": "PTO-ALM Plan",
    "pl_alm_pab": "ALM-PAB Plan", "pl_almacenaje": "Almacenaje Plan", "pl_cargador": "Cargador Plan",
    "pl_he": "He Plan",
    # costos reales (S/)
    "r_terminal": "Puerto", "r_surveyor": "Surveyor", "r_agencia": "AG Maritimo", "r_balanza": "Balanza",
    "r_descarga": "COSTOS DESCARGA REAL", "r_pto_pab": "PTO-PAB", "r_pto_alm": "PTO-ALM",
    "r_alm_pab": "COSTOS TRANSPORTE AT REAL", "r_almacenaje": "Almacenaje", "r_cargador": "Cargador",
    "r_he": "He", "r_almacen_total": "COSTOS ALMACENAMIENTO REAL",
    # presupuesto (S/)
    "pp_descarga": "COSTOS DESCARGA PPTO", "pp_transporte": "COSTOS TRANSPORTE PPTO",
    "pp_almacen": "COSTOS ALMACENAMIENTO PPTO", "pp_total": "COSTO TOTAL PPTO",
    # totales de la hoja, solo para conciliar (etl/validar_base.sql)
    "x_tm_descargada": "CANTIDAD TOTAL DESCARGADA", "x_tm_ingresada": "CANTIDAD TOTAL INGRESADA",
    "x_merma_total": "MERMA TOTAL DEL PROCESO", "x_costo_plan": "COSTO TOTAL PLAN",
    "x_costo_real": "COSTO TOTAL REAL",
    "comentarios": "Comentarios", "estado": "Estado",
}
TEXTO = {"mes_txt", "mn", "lote_sap", "producto", "material", "clave", "puerto", "origen", "comentarios", "estado"}


def norm(h):
    return " ".join(str(h).split())


def sql_val(v, texto):
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return "null"
    if texto:
        return "'" + " ".join(str(v).split()).replace("'", "''") + "'"
    if isinstance(v, str):
        v = v.strip()
        if v == "" or v.startswith("#"):
            return "null"
        try:
            v = float(v)
        except ValueError:
            return "null"
    return repr(round(float(v), 6))


def main(xlsx, out):
    df = pd.read_excel(xlsx, sheet_name="BASE")
    por_nombre = {norm(c): c for c in df.columns}
    faltan = [h for h in COLUMNAS.values() if norm(h) not in por_nombre]
    if faltan:
        sys.exit(f"Encabezados no encontrados en BASE: {faltan}")
    df = df[df[por_nombre[norm("MN")]].notna()]

    cols = list(COLUMNAS)
    lines = [
        "-- Generado por etl/base_a_staging.py — CONTIENE DATOS DE LA EMPRESA, no subir a git.",
        "create schema if not exists staging;",
        "drop table if exists staging.base;",
        "create table staging.base (fila int primary key, anio int, "
        + ", ".join(f"{c} {'text' if c in TEXTO else 'numeric'}" for c in cols if c != "anio")
        + ");",
    ]
    for i, (_, r) in enumerate(df.iterrows(), start=2):  # fila = fila de Excel
        vals = [str(i)] + [sql_val(r[por_nombre[norm(COLUMNAS[c])]], c in TEXTO) for c in cols]
        lines.append(f"insert into staging.base (fila, {', '.join(cols)}) values ({', '.join(vals)});")
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    Path(out).write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{len(df)} lotes -> {out}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
