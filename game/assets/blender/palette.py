import common

def get_palette():
    """Generates all standard horror palette materials."""
    p = {}
    p['ghost_skin'] = common.create_material('GhostSkin', (0.77, 0.82, 0.80), roughness=0.85)
    p['ghost_robe'] = common.create_material('GhostRobe', (0.09, 0.08, 0.11), roughness=0.95)
    p['ghost_hair'] = common.create_material('GhostHair', (0.12, 0.11, 0.13), roughness=0.75)
    p['ghost_eye_void'] = common.create_material('GhostEyeVoid', (0.02, 0.02, 0.03), roughness=1.0)
    p['ghost_claw'] = common.create_material('GhostClaw', (0.15, 0.14, 0.13), roughness=0.5)
    
    p['player_skin'] = common.create_material('PlayerSkin', (0.72, 0.58, 0.51), roughness=0.8)
    p['player_hair'] = common.create_material('PlayerHair', (0.12, 0.09, 0.08), roughness=0.9)
    p['player_jacket'] = common.create_material('PlayerJacket', (0.14, 0.20, 0.17), roughness=0.85)
    p['player_jeans'] = common.create_material('PlayerJeans', (0.10, 0.13, 0.18), roughness=0.9)
    p['player_boots'] = common.create_material('PlayerBoots', (0.09, 0.07, 0.06), roughness=0.7)
    
    p['tactical_metal'] = common.create_material('TacticalMetal', (0.12, 0.13, 0.14), roughness=0.45, metallic=0.75)
    p['flashlight_lens'] = common.create_material(
        'FlashlightLens', (0.86, 0.90, 0.93), roughness=0.1, metallic=0.1,
        emission=(1.0, 0.95, 0.8), emission_strength=3.0
    )
    
    p['leather_dark'] = common.create_material('LeatherDark', (0.17, 0.09, 0.05), roughness=0.8)
    p['brass_antique'] = common.create_material('BrassAntique', (0.58, 0.47, 0.22), roughness=0.4, metallic=0.85)
    p['parchment'] = common.create_material('Parchment', (0.80, 0.74, 0.59), roughness=0.9)
    p['blood_rune'] = common.create_material('BloodRune', (0.37, 0.05, 0.07), roughness=0.5)
    
    p['stone_altar'] = common.create_material('StoneAltar', (0.20, 0.20, 0.22), roughness=0.9)
    p['candle_wax'] = common.create_material('CandleWax', (0.86, 0.83, 0.76), roughness=0.4)
    p['candle_flame'] = common.create_material(
        'CandleFlame', (1.0, 0.53, 0.07), roughness=0.2,
        emission=(1.0, 0.6, 0.1), emission_strength=5.0
    )
    
    p['wood_plank'] = common.create_material('WoodPlank', (0.20, 0.13, 0.08), roughness=0.85)
    p['aged_iron'] = common.create_material('AgedIron', (0.11, 0.11, 0.12), roughness=0.5, metallic=0.8)
    
    p['wall_plaster'] = common.create_material('WallPlaster', (0.24, 0.24, 0.23), roughness=0.95)
    p['wood_trim'] = common.create_material('WoodTrim', (0.13, 0.09, 0.05), roughness=0.85)
    p['floor_boards'] = common.create_material('FloorBoards', (0.15, 0.10, 0.06), roughness=0.7)
    
    p['painting_frame'] = common.create_material('PaintingFrame', (0.16, 0.11, 0.06), roughness=0.7, metallic=0.3)
    p['painting_canvas'] = common.create_material('PaintingCanvas', (0.08, 0.07, 0.10), roughness=0.95)
    p['ghostly_figure'] = common.create_material('GhostlyFigure', (0.45, 0.47, 0.51), roughness=0.9)
    
    p['rug_crimson'] = common.create_material('RugCrimson', (0.29, 0.08, 0.10), roughness=0.95)
    p['rug_gold_border'] = common.create_material('RugGoldBorder', (0.46, 0.35, 0.16), roughness=0.9)
    p['rug_fringe'] = common.create_material('RugFringe', (0.65, 0.60, 0.50), roughness=0.95)
    
    # --- Farmhouse & Gameplay Props ---
    p['rat_fur'] = common.create_material('RatFur', (0.28, 0.23, 0.19), roughness=0.92)
    p['rat_pink'] = common.create_material('RatPink', (0.68, 0.46, 0.46), roughness=0.70)
    p['rat_eye'] = common.create_material('RatEye', (0.02, 0.02, 0.02), roughness=0.15)
    
    p['galvanized_metal'] = common.create_material('GalvanizedMetal', (0.48, 0.50, 0.52), roughness=0.42, metallic=0.85)
    p['metal_rust'] = common.create_material('MetalRust', (0.32, 0.16, 0.10), roughness=0.95, metallic=0.30)
    
    p['fuse_ceramic'] = common.create_material('FuseCeramic', (0.86, 0.85, 0.82), roughness=0.30)
    p['fuse_metal'] = common.create_material('FuseMetal', (0.75, 0.77, 0.80), roughness=0.25, metallic=0.90)
    p['fuse_indicator'] = common.create_material('FuseIndicator', (0.12, 0.12, 0.14), roughness=0.50)
    
    p['battery_casing'] = common.create_material('BatteryCasing', (0.08, 0.08, 0.09), roughness=0.45)
    p['battery_stripe'] = common.create_material('BatteryStripe', (0.78, 0.60, 0.10), roughness=0.35)
    p['battery_terminal'] = common.create_material('BatteryTerminal', (0.72, 0.74, 0.77), roughness=0.30, metallic=0.88)
    
    p['first_aid_body'] = common.create_material('FirstAidBody', (0.85, 0.85, 0.84), roughness=0.35)
    p['first_aid_cross'] = common.create_material('FirstAidCross', (0.76, 0.08, 0.08), roughness=0.40)
    p['first_aid_latch'] = common.create_material('FirstAidLatch', (0.25, 0.25, 0.27), roughness=0.30, metallic=0.85)
    
    p['can_metal'] = common.create_material('CanMetal', (0.66, 0.68, 0.70), roughness=0.35, metallic=0.85)
    p['can_label'] = common.create_material('CanLabel', (0.55, 0.20, 0.14), roughness=0.80)
    
    return p
