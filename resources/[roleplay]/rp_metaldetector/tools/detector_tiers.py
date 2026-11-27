"""
rp_metaldetector / tools/detector_tiers.py
Colores de cada nivel de detector (sRGB), compartidos por build_detector.py y render_icons.py.
Deben coincidir con METALDETECTOR.TIERS[n].color de shared/s_config.lua (color del cuerpo).
"""

# cuerpo (caja, apoyabrazos), acento (aros de la empuñadura, botón), vara
TIERS = {
    1: {"body": (0.10, 0.42, 0.95), "accent": (0.90, 0.92, 0.95), "shaft": (0.05, 0.05, 0.06)},  # azul
    2: {"body": (0.32, 0.78, 0.22), "accent": (0.10, 0.10, 0.10), "shaft": (0.05, 0.05, 0.06)},  # verde
    3: {"body": (0.82, 0.10, 0.08), "accent": (0.95, 0.95, 0.95), "shaft": (0.05, 0.05, 0.06)},  # rojo
    4: {"body": (1.00, 0.72, 0.02), "accent": (0.85, 0.06, 0.06), "shaft": (0.05, 0.05, 0.06)},  # amarillo
    5: {"body": (0.06, 0.06, 0.07), "accent": (1.00, 0.70, 0.10), "shaft": (0.55, 0.56, 0.60)},  # grafito y oro, vara cromada
}

# Colores que no cambian por nivel
FIXED = {"black": (0.035, 0.035, 0.04), "foam": (0.06, 0.06, 0.065), "knob": (0.12, 0.12, 0.13), "screen": (1, 1, 1)}


def srgb_to_lin(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)
