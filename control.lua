-- control.lua

-- File-level cache for static recipe organization and tech discovery order
local organized_recipes = nil
local recipe_to_tech = nil
local tech_orders = nil

-- Helper function to recursively check if a localized string table contains keywords
local function localized_string_contains_keyword(val)
  if type(val) == "string" then
    local lower = string.lower(val)
    return string.find(lower, "tech-card", 1, true)
      or string.find(lower, "tech_card", 1, true)
      or string.find(lower, "techcard", 1, true)
      or string.find(lower, "tech card", 1, true)
      or string.find(lower, "science-pack", 1, true)
      or string.find(lower, "science_pack", 1, true)
      or string.find(lower, "sciencepack", 1, true)
      or string.find(lower, "science pack", 1, true)
      or string.find(lower, "research-pack", 1, true)
      or string.find(lower, "research_pack", 1, true)
      or string.find(lower, "researchpack", 1, true)
      or string.find(lower, "research pack", 1, true)
  elseif type(val) == "table" then
    for _, sub_val in pairs(val) do
      if localized_string_contains_keyword(sub_val) then
        return true
      end
    end
  end
  return false
end

-- Helper function to check if a technology prototype has an unlock-space-location effect
local function has_unlock_space_location(tech_proto)
  if not tech_proto or not tech_proto.effects then return false end
  for _, effect in ipairs(tech_proto.effects) do
    if effect.type == "unlock-space-location" then
      return true
    end
  end
  return false
end

-- Determine if a specific technology is classified as a stop point on a planet
local function is_technology_stop_point(tech_name, location_name, start_tech)
  local current_proto = prototypes.technology[tech_name]
  if not current_proto then return false end
  
  -- Stop at planet discovery technologies (except the location's own start tech)
  local is_planet_discovery = (tech_name ~= start_tech) and has_unlock_space_location(current_proto)
  if is_planet_discovery then
    if location_name == "vesta" or location_name == "corrundum" then
      return false
    else
      return true
    end
  end

  -- Determine if it's a science pack / tech card technology
  local lower_name = string.lower(tech_name)

  -- Exempt basic Nauvis science packs from being stop points
  if string.find(lower_name, "automation-science-pack", 1, true)
    or string.find(lower_name, "logistic-science-pack", 1, true)
    or string.find(lower_name, "military-science-pack", 1, true)
    or string.find(lower_name, "chemical-science-pack", 1, true) then
    return false
  end

  local is_science_pack = string.find(lower_name, "tech-card", 1, true)
    or string.find(lower_name, "tech_card", 1, true)
    or string.find(lower_name, "techcard", 1, true)
    or string.find(lower_name, "tech card", 1, true)
    or string.find(lower_name, "science-pack", 1, true)
    or string.find(lower_name, "science_pack", 1, true)
    or string.find(lower_name, "sciencepack", 1, true)
    or string.find(lower_name, "science pack", 1, true)
    or string.find(lower_name, "research-pack", 1, true)
    or string.find(lower_name, "research_pack", 1, true)
    or string.find(lower_name, "researchpack", 1, true)
    or string.find(lower_name, "research pack", 1, true)
    or localized_string_contains_keyword(current_proto.localised_name)

  if is_science_pack then
    -- Certain planets bypass science pack stop conditions entirely
    local bypass_all_science_packs = (
      location_name == "rubia" or 
      location_name == "cerys" or 
      location_name == "moshine" or
      location_name == "vesta" or
      location_name == "corrundum" or
      location_name == "corundum"
    )
    if bypass_all_science_packs then
      return false
    end

    -- Every other science pack / tech card is a strict stop point
    return true
  end

  return false
end

-- Check if all local prerequisites of a technology have been unlocked
local function can_unlock_tech(tech_name, visited, candidates, location_name, start_tech)
  local proto = prototypes.technology[tech_name]
  if not proto or not proto.prerequisites then return true end
  
  for prereq_name, _ in pairs(proto.prerequisites) do
    -- Only wait for prerequisites that belong to this planet's local candidate set
    if candidates[prereq_name] and not visited[prereq_name] then
      return false
    end
  end
  return true
end

-- Helper function to find which page a planet belongs to
local function find_planet_page(planet_name, planet_list, page_size)
  for i, name in ipairs(planet_list) do
    if name == planet_name then
      return math.floor((i - 1) / page_size) + 1
    end
  end
  return 1
end

-- Robust string search helper that normalizes spaces, hyphens, and underscores
local function match_query(r_name, query)
  if not query or query == "" then return true end
  local norm_r = string.gsub(string.gsub(string.gsub(string.lower(r_name), "%-", ""), "_", ""), "%s", "")
  local norm_q = string.gsub(string.gsub(string.gsub(string.lower(query), "%-", ""), "_", ""), "%s", "")
  return string.find(norm_r, norm_q, 1, true) ~= nil
end

-- Helper function to build the technology graph and categorize recipes by planet/location
local function build_recipe_planet_map()
  local planet_recipes = {}      -- planet_name -> list of recipe_names
  local recipe_to_planets = {}    -- recipe_name -> set of planet_names
  local tech_to_planets = {}      -- tech_name -> set of planet_names
  local r_to_tech = {}            -- recipe_name -> tech_name (for tooltips)
  local t_orders = {}             -- planet_name -> tech_name -> BFS order index

  -- Initialize technology-to-planet map
  for tech_name, _ in pairs(prototypes.technology) do
    tech_to_planets[tech_name] = {}
  end

  -- 1. Identify starting technologies for each planet/location
  local starting_techs = {} -- planet_name -> tech_name
  -- Hardcoded starting technology for Space Platform
  starting_techs["space"] = "space-platform"

  -- Scan for unlock-space-location effects to dynamically associate planets with their starting technologies
  for tech_name, tech_proto in pairs(prototypes.technology) do
    if tech_proto.effects then
      for _, effect in ipairs(tech_proto.effects) do
        if effect.type == "unlock-space-location" and effect.space_location then
          starting_techs[effect.space_location] = tech_name
        end
      end
    end
  end

  -- 2. Build child technology mapping (dependency graph)
  local child_techs = {} -- parent_name -> list of child_names
  for tech_name, tech_proto in pairs(prototypes.technology) do
    if tech_proto.prerequisites then
      for prereq_name, _ in pairs(tech_proto.prerequisites) do
        child_techs[prereq_name] = child_techs[prereq_name] or {}
        table.insert(child_techs[prereq_name], tech_name)
      end
    end
  end

  -- 3. Run BFS downstream of starting techs
  
  -- Pass 1: Simple BFS to discover candidates for each planet
  local planet_techs = {} -- location_name -> set of tech_names
  for location_name, start_tech in pairs(starting_techs) do
    planet_techs[location_name] = {}
    local start_proto = prototypes.technology[start_tech]
    if start_proto then
      local queue = {start_tech}
      local visited = {[start_tech] = true}
      while #queue > 0 do
        local current = table.remove(queue, 1)
        planet_techs[location_name][current] = true
        
        local is_stop = is_technology_stop_point(current, location_name, start_tech)
        if not is_stop and child_techs[current] then
          for _, child in ipairs(child_techs[current]) do
            if not visited[child] then
              visited[child] = true
              table.insert(queue, child)
            end
          end
        end
      end
    end
  end

  -- Pass 2: Strict dependency-resolved BFS to assign consistent discovery order indices
  for location_name, start_tech in pairs(starting_techs) do
    t_orders[location_name] = {}
    local start_proto = prototypes.technology[start_tech]
    if start_proto then
      local queue = {start_tech}
      local visited = {[start_tech] = true}
      local current_order = 1
      local candidates = planet_techs[location_name] or {}

      while #queue > 0 do
        local current = table.remove(queue, 1)
        tech_to_planets[current][location_name] = true
        t_orders[location_name][current] = current_order
        current_order = current_order + 1

        local is_stop = is_technology_stop_point(current, location_name, start_tech)

        if not is_stop and child_techs[current] then
          for _, child in ipairs(child_techs[current]) do
            if not visited[child] then
              -- Check if all local prerequisites have been visited
              if can_unlock_tech(child, visited, candidates, location_name, start_tech) then
                visited[child] = true
                table.insert(queue, child)
              end
            end
          end
        end
      end
    end
  end

  -- 4. Map recipes to planets
  -- Default-enabled recipes start on Nauvis (which we won't show but BFS maps them internally)
  for recipe_name, recipe_proto in pairs(prototypes.recipe) do
    if recipe_proto.enabled then
      recipe_to_planets[recipe_name] = recipe_to_planets[recipe_name] or {}
      recipe_to_planets[recipe_name]["nauvis"] = true
    end
  end

  -- Map recipes unlocked by technology to the tech's planet(s)
  for tech_name, tech_proto in pairs(prototypes.technology) do
    local planets = tech_to_planets[tech_name]
    local has_planet = false
    for _, _ in pairs(planets) do
      has_planet = true
      break
    end
    if not has_planet then
      planets = {["nauvis"] = true}
    end

    if tech_proto.effects then
      for _, effect in ipairs(tech_proto.effects) do
        if effect.type == "unlock-recipe" and effect.recipe then
          local r_name = effect.recipe
          recipe_to_planets[r_name] = recipe_to_planets[r_name] or {}
          for p_name, _ in pairs(planets) do
            recipe_to_planets[r_name][p_name] = true
          end
          r_to_tech[r_name] = tech_name
        end
      end
    end
  end

  -- Organize recipe list by planet
  for recipe_name, planets in pairs(recipe_to_planets) do
    for p_name, _ in pairs(planets) do
      planet_recipes[p_name] = planet_recipes[p_name] or {}
      table.insert(planet_recipes[p_name], recipe_name)
    end
  end

  return planet_recipes, r_to_tech, t_orders
end

-- Organize recipes for GUI presentation
local function build_organized_recipes()
  local planet_recipes, r_to_tech, t_orders = build_recipe_planet_map()

  local organized = {} -- planet_name -> group_name -> subgroup_name -> list of recipe_names
  
  for planet_name, recipes in pairs(planet_recipes) do
    organized[planet_name] = organized[planet_name] or {}
    for _, r_name in ipairs(recipes) do
      local proto = prototypes.recipe[r_name]
      if proto and not proto.hidden then
        local g_name = proto.group.name
        local sg_name = proto.subgroup.name

        organized[planet_name][g_name] = organized[planet_name][g_name] or {}
        organized[planet_name][g_name][sg_name] = organized[planet_name][g_name][sg_name] or {}
        table.insert(organized[planet_name][g_name][sg_name], r_name)
      end
    end
  end

  return organized, r_to_tech, t_orders
end

-- Verify cache initialization
local function verify_cache()
  if not organized_recipes or not recipe_to_tech or not tech_orders then
    organized_recipes, recipe_to_tech, tech_orders = build_organized_recipes()
  end
end

-- Helper function to calculate a recipe's tech discovery order index
local function get_recipe_tech_order(recipe_name, planet_name)
  verify_cache()
  local proto = prototypes.recipe[recipe_name]
  if not proto then return 99999 end
  if proto.enabled then return 0 end

  local tech_name = recipe_to_tech[recipe_name]
  if not tech_name then return 99999 end

  local planet_orders = tech_orders[planet_name]
  if not planet_orders then return 99999 end

  return planet_orders[tech_name] or 99999
end

-- Rebuild the Planet Tabs Header
local function rebuild_planet_header(player)
  verify_cache()
  local player_state = storage.players[player.index]
  if not player_state or not player_state.window or not player_state.window.valid then return end

  local planet_header = player_state.window.planet_header
  if not planet_header or not planet_header.valid then return end

  planet_header.clear()

  -- Gather all locations that have recipes, excluding Nauvis
  local planet_list = {}
  for p_name, _ in pairs(organized_recipes) do
    if p_name ~= "nauvis" then
      table.insert(planet_list, p_name)
    end
  end
  -- Sort planets: alphabetized, Space last
  table.sort(planet_list, function(a, b)
    if a == "space" then return false end
    if b == "space" then return true end
    return a < b
  end)

  -- Pagination variables: 2 rows of 4 planets = page size of 8
  local PLANETS_PER_ROW = 4
  local PLANET_PAGE_SIZE = PLANETS_PER_ROW * 2
  local max_page = math.max(1, math.ceil(#planet_list / PLANET_PAGE_SIZE))
  if not player_state.planet_page or player_state.planet_page < 1 then
    player_state.planet_page = 1
  elseif player_state.planet_page > max_page then
    player_state.planet_page = max_page
  end

  local start_idx = (player_state.planet_page - 1) * PLANET_PAGE_SIZE + 1
  local end_idx = math.min(player_state.planet_page * PLANET_PAGE_SIZE, #planet_list)

  -- Left page arrow
  local prev_btn = planet_header.add({
    type = "button",
    caption = "<",
    tooltip = "",
    tags = {action = "prev_planet_page"},
    enabled = (player_state.planet_page > 1)
  })
  prev_btn.style.width = 30
  prev_btn.style.height = 50 -- Make it tall to span the double row height
  prev_btn.style.font = "default-bold"

  -- Center container for rows of planet tabs
  local rows_container = planet_header.add({
    type = "flow",
    direction = "vertical",
  })
  rows_container.style.left_padding = 4
  rows_container.style.right_padding = 4

  local row1 = rows_container.add({
    type = "flow",
    direction = "horizontal",
  })
  row1.style.horizontal_spacing = 4
  row1.style.bottom_padding = 2

  local row2 = rows_container.add({
    type = "flow",
    direction = "horizontal",
  })
  row2.style.horizontal_spacing = 4

  -- Render the planet buttons for the current page
  for idx = start_idx, end_idx do
    local p_name = planet_list[idx]
    local is_active = (p_name == player_state.active_planet)
    local style = is_active and "confirm_button" or "button"

    local cap
    if p_name == "space" then
      cap = {"item-group-name.space"}
    else
      local planet = game.planets[p_name]
      if planet then
        cap = planet.prototype.localised_name
      else
        local loc_proto = prototypes.space_location[p_name]
        cap = loc_proto and loc_proto.localised_name or p_name
      end
    end

    -- Determine which row to add the button to
    local relative_idx = idx - start_idx
    local target_row = (relative_idx < PLANETS_PER_ROW) and row1 or row2

    local btn = target_row.add({
      type = "button",
      caption = cap,
      style = style,
      tags = {action = "select_planet", planet = p_name}
    })
    btn.style.font = "default-semibold"
    btn.style.width = 110
  end

  -- Right page arrow
  local next_btn = planet_header.add({
    type = "button",
    caption = ">",
    tooltip = "",
    tags = {action = "next_planet_page"},
    enabled = (player_state.planet_page < max_page)
  })
  next_btn.style.width = 30
  next_btn.style.height = 50 -- Make it tall to span the double row height
  next_btn.style.font = "default-bold"
end

-- Rebuild the Item Group Column
local function rebuild_group_column(player)
  verify_cache()
  local player_state = storage.players[player.index]
  if not player_state or not player_state.window or not player_state.window.valid then return end

  local main_body = player_state.window.main_body
  if not main_body or not main_body.valid then return end

  local group_scroll = main_body.group_scroll
  if not group_scroll or not group_scroll.valid then return end

  local group_column = group_scroll.group_column
  if not group_column or not group_column.valid then return end

  group_column.clear()

  local active_planet = player_state.active_planet
  local planet_data = organized_recipes[active_planet] or {}

  -- Get and sort group names
  local group_list = {}
  for g_name, _ in pairs(planet_data) do
    table.insert(group_list, g_name)
  end
  table.sort(group_list, function(a, b)
    local order_a = prototypes.item_group[a] and prototypes.item_group[a].order or ""
    local order_b = prototypes.item_group[b] and prototypes.item_group[b].order or ""
    return order_a < order_b
  end)

  local search_query = player_state.search_query
  local active_group = player_state.active_group

  -- 1. Add "All" Filter Button at the top
  local is_all_active = (active_group == "all")
  local has_all_matches = false
  if search_query ~= "" then
    for g_name, group_data in pairs(planet_data) do
      for sg_name, recipes in pairs(group_data) do
        for _, r_name in ipairs(recipes) do
          if match_query(r_name, search_query) then
            has_all_matches = true
            break
          end
        end
        if has_all_matches then break end
      end
      if has_all_matches then break end
    end
  end

  local all_style = "slot_button"
  local all_toggled = false
  if is_all_active then
    all_style = "slot_button"
    all_toggled = true
  elseif has_all_matches then
    all_style = "yellow_slot_button"
    all_toggled = false
  end

  group_column.add({
    type = "sprite-button",
    sprite = "utility/slots_view",
    style = all_style,
    toggled = all_toggled,
    tooltip = "All",
    tags = {action = "select_group", group = "all"}
  })

  -- 2. Add individual Item Group buttons
  for _, g_name in ipairs(group_list) do
    local is_active = (g_name == active_group)
    
    -- Check if this group has matching recipes for the search query to highlight it
    local has_search_matches = false
    if search_query ~= "" then
      local group_data = planet_data[g_name] or {}
      for sg_name, recipes in pairs(group_data) do
        for _, r_name in ipairs(recipes) do
          if match_query(r_name, search_query) then
            has_search_matches = true
            break
          end
        end
        if has_search_matches then break end
      end
    end

    local style = "slot_button"
    local toggled = false
    if is_active then
      style = "slot_button"
      toggled = true
    elseif has_search_matches then
      style = "yellow_slot_button"
      toggled = false
    end

    group_column.add({
      type = "sprite-button",
      sprite = "item-group/" .. g_name,
      style = style,
      toggled = toggled,
      tooltip = prototypes.item_group[g_name] and prototypes.item_group[g_name].localised_name or g_name,
      tags = {action = "select_group", group = "all"}
    })
    
    local btn = group_column.children[#group_column.children]
    if btn and btn.valid then
      btn.tags = {action = "select_group", group = g_name}
    end
  end
end

-- Rebuild the Recipe grid Scroll Pane
local function rebuild_recipe_grid(player)
  verify_cache()
  local player_state = storage.players[player.index]
  if not player_state or not player_state.window or not player_state.window.valid then return end

  local main_body = player_state.window.main_body
  if not main_body or not main_body.valid then return end

  local scroll_pane = main_body.scroll_pane
  if not scroll_pane or not scroll_pane.valid then return end

  scroll_pane.clear()

  local active_planet = player_state.active_planet
  local planet_data = organized_recipes[active_planet] or {}
  local active_group = player_state.active_group
  
  -- Gather all recipes matching search query for the selected group(s)
  local recipes_to_show = {}
  local search_query = player_state.search_query

  if active_group == "all" then
    -- Flatten all groups on the active planet into one search set
    for g_name, group_data in pairs(planet_data) do
      for sg_name, recipes in pairs(group_data) do
        for _, r_name in ipairs(recipes) do
          if match_query(r_name, search_query) then
            table.insert(recipes_to_show, r_name)
          end
        end
      end
    end
  else
    -- Filter recipes only in the single active group
    local group_data = planet_data[active_group] or {}
    for sg_name, recipes in pairs(group_data) do
      for _, r_name in ipairs(recipes) do
        if match_query(r_name, search_query) then
          table.insert(recipes_to_show, r_name)
        end
      end
    end
  end

  -- Sort recipes: Tech tree order first (chronological progression), then Group order, then Subgroup order, then Recipe order
  table.sort(recipes_to_show, function(a, b)
    -- 1. Sort by Tech discovery order index
    local tech_order_a = get_recipe_tech_order(a, active_planet)
    local tech_order_b = get_recipe_tech_order(b, active_planet)
    if tech_order_a ~= tech_order_b then
      return tech_order_a < tech_order_b
    end

    -- 2. Fallback to Group order
    local proto_a = prototypes.recipe[a]
    local proto_b = prototypes.recipe[b]
    
    local g_a = proto_a.group.name
    local g_b = proto_b.group.name
    
    if g_a ~= g_b then
      local order_g_a = prototypes.item_group[g_a] and prototypes.item_group[g_a].order or ""
      local order_g_b = prototypes.item_group[g_b] and prototypes.item_group[g_b].order or ""
      if order_g_a ~= order_g_b then
        return order_g_a < order_g_b
      end
      return g_a < g_b
    end
    
    -- 3. Fallback to Subgroup order
    local sg_a = proto_a.subgroup.name
    local sg_b = proto_b.subgroup.name
    if sg_a ~= sg_b then
      local order_sg_a = prototypes.item_subgroup[sg_a] and prototypes.item_subgroup[sg_a].order or ""
      local order_sg_b = prototypes.item_subgroup[sg_b] and prototypes.item_subgroup[sg_b].order or ""
      if order_sg_a ~= order_sg_b then
        return order_sg_a < order_sg_b
      end
      return sg_a < sg_b
    end
    
    -- 4. Fallback to Recipe order
    local order_a = proto_a.order or ""
    local order_b = proto_b.order or ""
    if order_a ~= order_b then
      return order_a < order_b
    end
    return a < b
  end)

  if #recipes_to_show > 0 then
    local grid = scroll_pane.add({
      type = "table",
      column_count = 10,
    })
    grid.style.horizontal_spacing = 2
    grid.style.vertical_spacing = 2

    for _, r_name in ipairs(recipes_to_show) do
      local proto = prototypes.recipe[r_name]
      local is_unlocked = player.force.recipes[r_name] and player.force.recipes[r_name].enabled or false
      local style = is_unlocked and "slot_button" or "red_slot_button"

      -- Tooltip calculation showing technology requirements for locked recipes
      local tech_name = recipe_to_tech[r_name]
      local tooltip
      if not is_unlocked and tech_name then
        local tech_proto = prototypes.technology[tech_name]
        local tech_localised = tech_proto and tech_proto.localised_name or tech_name
        tooltip = {"", proto.localised_name, "\n", {"gui.planet-recipes-locked-by", tech_localised}}
      else
        tooltip = proto.localised_name
      end

      grid.add({
        type = "sprite-button",
        sprite = "recipe/" .. r_name,
        style = style,
        tooltip = tooltip,
        tags = {action = "click_recipe", recipe = r_name}
      })
    end
  end
end

-- Rebuild all GUI content in-place
local function rebuild_gui_content(player)
  rebuild_planet_header(player)
  rebuild_group_column(player)
  rebuild_recipe_grid(player)
end

-- Create or retrieve the custom browser window skeleton
local function get_or_create_gui(player)
  verify_cache()
  local player_state = storage.players[player.index]
  if not player_state then
    player_state = {
      active_planet = nil,
      active_group = nil,
      search_query = nil,
      planet_page = 1,
    }
    storage.players[player.index] = player_state
  end

  if player_state.window and player_state.window.valid then
    return player_state.window
  end

  -- Gather planet list excluding Nauvis for default calculations
  local planet_list = {}
  for p_name, _ in pairs(organized_recipes) do
    if p_name ~= "nauvis" then
      table.insert(planet_list, p_name)
    end
  end
  table.sort(planet_list, function(a, b)
    if a == "space" then return false end
    if b == "space" then return true end
    return a < b
  end)

  -- Determine player's current location (planet/platform) as fallback defaults
  local default_planet = "vulcanus"
  if player.surface and player.surface.planet then
    default_planet = player.surface.planet.name
  elseif player.surface and player.surface.platform then
    default_planet = "space"
  end

  -- If player is on Nauvis or location is not in our list, default to the first mod/expansion planet
  if default_planet == "nauvis" or not organized_recipes[default_planet] then
    default_planet = planet_list[1] or "vulcanus"
  end

  -- Initialize active state variables only if they are nil to remember where the player left off
  if not player_state.active_planet then
    player_state.active_planet = default_planet
  end
  if not player_state.active_group then
    player_state.active_group = "all"
  end
  if not player_state.search_query then
    player_state.search_query = ""
  end

  -- Calculate the correct page index for the active planet tab (using page size of 8)
  player_state.planet_page = find_planet_page(player_state.active_planet, planet_list, 8)

  -- Build the custom window frame (Enforce fixed width and height to prevent page shifting/resizing)
  local window = player.gui.screen.add({
    type = "frame",
    name = "planet_recipe_browser_window",
    direction = "vertical",
  })
  window.style.width = 540
  window.style.height = 490 -- Made slightly taller to comfortably fit the 2nd row of tabs
  window.auto_center = true
  player_state.window = window
  player.opened = window

  -- 1. Custom Title Bar
  local title_bar = window.add({
    type = "flow",
    direction = "horizontal",
  })
  title_bar.style.vertical_align = "center"
  title_bar.style.bottom_padding = 8
  title_bar.drag_target = window

  title_bar.add({
    type = "label",
    caption = {"gui.planet-recipe-browser-title"},
    style = "frame_title",
    ignored_by_interaction = true
  })

  -- Spacer to push the close button to the right
  local filler = title_bar.add({
    type = "empty-widget",
    style = "draggable_space",
    ignored_by_interaction = true
  })
  filler.style.height = 24
  filler.style.horizontally_stretchable = true

  -- Close button
  title_bar.add({
    type = "sprite-button",
    sprite = "utility/close",
    style = "frame_action_button",
    tags = {action = "close_window"},
    tooltip = {"gui.close-instruction"}
  })

  -- 2. Planet Tab Header container
  window.add({
    type = "flow",
    name = "planet_header",
    direction = "horizontal",
  })

  -- 3. Search Bar Container
  local search_flow = window.add({
    type = "flow",
    name = "search_flow",
    direction = "horizontal",
  })
  search_flow.style.bottom_padding = 8
  search_flow.style.vertical_align = "center"

  search_flow.add({
    type = "label",
    caption = {"gui.search-recipes"}
  }).style.right_padding = 8

  local search_field = search_flow.add({
    type = "textfield",
    text = player_state.search_query,
    name = "search_field",
  })
  search_field.style.width = 200

  -- 4. Main Area
  local main_body = window.add({
    type = "flow",
    name = "main_body",
    direction = "horizontal"
  })

  -- Left side: Scroll-pane for group column (width 62 provides vertical scrollbar spacing to avoid covering buttons)
  local group_scroll = main_body.add({
    type = "scroll-pane",
    name = "group_scroll",
    direction = "vertical",
    horizontal_scroll_policy = "never",
    vertical_scroll_policy = "auto",
  })
  group_scroll.style.width = 62
  group_scroll.style.height = 320

  -- Container layout inside the scroll-pane
  local group_column = group_scroll.add({
    type = "flow",
    name = "group_column",
    direction = "vertical",
  })
  group_column.style.vertical_spacing = 2

  -- Right side: Scroll pane for recipe grid
  local scroll_pane = main_body.add({
    type = "scroll-pane",
    name = "scroll_pane",
    direction = "vertical",
    horizontal_scroll_policy = "never",
    vertical_scroll_policy = "auto",
  })
  scroll_pane.style.width = 460
  scroll_pane.style.height = 320

  -- Set shortcut toggle state to true
  player.set_shortcut_toggled("planet-recipes-toggle", true)

  -- Draw the contents inside the skeleton
  rebuild_planet_header(player)
  rebuild_group_column(player)
  rebuild_recipe_grid(player)

  return window
end

-- Dismiss the custom window
local function destroy_gui(player)
  local player_state = storage.players[player.index]
  if player_state then
    if player_state.window and player_state.window.valid then
      player_state.window.destroy()
    end
    player_state.window = nil
  end
  player.set_shortcut_toggled("planet-recipes-toggle", false)
end

-- Toggle the GUI
local function toggle_gui(player)
  local player_state = storage.players[player.index]
  if player_state and player_state.window and player_state.window.valid then
    destroy_gui(player)
  else
    get_or_create_gui(player)
  end
end

-- Initialize players map
local function init_players()
  storage.players = storage.players or {}
  for _, player in pairs(game.players) do
    storage.players[player.index] = storage.players[player.index] or {
      active_planet = nil,
      active_group = nil,
      search_query = nil,
      planet_page = 1,
    }
  end
end

-- Event Subscriptions

script.on_init(function()
  -- Clear legacy save cache tables to prevent storage leakage
  storage.organized_recipes = nil
  storage.recipe_to_tech = nil
  storage.tech_orders = nil

  -- Initialize local memory caches
  verify_cache()
  init_players()
end)

script.on_configuration_changed(function()
  -- Clear legacy save cache tables to prevent storage leakage
  storage.organized_recipes = nil
  storage.recipe_to_tech = nil
  storage.tech_orders = nil

  -- Force memory cache rebuild
  organized_recipes = nil
  recipe_to_tech = nil
  tech_orders = nil
  verify_cache()
  init_players()

  -- Refresh active GUIs
  for _, player in pairs(game.players) do
    if storage.players[player.index] and storage.players[player.index].window and storage.players[player.index].window.valid then
      rebuild_gui_content(player)
    end
  end
end)

script.on_event(defines.events.on_player_created, function(event)
  storage.players[event.player_index] = {
    active_planet = nil,
    active_group = nil,
    search_query = nil,
    planet_page = 1,
  }
end)

script.on_event(defines.events.on_player_removed, function(event)
  storage.players[event.player_index] = nil
end)

-- Handle GUI Clicks
script.on_event(defines.events.on_gui_click, function(event)
  local element = event.element
  if not element or not element.valid then return end
  local tags = element.tags
  if not tags or not tags.action then return end

  local player = game.players[event.player_index]
  local player_state = storage.players[player.index]

  if tags.action == "close_window" then
    destroy_gui(player)
  elseif tags.action == "select_planet" then
    if player_state then
      player_state.active_planet = tags.planet
      player_state.search_query = ""
      player_state.active_group = "all" -- Default to All for the new planet!
      
      -- Correctly navigate layout path and clear search field
      local window = player_state.window
      if window and window.valid and window.search_flow and window.search_flow.search_field then
        window.search_flow.search_field.text = ""
      end
      
      rebuild_gui_content(player)
    end
  elseif tags.action == "select_group" then
    if player_state then
      player_state.active_group = tags.group
      rebuild_group_column(player)
      rebuild_recipe_grid(player)
    end
  elseif tags.action == "click_recipe" then
    -- Delegate to the native Factoriopedia detail panel
    player.open_factoriopedia_gui(prototypes.recipe[tags.recipe])
  elseif tags.action == "prev_planet_page" then
    if player_state and player_state.planet_page > 1 then
      player_state.planet_page = player_state.planet_page - 1
      rebuild_planet_header(player)
    end
  elseif tags.action == "next_planet_page" then
    verify_cache()
    local planet_list = {}
    for p_name, _ in pairs(organized_recipes) do
      if p_name ~= "nauvis" then
        table.insert(planet_list, p_name)
      end
    end
    table.sort(planet_list, function(a, b)
      if a == "space" then return false end
      if b == "space" then return true end
      return a < b
    end)
    local max_page = math.max(1, math.ceil(#planet_list / 8)) -- Page size is 8
    if player_state and player_state.planet_page < max_page then
      player_state.planet_page = player_state.planet_page + 1
      rebuild_planet_header(player)
    end
  end
end)

-- Handle Search Bar Typing
script.on_event(defines.events.on_gui_text_changed, function(event)
  local element = event.element
  if not element or not element.valid then return end
  
  if element.name == "search_field" then
    local player = game.players[event.player_index]
    local player_state = storage.players[player.index]
    if player_state then
      player_state.search_query = event.text
      rebuild_group_column(player) -- Update highlights for category buttons
      rebuild_recipe_grid(player)  -- Update recipe grid inside scroll pane
    end
  end
end)

-- Handle GUI Dismissals (E / Esc / etc.)
script.on_event(defines.events.on_gui_closed, function(event)
  if event.gui_type == defines.gui_type.custom then
    local element = event.element
    if element and element.valid and element.name == "planet_recipe_browser_window" then
      local player = game.players[event.player_index]
      destroy_gui(player)
    end
  end
end)

-- Handle Shortcut Activation
script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name == "planet-recipes-toggle" then
    local player = game.players[event.player_index]
    toggle_gui(player)
  end
end)
