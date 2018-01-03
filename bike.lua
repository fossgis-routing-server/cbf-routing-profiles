api_version = 1

-- Bicycle profile
local find_access_tag = require("lib/access").find_access_tag
local Set = require('lib/set')
local Sequence = require('lib/sequence')
local Handlers = require("lib/handlers")
local next = next       -- bind to local for speed
local limit = require("lib/maxspeed").limit
local Tags = require('lib/tags')

-- these need to be global because they are accesed externaly
properties.max_speed_for_map_matching    = 110/3.6 -- kmph -> m/s
properties.use_turn_restrictions         = false
properties.continue_straight_at_waypoint = false
--properties.weight_name                   = 'duration'
properties.weight_name                   = 'routability'


local default_speed = 15
local walking_speed = 6

local profile = {
  default_mode              = mode.cycling,
  default_speed             = 16,
  designated_speed          = 18,
  oneway_handling           = true,
  traffic_light_penalty     = 2,
  u_turn_penalty            = 20,
  turn_penalty              = 6,
  turn_bias                 = 1.4,

  -- reduce the driving speed by 30% for unsafe roads
  -- local safety_penalty            = 0.7,
  safety_penalty            = 1.0,
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
    'no',
    'kerb',
    'block'
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
  	'opposite',
  	'opposite_lane',
  	'opposite_track',
  	'share_busway',
  	'sharrow',
  	'shared'
  },

  unsafe_highway_list = Set {
  	'primary',
   	'secondary',
   	'tertiary',
   	'primary_link',
   	'secondary_link',
   	'tertiary_link'
  },

  service_penalties = {
    alley             = 0.5,
  },

  bicycle_speeds = {
    cycleway = 18,
    primary = 15,
    primary_link = 15,
    secondary = 16,
    secondary_link = 16,
    tertiary = 17,
    tertiary_link = 17,
    residential = 18,
    unclassified = 18,
    living_street = 18,
    road = 17,
    service = 17,
    track = 12,
    path = 6,
    footway = 5,
    pedestrian = 5,
    steps = 1
  },

  pedestrian_speeds = {
    footway = walking_speed,
    pedestrian = walking_speed,
    steps = 2
  },

  railway_speeds = {
    train = 10,
    railway = 10,
    subway = 10,
    light_rail = 10,
    monorail = 10,
    tram = 10
  },

  platform_speeds = {
    platform = walking_speed
  },

  amenity_speeds = {
    parking = 10,
    parking_entrance = 10
  },

  man_made_speeds = {
    pier = walking_speed
  },

  route_speeds = {
    ferry = 4
  },

  bridge_speeds = {
    movable = 5
  },

  surface_penalties = { 
    ["gravel"] = 0.8,
    ["ground"] = 0.6,
    ["unpaved"] = 0.8,
    ["grass"] = 0.4,
    ["dirt"] = 0.4,
    ["cobblestone"] = 0.5, 
    ["pebblestone"] = 0.9, 
    ["compacted"] = 0.9, 
    ["wood"] = 0.95,
    ["grit"] = 0.5,
    ["sand"] = 0.4,
    ground = 0.5,
    earth = 0.4,
    grass = 0.4,
    mud = 0.1
  },
  
  -- max speed for tracktypes
  tracktype_speeds = {
    grade1 =  18,
    grade2 =  16,
    grade3 =  12,
    grade4 =   0,
    grade5 =   0
  },

  smoothness_speeds = {
  },

  avoid = Set {
    'impassable',
    'construction'
  },

  speed_path = {
    sac_scale = nil,
    foot = { designated = 0.5,
             yes = 0.9 },
    bicycle = { yes = 3 },
    ["mtb:scale"] = nil
  }

}


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

function get_restrictions(vector)
  for i,v in ipairs(profile.restrictions) do
    vector:Add(v)
  end
end

function node_function (node, result)
  -- parse access and barrier tags
  local highway = node:get_value_by_key("highway")
  local is_crossing = highway and highway == "crossing"

  local access = find_access_tag(node, profile.access_tags_hierarchy)
  if access and access ~= "" then
    -- access restrictions on crossing nodes are not relevant for
    -- the traffic on the road
    if profile.access_tag_blacklist[access] and not profile.restricted_access_tag_list[access] and not is_crossing then
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

function way_function (way, result)
  -- the intial filtering of ways based on presence of tags
  -- affects processing times significantly, because all ways
  -- have to be checked.
  -- to increase performance, prefetching and intial tag check
  -- is done in directly instead of via a handler.

  -- in general we should  try to abort as soon as
  -- possible if the way is not routable, to avoid doing
  -- unnecessary work. this implies we should check things that
  -- commonly forbids access early, and handle edge cases later.

  -- data table for storing intermediate values during processing

  local data = {
    -- prefetch tags
    highway = way:get_value_by_key('highway'),
  }

  local handlers = Sequence {
    -- set the default mode for this profile. if can be changed later
    -- in case it turns we're e.g. on a ferry
    'handle_default_mode',

    -- check various tags that could indicate that the way is not
    -- routable. this includes things like status=impassable,
    -- toll=yes and oneway=reversible
    'handle_blocked_ways',
  }

  if Handlers.run(handlers,way,result,data,profile) == false then
    return
  end

  -- initial routability check, filters out buildings, boundaries, etc
  local route = way:get_value_by_key("route")
  local man_made = way:get_value_by_key("man_made")
  local railway = way:get_value_by_key("railway")
  local amenity = way:get_value_by_key("amenity")
  local public_transport = way:get_value_by_key("public_transport")
  local bridge = way:get_value_by_key("bridge")

  if (not data.highway or data.highway == '') and
  (not route or route == '') and
  (not profile.use_public_transport or not railway or railway=='') and
  (not amenity or amenity=='') and
  (not man_made or man_made=='') and
  (not public_transport or public_transport=='') and
  (not bridge or bridge=='')
  then
    return
  end

  -- access
  data.forward_access, data.backward_access =
    Tags.get_forward_backward_by_set(way,data,profile.access_tags_hierarchy)

  if profile.restricted_access_tag_list[data.forward_access] then
      result.forward_restricted = true
  end

  if profile.restricted_access_tag_list[data.backward_access] then
      result.backward_restricted = true
  end

  if profile.access_tag_blacklist[data.forward_access] and not result.forward_restricted then
    result.forward_mode = mode.inaccessible
  end

  if profile.access_tag_blacklist[data.backward_access] and not result.backward_restricted then
    result.backward_mode = mode.inaccessible
  end

  if result.forward_mode == mode.inaccessible and result.backward_mode == mode.inaccessible then
    return false
  end

  -- other tags
  local junction = way:get_value_by_key("junction")
  local maxspeed = parse_maxspeed(way:get_value_by_key ( "maxspeed") )
  local maxspeed_forward = parse_maxspeed(way:get_value_by_key( "maxspeed:forward"))
  local maxspeed_backward = parse_maxspeed(way:get_value_by_key( "maxspeed:backward"))
  local barrier = way:get_value_by_key("barrier")
  local oneway = way:get_value_by_key("oneway")
  local onewayClass = way:get_value_by_key("oneway:bicycle")
  local cycleway = way:get_value_by_key("cycleway")
  local cycleway_left = way:get_value_by_key("cycleway:left")
  local cycleway_right = way:get_value_by_key("cycleway:right")
  local duration = way:get_value_by_key("duration")
  local service = way:get_value_by_key("service")
  local foot = way:get_value_by_key("foot")
  local foot_forward = way:get_value_by_key("foot:forward")
  local foot_backward = way:get_value_by_key("foot:backward")
  local bicycle = way:get_value_by_key("bicycle")
  local tracktype = way:get_value_by_key("tracktype")
  local smoothness = way:get_value_by_key("smoothness")


  -- speed
  local bridge_speed = profile.bridge_speeds[bridge]
  if (bridge_speed and bridge_speed > 0) then
    data.highway = bridge
    if duration and durationIsValid(duration) then
      result.duration = math.max( parseDuration(duration), 1 )
    end
    result.forward_speed = bridge_speed
    result.backward_speed = bridge_speed
  elseif profile.route_speeds[route] then
    -- ferries (doesn't cover routes tagged using relations)
    result.forward_mode = mode.ferry
    result.backward_mode = mode.ferry
    if duration and durationIsValid(duration) then
      result.duration = math.max( 1, parseDuration(duration) )
    else
       result.forward_speed = profile.route_speeds[route]
       result.backward_speed = profile.route_speeds[route]
    end
  -- railway platforms (old tagging scheme)
  elseif railway and profile.platform_speeds[railway] then
    result.forward_speed = profile.platform_speeds[railway]
    result.backward_speed = profile.platform_speeds[railway]
  -- public_transport platforms (new tagging platform)
  elseif public_transport and profile.platform_speeds[public_transport] then
    result.forward_speed = profile.platform_speeds[public_transport]
    result.backward_speed = profile.platform_speeds[public_transport]
  -- railways
  elseif profile.use_public_transport and railway and profile.railway_speeds[railway] and profile.access_tag_whitelist[access] then
    result.forward_mode = mode.train
    result.backward_mode = mode.train
    result.forward_speed = profile.railway_speeds[railway]
    result.backward_speed = profile.railway_speeds[railway]
  elseif amenity and profile.amenity_speeds[amenity] then
    -- parking areas
    result.forward_speed = profile.amenity_speeds[amenity]
    result.backward_speed = profile.amenity_speeds[amenity]
  elseif smoothness and profile.smoothness_speeds[smoothness] then
    -- smoothness
    result.forward_speed = profile.smoothness_speeds[smoothness]
    result.backward_speed = profile.smoothness_speeds[smoothness]
  elseif tracktype and profile.tracktype_speeds[tracktype] then
    -- tracks
    result.forward_speed = profile.tracktype_speeds[tracktype]
    result.backward_speed = profile.tracktype_speeds[tracktype]
  elseif profile.bicycle_speeds[data.highway] then
    -- regular ways
    result.forward_speed = profile.bicycle_speeds[data.highway]
    result.backward_speed = profile.bicycle_speeds[data.highway]
  elseif access and profile.access_tag_whitelist[access]  then
    -- unknown way, but valid access tag
    result.forward_speed = default_speed
    result.backward_speed = default_speed
  else
    -- biking not allowed, maybe we can push our bike?
    -- essentially requires pedestrian profiling, for example foot=no mean we can't push a bike
    if foot ~= 'no' and (junction ~= "roundabout" and junction ~= "circular") then
      if profile.pedestrian_speeds[data.highway] then
        -- pedestrian-only ways and areas
        result.forward_speed = profile.pedestrian_speeds[data.highway]
        result.backward_speed = profile.pedestrian_speeds[data.highway]
        result.forward_mode = mode.pushing_bike
        result.backward_mode = mode.pushing_bike
      elseif man_made and profile.man_made_speeds[man_made] then
        -- man made structures
        result.forward_speed = profile.man_made_speeds[man_made]
        result.backward_speed = profile.man_made_speeds[man_made]
        result.forward_mode = mode.pushing_bike
        result.backward_mode = mode.pushing_bike
      elseif foot == 'yes' then
        result.forward_speed = walking_speed
        result.backward_speed = walking_speed
        result.forward_mode = mode.pushing_bike
        result.backward_mode = mode.pushing_bike
      elseif foot_forward == 'yes' then
        result.forward_speed = walking_speed
        result.forward_mode = mode.pushing_bike
        result.backward_mode = mode.inaccessible
      elseif foot_backward == 'yes' then
        result.forward_speed = walking_speed
        result.forward_mode = mode.inaccessible
        result.backward_mode = mode.pushing_bike
      end
    end
  end

  -- direction
  local impliedOneway = false
  if junction == "roundabout" or junction == "circular" or data.highway == "motorway" then
    impliedOneway = true
  end

  if onewayClass == "yes" or onewayClass == "1" or onewayClass == "true" then
    result.backward_mode = mode.inaccessible
  elseif onewayClass == "no" or onewayClass == "0" or onewayClass == "false" then
    -- prevent implied oneway
  elseif onewayClass == "-1" then
    result.forward_mode = mode.inaccessible
  elseif oneway == "no" or oneway == "0" or oneway == "false" then
    -- prevent implied oneway
  elseif cycleway and string.find(cycleway, "opposite") == 1 then
    if impliedOneway then
      result.forward_mode = mode.inaccessible
      result.backward_mode = mode.cycling
      result.backward_speed = profile.bicycle_speeds["cycleway"]
    end
  elseif cycleway_left and profile.cycleway_tags[cycleway_left] and cycleway_right and profile.cycleway_tags[cycleway_right] then
    -- prevent implied
  elseif cycleway_left and profile.cycleway_tags[cycleway_left] then
    if impliedOneway then
      result.forward_mode = mode.inaccessible
      result.backward_mode = mode.cycling
      result.backward_speed = profile.bicycle_speeds["cycleway"]
    end
  elseif cycleway_right and profile.cycleway_tags[cycleway_right] then
    if impliedOneway then
      result.forward_mode = mode.cycling
      result.backward_speed = profile.bicycle_speeds["cycleway"]
      result.backward_mode = mode.inaccessible
    end
  elseif oneway == "-1" then
    result.forward_mode = mode.inaccessible
  elseif oneway == "yes" or oneway == "1" or oneway == "true" or impliedOneway then
    result.backward_mode = mode.inaccessible
  end

  -- pushing bikes
  if profile.bicycle_speeds[data.highway] or profile.pedestrian_speeds[data.highway] then
    if foot ~= "no" and junction ~= "roundabout" and junction ~= "circular" then
      if result.backward_mode == mode.inaccessible then
        result.backward_speed = walking_speed
        result.backward_mode = mode.pushing_bike
      elseif result.forward_mode == mode.inaccessible then
        result.forward_speed = walking_speed
        result.forward_mode = mode.pushing_bike
      end
    end
  end

  -- cycleways
  local has_cycleway_left, has_cycleway_right
  if cycleway and profile.cycleway_tags[cycleway] then
    has_cycleway_left = true
    has_cycleway_right = true
  elseif cycleway_left and profile.cycleway_tags[cycleway_left] then
    has_cycleway_left = true
    has_cycleway_right = true
  elseif cycleway_right and profile.cycleway_tags[cycleway_right] then
    has_cycleway_left = true
    has_cycleway_right = true
  end
  if has_cycleway_right and
     (result.forward_mode == mode.inaccessible or
      result.forward_mode == mode.cycling) then
    result.forward_speed = profile.bicycle_speeds["cycleway"]
  end
  if has_cycleway_left and
     (result.backward_mode == mode.inaccessible or
      result.backward_mode == mode.cycling) then
    result.backward_speed = profile.bicycle_speeds["cycleway"]
  end


  -- dismount
  if bicycle == "dismount" then
    result.forward_mode = mode.pushing_bike
    result.backward_mode = mode.pushing_bike
    result.forward_speed = walking_speed
    result.backward_speed = walking_speed
  end


  -- maxspeed
  limit( result, maxspeed, maxspeed_forward, maxspeed_backward )

  -- convert duration into routability
  if properties.weight_name == 'routability' then
      local is_unsafe = profile.safety_penalty < 1 and profile.unsafe_highway_list[data.highway]
      local is_undesireable = data.highway == "service" and profile.service_penalties[service]
      local surface = way:get_value_by_key("surface") and profile.surface_penalties[surface]
      local penalty = 1.0
      if is_unsafe then
        penalty = math.min(penalty, profile.safety_penalty)
      end
      if is_undesireable then
        penalty = math.min(penalty, profile.service_penalties[service])
      end
      if surface then
        penalty = math.min(penalty, profile.service_penalties[service])
      end

      if result.forward_speed > 0 then
        -- convert from km/h to m/s
        result.forward_rate = result.forward_speed / 3.6 * penalty
      end
      if result.backward_speed > 0 then
        -- convert from km/h to m/s
        result.backward_rate = result.backward_speed / 3.6 * penalty
      end
      if result.duration > 0 then
        result.weight = result.duration / penalty
      end
  end

  local handlers = Sequence {
    -- handle turn lanes and road classification, used for guidance
    'handle_classification',

    -- handle various other flags
    'handle_roundabouts',
    --'handle_startpoint',

    -- set name, ref and pronunciation
    'handle_names',

    -- set speed for path
    'adjust_speed_for_path'
  }

  Handlers.run(handlers,way,result,data,profile)

end

function turn_function(turn)
  -- compute turn penalty as angle^2, with a left/right bias
  local normalized_angle = turn.angle / 90.0
  if normalized_angle >= 0.0 then
    turn.duration = normalized_angle * normalized_angle * profile.turn_penalty / profile.turn_bias
  else
    turn.duration = normalized_angle * normalized_angle * profile.turn_penalty * profile.turn_bias
  end

  if turn.direction_modifier == direction_modifier.uturn then
    turn.duration = turn.duration + profile.u_turn_penalty
  end

  if turn.has_traffic_light then
     turn.duration = turn.duration + profile.traffic_light_penalty
  end
  if properties.weight_name == 'routability' then
      turn.weight = turn.duration
  end

  -- penalize turns from non-local access only segments onto local access only tags
  if not turn.source_restricted and turn.target_restricted then
      turn.weight = turn.weight + 3000
  end
end
