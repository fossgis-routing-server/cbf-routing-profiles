-- Bicycle profile

api_version = 4

Set = require('lib/set')
Sequence = require('lib/sequence')
Handlers = require("lib/way_handlers_weight")
find_access_tag = require("lib/access").find_access_tag
limit = require("lib/maxspeed").limit

function setup()
  local default_speed = {1,   15}
  local walking_speed = {0.25, 4}

  return {
    properties = {
      u_turn_penalty                = 20,
      traffic_light_penalty         = 2,
      weight_name                   = 'duration',
      process_call_tagless_node     = false,
      max_speed_for_map_matching    = 110/3.6, -- kmph -> m/s
      use_turn_restrictions         = false,
      continue_straight_at_waypoint = false,
      mode_change_penalty           = 30,
    },

    default_mode              = mode.cycling,
    default_speed             = default_speed,
    walking_speed             = walking_speed,
    oneway_handling           = true,
    turn_penalty              = 6,
    turn_bias                 = 1.4,
    use_public_transport      = true,

    allowed_start_modes = Set {
      mode.cycling,
      mode.pushing_bike
    },

    barrier_whitelist = Set {
      'sump_buster',
      'bus_trap',
      'cycle_barrier',
      'bollard',
      'entrance',
      'cattle_grid',
      'border_control',
      'toll_booth',
      'sally_port',
      'gate',
      'lift_gate',
      'swing_gate',
      'sliding_gate',
      'hampshire_gate',
      'no',
      'block',
      'kerb',
      'height_restrictor'
    },

    access_tag_whitelist = Set {
      'yes',
      'permissive',
      'designated'
    },

    access_tag_blacklist = Set {
      'no',
      'agricultural',
      'forestry',
      'emergency',
      'customers',
      'private',
      'delivery',
      'destination'
  },

  restricted_access_tag_list = Set {
    'private',
    'delivery',
    'destination',
    'customers',
  },

    restricted_highway_whitelist = Set { },

    -- tags disallow access to in combination with highway=service
    service_access_tag_blacklist = Set { },

    construction_whitelist = Set {
      'no',
      'widening',
      'minor',
    },

    access_tags_hierarchy = Sequence {
      'bicycle',
      'vehicle',
      'access'
    },

  restrictions = Sequence {
    'bicycle',
    'vehicle'
  },

    cycleway_tags = Set {
      'track',
      'lane',
      'share_busway',
      'sharrow',
      'shared',
      'shared_lane'
    },

    opposite_cycleway_tags = Set {
      'opposite',
      'opposite_lane',
      'opposite_track',
    },

    service_penalties = {
      alley             = 0.5,
    },

  bicycle_speeds = {
    cycleway       = {1.3, 16},
    primary        = {1.0, 16},
    primary_link   = {1.0, 16},
    secondary      = {1.1, 16},
    secondary_link = {1.1, 16},
    tertiary       = {1.2, 16},
    tertiary_link  = {1.2, 16},
    residential    = {1.3, 15},
    unclassified   = {1.3, 16},
    living_street  = {1.3, 15},
    road           = {1.2, 15},
    service        = {1.2, 15},
    track          = {0.8, 13},
    path           = {0.4,  8},
    footway        = {0.35, 6},
    pedestrian     = {0.35, 6},
    steps          = {0.05, 1}
  },

    pedestrian_speeds = {
      footway = walking_speed,
      pedestrian = walking_speed,
      steps = {0.05, 2}
    },

    railway_speeds = {
      train = {0.7, 45},
      railway = {0.7, 45},
      subway = {0.7, 30},
      light_rail = {0.7, 30},
      monorail = {0.7, 10},
      tram = {0.7, 20}
    },

    platform_speeds = {
      platform = walking_speed
    },

    man_made_speeds = {
      pier = walking_speed
    },

    route_speeds = {
      ferry = {0.3, nil}
    },

    bridge_speeds = {
      movable = {0.3, 5}
    },

    surface_speeds = {
      asphalt = default_speed,
      ["cobblestone:flattened"] = {0.8, 13},
      paving_stones = {0.8, 13},
      compacted = {0.8, 14},
      cobblestone = {0.4, 6},
      unpaved = {0.4, 6},
      fine_gravel = {0.8, 14},
      gravel = {0.3, 4},
      pebblestone = {0.4, 6},
      ground = {0.4, 10},
      dirt = {0.4, 6},
      earth = {0.4, 6},
      grass = {0.3, 6},
      mud = {0.2, 3},
      sand = {0.2, 3},
      sett = {0.7, 10}
    },

    classes = Sequence {
        'ferry', 'tunnel'
    },

    tracktype_speeds = {
    grade1 =  {1.3, 18},
    grade2 =  {1.1, 16},
    grade3 =  {0.8, 12},
    grade4 =  {0, 0},
    grade5 =  {0, 0}
    },

    smoothness_speeds = {
    },

    avoid = Set {
      'impassable',
      'construction'
    },


    speed_path = {
      sac_scale = nil,
      foot = { designated = {0.2, 8},
               yes = {0.35, 8} },
      bicycle = { yes = {1.2, 16} },
      ["mtb:scale"] = nil
    }
  }
end

local function parse_maxspeed(source)
    if not source then
        return 0
    end
    local n = tonumber(source:match("%d*"))
    if not n then
        n = 0
    end
    if string.match(source, "mph") or string.match(source, "mp/h") then
        n = (n*1609)/1000
    end
    return n
end

function process_node(profile, node, result)
  -- parse access and barrier tags
  local highway = node:get_value_by_key("highway")
  local is_crossing = highway and highway == "crossing"

  local access = find_access_tag(node, profile.access_tags_hierarchy)
  if access and access ~= "" then
    -- access restrictions on crossing nodes are not relevant for
    -- the traffic on the road
    if profile.access_tag_blacklist[access] and not is_crossing then
      result.barrier = true
    end
  else
    local barrier = node:get_value_by_key("barrier")
    if barrier and "" ~= barrier then
      if not profile.barrier_whitelist[barrier] then
        result.barrier = true
      end
    end
  end

  -- check if node is a traffic light
  local tag = node:get_value_by_key("highway")
  if tag and "traffic_signals" == tag then
    result.traffic_lights = true
  end
end

function handle_bicycle_tags(profile,way,result,data)
    -- initial routability check, filters out buildings, boundaries, etc
  data.route = way:get_value_by_key("route")
  data.man_made = way:get_value_by_key("man_made")
  data.railway = way:get_value_by_key("railway")
  data.amenity = way:get_value_by_key("amenity")
  data.public_transport = way:get_value_by_key("public_transport")
  data.bridge = way:get_value_by_key("bridge")

  if (not data.highway or data.highway == '') and
  (not data.route or data.route == '') and
  (not profile.use_public_transport or not data.railway or data.railway=='') and
  (not data.amenity or data.amenity=='') and
  (not data.man_made or data.man_made=='') and
  (not data.public_transport or data.public_transport=='') and
  (not data.bridge or data.bridge=='')
  then
    return false
  end

  -- access
  data.access = find_access_tag(way, profile.access_tags_hierarchy)
  if data.access and profile.access_tag_blacklist[data.access] then
    return false
  end

  -- other tags
  data.junction = way:get_value_by_key("junction")
  data.maxspeed = parse_maxspeed(way:get_value_by_key ( "maxspeed") )
  data.maxspeed_forward = parse_maxspeed(way:get_value_by_key( "maxspeed:forward"))
  data.maxspeed_backward = parse_maxspeed(way:get_value_by_key( "maxspeed:backward"))
  data.barrier = way:get_value_by_key("barrier")
  data.oneway = way:get_value_by_key("oneway")
  data.oneway_bicycle = way:get_value_by_key("oneway:bicycle")
  data.cycleway = way:get_value_by_key("cycleway")
  data.cycleway_left = way:get_value_by_key("cycleway:left")
  data.cycleway_right = way:get_value_by_key("cycleway:right")
  data.duration = way:get_value_by_key("duration")
  data.service = way:get_value_by_key("service")
  data.foot = way:get_value_by_key("foot")
  data.foot_forward = way:get_value_by_key("foot:forward")
  data.foot_backward = way:get_value_by_key("foot:backward")
  data.bicycle = way:get_value_by_key("bicycle")

  speed_handler(profile,way,result,data)

  oneway_handler(profile,way,result,data)

  cycleway_handler(profile,way,result,data)

  bike_push_handler(profile,way,result,data)


  -- maxspeed
  limit( result, data.maxspeed, data.maxspeed_forward, data.maxspeed_backward )

  -- not routable if no speed assigned
  -- this avoid assertions in debug builds
  if result.forward_speed <= 0 and result.duration <= 0 then
    result.forward_mode = mode.inaccessible
  end
  if result.backward_speed <= 0 and result.duration <= 0 then
    result.backward_mode = mode.inaccessible
  end

end



function speed_handler(profile,way,result,data)

  data.way_type_allows_pushing = false

  -- speed
  local bridge_speed = profile.bridge_speeds[data.bridge]
  if (bridge_speed and bridge_speed[1] > 0) then
    data.highway = data.bridge
    if data.duration and durationIsValid(data.duration) then
      result.duration = math.max( parseDuration(data.duration), 1 )
    end
    result.forward_rate = bridge_speed[1]
    result.backward_rate = bridge_speed[1]
    result.forward_speed = bridge_speed[2]
    result.backward_speed = bridge_speed[2]
    data.way_type_allows_pushing = true
  elseif data.route == "ferry" then
    -- ferries (doesn't cover routes tagged using relations)
    result.forward_mode = mode.ferry
    result.backward_mode = mode.ferry
    if data.duration and durationIsValid(data.duration) and (not profile.route_speeds["ferry"] or not profile.route_speeds["ferry"][2]) then
      result.duration = math.max( 1, parseDuration(data.duration) )
    end
    if profile.route_speeds["ferry"] then
       result.forward_rate = profile.route_speeds["ferry"][1]
       result.backward_rate = profile.route_speeds["ferry"][1]
       if profile.route_speeds["ferry"][2] then
         result.forward_speed = profile.route_speeds["ferry"][2]
         result.backward_speed = profile.route_speeds["ferry"][2]
       end
    end
  -- railway platforms (old tagging scheme)
  elseif data.railway and profile.platform_speeds[data.railway] then
    result.forward_rate = profile.platform_speeds[data.railway][1]
    result.backward_rate = profile.platform_speeds[data.railway][1]
    result.forward_speed = profile.platform_speeds[data.railway][2]
    result.backward_speed = profile.platform_speeds[data.railway][2]
    data.way_type_allows_pushing = true
  -- public_transport platforms (new tagging platform)
  elseif data.public_transport and profile.platform_speeds[data.public_transport] then
    result.forward_rate = profile.platform_speeds[data.public_transport][1]
    result.backward_rate = profile.platform_speeds[data.public_transport][1]
    result.forward_speed = profile.platform_speeds[data.public_transport][2]
    result.backward_speed = profile.platform_speeds[data.public_transport][2]
    data.way_type_allows_pushing = true
  -- railways
  elseif profile.use_public_transport and data.railway and profile.railway_speeds[data.railway] and profile.access_tag_whitelist[data.access] then
    result.forward_mode = mode.train
    result.backward_mode = mode.train
    result.forward_rate = profile.railway_speeds[data.railway][1]
    result.backward_rate = profile.railway_speeds[data.railway][1]
    result.forward_speed = profile.railway_speeds[data.railway][2]
    result.backward_speed = profile.railway_speeds[data.railway][2]
  elseif profile.bicycle_speeds[data.highway] then
    -- regular ways
    result.forward_rate = profile.bicycle_speeds[data.highway][1]
    result.backward_rate = profile.bicycle_speeds[data.highway][1]
    result.forward_speed = profile.bicycle_speeds[data.highway][2]
    result.backward_speed = profile.bicycle_speeds[data.highway][2]
    data.way_type_allows_pushing = true
  elseif data.access and profile.access_tag_whitelist[data.access]  then
    -- unknown way, but valid access tag
    result.forward_rate = profile.default_speed[1]
    result.backward_rate = profile.default_speed[1]
    result.forward_speed = profile.default_speed[2]
    result.backward_speed = profile.default_speed[2]
    data.way_type_allows_pushing = true
  end
end

function oneway_handler(profile,way,result,data)
  -- oneway
  data.implied_oneway = data.junction == "roundabout" or data.junction == "circular" or data.highway == "motorway"
  data.reverse = false

  if data.oneway_bicycle == "yes" or data.oneway_bicycle == "1" or data.oneway_bicycle == "true" then
    result.backward_mode = mode.inaccessible
  elseif data.oneway_bicycle == "no" or data.oneway_bicycle == "0" or data.oneway_bicycle == "false" then
   -- prevent other cases
  elseif data.oneway_bicycle == "-1" then
    result.forward_mode = mode.inaccessible
    data.reverse = true
  elseif data.oneway == "yes" or data.oneway == "1" or data.oneway == "true" then
    result.backward_mode = mode.inaccessible
  elseif data.oneway == "no" or data.oneway == "0" or data.oneway == "false" then
    -- prevent other cases
  elseif data.oneway == "-1" then
    result.forward_mode = mode.inaccessible
    data.reverse = true
  elseif data.implied_oneway then
    result.backward_mode = mode.inaccessible
  end
end

function cycleway_handler(profile,way,result,data)
  -- cycleway
  data.has_cycleway_forward = false
  data.has_cycleway_backward = false
  data.is_twoway = result.forward_mode ~= mode.inaccessible and result.backward_mode ~= mode.inaccessible and not data.implied_oneway

  -- cycleways on normal roads
  if data.is_twoway then
    if data.cycleway and profile.cycleway_tags[data.cycleway] then
      data.has_cycleway_backward = true
      data.has_cycleway_forward = true
    end
    if (data.cycleway_right and profile.cycleway_tags[data.cycleway_right]) or (data.cycleway_left and profile.opposite_cycleway_tags[data.cycleway_left]) then
      data.has_cycleway_forward = true
    end
    if (data.cycleway_left and profile.cycleway_tags[data.cycleway_left]) or (data.cycleway_right and profile.opposite_cycleway_tags[data.cycleway_right]) then
      data.has_cycleway_backward = true
    end
  else
    local has_twoway_cycleway = (data.cycleway and profile.opposite_cycleway_tags[data.cycleway]) or (data.cycleway_right and profile.opposite_cycleway_tags[data.cycleway_right]) or (data.cycleway_left and profile.opposite_cycleway_tags[data.cycleway_left])
    local has_opposite_cycleway = (data.cycleway_left and profile.opposite_cycleway_tags[data.cycleway_left]) or (data.cycleway_right and profile.opposite_cycleway_tags[data.cycleway_right])
    local has_oneway_cycleway = (data.cycleway and profile.cycleway_tags[data.cycleway]) or (data.cycleway_right and profile.cycleway_tags[data.cycleway_right]) or (data.cycleway_left and profile.cycleway_tags[data.cycleway_left])

    -- set cycleway even though it is an one-way if opposite is tagged
    if has_twoway_cycleway then
      data.has_cycleway_backward = true
      data.has_cycleway_forward = true
    elseif has_opposite_cycleway then
      if not data.reverse then
        data.has_cycleway_backward = true
      else
        data.has_cycleway_forward = true
      end
    elseif has_oneway_cycleway then
      if not data.reverse then
        data.has_cycleway_forward = true
      else
        data.has_cycleway_backward = true
      end

    end
  end

  if data.has_cycleway_backward then
    result.backward_mode = mode.cycling
    result.backward_rate = profile.bicycle_speeds["cycleway"][1]
    result.backward_speed = profile.bicycle_speeds["cycleway"][2]
  end

  if data.has_cycleway_forward then
    result.forward_mode = mode.cycling
    result.forward_rate = profile.bicycle_speeds["cycleway"][1]
    result.forward_speed = profile.bicycle_speeds["cycleway"][2]
  end
end

function bike_push_handler(profile,way,result,data)
  -- pushing bikes - if no other mode found
  if result.forward_mode == mode.inaccessible or result.backward_mode == mode.inaccessible or
    result.forward_speed == -1 or result.backward_speed == -1 then
    if data.foot ~= 'no' then
      local push_forward_speed = nil
      local push_backward_speed = nil

      if profile.pedestrian_speeds[data.highway] then
        push_forward_speed = profile.pedestrian_speeds[data.highway]
        push_backward_speed = profile.pedestrian_speeds[data.highway]
      elseif data.man_made and profile.man_made_speeds[data.man_made] then
        push_forward_speed = profile.man_made_speeds[data.man_made]
        push_backward_speed = profile.man_made_speeds[data.man_made]
      else
        if data.foot == 'yes' then
          push_forward_speed = profile.walking_speed
          if not data.implied_oneway then
            push_backward_speed = profile.walking_speed
          end
        elseif data.foot_forward == 'yes' then
          push_forward_speed = profile.walking_speed
        elseif data.foot_backward == 'yes' then
          push_backward_speed = profile.walking_speed
        elseif data.way_type_allows_pushing then
          push_forward_speed = profile.walking_speed
          if not data.implied_oneway then
            push_backward_speed = profile.walking_speed
          end
        end
      end

      if push_forward_speed and (result.forward_mode == mode.inaccessible or result.forward_speed == -1) then
        result.forward_mode = mode.pushing_bike
        result.forward_rate = push_forward_speed[1]
        result.forward_speed = push_forward_speed[2]
      end
      if push_backward_speed and (result.backward_mode == mode.inaccessible or result.backward_speed == -1)then
        result.backward_mode = mode.pushing_bike
        result.backward_rate = push_backward_speed[1]
        result.backward_speed = push_backward_speed[2]
      end

    end

  end

  -- dismount
  if data.bicycle == "dismount" then
    result.forward_mode = mode.pushing_bike
    result.backward_mode = mode.pushing_bike
    result.forward_rate = profile.walking_speed[1]
    result.backward_rate = profile.walking_speed[1]
    result.forward_speed = profile.walking_speed[2]
    result.backward_speed = profile.walking_speed[2]
  end
end

function process_way(profile, way, result)
  -- the initial filtering of ways based on presence of tags
  -- affects processing times significantly, because all ways
  -- have to be checked.
  -- to increase performance, prefetching and initial tag check
  -- is done directly instead of via a handler.

  -- in general we should try to abort as soon as
  -- possible if the way is not routable, to avoid doing
  -- unnecessary work. this implies we should check things that
  -- commonly forbids access early, and handle edge cases later.

  -- data table for storing intermediate values during processing

  local data = {
    -- prefetch tags
    highway = way:get_value_by_key('highway'),

    route = nil,
    man_made = nil,
    railway = nil,
    amenity = nil,
    public_transport = nil,
    bridge = nil,

    access = nil,

    junction = nil,
    maxspeed = nil,
    maxspeed_forward = nil,
    maxspeed_backward = nil,
    barrier = nil,
    oneway = nil,
    oneway_bicycle = nil,
    cycleway = nil,
    cycleway_left = nil,
    cycleway_right = nil,
    duration = nil,
    service = nil,
    foot = nil,
    foot_forward = nil,
    foot_backward = nil,
    bicycle = nil,

    way_type_allows_pushing = false,
    has_cycleway_forward = false,
    has_cycleway_backward = false,
    is_twoway = true,
    reverse = false,
    implied_oneway = false
  }

  local handlers = Sequence {
    -- set the default mode for this profile. if can be changed later
    -- in case it turns we're e.g. on a ferry
    WayHandlers.default_mode,

    -- check various tags that could indicate that the way is not
    -- routable. this includes things like status=impassable,
    -- toll=yes and oneway=reversible
    WayHandlers.blocked_ways,

    -- our main handler
    handle_bicycle_tags,

    -- compute speed taking into account way type, maxspeed tags, etc.
    WayHandlers.surface,

    -- handle turn lanes and road classification, used for guidance
    WayHandlers.classification,

    -- handle allowed start/end modes
    WayHandlers.startpoint,

    -- handle roundabouts
    WayHandlers.roundabouts,

    -- set name, ref and pronunciation
    WayHandlers.names,

    -- set classes
    WayHandlers.classes,

    -- set speed for path
    WayHandlers.adjust_speed_for_path,

    -- set weight properties of the way
    WayHandlers.weights
  }

  WayHandlers.run(profile, way, result, data, handlers)

  if result.forward_rate > 0 then
    result.forward_rate = result.forward_rate * 10
  end

  if result.backward_rate > 0 then
    result.backward_rate = result.backward_rate * 10
  end
end

function process_turn(profile, turn)
  -- compute turn penalty as angle^2, with a left/right bias
  local normalized_angle = turn.angle / 90.0
  if normalized_angle >= 0.0 then
    turn.duration = normalized_angle * normalized_angle * profile.turn_penalty / profile.turn_bias
  else
    turn.duration = normalized_angle * normalized_angle * profile.turn_penalty * profile.turn_bias
  end

  if turn.is_u_turn then
    turn.duration = turn.duration + profile.properties.u_turn_penalty
  end

  if turn.has_traffic_light then
     turn.duration = turn.duration + profile.properties.traffic_light_penalty
  end
  if profile.properties.weight_name == 'cyclability' then
    turn.weight = turn.duration
  end
  if turn.source_mode == mode.cycling and turn.target_mode ~= mode.cycling then
    turn.weight = turn.weight + profile.properties.mode_change_penalty
  end
end

return {
  setup = setup,
  process_way = process_way,
  process_node = process_node,
  process_turn = process_turn
}
