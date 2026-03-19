local advisor = {}

local TRACKED_TECHS = {
  "automation",
  "logistics",
  "military",
  "steel-processing",
  "electronics",
  "automation-2",
  "advanced-material-processing",
  "oil-processing",
  "advanced-electronics",
  "advanced-oil-processing",
  "chemical-science-pack",
  "production-science-pack",
  "utility-science-pack",
  "construction-robotics",
  "logistic-robotics",
  "rocket-silo",
  "solar-energy",
  "laser",
  "flamethrower"
}

local TRACKED_ENTITIES = {
  "burner-mining-drill",
  "electric-mining-drill",
  "offshore-pump",
  "boiler",
  "steam-engine",
  "solar-panel",
  "accumulator",
  "stone-furnace",
  "steel-furnace",
  "electric-furnace",
  "assembling-machine-1",
  "assembling-machine-2",
  "assembling-machine-3",
  "lab",
  "radar",
  "transport-belt",
  "fast-transport-belt",
  "express-transport-belt",
  "underground-belt",
  "fast-underground-belt",
  "express-underground-belt",
  "splitter",
  "fast-splitter",
  "express-splitter",
  "burner-inserter",
  "inserter",
  "long-handed-inserter",
  "fast-inserter",
  "bulk-inserter",
  "pumpjack",
  "oil-refinery",
  "chemical-plant",
  "storage-tank",
  "pump",
  "gun-turret",
  "laser-turret",
  "flamethrower-turret",
  "stone-wall",
  "roboport",
  "logistic-robot",
  "construction-robot",
  "locomotive",
  "cargo-wagon",
  "train-stop",
  "rocket-silo"
}

local TRACKED_ITEMS = {
  "automation-science-pack",
  "logistic-science-pack",
  "military-science-pack",
  "chemical-science-pack",
  "production-science-pack",
  "utility-science-pack",
  "space-science-pack",
  "iron-plate",
  "copper-plate",
  "steel-plate",
  "stone-brick",
  "electronic-circuit",
  "advanced-circuit",
  "processing-unit",
  "plastic-bar",
  "low-density-structure",
  "rocket-fuel",
  "rocket-control-unit"
}

local TRACKED_FLUIDS = {
  "water",
  "steam",
  "crude-oil",
  "heavy-oil",
  "light-oil",
  "petroleum-gas",
  "lubricant",
  "sulfuric-acid"
}

local SURFACE_RESOURCES = {
  "iron-ore",
  "copper-ore",
  "coal",
  "stone",
  "uranium-ore",
  "crude-oil"
}

local function initialize_storage_table()
  storage.player_data = storage.player_data or {}
  storage.external_reports = storage.external_reports or {}
  storage.detail_cache = storage.detail_cache or {}
  storage.expanded_details = storage.expanded_details or {}
end

local function round(value)
  return math.floor(value + 0.5)
end

local function sum(entity_counts, names)
  local total = 0
  for _, name in ipairs(names) do
    total = total + (entity_counts[name] or 0)
  end
  return total
end

local function push(items, severity, text)
  table.insert(items, ("[%s] %s"):format(severity, text))
end

local function trim_items(items, maximum)
  while #items > maximum do
    table.remove(items)
  end
end

local function safe_entity_count(force, name)
  local ok, value = pcall(function()
    return force.get_entity_count(name)
  end)
  if ok and value ~= nil then
    return value
  end
  return 0
end

local function tech_researched(force, name)
  local technology = force.technologies[name]
  return technology ~= nil and technology.valid and technology.researched
end

local function one_minute_flow(statistics, name, category)
  if not statistics or not statistics.valid then
    return 0
  end

  local ok, value = pcall(function()
    return statistics.get_flow_count({
      name = name,
      category = category,
      precision_index = defines.flow_precision_index.one_minute
    })
  end)

  if ok and value then
    return value
  end

  return 0
end

local function total_flow(statistics, name, category)
  if not statistics or not statistics.valid then
    return 0
  end

  local ok, value = pcall(function()
    if category == "output" then
      return statistics.get_output_count(name)
    else
      return statistics.get_input_count(name)
    end
  end)

  if ok and value then
    return value
  end

  return 0
end

local function stage_rank(stage_id)
  local order = {
    bootstrapping = 1,
    green = 2,
    oil = 3,
    midgame = 4,
    rocket = 5,
    launch = 6,
    victory = 7
  }

  return order[stage_id] or 1
end

local function describe_stage(snapshot)
  local technologies = snapshot.technologies
  local force_info = snapshot.force
  local metrics = snapshot.metrics

  if force_info.rockets_launched > 0 then
    return {
      id = "victory",
      label = "Post-launch",
      focus = "Tune throughput, stabilize outposts, and scale toward repeatable high-output blocks."
    }
  end

  if technologies["rocket-silo"] then
    return {
      id = "launch",
      label = "Launch prep",
      focus = "Keep the silo fed and eliminate any final shortages in low density structures, rocket fuel, and processing units."
    }
  end

  if technologies["production-science-pack"] and technologies["utility-science-pack"] then
    return {
      id = "rocket",
      label = "Rocket rush",
      focus = "Unlock and build the rocket silo chain while hardening ore, oil, and power for sustained production."
    }
  end

  if technologies["oil-processing"] then
    return {
      id = "midgame",
      label = "Midgame expansion",
      focus = "Scale oil, red circuits, steel, and rail/outpost logistics so purple and yellow science become sustainable."
    }
  end

  if technologies["automation"] and technologies["logistics"] and technologies["steel-processing"] then
    return {
      id = "oil",
      label = "Blue science transition",
      focus = "Bring crude oil online and automate the chain for chemical science."
    }
  end

  if technologies["automation"] or metrics.labs > 0 then
    return {
      id = "green",
      label = "Early automation",
      focus = "Automate red and green science, replace burner work, and build enough smelting to stop hand-feeding the base."
    }
  end

  return {
    id = "bootstrapping",
    label = "Bootstrapping",
    focus = "Set up basic mining, smelting, and red science automation as quickly as possible."
  }
end

local function build_metrics(snapshot)
  local entities = snapshot.entities
  local metrics = {}

  metrics.mining_drills = sum(entities, { "burner-mining-drill", "electric-mining-drill" })
  metrics.burner_drills = entities["burner-mining-drill"] or 0
  metrics.electric_drills = entities["electric-mining-drill"] or 0
  metrics.furnaces = sum(entities, { "stone-furnace", "steel-furnace", "electric-furnace" })
  metrics.stone_furnaces = entities["stone-furnace"] or 0
  metrics.modern_furnaces = sum(entities, { "steel-furnace", "electric-furnace" })
  metrics.assemblers = sum(entities, {
    "assembling-machine-1",
    "assembling-machine-2",
    "assembling-machine-3"
  })
  metrics.labs = entities["lab"] or 0
  metrics.belts = sum(entities, {
    "transport-belt",
    "fast-transport-belt",
    "express-transport-belt"
  })
  metrics.undergrounds = sum(entities, {
    "underground-belt",
    "fast-underground-belt",
    "express-underground-belt"
  })
  metrics.splitters = sum(entities, { "splitter", "fast-splitter", "express-splitter" })
  metrics.inserters = sum(entities, {
    "burner-inserter",
    "inserter",
    "long-handed-inserter",
    "fast-inserter",
    "bulk-inserter"
  })
  metrics.oil_chain = sum(entities, { "pumpjack", "oil-refinery", "chemical-plant" })
  metrics.defense_turrets = sum(entities, {
    "gun-turret",
    "laser-turret",
    "flamethrower-turret"
  })
  metrics.walls = entities["stone-wall"] or 0
  metrics.roboports = entities["roboport"] or 0
  metrics.trains = sum(entities, { "locomotive", "cargo-wagon", "train-stop" })
  metrics.radars = entities["radar"] or 0
  metrics.rocket_silos = entities["rocket-silo"] or 0
  metrics.steam_power = (entities["boiler"] or 0) + (entities["steam-engine"] or 0)
  metrics.solar_power = entities["solar-panel"] or 0
  metrics.accumulators = entities["accumulator"] or 0

  return metrics
end

local function collect_rates(force, surface, sparse)
  local item_stats = force.get_item_production_statistics(surface)
  local fluid_stats = force.get_fluid_production_statistics(surface)
  local item_rates = {}
  local fluid_rates = {}
  local item_totals = {}

  for _, item in ipairs(TRACKED_ITEMS) do
    local prod = round(one_minute_flow(item_stats, item, "input"))
    local cons = round(one_minute_flow(item_stats, item, "output"))
    local total_prod = total_flow(item_stats, item, "input")
    local total_cons = total_flow(item_stats, item, "output")

    -- In sparse mode, only include items with activity
    if not sparse or prod > 0 or cons > 0 then
      item_rates[item] = { production = prod, consumption = cons }
    end
    if not sparse or total_prod > 0 or total_cons > 0 then
      item_totals[item] = { produced = total_prod, consumed = total_cons }
    end
  end

  for _, fluid in ipairs(TRACKED_FLUIDS) do
    local prod = round(one_minute_flow(fluid_stats, fluid, "input"))
    local cons = round(one_minute_flow(fluid_stats, fluid, "output"))

    -- In sparse mode, only include fluids with activity
    if not sparse or prod > 0 or cons > 0 then
      fluid_rates[fluid] = { production = prod, consumption = cons }
    end
  end

  return item_rates, fluid_rates, item_totals
end

local function surface_has_entities(force, surface)
  -- Check if the force has any significant entities on this surface
  -- We use a quick heuristic: check for common early-game entities
  local check_entities = {
    "electric-mining-drill",
    "burner-mining-drill",
    "assembling-machine-1",
    "assembling-machine-2",
    "assembling-machine-3",
    "lab",
    "stone-furnace",
    "steel-furnace",
    "electric-furnace",
    "roboport",
    "rocket-silo"
  }

  for _, entity_name in ipairs(check_entities) do
    local count = surface.count_entities_filtered({
      force = force,
      name = entity_name,
      limit = 1
    })
    if count > 0 then
      return true
    end
  end

  return false
end

local function collect_surface_data(force, surface)
  -- Collect resources for this surface (sparse: only non-zero)
  local resources = {}
  local available_resources = surface.get_resource_counts()
  for _, resource_name in ipairs(SURFACE_RESOURCES) do
    local amount = available_resources[resource_name] or 0
    if amount > 0 then
      resources[resource_name] = amount
    end
  end

  -- Collect rates for this surface (sparse mode: only non-zero)
  local item_rates, fluid_rates, item_totals = collect_rates(force, surface, true)

  -- Collect environment data for this surface
  local enemy_force = game.forces.enemy
  local environment = {
    total_pollution = round(surface.get_total_pollution()),
    enemy_evolution = enemy_force and enemy_force.get_evolution_factor(surface) or 0,
    pollution_evolution = enemy_force and enemy_force.get_evolution_factor_by_pollution(surface) or 0
  }

  return {
    resources = resources,
    rates = {
      items = item_rates,
      fluids = fluid_rates
    },
    totals = {
      items = item_totals
    },
    environment = environment
  }
end

local function aggregate_rates(surfaces_data)
  -- Sum up rates across all surfaces for backward compatibility
  local agg_item_rates = {}
  local agg_fluid_rates = {}
  local agg_item_totals = {}

  -- Initialize with zeros
  for _, item in ipairs(TRACKED_ITEMS) do
    agg_item_rates[item] = { production = 0, consumption = 0 }
    agg_item_totals[item] = { produced = 0, consumed = 0 }
  end
  for _, fluid in ipairs(TRACKED_FLUIDS) do
    agg_fluid_rates[fluid] = { production = 0, consumption = 0 }
  end

  -- Sum across all surfaces
  for _, surface_data in pairs(surfaces_data) do
    for _, item in ipairs(TRACKED_ITEMS) do
      local rate = surface_data.rates.items[item]
      if rate then
        agg_item_rates[item].production = agg_item_rates[item].production + rate.production
        agg_item_rates[item].consumption = agg_item_rates[item].consumption + rate.consumption
      end
      local total = surface_data.totals.items[item]
      if total then
        agg_item_totals[item].produced = agg_item_totals[item].produced + total.produced
        agg_item_totals[item].consumed = agg_item_totals[item].consumed + total.consumed
      end
    end
    for _, fluid in ipairs(TRACKED_FLUIDS) do
      local rate = surface_data.rates.fluids[fluid]
      if rate then
        agg_fluid_rates[fluid].production = agg_fluid_rates[fluid].production + rate.production
        agg_fluid_rates[fluid].consumption = agg_fluid_rates[fluid].consumption + rate.consumption
      end
    end
  end

  return agg_item_rates, agg_fluid_rates, agg_item_totals
end

local function aggregate_resources(surfaces_data)
  -- Sum resources across all surfaces
  local agg_resources = {}
  for _, resource_name in ipairs(SURFACE_RESOURCES) do
    agg_resources[resource_name] = 0
  end

  for _, surface_data in pairs(surfaces_data) do
    for _, resource_name in ipairs(SURFACE_RESOURCES) do
      agg_resources[resource_name] = agg_resources[resource_name] + (surface_data.resources[resource_name] or 0)
    end
  end

  return agg_resources
end

local function collect_snapshot(player)
  local force = player.force
  local current_surface = player.surface
  local technologies = {}
  local entities = {}

  -- Collect technologies (force-wide)
  for _, technology in ipairs(TRACKED_TECHS) do
    technologies[technology] = tech_researched(force, technology)
  end

  -- Collect entity counts (force-wide)
  for _, entity in ipairs(TRACKED_ENTITIES) do
    entities[entity] = safe_entity_count(force, entity)
  end

  -- Collect per-surface data for all surfaces with infrastructure
  local surfaces_data = {}
  local surface_names = {}

  for _, surface in pairs(game.surfaces) do
    if surface.valid and surface_has_entities(force, surface) then
      surfaces_data[surface.name] = collect_surface_data(force, surface)
      table.insert(surface_names, surface.name)
    end
  end

  -- If no surfaces have entities, at least include the current surface
  if next(surfaces_data) == nil then
    surfaces_data[current_surface.name] = collect_surface_data(force, current_surface)
    table.insert(surface_names, current_surface.name)
  end

  -- Aggregate rates and resources across all surfaces (for backward compat with rule engine)
  local agg_item_rates, agg_fluid_rates, agg_item_totals = aggregate_rates(surfaces_data)
  local agg_resources = aggregate_resources(surfaces_data)

  -- Use current surface's environment for the top-level (backward compat)
  local current_surface_data = surfaces_data[current_surface.name] or collect_surface_data(force, current_surface)

  local snapshot = {
    meta = {
      advisor_version = "0.2.0",
      game_version = helpers.game_version,
      tick = game.tick,
      surface = current_surface.name,
      player_index = player.index,
      player_name = player.name,
      force = force.name,
      surface_count = #surface_names,
      surfaces_collected = surface_names
    },
    force = {
      rockets_launched = force.rockets_launched,
      current_research = force.current_research and force.current_research.name or nil
    },
    technologies = technologies,
    entities = entities,

    -- Per-surface breakdown (NEW)
    surfaces = surfaces_data,

    -- Aggregated data (backward compatibility with rule engine)
    resources = agg_resources,
    environment = current_surface_data.environment,
    rates = {
      items = agg_item_rates,
      fluids = agg_fluid_rates
    },
    totals = {
      items = agg_item_totals
    }
  }

  snapshot.metrics = build_metrics(snapshot)
  snapshot.stage = describe_stage(snapshot)
  snapshot.metrics.stage_rank = stage_rank(snapshot.stage.id)

  return snapshot
end

local function top_science_rate(snapshot)
  local names = {
    "automation-science-pack",
    "logistic-science-pack",
    "military-science-pack",
    "chemical-science-pack",
    "production-science-pack",
    "utility-science-pack",
    "space-science-pack"
  }
  local highest = 0

  for _, name in ipairs(names) do
    highest = math.max(highest, snapshot.rates.items[name].production)
  end

  return highest
end

local function analyze_next_focus(snapshot)
  local stage = snapshot.stage
  local metrics = snapshot.metrics
  local items = {}

  push(items, "High", stage.focus)

  if stage.id == "bootstrapping" then
    push(items, "High", "Get to 8-12 mining drills and enough furnaces to fully smelt both iron and copper before chasing more research.")
    push(items, "Medium", "Automate red science with inserter-fed assemblers instead of hand-crafting the pack ingredients.")
  elseif stage.id == "green" then
    push(items, "High", "Push green science so logistics, underground belts, splitters, and steel stop being growth blockers.")
    push(items, "Medium", ("Your base has %d assemblers and %d labs; add more assemblers so research is not outrunning production.")
      :format(metrics.assemblers, metrics.labs))
  elseif stage.id == "oil" then
    push(items, "High", "Bring crude oil online with pumpjacks, refineries, chemical plants, and sulfur/plastic automation for blue science.")
    push(items, "Medium", "Prepare stronger red circuit and steel production before chemical science starts pulling the base apart.")
  elseif stage.id == "midgame" then
    push(items, "High", "Build toward purple and yellow science with rail/logistics expansion, red circuits, and a much larger steel backbone.")
    push(items, "Medium", "Start ore outposts before your starter patches become the next hard stop.")
  elseif stage.id == "rocket" then
    push(items, "High", "Dedicate separate production blocks for low density structures, rocket fuel, and processing units.")
    push(items, "Medium", "Treat ore, oil, and power as launch-critical infrastructure now, not support systems.")
  elseif stage.id == "launch" then
    push(items, "High", "Keep the silo continuously fed and remove any final oil, plate, or power instability.")
    push(items, "Medium", "Make sure outposts and perimeter defenses can survive while the silo drains resources.")
  else
    push(items, "Medium", "You can pivot from winning the map to scaling cleaner block-based production and rail-fed expansion.")
  end

  return {
    title = "1. What To Focus On Next",
    items = items
  }
end

local function analyze_bottleneck(snapshot)
  local metrics = snapshot.metrics
  local resources = snapshot.resources
  local item_rates = snapshot.rates.items
  local fluid_rates = snapshot.rates.fluids
  local candidates = {}

  local function add_candidate(score, text)
    table.insert(candidates, { score = score, text = text })
  end

  local iron_gap = item_rates["iron-plate"].consumption - item_rates["iron-plate"].production
  if iron_gap > 10 or (metrics.stage_rank >= 3 and resources["iron-ore"] < 150000) then
    add_candidate(
      iron_gap + math.max(0, 150000 - resources["iron-ore"]) / 5000,
      ("[High] Iron looks like the tightest core resource: %.0f/min produced vs %.0f/min consumed, with about %d ore left on %s.")
        :format(
          item_rates["iron-plate"].production,
          item_rates["iron-plate"].consumption,
          round(resources["iron-ore"]),
          snapshot.meta.surface
        )
    )
  end

  local copper_gap = item_rates["copper-plate"].consumption - item_rates["copper-plate"].production
  if copper_gap > 10 or (metrics.stage_rank >= 3 and resources["copper-ore"] < 120000) then
    add_candidate(
      copper_gap + math.max(0, 120000 - resources["copper-ore"]) / 5000,
      ("[High] Copper is under pressure: %.0f/min produced vs %.0f/min consumed, with about %d ore left on %s.")
        :format(
          item_rates["copper-plate"].production,
          item_rates["copper-plate"].consumption,
          round(resources["copper-ore"]),
          snapshot.meta.surface
        )
    )
  end

  local steel_gap = item_rates["steel-plate"].consumption - item_rates["steel-plate"].production
  if metrics.stage_rank >= 3 and (steel_gap > 5 or item_rates["steel-plate"].production < 20) then
    add_candidate(
      steel_gap + 12,
      ("[High] Steel is likely throttling expansion: %.0f/min produced vs %.0f/min consumed. Add more iron throughput before adding more assemblers.")
        :format(item_rates["steel-plate"].production, item_rates["steel-plate"].consumption)
    )
  end

  if metrics.stage_rank >= 3 and fluid_rates["crude-oil"].production < 300 then
    add_candidate(
      20 + (300 - fluid_rates["crude-oil"].production) / 10,
      ("[High] Crude oil is thin for your stage: only %.0f/min on average. More pumpjacks/refineries will unlock the rest of the factory.")
        :format(fluid_rates["crude-oil"].production)
    )
  end

  if metrics.stage_rank >= 3 and fluid_rates["petroleum-gas"].production < fluid_rates["petroleum-gas"].consumption then
    add_candidate(
      20 + fluid_rates["petroleum-gas"].consumption - fluid_rates["petroleum-gas"].production,
      ("[High] Petroleum gas is the immediate oil bottleneck: %.0f/min produced vs %.0f/min consumed.")
        :format(fluid_rates["petroleum-gas"].production, fluid_rates["petroleum-gas"].consumption)
    )
  end

  local estimated_load = metrics.electric_drills * 0.8 + metrics.assemblers * 1.1 + metrics.labs * 1.5 + metrics.defense_turrets * 0.4
  local estimated_supply = metrics.steam_power * 2.2 + metrics.solar_power * 0.9 + metrics.accumulators * 0.3
  if metrics.electric_drills > 0 and estimated_supply > 0 and estimated_load > estimated_supply * 1.15 then
    add_candidate(
      estimated_load - estimated_supply + 10,
      ("[Medium] Power is likely close to a brownout: estimated demand %.0f vs supply %.0f from current generators.")
        :format(estimated_load, estimated_supply)
    )
  end

  table.sort(candidates, function(left, right)
    return left.score > right.score
  end)

  local items = {}
  if #candidates == 0 then
    push(items, "Medium", "No single resource bottleneck dominates the heuristics yet; the next constraint is probably general scale rather than one missing input.")
  else
    push(items, "High", candidates[1].text:gsub("^%[High%] ", ""))
    if candidates[2] then
      push(items, "Medium", candidates[2].text:gsub("^%[[^%]]+%] ", ""))
    end
  end

  return {
    title = "2. Biggest Resource Bottleneck",
    items = items
  }
end

local function analyze_patterns(snapshot)
  local metrics = snapshot.metrics
  local technologies = snapshot.technologies
  local items = {}

  if metrics.belts >= 50 and metrics.undergrounds + metrics.splitters < math.max(4, metrics.belts * 0.08) then
    push(items, "High", "Adopt repeatable bus junctions with splitters and undergrounds so expansions stop tearing up your main lines.")
  end

  if metrics.assemblers >= 6 and metrics.labs > 0 then
    push(items, "Medium", "Use modular science blocks: one lane pair per science ingredient, one output lane, and consistent inserter/power spacing.")
  end

  if technologies["oil-processing"] then
    push(items, "Medium", "Add simple circuit control to tanks and cracking pumps so heavy and light oil stop deadlocking each other.")
  end

  if metrics.solar_power > 0 and metrics.accumulators < metrics.solar_power * 0.7 then
    push(items, "Medium", "Use solar blocks with a healthier accumulator ratio so night-time demand does not flatten the grid.")
  end

  if metrics.stage_rank >= 4 and metrics.trains == 0 then
    push(items, "High", "Move expansion to rail-fed ore outposts instead of stretching the starter base farther and farther.")
  end

  if metrics.defense_turrets > 0 and metrics.walls < metrics.defense_turrets * 2 then
    push(items, "Medium", "Use layered perimeter slices: radar, wall, turret line, repair access, and room for ammo or power.")
  end

  if metrics.stage_rank >= 4 and metrics.roboports > 0 then
    push(items, "Medium", "Blueprintable production blocks plus roboport coverage will make refactors much safer from this point onward.")
  end

  if metrics.stage_rank >= 4 and technologies["construction-robotics"] and metrics.roboports == 0 then
    push(items, "High", "Lean into robotics with build zones and blueprintable modules; manual rebuilds become too expensive from midgame onward.")
  end

  trim_items(items, 4)

  if #items == 0 then
    push(items, "Medium", "The base is still small enough that cleaner lane discipline and repeatable production cells will give the biggest design payoff.")
  end

  return {
    title = "3. New Patterns To Apply",
    items = items
  }
end

local function analyze_predictions(snapshot)
  local metrics = snapshot.metrics
  local environment = snapshot.environment
  local resources = snapshot.resources
  local fluid_rates = snapshot.rates.fluids
  local items = {}

  if metrics.stage_rank >= 3 and resources["iron-ore"] < 200000 then
    push(items, "High", "Your starter iron patch is heading toward becoming a strategic problem soon. Plan the next outpost before the belts run thin.")
  end

  if metrics.stage_rank >= 3 and resources["copper-ore"] < 150000 then
    push(items, "Medium", "Copper demand will spike hard in the next stage; expect red circuits and LDS to expose this patch first.")
  end

  if environment.enemy_evolution >= 0.45 and (metrics.defense_turrets < 12 or metrics.walls < 40) then
    push(items, "High", ("Enemy pressure is climbing fast: evolution is %.0f%% and your perimeter looks light for it.")
      :format(environment.enemy_evolution * 100))
  end

  if environment.total_pollution >= 10000 and metrics.radars == 0 then
    push(items, "Medium", "High pollution without radar coverage means attacks may feel 'sudden' when they are really just unseen.")
  end

  if metrics.stage_rank >= 3 and snapshot.technologies["oil-processing"] and not snapshot.technologies["advanced-oil-processing"] then
    push(items, "Medium", "Oil balancing will get messier soon unless you unlock better cracking control and a more structured refinery layout.")
  end

  if metrics.stage_rank >= 4 and fluid_rates["petroleum-gas"].production < 100 then
    push(items, "High", "Late-game oil demand is coming faster than your current gas output. Expect plastic, sulfur, and blue circuits to stall together.")
  end

  if metrics.solar_power > 0 and metrics.accumulators < metrics.solar_power * 0.6 then
    push(items, "Medium", "Night-time brownouts are likely as solar grows unless accumulator coverage improves.")
  end

  trim_items(items, 4)

  if #items == 0 then
    push(items, "Medium", "No major short-horizon failure is standing out; the next issues are more likely to be scale and cleanliness than emergencies.")
  end

  return {
    title = "4. Upcoming Issues To Address",
    items = items
  }
end

local function analyze_antipatterns(snapshot)
  local metrics = snapshot.metrics
  local technologies = snapshot.technologies
  local environment = snapshot.environment
  local items = {}

  if technologies["automation"] and metrics.burner_drills > metrics.electric_drills and metrics.burner_drills >= 4 then
    push(items, "High", ("Burner miners still dominate production (%d burner vs %d electric). That usually means the base is scaling by effort, not automation.")
      :format(metrics.burner_drills, metrics.electric_drills))
  end

  if metrics.stage_rank >= 3 and metrics.stone_furnaces > metrics.modern_furnaces and metrics.stone_furnaces >= 12 then
    push(items, "High", ("Stone furnaces are still carrying most smelting (%d stone vs %d steel/electric). That is a major throughput anchor now.")
      :format(metrics.stone_furnaces, metrics.modern_furnaces))
  end

  if metrics.labs >= 4 and metrics.assemblers < metrics.labs * 2 then
    push(items, "High", ("Research capacity is outrunning factory capacity (%d labs vs %d assemblers). This often creates a very manual-feeling base.")
      :format(metrics.labs, metrics.assemblers))
  end

  if metrics.belts >= 80 and metrics.undergrounds + metrics.splitters <= 4 then
    push(items, "Medium", "A lot of belt laid with almost no routing tools usually points to spaghetti that will fight every upgrade.")
  end

  if metrics.stage_rank >= 4 and metrics.radars == 0 then
    push(items, "Medium", "Operating a midgame base with zero radars is an information anti-pattern; outposts and attacks become guesswork.")
  end

  if environment.total_pollution >= 12000 and metrics.defense_turrets < 10 then
    push(items, "High", "Pollution is high but the base defense footprint is still thin. Expansion will be paid for in repair time.")
  end

  if metrics.stage_rank >= 5 and metrics.roboports == 0 then
    push(items, "High", "Being at rocket stage without roboports makes every correction slower and riskier than it needs to be.")
  end

  trim_items(items, 5)

  if #items == 0 then
    push(items, "Medium", "No severe anti-patterns are standing out from the current ruleset.")
  end

  return {
    title = "5. Serious Anti-Patterns",
    items = items
  }
end

function advisor.initialize_storage()
  initialize_storage_table()
end

function advisor.ensure_player(player_index)
  initialize_storage_table()
  storage.player_data[player_index] = storage.player_data[player_index] or {}
end

function advisor.store_player_state(player_index, report, snapshot)
  advisor.ensure_player(player_index)
  storage.player_data[player_index].report = report
  storage.player_data[player_index].snapshot = snapshot
end

function advisor.get_last_report(player_index)
  advisor.ensure_player(player_index)
  return storage.player_data[player_index].report
end

function advisor.get_last_snapshot(player_index)
  advisor.ensure_player(player_index)
  return storage.player_data[player_index].snapshot
end

function advisor.set_external_report(player_index, report)
  initialize_storage_table()
  storage.external_reports[player_index] = report
  -- Clear detail cache when a new external report replaces the old one
  storage.detail_cache[player_index] = {}
  storage.expanded_details[player_index] = {}
end

function advisor.get_external_report(player_index)
  initialize_storage_table()
  return storage.external_reports[player_index]
end

function advisor.build_report(player)
  local snapshot = collect_snapshot(player)
  local sections = {
    analyze_next_focus(snapshot),
    analyze_bottleneck(snapshot),
    analyze_patterns(snapshot),
    analyze_predictions(snapshot),
    analyze_antipatterns(snapshot)
  }

  local ticks = snapshot.meta.tick
  local total_seconds = math.floor(ticks / 60)
  local hours = math.floor(total_seconds / 3600)
  local minutes = math.floor((total_seconds % 3600) / 60)

  local report = {
    summary = snapshot.stage.focus,
    stage = snapshot.stage,
    generated_at_tick = ticks,
    sections = sections,
    stats = {
      iron_rate = snapshot.rates.items["iron-plate"].production,
      copper_rate = snapshot.rates.items["copper-plate"].production,
      steel_rate = snapshot.rates.items["steel-plate"].production,
      top_science = top_science_rate(snapshot),
      evolution = snapshot.environment.enemy_evolution,
      pollution = snapshot.environment.total_pollution,
      game_time = ("%d:%02d"):format(hours, minutes)
    }
  }

  return report, snapshot
end


-- Detail cache: stores "get more info" responses keyed by "section_item" (e.g. "1_2")
function advisor.get_detail_cache(player_index)
  initialize_storage_table()
  storage.detail_cache[player_index] = storage.detail_cache[player_index] or {}
  return storage.detail_cache[player_index]
end

function advisor.set_detail(player_index, key, detail_text)
  initialize_storage_table()
  storage.detail_cache[player_index] = storage.detail_cache[player_index] or {}
  storage.detail_cache[player_index][key] = detail_text
end

function advisor.get_detail(player_index, key)
  initialize_storage_table()
  if not storage.detail_cache[player_index] then
    return nil
  end
  return storage.detail_cache[player_index][key]
end

function advisor.clear_detail_cache(player_index)
  initialize_storage_table()
  storage.detail_cache[player_index] = {}
  storage.expanded_details[player_index] = {}
end

-- Expanded details: tracks which items are currently showing their detail expansion
function advisor.get_expanded_details(player_index)
  initialize_storage_table()
  storage.expanded_details[player_index] = storage.expanded_details[player_index] or {}
  return storage.expanded_details[player_index]
end

function advisor.toggle_expanded(player_index, key)
  initialize_storage_table()
  storage.expanded_details[player_index] = storage.expanded_details[player_index] or {}
  if storage.expanded_details[player_index][key] then
    storage.expanded_details[player_index][key] = nil
    return false
  else
    storage.expanded_details[player_index][key] = true
    return true
  end
end

function advisor.is_expanded(player_index, key)
  initialize_storage_table()
  if not storage.expanded_details[player_index] then
    return false
  end
  return storage.expanded_details[player_index][key] == true
end

return advisor
