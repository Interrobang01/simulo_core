--[[
Component for fans
--]]

local base_filepath = 'core/scripts/everything/fans/';

local debug = false;

local rays_per_meter = 10;

local line = nil;
if debug then
    line = require("@interrobang/iblib/lib/line.lua");
end; -- don't require if debug is off cause we don't want iblib to be a dependency
local destroy_list = {};

local particles = {};

local function get_range(rpm)
    return rpm^(1/2);
end;

local function get_force(rpm)
    return rpm / 60;
end;

local function set_property_value(component, key, value)
    local prop = component:get_property(key);
    prop.value = value;
    component:set_property(key, prop);
end;

local particle_component = Scene:add_component_def({
    name = "Particle",
    id = "core/fan_particle",
    version = "0.1.0",
    code = require(base_filepath.."fan_particle_component.lua", "string"),
    properties = {
        {
            id = "size_multiplier",
            name = "Size Multiplier",
            input_type = "slider",
            default_value = 1,
            min_value = 0.1,
            max_value = 10,
        },
        {
            id = "velocity_x",
            name = "Velocity X",
            input_type = "slider",
            default_value = 1,
            min_value = -999,
            max_value = 999,
        },
        {
            id = "velocity_y",
            name = "Velocity Y",
            input_type = "slider",
            default_value = 1,
            min_value = -999,
            max_value = 999,
        },
    },
});

local function make_particle(position, velocity, size)
    local particle = Scene:add_attachment({
        parent = nil,
        local_position = position,
        images = {
            {
                texture = require("core/assets/textures/fan_particle.png"),
                scale = vec2(0, 0),
            },
        },
    });
    local comp = particle:add_component({ hash = particle_component });
    set_property_value(comp, "size_multiplier", size);
    set_property_value(comp, "velocity_x", velocity.x);
    set_property_value(comp, "velocity_y", velocity.y);
    table.insert(particles, particle);
end;

local function make_particles(p1, vector, velocity, surface_length, wind_speed, time)
    local particle_delay = 1 / wind_speed * 500;
    if time % particle_delay == 0 then
        local distance = math.random();
        local position = p1 + vector * distance;
        local size = surface_length * 0.01;
        make_particle(position, velocity / 7 / 60, size);
    end;
end;

-- WARNING: MATH
local function get_bounding_box_dimensions(range, fan_attachment)
    local shape = self:get_shape();
    local x = shape.size.x;
    local y = shape.size.y;
    local mult = self_component:get_property("size_multiplier").value;
    local corner = fan_attachment:get_world_point(vec2(-0.01, -y/2*mult));
    local perpendicular_wind_direction = fan_attachment:get_world_point(vec2(0, y/2*mult)) - corner;
    local wind_direction = fan_attachment:get_world_point(vec2(range + x/2, 0)) - fan_attachment:get_world_point(vec2(x/2, 0));
    local surface_length = y*mult;
    return corner, perpendicular_wind_direction, wind_direction, surface_length;
    -- end
end;

local function get_ray_hits(ray_start, ray_gap, total_rays, wind_direction)
    local hitlist = {};
    for i = 0, total_rays do
        local ray_origin = ray_start + ray_gap * i;
        local hits = Scene:raycast{
            origin = ray_origin, -- where to start the ray
            direction = wind_direction, -- direction of the ray, itll be normalized probably
            distance = wind_direction:magnitude(), -- how long before it gives up on everything in life
            closest_only = true, -- if false it should get the everything along the way (nothing is tested in this insane game)
            collision_layers = self:get_collision_layers(), -- what layers to check against
        };
        if debug then
            local args = line(ray_origin, ray_origin + wind_direction, 0.01);
            args.color = Color:rgb(0.1, 0.4, 0.1);
            args.body_type = BodyType.Static;
            local line_obj = Scene:add_box(args);
            line_obj:set_angle(args.rotation);
            line_obj:set_collision_layers({});
            table.insert(destroy_list, line_obj);
        end;
        if hits then
            for i = 1, #hits do
                local hit = hits[i];
                if hit then
                    table.insert(hitlist, hit);
                end;
            end;
        end;
    end;
    return hitlist;
end;

local function apply_force_to_hits(hits, force_vector, range)
    for i = 1, #hits do
        local hit = hits[i];
        if hit then
            local deflected_force_vector = -hit.normal * (force_vector.x*-hit.normal.x + force_vector.y*-hit.normal.y); -- TODO MAKE THIS ACCURATE
            local distance_scalar = 1-(hit.fraction^2);
            hit.object:apply_force(deflected_force_vector * distance_scalar, hit.point);

            if debug then
                local sphere = Scene:add_circle{
                    position = hit.point,
                    radius = 0.1,
                    body_type = BodyType.Static,
                    color = Color:rgb(0.1, 0.1, 0.1),
                };
                sphere:set_collision_layers({});
                table.insert(destroy_list, sphere);
            end;
        end;
    end;
end;

local function rotate_fan(rpm, time, fan_attachment, largest_side)
    local angle = (rpm^(1/2) * 6) * (time/60) / 60 * 2 * math.pi;
    local scale = math.cos(angle);
    local images = fan_attachment:get_images();
    local image_size = 512;
    local base_scale = largest_side / image_size;
    images[1].scale = vec2(base_scale, scale * base_scale);
    images[2].scale = vec2(base_scale, base_scale);
    fan_attachment:set_images(images);
end;

local fan_attachment = nil;

function on_save()
    return fan_attachment;
end;

function on_start(saved_data)
    if fan_attachment == nil or fan_attachment:is_destroyed() then
        if saved_data then
            fan_attachment = saved_data;
        else
            print("fan start", fan_attachment);
            local size = self:get_shape().size;
            local angle = size.x > size.y and math.pi/2 or 0;
            local edge_position = size.x > size.y and vec2(0, size.y/2) or vec2(size.x/2, 0);
            fan_attachment = Scene:add_attachment({
                parent = self,
                local_position = edge_position,
                local_angle = angle,
                images = {
                    {
                        texture = require("core/assets/textures/fan_blades.png"), -- this gets scaled
                        scale = vec2(0, 0),
                        color = Color:rgb(0, 0, 0),
                    },
                    {
                        texture = require("core/assets/textures/fan_center.png"), -- this stays still
                        scale = vec2(0, 0),
                        color = Color:rgb(0, 0, 0),
                    }
                },
                component = {
                    name = "Fan Attachment",
                    version = "0.1.0",
                    id = "core/fan_attachment",
                    icon = require("core/assets/textures/fan.png"),
                    code = require(base_filepath.."fan_attachment_component.lua", "string"),
                    properties = {
                        {
                            id = "color",
                            name = "Color",
                            input_type = "color",
                            default_value = Color:rgb(0, 0, 0),
                        },
                    },
                },
            });
            fan_attachment:set_name("Fan Blades");
        end;
    end;
end;

local on = false;
local rpm = 0;
function on_event(id, data)
    if id == "activate" then
        on = true;
        rpm = math.abs(data.power * 10 * self_component:get_property("multiplier").value);
    end;
end;

local time = 0;
function on_step()

    for i = 1, #destroy_list do
        local to_destroy = destroy_list[i];
        if to_destroy then
            to_destroy:destroy();
        end;
    end;
    destroy_list = {};


    
    local range = get_range(rpm);
    local force = get_force(rpm); -- force per meter surface area
    
    if not fan_attachment or fan_attachment:is_destroyed() then
        on_start();
    end;

    local ray_start, perpendicular_wind_direction, wind_direction, surface_length = get_bounding_box_dimensions(range, fan_attachment);
    
    rotate_fan(rpm, time, fan_attachment, surface_length);

    if not on then
        return;
    end;
    on = false;

    local total_rays = surface_length * rays_per_meter;
    local ray_gap = perpendicular_wind_direction / total_rays;

    if not self_component:get_property("disable_particles").value then
        make_particles(ray_start, perpendicular_wind_direction, wind_direction, surface_length, force, time);
    end;

    local hits = get_ray_hits(ray_start, ray_gap, total_rays, wind_direction);

    local force_vector = wind_direction:normalize() * force / rays_per_meter;

    if debug then
        local force_vector_line_args = line(ray_start, ray_start + force_vector, 0.01);
        force_vector_line_args.color = Color:rgb(0.1, 0.1, 0.8);
        force_vector_line_args.body_type = BodyType.Static;
        local force_vector_line = Scene:add_box(force_vector_line_args);
        force_vector_line:set_angle(force_vector_line_args.rotation);
        force_vector_line:set_collision_layers({});
        table.insert(destroy_list, force_vector_line);
    end;

    apply_force_to_hits(hits, force_vector, range);

    self:apply_force_to_center(-wind_direction:normalize() * force * surface_length);


    time = time + 1;
end;
