-- control.lua

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

-- Helper function to find which page a planet belongs to
local function find_planet_page(planet_name, planet_list, page_size)
  for i, name in ipairs(planet_list) do
    if name == planet_name then
      return math.floor((i - 1) / page_size) + 1
    end
  end
  return 1
end

-- Helper function to build the technology graph and categorize recipes by planet/location
local function build_recipe_planet_map()
  local planet_recipes = {}     -- planet_name -> list of recipe_names
  local recipe_to_planets = {}   -- recipe_name -> set of planet_names
  local tech_to_planets = {}     -- tech_name -> set of planet_names
  local recipe_to_tech = {}      -- recipe_name -> tech_name (for tooltips)

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

  -- 3. Run BFS/DFS downstream of each starting tech to classify techs under planets
  for location_name, start_tech in pairs(starting_techs) do
    local start_proto = prototypes.technology[start_tech]
    if start_proto then
      local queue = {start_tech}
      local visited = {[start_tech] = true}
      while #queue > 0 do
        local current = table.remove(queue, 1)
        tech_to_planets[current][location_name] = true

        -- Stop traversal downstream once we reach anything containing "tech card" or "science pack"
        local lower_name = string.lower(current)
        local current_proto = prototypes.technology[current]
        local should_stop = string.find(lower_name, "tech-card", 1, true)
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
          or (current_proto and localized_string_contains_keyword(current_proto.localised_name))

        if not should_stop and child_techs[current] then
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

  -- 4. Map recipes to planets
  -- Default-enabled recipes start on Nauvis
  for recipe_name, recipe_proto in pairs(prototypes.recipe) do
    if recipe_proto.enabled then
      recipe_to_planets[recipe_name] = recipe_to_planets[recipe_name] or {}
      recipe_to_planets[recipe_name]["nauvis"] = true
    end
  end

  -- Map recipes unlocked by technology to the tech's planet(s)
  for tech_name, tech_proto in pairs(prototypes.technology) do
    -- If tech has no planet tags, default to Nauvis
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
          -- Cache the tech unlocking this recipe (for tooltips)
          recipe_to_tech[r_name] = tech_name
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

  return planet_recipes, recipe_to_tech
end

-- Organize and sort recipes for GUI presentation
local function build_organized_recipes()
  local planet_recipes, recipe_to_tech = build_recipe_planet_map()

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

  -- Sort recipes within each subgroup by their prototype order
  for planet_name, groups in pairs(organized) do
    for g_name, subgroups in pairs(groups) do
      for sg_name, recipes in pairs(subgroups) do
        table.sort(recipes, function(a, b)
          local proto_a = prototypes.recipe[a]
          local proto_b = prototypes.recipe[b]
          local order_a = proto_a and proto_a.order or ""
          local order_b = proto_b and proto_b.order or ""
          if order_a ~= order_b then
            return order_a < order_b
          end
          return a < b
        end)
      end
    end
  end

  return organized, recipe_to_tech
end

-- Rebuild the custom Planet Recipe Browser GUI contents
local function rebuild_gui_content(player)
  local player_state = storage.players[player.index]
  if not player_state or not player_state.window or not player_state.window.valid then return end

  local window = player_state.window
  window.clear()

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

  -- 2. Planet Tab Header (with pagination and 2 rows)
  local planet_header = window.add({
    type = "flow",
    direction = "horizontal",
  })
  planet_header.style.bottom_padding = 8
  planet_header.style.vertical_align = "center"

  -- Gather all locations that have recipes
  local planet_list = {}
  for p_name, _ in pairs(storage.organized_recipes) do
    table.insert(planet_list, p_name)
  end
  -- Sort planets: Nauvis first, then others alphabetically, Space last
  table.sort(planet_list, function(a, b)
    if a == "nauvis" then return true end
    if b == "nauvis" then return false end
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
    btn.style.width = 110 -- Strict fixed width to prevent horizontal window sizing changes
  end

  -- Right page arrow
  local next_btn = planet_header.add({
    type = "button",
    caption = ">",
    tags = {action = "next_planet_page"},
    enabled = (player_state.planet_page < max_page)
  })
  next_btn.style.width = 30
  next_btn.style.height = 50 -- Make it tall to span the double row height
  next_btn.style.font = "default-bold"

  -- 3. Search Bar
  local search_flow = window.add({
    type = "flow",
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
    direction = "horizontal"
  })

  local active_planet = player_state.active_planet
  local planet_data = storage.organized_recipes[active_planet] or {}

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

  -- Validate active group
  local active_group = player_state.active_group
  local has_active_group = false
  for _, g_name in ipairs(group_list) do
    if g_name == active_group then
      has_active_group = true
      break
    end
  end
  if not has_active_group and #group_list > 0 then
    active_group = group_list[1]
    player_state.active_group = active_group
  end

  -- Left side: Item group button column
  local group_column = main_body.add({
    type = "flow",
    direction = "vertical",
  })
  group_column.style.right_padding = 8

  for _, g_name in ipairs(group_list) do
    local is_active = (g_name == active_group)
    local style = is_active and "yellow_slot_button" or "slot_button"

    group_column.add({
      type = "sprite-button",
      sprite = "item-group/" .. g_name,
      style = style,
      tooltip = prototypes.item_group[g_name] and prototypes.item_group[g_name].localised_name or g_name,
      tags = {action = "select_group", group = g_name}
    })
  end

  -- Right side: Scroll pane for recipe grid
  local scroll_pane = main_body.add({
    type = "scroll-pane",
    direction = "vertical",
    horizontal_scroll_policy = "never",
    vertical_scroll_policy = "auto",
  })
  scroll_pane.style.width = 460
  scroll_pane.style.height = 320

  local group_data = planet_data[active_group] or {}
  
  -- Gather all recipes in the active group matching search query
  local recipes_to_show = {}
  local search_query = string.lower(player_state.search_query or "")

  for sg_name, recipes in pairs(group_data) do
    for _, r_name in ipairs(recipes) do
      local proto = prototypes.recipe[r_name]
      if proto then
        local name_match = string.find(string.lower(r_name), search_query, 1, true)
        if name_match then
          table.insert(recipes_to_show, r_name)
        end
      end
    end
  end

  -- Sort recipes: subgroup order first, then recipe order
  table.sort(recipes_to_show, function(a, b)
    local proto_a = prototypes.recipe[a]
    local proto_b = prototypes.recipe[b]
    
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
      local tech_name = storage.recipe_to_tech[r_name]
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

-- Create or retrieve the custom browser window
local function get_or_create_gui(player)
  local player_state = storage.players[player.index]
  if not player_state then
    player_state = {
      active_planet = nil,
      active_group = nil,
      search_query = "",
      planet_page = 1,
    }
    storage.players[player.index] = player_state
  end

  if player_state.window and player_state.window.valid then
    return player_state.window
  end

  -- Determine player's current location (planet/platform)
  local current_planet = "nauvis"
  if player.surface and player.surface.planet then
    current_planet = player.surface.planet.name
  elseif player.surface and player.surface.platform then
    current_planet = "space"
  end

  -- Fallback to Nauvis if location has no recipes organized
  if not storage.organized_recipes[current_planet] then
    current_planet = "nauvis"
  end

  player_state.active_planet = current_planet
  player_state.search_query = ""

  -- Calculate the correct page index for the current planet tab (using page size of 8)
  local planet_list = {}
  for p_name, _ in pairs(storage.organized_recipes) do
    table.insert(planet_list, p_name)
  end
  table.sort(planet_list, function(a, b)
    if a == "nauvis" then return true end
    if b == "nauvis" then return false end
    if a == "space" then return false end
    if b == "space" then return true end
    return a < b
  end)
  player_state.planet_page = find_planet_page(current_planet, planet_list, 8)

  -- Determine active item group for the planet
  local groups = storage.organized_recipes[current_planet] or {}
  local sorted_groups = {}
  for g_name, _ in pairs(groups) do
    table.insert(sorted_groups, g_name)
  end
  table.sort(sorted_groups, function(a, b)
    local order_a = prototypes.item_group[a] and prototypes.item_group[a].order or ""
    local order_b = prototypes.item_group[b] and prototypes.item_group[b].order or ""
    return order_a < order_b
  end)
  player_state.active_group = sorted_groups[1] or "production"

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

  -- Set shortcut toggle state to true
  player.set_shortcut_toggled("planet-recipes-toggle", true)

  rebuild_gui_content(player)
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
      search_query = "",
      planet_page = 1,
    }
  end
end

-- Event Subscriptions

script.on_init(function()
  local organized, r_to_tech = build_organized_recipes()
  storage.organized_recipes = organized
  storage.recipe_to_tech = r_to_tech
  init_players()
end)

script.on_configuration_changed(function()
  local organized, r_to_tech = build_organized_recipes()
  storage.organized_recipes = organized
  storage.recipe_to_tech = r_to_tech
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
    search_query = "",
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
      
      -- Auto-select the first group for the chosen planet
      local groups = storage.organized_recipes[tags.planet] or {}
      local sorted_groups = {}
      for g_name, _ in pairs(groups) do
        table.insert(sorted_groups, g_name)
      end
      table.sort(sorted_groups, function(a, b)
        local order_a = prototypes.item_group[a] and prototypes.item_group[a].order or ""
        local order_b = prototypes.item_group[b] and prototypes.item_group[b].order or ""
        return order_a < order_b
      end)
      player_state.active_group = sorted_groups[1] or "production"
      
      rebuild_gui_content(player)
    end
  elseif tags.action == "select_group" then
    if player_state then
      player_state.active_group = tags.group
      rebuild_gui_content(player)
    end
  elseif tags.action == "click_recipe" then
    -- Delegate to the native Factoriopedia detail panel
    player.open_factoriopedia_gui(prototypes.recipe[tags.recipe])
  elseif tags.action == "prev_planet_page" then
    if player_state and player_state.planet_page > 1 then
      player_state.planet_page = player_state.planet_page - 1
      rebuild_gui_content(player)
    end
  elseif tags.action == "next_planet_page" then
    local planet_list = {}
    for p_name, _ in pairs(storage.organized_recipes) do
      table.insert(planet_list, p_name)
    end
    local max_page = math.max(1, math.ceil(#planet_list / 8)) -- Page size is 8
    if player_state and player_state.planet_page < max_page then
      player_state.planet_page = player_state.planet_page + 1
      rebuild_gui_content(player)
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
      rebuild_gui_content(player)
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
