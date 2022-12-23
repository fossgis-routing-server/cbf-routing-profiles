-- Foot profile

api_version = 4


Set = require('lib/set')
Sequence = require('lib/sequence')
Handlers = require("lib/way_handlers_weight")
find_access_tag = require("lib/access").find_access_tag
local Tags = require('lib/tags')

function setup()

  return {

    properties = {
      weight_name                   = 'routability',
      weight_precision              = 2,
      max_speed_for_map_matching    = 40/3.6, -- kmph -> m/s
      call_tagless_node_function    = false,
      traffic_light_penalty         = 2,
      u_turn_penalty                = 2,
      continue_straight_at_waypoint = false,
      use_turn_restrictions         = false,
    },

    default_mode            = mode.walking,
    default_speed           = 4.5,
    default_weight          = 1,
    designated_weight       = 1.2,
    oneway_handling         = 'specific',     -- respect 'oneway:foot' but not 'oneway'
    traffic_light_penalty   = 2,
    u_turn_penalty          = 2,

    barrier_whitelist = Set {
      'kerb',
      'block',
      'bollard',
      'border_control',
      'cattle_grid',
      'entrance',
      'sally_port',
      'toll_booth',
      'cycle_barrier',
      'gate',
      'no',
      'stile',
      'bock',
      'kissing_gate',
      'turnstile',
      'hampshire_gate'
    },

    access_tag_whitelist = Set {
      'yes',
      'foot',
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

    construction_whitelist = Set {},

    access_tags_hierarchy = Sequence {
      'foot',
      'access'
    },

    -- tags disallow access to in combination with highway=service
    service_access_tag_blacklist = Set { },

    restrictions = Sequence {
      'foot'
    },

    -- list of suffixes to suppress in name change instructions
    suffix_list = Set {
      'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW', 'North', 'South', 'West', 'East'
    },

    avoid = Set {
      'impassable'
    },

    speeds = Sequence {
      highway = {
        footway         = {1.2, 4.5},
        cycleway        = {1.0, 4.5},
        primary         = {0.7, 4.5},
        primary_link    = {0.7, 4.5},
        secondary       = {0.8, 4.5},
        secondary_link  = {0.8, 4.5},
        tertiary        = {0.9, 4.5},
        tertiary_link   = {0.9, 4.5},
        unclassified    = {1.0, 4.5},
        residential     = {1.0, 4.5},
        road            = {1.0, 4.5},
        living_street   = {1.1, 4.5},
        service         = {1.0, 4.5},
        path            = {1.2, 4.5},
        track           = {1.1, 4.5},
        steps           = {1.1, 4.5},
        pedestrian      = {1.2, 4.5},
        pier            = {1.0, 4.5},
      },

      railway = {
        platform        = {1.0, 4.5},
      },

      amenity = {
        parking         = {1.0, 4.5},
        parking_entrance= {1.0, 4.5}
      },

      man_made = {
        pier            = {1.0, 4.5}
      },

      leisure = {
        track           = {1.0, 4.5}
      }
    },

    route_weights = {
      ferry = {0.3, nil}
    },

    bridge_speeds = {
    },

    surface_speeds= {
      ["fine_gravel"] = {0.8, 4.5},
      ["gravel"]      = {0.7, 3.5},
      ["pebblestone"] = {0.7, 3.5},
      ["mud"]         = {0.5, 3.5},
      ["ground"]      = {0.8, 4.5},
      ["unpaved"]     = {0.8, 4.5},
      ["grass"]       = {0.5, 3.5},
      ["dirt"]        = {0.5, 3.5},
      ["compacted"]   = {0.9, 4.5},
      ["grit"]        = {0.8, 4.5},
      ["sand"]        = {0.6, 4.5}
    },

    tracktype_speeds = {
      grade1 =  {1.1, 4.5},
      grade2 =  {1.1, 4.5},
      grade3 =  {1.0, 3.5},
      grade4 =  {0.9, 3.5},
      grade5 =  {0.9, 3.5}
    },

    smoothness_speeds = {
    },

    speed_path = {
      sac_scale = { hiking = {0.5, 3.5},
                    mountain_hiking = {0,0},
                    demanding_mountain_hiking = {0,0},
                    alpine_hiking = {0,0},
                    demanding_alpine_hiking = {0,0},
                    difficult_alpine_hiking = {0,0}
                  },
      bicycle = { designated = {0.5, 4.5}, yes = {0.9, 4.5} }
    }
  }

end


function process_node (profile, node, result)
  -- parse access and barrier tags
  local access = find_access_tag(node, profile.access_tags_hierarchy)
  if access then
    if profile.access_tag_blacklist[access] and not profile.restricted_access_tag_list[access] then
      result.barrier = true
    end
  else
    local barrier = node:get_value_by_key("barrier")
    if barrier then
      --  make an exception for rising bollard barriers
      local bollard = node:get_value_by_key("bollard")
      local rising_bollard = bollard and "rising" == bollard

      if not profile.barrier_whitelist[barrier] and not rising_bollard then
        result.barrier = true
      end
    end
  end

  -- check if node is a traffic light
  local tag = node:get_value_by_key("highway")
  if "traffic_signals" == tag then
    result.traffic_lights = true
  end
end

-- main entry point for processsing a way
function process_way(profile, way, result)
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
    bridge = way:get_value_by_key('bridge'),
    route = way:get_value_by_key('route'),
    leisure = way:get_value_by_key('leisure'),
    man_made = way:get_value_by_key('man_made'),
    railway = way:get_value_by_key('railway'),
    platform = way:get_value_by_key('platform'),
    amenity = way:get_value_by_key('amenity'),
    public_transport = way:get_value_by_key('public_transport')
  }

  -- perform an quick initial check and abort if the way is
  -- obviously not routable. here we require at least one
  -- of the prefetched tags to be present, ie. the data table
  -- cannot be empty
  if next(data) == nil then     -- is the data table empty?
    return
  end

  local handlers = Sequence {
    -- set the default mode for this profile. if can be changed later
    -- in case it turns we're e.g. on a ferry
    WayHandlers.default_mode,

    -- check various tags that could indicate that the way is not
    -- routable. this includes things like status=impassable,
    -- toll=yes and oneway=reversible
    WayHandlers.blocked_ways,

    -- determine access status by checking our hierarchy of
    -- access tags, e.g: motorcar, motor_vehicle, vehicle
    WayHandlers.access,

    -- check whether forward/backward directons are routable
    WayHandlers.oneway,

    -- check whether forward/backward directons are routable
    WayHandlers.destinations,

    -- check whether we're using a special transport mode
    WayHandlers.ferries,
    WayHandlers.movables,

    -- compute speed taking into account way type, maxspeed tags, etc.
    WayHandlers.speed,
    WayHandlers.surface,

    -- set speed for path
    WayHandlers.adjust_speed_for_path,

    -- handle turn lanes and road classification, used for guidance
    WayHandlers.classification,

    -- handle various other flags
    WayHandlers.roundabouts,
    WayHandlers.startpoint,

    -- set name, ref and pronunciation
    WayHandlers.names,
  }

  WayHandlers.run(profile, way, result, data, handlers)

  if result.forward_rate > 0 then
    result.forward_rate = result.forward_rate * 10
  end

  if result.backward_rate > 0 then
    result.backward_rate = result.backward_rate * 10
  end
  
  if result.forward_rate == -1 and result.forward_speed > 0 then
    result.forward_rate = result.forward_speed / 3.6;
  end
  if result.backward_rate == -1 and result.backward_speed > 0  then
    result.backward_rate = result.backward_speed / 3.6;
  end
end

function process_turn(profile, turn)
  turn.duration = 0.

  if turn.is_u_turn then
    turn.duration = turn.duration + profile.properties.u_turn_penalty
  end

  if turn.has_traffic_light then
     turn.duration = turn.duration + profile.properties.traffic_light_penalty
  end

  if profile.properties.weight_name == 'cyclability' then
    turn.weight = turn.duration
  end

  -- penalize turns from non-local access only segments onto local access only tags
  if not turn.source_restricted and turn.target_restricted then
      turn.weight = turn.weight + 3000
  end
end

return {
  setup = setup,
  process_way = process_way,
  process_node = process_node,
  process_turn = process_turn
}
