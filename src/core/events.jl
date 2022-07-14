abstract type EventType end
-
struct EventKey{T <: EventType, U <: Union{PSY.Component, PSY.System}}
    meta::String
end

function EventKey(
    ::Type{T},
    ::Type{U},
    meta=CONTAINER_KEY_EMPTY_META,
) where {T <: EventType, U <: Union{PSY.Component, PSY.System}}
    if isabstracttype(U)
        error("Type $U can't be abstract")
    end
    check_meta_chars(meta)
    return EventKey{T, U}(meta)
end

function EventKey(
    ::Type{T},
    meta::String=CONTAINER_KEY_EMPTY_META,
) where {T <: EventType}
    return EventKey(T, PSY.Component, meta)
end

get_entry_type(
    ::EventKey{T, U},
) where {T <: EventType, U <: Union{PSY.Component, PSY.System}} = T
get_component_type(
    ::EventKey{T, U},
) where {T <: EventType, U <: Union{PSY.Component, PSY.System}} = U

"""
Struct to simulation a device trip
"""
struct UnplanedOutage <: EventType end
