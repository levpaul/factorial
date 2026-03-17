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
  local ok, value = pcall(force.get_entity_count, force, name)
  if ok then
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

  local ok, value = pcall(statistics.get_flow_count, statistics, {
    name = name,
    category = category,
    precision_index = defines.flow_precision_index.one_minute
  })

  if ok then
    return value
  end

  return 0
end

local function total_flow(statistics, name, category)
  if not statistics or not statistics.valid then
    return 0
  end

  local getter = statistics.get_input_count
  if category == "output" then
    getter = statistics.get_output_count
  end

  local ok, value = pcall(getter, statistics, name)
  if ok then
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

local function collect_rates(force, surface)
  local item_stats = force.get_item_production_statistics(surface)
  local fluid_stats = force.get_fluid_production_statistics(surface)
  local item_rates = {}
  local fluid_rates = {}
  local item_totals = {}

  for _, item in ipairs(TRACKED_ITEMS) do
    item_rates[item] = {
      production = one_minute_flow(item_stats, item, "input"),
      consumption = one_minute_flow(item_stats, item, "output")
    }
    item_totals[item] = {
      produced = total_flow(item_stats, item, "input"),
      consumed = total_flow(item_stats, item, "output")
    }
  end

  for _, fluid in ipairs(TRACKED_FLUIDS) do
    fluid_rates[fluid] = {
      production = one_minute_flow(fluid_stats, fluid, "input"),
      consumption = one_minute_flow(fluid_stats, fluid, "output")
    }
  end

  return item_rates, fluid_rates, item_totals
end

local function collect_snapshot(player)
  local force = player.force
  local surface = player.surface
  local technologies = {}
  local entities = {}
  local resources = {}

  for _, technology in ipairs(TRACKED_TECHS) do
    technologies[technology] = tech_researched(force, technology)
  end

  for _, entity in ipairs(TRACKED_ENTITIES) do
    entities[entity] = safe_entity_count(force, entity)
  end

  local available_resources = surface.get_resource_counts()
  for _, resource_name in ipairs(SURFACE_RESOURCES) do
    resources[resource_name] = available_resources[resource_name] or 0
  end

  local item_rates, fluid_rates, item_totals = collect_rates(force, surface)
  local snapshot = {
    meta = {
      advisor_version = "0.1.0",
      game_version = helpers.game_version,
      tick = game.tick,
      surface = surface.name,
      player_index = player.index,
      player_name = player.name,
      force = force.name
    },
    force = {
      rockets_launched = force.rockets_launched,
      current_research = force.current_research and force.current_research.name or nil
    },
    technologies = technologies,
    entities = entities,
    resources = resources,
    environment = {
      total_pollution = round(surface.get_total_pollution()),
      enemy_evolution = game.forces.enemy.get_evolution_factor(surface),
      pollution_evolution = game.forces.enemy.get_evolution_factor_by_pollution(surface)
    },
    rates = {
      items = item_rates,
      fluids = fluid_rates
    },
    totals = {
      items = item_totals
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

  local report = {
    summary = snapshot.stage.focus,
    stage = snapshot.stage,
    generated_at_tick = snapshot.meta.tick,
    sections = sections
  }

  return report, snapshot
end

return advisor
