"""
Struct to simulation a device trip
"""
struct UnplannedOutage <: EventType
    device_type::DataType
    name::String
    timestamp::Dates.DateTime
end
